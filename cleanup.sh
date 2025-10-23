#!/bin/bash
set -e

# cleanup.sh
# Usage: ./cleanup.sh <RESOURCE_GROUP_NAME>

if [ -z "$1" ]; then
    echo "Usage: $0 <RESOURCE_GROUP_NAME>"
    exit 1
fi

RESOURCE_GROUP="$1"

echo "Starting cleanup of security configurations in resource group: $RESOURCE_GROUP"


# Disable Defender for AI workspace-setting (applies to all OpenAI resources in the workspace)
echo "Disabling Defender for AI workspace-setting (default) in this subscription..."
az security workspace-setting delete --name "default" || true

# Disable Defender for Storage at the storage account level using ARM API
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
for sa in $STORAGE_ACCOUNTS; do
    echo "Disabling Defender for Storage on account: $sa"
    url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${sa}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
    body='{ "properties": { "isEnabled": false, "overrideSubscriptionLevelSettings": true, "malwareScanning": { "onUpload": { "isEnabled": false } }, "sensitiveDataDiscovery": { "isEnabled": false } } }'
    az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
done

echo "Security configurations successfully removed!"

# Optionally revert subscription-wide Defender plan changes recorded by deploy script
revert_subscription_defender_plans() {
    local script_dir state_file ans
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    state_file="$script_dir/.defender_state.env"
    local YELLOW='\033[1;33m'; local NC='\033[0m'
    if [ -f "$state_file" ]; then
        # shellcheck disable=SC1090
        source "$state_file"
        if [ "${APPSERVICES_CHANGED:-0}" = "1" ] || [ "${COSMOSDBS_CHANGED:-0}" = "1" ]; then
            echo -e "${YELLOW}Warning:${NC} Subscription-wide Defender plans were enabled by the deploy script."
            read -r -p "Revert these subscription-wide changes now? [y/N] " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                if [ "${APPSERVICES_CHANGED:-0}" = "1" ]; then
                    echo "Reverting Defender plan for App Services at subscription scope..."
                    local url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
                    local body='{ "properties": { "pricingTier": "Free" } }'
                    az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
                fi
                if [ "${COSMOSDBS_CHANGED:-0}" = "1" ]; then
                    echo "Reverting Defender plan for Cosmos DBs at subscription scope..."
                    local url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/CosmosDbs?api-version=2024-01-01"
                    local body='{ "properties": { "pricingTier": "Free" } }'
                    az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json" || true
                fi
                echo "Revert complete."
                rm -f "$state_file" || true
            else
                echo "Leaving subscription-wide Defender plans as-is."
            fi
        fi
    fi
}

# Optionally, clean up all resources if azd was used
azd_teardown() {
    local script_dir azd_state_file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    azd_state_file="$script_dir/.azd_state.env"
    if [ -f "$azd_state_file" ]; then
        # shellcheck disable=SC1090
        source "$azd_state_file"
        if [ -n "${AZD_WORKDIR:-}" ] && [ -d "$AZD_WORKDIR" ]; then
            echo "Running 'azd down --force --purge' in $AZD_WORKDIR ..."
            if [ -n "${AZD_ENV:-}" ]; then
                (cd "$AZD_WORKDIR" && azd down --force --purge -e "$AZD_ENV") || true
            else
                (cd "$AZD_WORKDIR" && azd down --force --purge) || true
            fi
        else
            echo "(Info) No recorded azd workdir found; attempting azd down in current directory."
            azd down --force --purge || true
        fi
    else
        echo "(Info) No .azd_state.env present; attempting azd down in current directory."
        azd down --force --purge || true
    fi
}

# Delete any client secrets for app registrations discovered via azd env
delete_client_secrets() {
    local script_dir azd_state_file env_values candidates id confirm
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    azd_state_file="$script_dir/.azd_state.env"
    candidates=()

    if [ -f "$azd_state_file" ]; then
        # shellcheck disable=SC1090
        source "$azd_state_file"
        if [ -n "${AZD_WORKDIR:-}" ] && [ -d "$AZD_WORKDIR" ]; then
            if [ -n "${AZD_ENV:-}" ]; then
                env_values=$(cd "$AZD_WORKDIR" && azd env get-values -e "$AZD_ENV" 2>/dev/null || true)
            else
                env_values=$(cd "$AZD_WORKDIR" && azd env get-values 2>/dev/null || true)
            fi
        fi
    fi

    # Fallback to current directory if no recorded azd workdir/env
    if [ -z "$env_values" ]; then
        if [ -n "${AZD_ENV:-}" ]; then
            env_values=$(azd env get-values -e "$AZD_ENV" 2>/dev/null || true)
        else
            env_values=$(azd env get-values 2>/dev/null || true)
        fi
    fi

    if [ -n "$env_values" ]; then
        while IFS= read -r val; do
            # Strip quotes
            val="${val%\"}"; val="${val#\"}"
            if [[ "$val" =~ ^[0-9a-fA-F-]{36}$ ]]; then
                candidates+=("$val")
            fi
        done < <(echo "$env_values" | grep -E '(_CLIENT_ID|APP_ID|AAD_APP_ID|APP_REGISTRATION_ID)=' | sed 's/^[^=]*=//' | tr -d '\r' | sort -u)
    fi

    # De-duplicate
    if [ ${#candidates[@]} -eq 0 ]; then
        echo "No candidate app registration IDs found in azd env. Skipping client secret deletion."
        return 0
    fi

    echo "Found candidate app registrations (from azd env):"
    for id in "${candidates[@]}"; do
        local name
        name=$(az ad app show --id "$id" --query displayName -o tsv 2>/dev/null || true)
        name=${name:-"(unknown)"}
        local secret_count
        secret_count=$(az ad app show --id "$id" --query "length(passwordCredentials)" -o tsv 2>/dev/null || echo 0)
        echo "- $id  name: $name  passwordSecrets: $secret_count"
    done

    read -r -p "Delete ALL password secrets for the above apps? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Skipping client secret deletion."
        return 0
    fi

    for id in "${candidates[@]}"; do
        local key_ids
        key_ids=$(az ad app show --id "$id" --query "passwordCredentials[].keyId" -o tsv 2>/dev/null || true)
        if [ -z "$key_ids" ]; then
            echo "No password secrets to delete for app $id."
            continue
        fi
        for kid in $key_ids; do
            echo "Deleting secret keyId=$kid for app $id ..."
            az ad app credential delete --id "$id" --key-id "$kid" --only-show-errors || true
        done
    done
    echo "Client secret deletion completed."
}

# Execute teardown steps
revert_subscription_defender_plans
azd_teardown
delete_client_secrets || true

# Remove Azure Front Door profile created by the secure step (no prompt)
PROFILE_NAME="fd-${RESOURCE_GROUP}"
ID=$(az resource show -g "$RESOURCE_GROUP" -n "$PROFILE_NAME" --resource-type Microsoft.Cdn/profiles --query id -o tsv 2>/dev/null || true)
if [ -z "$ID" ]; then
    echo "No Front Door profile '$PROFILE_NAME' found in RG '$RESOURCE_GROUP'. Skipping."
else
    echo "Deleting Front Door profile '$PROFILE_NAME'..."
    az resource delete --ids "$ID" --only-show-errors || true
    echo "Front Door removal complete."
fi

echo "Cleanup complete!"
