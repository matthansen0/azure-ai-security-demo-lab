#!/bin/bash
set -e

# azureAISecurityDeploy.sh
# Usage: ./azureAISecurityDeploy.sh [RESOURCE_GROUP_NAME]
echo "version 2.9"

# Try to resolve resource group automatically if not provided
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.azd_state.env"

detect_rg() {
    local rg=""
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [ -n "${AZD_WORKDIR:-}" ] && [ -d "${AZD_WORKDIR}" ]; then
            if [ -n "${AZD_ENV:-}" ]; then
                rg=$(cd "$AZD_WORKDIR" && azd env get-values -e "$AZD_ENV" | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
            else
                rg=$(cd "$AZD_WORKDIR" && azd env get-values | sed -n 's/^AZURE_RESOURCE_GROUP=//p' | tr -d '\r')
            fi
        fi
    fi
    echo "$rg"
}

RESOURCE_GROUP="${1:-}"
if [ -z "$RESOURCE_GROUP" ]; then
    RESOURCE_GROUP=$(detect_rg)
fi
if [ -z "$RESOURCE_GROUP" ]; then
    read -r -p "Enter the resource group name to secure: " RESOURCE_GROUP
fi

# Subscription ID used for subscription-scope checks and ARM calls
SUBSCRIPTION_ID=$(az account show --query id -o tsv)


# Find the Log Analytics workspace in the resource group
LOG_ANALYTICS_WS_ID=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[0].id" -o tsv)
if [ -z "$LOG_ANALYTICS_WS_ID" ]; then
    echo "No Log Analytics workspace found in resource group $RESOURCE_GROUP. Defender for AI cannot be enabled."
    exit 1
fi



# Check subscription-wide Defender for AI plan; skip workspace wiring if already enabled
AI_SUB_STATUS="unknown"
AI_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01"
AI_JSON=$(az rest --method GET --url "$AI_URL" --only-show-errors 2>/dev/null || true)
if echo "$AI_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    AI_SUB_STATUS="already enabled"
    AI_PLAN_ENABLED=1
else
    AI_SUB_STATUS="not enabled"
    AI_PLAN_ENABLED=0
fi

# Enable Defender for AI on OpenAI resources (only if not already enabled at subscription)
OPENAI_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.CognitiveServices/accounts" --query "[?kind=='OpenAI'].name" -o tsv)
OPENAI_STATUS="➖"
if [ "$AI_PLAN_ENABLED" -eq 1 ]; then
    OPENAI_STATUS="✅ (subscription)"
else
for openai in $OPENAI_RESOURCES; do
    echo "Checking Defender for AI on OpenAI resource: $openai"
    current_ws=$(az security workspace-setting list --query "[?name=='default'].workspaceId" -o tsv)
    if [ "$current_ws" = "$LOG_ANALYTICS_WS_ID" ]; then
        echo "Defender for AI already enabled for $openai."
        OPENAI_STATUS="✅"
    else
        echo "Enabling Defender for AI on OpenAI resource: $openai"
        if az security workspace-setting create --name "default" --target-workspace "$LOG_ANALYTICS_WS_ID"; then
            OPENAI_STATUS="✅"
        else
            OPENAI_STATUS="❌"
        fi
    fi
done
fi
# Check subscription-wide Defender for Storage plan; skip per-account if already enabled
STORAGE_SUB_STATUS="unknown"
STG_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01"
STG_JSON=$(az rest --method GET --url "$STG_URL" --only-show-errors 2>/dev/null || true)
if echo "$STG_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    STORAGE_SUB_STATUS="already enabled"
    STORAGE_PLAN_ENABLED=1
else
    STORAGE_SUB_STATUS="not enabled"
    STORAGE_PLAN_ENABLED=0
fi

# Enable Defender for Storage at the storage account level using ARM API (only if not subscription-wide enabled)
STORAGE_ACCOUNTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].name" -o tsv)
declare -A STORAGE_RESULTS
if [ "${STORAGE_PLAN_ENABLED:-0}" -eq 1 ]; then
    STORAGE_SUB_MARK="✅"
else
    for sa in $STORAGE_ACCOUNTS; do
        echo "Enabling Defender for Storage (with advanced settings) on account: $sa"
        url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${sa}/providers/Microsoft.Security/defenderForStorageSettings/current?api-version=2025-01-01"
        body='{ "properties": { "isEnabled": true, "overrideSubscriptionLevelSettings": true, "malwareScanning": { "onUpload": { "isEnabled": true } }, "sensitiveDataDiscovery": { "isEnabled": true } } }'
        if az rest --method PUT --url "$url" --body "$body" --headers "Content-Type=application/json"; then
            STORAGE_RESULTS[$sa]="✅"
        else
            echo "Failed to enable Defender for Storage on $sa."
            STORAGE_RESULTS[$sa]="❌"
        fi
    done
fi


# Summary of protections (will be displayed after optional Defender plan prompts)
print_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Security Protections Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "- Azure Front Door + WAF: ${AFD_STATUS:-➖}"
    echo "- Defender for AI (subscription): $( [ "$AI_PLAN_ENABLED" -eq 1 ] && echo "✅ already enabled" || echo "❌ not enabled" )"
    echo "- Defender for AI (OpenAI): $OPENAI_STATUS"
    if [ "${STORAGE_PLAN_ENABLED:-0}" -eq 1 ]; then
        echo "- Defender for Storage (subscription): ✅ already enabled"
    else
        echo "- Defender for Storage (per account):"
        for sa in "${!STORAGE_RESULTS[@]}"; do
            echo "    - $sa: ${STORAGE_RESULTS[$sa]}"
        done
    fi
}

# Optional: subscription-wide Defender plans with prompt and state tracking
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.defender_state.env"
YELLOW='\033[1;33m'; NC='\033[0m'

# Check AppServices plan status at subscription scope
APPSVC_SUB_STATUS="skipped"
APPSVC_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/AppServices?api-version=2024-01-01"
APPSVC_JSON=$(az rest --method GET --url "$APPSVC_URL" --only-show-errors 2>/dev/null || true)
if echo "$APPSVC_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    APPSVC_SUB_STATUS="already enabled"
else
    echo -e "${YELLOW}Warning:${NC} Defender for App Services is not enabled at subscription scope. This plan cannot be scoped to resource group."
    read -r -p "Enable Defender for App Services subscription-wide now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        body='{ "properties": { "pricingTier": "Standard" } }'
        if az rest --method PUT --url "$APPSVC_URL" --body "$body" --headers "Content-Type=application/json"; then
            APPSVC_SUB_STATUS="enabled now"
            APPSERVICES_CHANGED=1
        else
            APPSVC_SUB_STATUS="failed"
        fi
    fi
fi

# Check CosmosDbs plan status at subscription scope
COSMOS_SUB_STATUS="skipped"
COSMOS_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Security/pricings/CosmosDbs?api-version=2024-01-01"
COSMOS_JSON=$(az rest --method GET --url "$COSMOS_URL" --only-show-errors 2>/dev/null || true)
if echo "$COSMOS_JSON" | grep -q '"pricingTier"\s*:\s*"Standard"'; then
    COSMOS_SUB_STATUS="already enabled"
else
    echo -e "${YELLOW}Warning:${NC} Defender for Cosmos DB is not enabled at subscription scope. This plan cannot be scoped to resource group."
    read -r -p "Enable Defender for Cosmos DB subscription-wide now? [y/N] " ans2
    if [[ "$ans2" =~ ^[Yy]$ ]]; then
        body='{ "properties": { "pricingTier": "Standard" } }'
        if az rest --method PUT --url "$COSMOS_URL" --body "$body" --headers "Content-Type=application/json"; then
            COSMOS_SUB_STATUS="enabled now"
            COSMOSDBS_CHANGED=1
        else
            COSMOS_SUB_STATUS="failed"
        fi
    fi
fi

# Persist state so cleanup can optionally revert
APPSERVICES_CHANGED=${APPSERVICES_CHANGED:-0}
COSMOSDBS_CHANGED=${COSMOSDBS_CHANGED:-0}
if [ "$APPSERVICES_CHANGED" = "1" ] || [ "$COSMOSDBS_CHANGED" = "1" ]; then
    {
        echo "# Auto-generated by azureAISecurityDeploy.sh"
        echo "SUBSCRIPTION_ID=\"$SUBSCRIPTION_ID\""
        echo "APPSERVICES_CHANGED=\"$APPSERVICES_CHANGED\""
        echo "COSMOSDBS_CHANGED=\"$COSMOSDBS_CHANGED\""
    } > "$STATE_FILE"
    echo "Recorded subscription-wide Defender changes to $STATE_FILE"
fi

APPSVC_MARK="➖"; [ "$APPSVC_SUB_STATUS" = "already enabled" ] && APPSVC_MARK="✅"; [ "$APPSVC_SUB_STATUS" = "enabled now" ] && APPSVC_MARK="✅"; [ "$APPSVC_SUB_STATUS" = "failed" ] && APPSVC_MARK="❌"
COSMOS_MARK="➖"; [ "$COSMOS_SUB_STATUS" = "already enabled" ] && COSMOS_MARK="✅"; [ "$COSMOS_SUB_STATUS" = "enabled now" ] && COSMOS_MARK="✅"; [ "$COSMOS_SUB_STATUS" = "failed" ] && COSMOS_MARK="❌"
echo "- Defender plan (App Services) at subscription: $APPSVC_MARK $APPSVC_SUB_STATUS"
echo "- Defender plan (Cosmos DBs) at subscription: $COSMOS_MARK $COSMOS_SUB_STATUS"

# Print comprehensive summary
print_summary
AFD_STATUS="➖"
AFD_PROFILE_NAME="fd-${RESOURCE_GROUP}"
AFD_ENDPOINT_NAME="endpoint-${RESOURCE_GROUP}"
AFD_ORIGIN_GROUP_NAME="appservice-origin-group"
AFD_ROUTE_NAME="default-route"
AFD_WAF_POLICY_NAME="waf${RESOURCE_GROUP//[^a-zA-Z0-9]/}"  # Remove special chars for WAF policy name
AFD_SECURITY_POLICY_NAME="waf-security-policy"

echo
echo "Setting up Azure Front Door with WAF..."

# Find the App Service in the resource group
APP_SERVICE_NAME=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Web/sites" --query "[0].name" -o tsv)
if [ -z "$APP_SERVICE_NAME" ]; then
    echo "Warning: No App Service found in resource group $RESOURCE_GROUP. Skipping Front Door deployment."
    AFD_STATUS="⚠️ No App Service"
else
    APP_SERVICE_HOSTNAME="${APP_SERVICE_NAME}.azurewebsites.net"
    echo "Found App Service: $APP_SERVICE_NAME"
    
    # Get location from resource group
    LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    
    # Step 1: Create Front Door Premium profile (required for WAF)
    echo "Creating Front Door Premium profile: $AFD_PROFILE_NAME"
    AFD_PROFILE_EXISTS=$(az afd profile show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --query id -o tsv 2>/dev/null || true)
    if [ -z "$AFD_PROFILE_EXISTS" ]; then
        if az afd profile create \
            --profile-name "$AFD_PROFILE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --sku Premium_AzureFrontDoor \
            --only-show-errors; then
            echo "Front Door profile created successfully."
        else
            echo "Failed to create Front Door profile."
            AFD_STATUS="❌"
        fi
    else
        echo "Front Door profile already exists."
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 2: Create WAF policy using ARM API
        echo "Creating WAF policy: $AFD_WAF_POLICY_NAME"
        WAF_POLICY_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/frontdoorwebapplicationfirewallpolicies/${AFD_WAF_POLICY_NAME}?api-version=2024-02-01"
        WAF_POLICY_BODY=$(cat <<EOF
{
  "location": "Global",
  "sku": {
    "name": "Premium_AzureFrontDoor"
  },
  "properties": {
    "policySettings": {
      "enabledState": "Enabled",
      "mode": "Prevention",
      "requestBodyCheck": "Enabled"
    },
    "managedRules": {
      "managedRuleSets": [
        {
          "ruleSetType": "Microsoft_DefaultRuleSet",
          "ruleSetVersion": "2.1",
          "ruleSetAction": "Block"
        },
        {
          "ruleSetType": "Microsoft_BotManagerRuleSet",
          "ruleSetVersion": "1.0"
        }
      ]
    }
  }
}
EOF
)
        if az rest --method PUT --url "$WAF_POLICY_URL" --body "$WAF_POLICY_BODY" --headers "Content-Type=application/json" --only-show-errors; then
            echo "WAF policy created successfully."
        else
            echo "Failed to create WAF policy."
            AFD_STATUS="❌"
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 3: Create AFD endpoint
        echo "Creating Front Door endpoint: $AFD_ENDPOINT_NAME"
        AFD_ENDPOINT_EXISTS=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --endpoint-name "$AFD_ENDPOINT_NAME" --query id -o tsv 2>/dev/null || true)
        if [ -z "$AFD_ENDPOINT_EXISTS" ]; then
            if az afd endpoint create \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$AFD_PROFILE_NAME" \
                --endpoint-name "$AFD_ENDPOINT_NAME" \
                --enabled-state Enabled \
                --only-show-errors; then
                echo "Front Door endpoint created successfully."
            else
                echo "Failed to create Front Door endpoint."
                AFD_STATUS="❌"
            fi
        else
            echo "Front Door endpoint already exists."
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 4: Create origin group
        echo "Creating origin group: $AFD_ORIGIN_GROUP_NAME"
        AFD_ORIGIN_GROUP_EXISTS=$(az afd origin-group show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --origin-group-name "$AFD_ORIGIN_GROUP_NAME" --query id -o tsv 2>/dev/null || true)
        if [ -z "$AFD_ORIGIN_GROUP_EXISTS" ]; then
            if az afd origin-group create \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$AFD_PROFILE_NAME" \
                --origin-group-name "$AFD_ORIGIN_GROUP_NAME" \
                --probe-request-type GET \
                --probe-protocol Https \
                --probe-interval-in-seconds 120 \
                --probe-path / \
                --sample-size 4 \
                --successful-samples-required 3 \
                --additional-latency-in-milliseconds 50 \
                --only-show-errors; then
                echo "Origin group created successfully."
            else
                echo "Failed to create origin group."
                AFD_STATUS="❌"
            fi
        else
            echo "Origin group already exists."
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 5: Create origin (App Service)
        echo "Creating origin for App Service: $APP_SERVICE_HOSTNAME"
        AFD_ORIGIN_EXISTS=$(az afd origin show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --origin-group-name "$AFD_ORIGIN_GROUP_NAME" --origin-name appservice-origin --query id -o tsv 2>/dev/null || true)
        if [ -z "$AFD_ORIGIN_EXISTS" ]; then
            if az afd origin create \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$AFD_PROFILE_NAME" \
                --origin-group-name "$AFD_ORIGIN_GROUP_NAME" \
                --origin-name appservice-origin \
                --host-name "$APP_SERVICE_HOSTNAME" \
                --origin-host-header "$APP_SERVICE_HOSTNAME" \
                --priority 1 \
                --weight 1000 \
                --enabled-state Enabled \
                --http-port 80 \
                --https-port 443 \
                --only-show-errors; then
                echo "Origin created successfully."
            else
                echo "Failed to create origin."
                AFD_STATUS="❌"
            fi
        else
            echo "Origin already exists."
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 6: Create route
        echo "Creating route: $AFD_ROUTE_NAME"
        AFD_ROUTE_EXISTS=$(az afd route show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --endpoint-name "$AFD_ENDPOINT_NAME" --route-name "$AFD_ROUTE_NAME" --query id -o tsv 2>/dev/null || true)
        if [ -z "$AFD_ROUTE_EXISTS" ]; then
            if az afd route create \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$AFD_PROFILE_NAME" \
                --endpoint-name "$AFD_ENDPOINT_NAME" \
                --route-name "$AFD_ROUTE_NAME" \
                --origin-group "$AFD_ORIGIN_GROUP_NAME" \
                --supported-protocols Https Http \
                --link-to-default-domain Enabled \
                --https-redirect Enabled \
                --forwarding-protocol HttpsOnly \
                --patterns-to-match "/*" \
                --only-show-errors; then
                echo "Route created successfully."
            else
                echo "Failed to create route."
                AFD_STATUS="❌"
            fi
        else
            echo "Route already exists."
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 7: Associate WAF policy with endpoint using security policy
        echo "Associating WAF policy with endpoint..."
        AFD_ENDPOINT_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${AFD_PROFILE_NAME}/afdEndpoints/${AFD_ENDPOINT_NAME}"
        WAF_POLICY_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/frontdoorwebapplicationfirewallpolicies/${AFD_WAF_POLICY_NAME}"
        
        AFD_SECURITY_POLICY_EXISTS=$(az afd security-policy show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --security-policy-name "$AFD_SECURITY_POLICY_NAME" --query id -o tsv 2>/dev/null || true)
        if [ -z "$AFD_SECURITY_POLICY_EXISTS" ]; then
            if az afd security-policy create \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$AFD_PROFILE_NAME" \
                --security-policy-name "$AFD_SECURITY_POLICY_NAME" \
                --domains "$AFD_ENDPOINT_ID" \
                --waf-policy "$WAF_POLICY_ID" \
                --only-show-errors; then
                echo "WAF policy associated with endpoint successfully."
            else
                echo "Failed to associate WAF policy with endpoint."
                AFD_STATUS="❌"
            fi
        else
            echo "Security policy already exists."
        fi
    fi
    
    if [ "$AFD_STATUS" != "❌" ]; then
        # Step 8: Configure App Service to trust Front Door headers and prevent direct access
        echo "Configuring App Service for Front Door integration..."
        
        # Get the Front Door ID for access restriction
        AFD_PROFILE_ID=$(az afd profile show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --query id -o tsv)
        
        # Configure App Service to trust X-Forwarded-For headers from Front Door
        # Set AZURE_FRONTDOOR_ID to enable Front Door integration
        if az webapp config appsettings set \
            --name "$APP_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --settings "AZURE_FRONTDOOR_ID=${AFD_PROFILE_ID}" \
            --only-show-errors >/dev/null 2>&1; then
            echo "App Service configured to trust Front Door headers."
        else
            echo "Warning: Could not configure App Service settings for Front Door."
        fi
        
        # Configure App Service access restrictions to only allow traffic from Front Door
        # This prevents direct access to the App Service bypassing the WAF
        echo "Restricting App Service access to Front Door only..."
        
        # Get current access restrictions
        CURRENT_RESTRICTIONS=$(az webapp config access-restriction show \
            --name "$APP_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "ipSecurityRestrictions" -o json 2>/dev/null || echo "[]")
        
        # Check if Front Door rule already exists
        if echo "$CURRENT_RESTRICTIONS" | grep -q "AllowFrontDoor"; then
            echo "Front Door access restriction already configured."
        else
            # Add access restriction rule
            if az webapp config access-restriction add \
                --name "$APP_SERVICE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --rule-name "AllowFrontDoor" \
                --action Allow \
                --service-tag AzureFrontDoor.Backend \
                --priority 100 \
                --only-show-errors; then
                echo "Access restriction configured: only Front Door can access App Service."
            else
                echo "Warning: Could not configure access restrictions. App Service may be accessible directly."
            fi
        fi
        
        # Get Front Door endpoint URL
        AFD_ENDPOINT_URL=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$AFD_PROFILE_NAME" --endpoint-name "$AFD_ENDPOINT_NAME" --query "hostName" -o tsv)
        AFD_STATUS="✅"
        echo
        echo "Azure Front Door deployment complete!"
        echo "Front Door URL: https://${AFD_ENDPOINT_URL}"
        echo "⚠️  Please use the Front Door URL to access your application."
        echo "⚠️  Direct access to App Service URL is now restricted."
    fi
fi

echo
echo "All specified security features have been attempted for resources in $RESOURCE_GROUP."
