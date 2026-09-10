#!/usr/bin/env bash
set -euo pipefail

# Recover only resources named by this azd environment. Never purge by type alone.
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-}"
if [[ -z "$RESOURCE_GROUP_NAME" && -n "${AZURE_ENV_NAME:-}" ]]; then
  RESOURCE_GROUP_NAME="rg-${AZURE_ENV_NAME}"
fi
OPENAI_NAME="${AZURE_OPENAI_SERVICE:-}"
FOUNDRY_NAME="${AI_FOUNDRY_ACCOUNT_NAME:-}"
APIM_NAME="${APIM_SERVICE_NAME:-}"

if [[ -z "$OPENAI_NAME" && -z "$FOUNDRY_NAME" && -z "$APIM_NAME" ]]; then
  echo "No environment-scoped soft-delete names are available; skipping recovery."
  exit 0
fi

DELETED_COGNITIVE_SERVICES=$(az cognitiveservices account list-deleted \
  --subscription "$SUBSCRIPTION_ID" -o json)

for NAME in "$OPENAI_NAME" "$FOUNDRY_NAME"; do
  [[ -z "$NAME" ]] && continue

  LOCATION=$(printf '%s' "$DELETED_COGNITIVE_SERVICES" | jq -r --arg name "$NAME" \
    '.[] | select(.name == $name) | .location' | head -n 1)

  if [[ "$NAME" == "$OPENAI_NAME" ]]; then
    if [[ -n "$LOCATION" && "$LOCATION" != "null" ]]; then
      echo "Soft-deleted Azure OpenAI found: $NAME. Enabling restore for this deployment."
      azd env set restoreSoftDeletedOpenAi true
    else
      echo "Azure OpenAI is not soft-deleted: $NAME. Disabling restore mode."
      azd env set restoreSoftDeletedOpenAi false
    fi
  else
    [[ -z "$LOCATION" || "$LOCATION" == "null" ]] && continue
    echo "Purging soft-deleted Foundry account: $NAME"
    az cognitiveservices account purge \
      --name "$NAME" \
      --resource-group "$RESOURCE_GROUP_NAME" \
      --location "$LOCATION" \
      --subscription "$SUBSCRIPTION_ID" \
      --output none
  fi
done

# AI Foundry uses an Azure Machine Learning workspace underneath. Its soft-delete
# state is not returned by the Cognitive Services deleted-account list.
if [[ -n "$FOUNDRY_NAME" && -n "$RESOURCE_GROUP_NAME" ]]; then
  AML_WORKSPACE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.MachineLearningServices/workspaces/${FOUNDRY_NAME}"
  if ! az resource show --ids "$AML_WORKSPACE_ID" --only-show-errors -o none 2>/dev/null; then
    echo "Purging soft-deleted Foundry workspace: $FOUNDRY_NAME"
    az rest --method delete \
      --uri "https://management.azure.com${AML_WORKSPACE_ID}?api-version=2024-04-01&forceToPurge=true" \
      --output none 2>/dev/null || true
  fi
fi

DELETED_APIM=$(az apim deletedservice list --subscription "$SUBSCRIPTION_ID" -o json)
APIM_LOCATION=$(printf '%s' "$DELETED_APIM" | jq -r --arg name "$APIM_NAME" \
  '.[] | select(.name == $name) | .location' | head -n 1)
if [[ -n "$APIM_NAME" && -n "$APIM_LOCATION" && "$APIM_LOCATION" != "null" ]]; then
  echo "Purging soft-deleted API Management service: $APIM_NAME"
  az apim deletedservice purge \
    --service-name "$APIM_NAME" \
    --location "$APIM_LOCATION" \
    --subscription "$SUBSCRIPTION_ID"
fi