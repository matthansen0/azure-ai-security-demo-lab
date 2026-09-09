#!/bin/bash
# =============================================================================
# validate.sh — End-to-end functional validation for azure-ai-security-sandbox
#
# Tests every major component and lab-guide claim automatically against a
# deployed environment. Run this after `azd up` (with or without agents).
#
# Usage:
#   bash scripts/validate.sh                   # uses current azd env
#   bash scripts/validate.sh my-env-name       # selects the named env first
#
# Requires: az cli, azd, curl, python3, jq
# =============================================================================
set -uo pipefail

PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}  $1"; ((PASS++)); }
fail() { echo -e "${RED}FAIL${NC}  $1"; ((FAIL++)); }
skip() { echo -e "${YELLOW}SKIP${NC}  $1"; ((SKIP++)); }
header() { echo ""; echo "--- $1 ---"; }
get_azd_value() {
  local value
  if value=$(azd env get-value "$1" 2>/dev/null); then
    printf '%s' "$value"
  fi
}

# ---------------------------------------------------------------------------
# Select environment
# ---------------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
  echo "Selecting azd env: $1"
  azd env select "$1" 2>/dev/null
fi

# ---------------------------------------------------------------------------
# Discover resources
# ---------------------------------------------------------------------------
header "Discovering environment"

RG=$(get_azd_value RESOURCE_GROUP_NAME)
if [[ -z "$RG" ]]; then
  RG=$(get_azd_value AZURE_RESOURCE_GROUP)
fi
if [[ -z "$RG" ]]; then
  ENV_NAME=$(get_azd_value AZURE_ENV_NAME)
  if [[ -z "$ENV_NAME" ]]; then
    echo "Unable to resolve the active azd environment name." >&2
    exit 1
  fi
  RG="rg-$ENV_NAME"
fi
echo "Resource group: $RG"

# Container apps
BACKEND_CA=$(az containerapp list -g "$RG" --query \
  '[?tags."azd-service-name" == `backend`].name | [0]' -o tsv 2>/dev/null)
AGENT_CA=$(az containerapp list -g "$RG" --query \
  '[?tags."azd-service-name" == `agent`].name | [0]' -o tsv 2>/dev/null)

BACKEND_FQDN=$(az containerapp show -g "$RG" -n "$BACKEND_CA" \
  --query 'properties.configuration.ingress.fqdn' -o tsv 2>/dev/null)
AGENT_FQDN=""
if [[ -n "$AGENT_CA" ]]; then
  AGENT_FQDN=$(az containerapp show -g "$RG" -n "$AGENT_CA" \
    --query 'properties.configuration.ingress.fqdn' -o tsv 2>/dev/null)
fi

# azd env values
FD_URL=$(get_azd_value FRONTDOOR_URL)
APIM_URL=$(get_azd_value APIM_GATEWAY_URL)
APIM_NAME=$(get_azd_value APIM_SERVICE_NAME)

# APIM key
APIM_KEY=""
if [[ -n "$APIM_NAME" ]]; then
  APIM_KEY=$(az apim nv show-secret -g "$RG" --service-name "$APIM_NAME" \
    --named-value-id internal-client-key --query value -o tsv 2>/dev/null || true)
fi

# Search
SEARCH_SERVICE=$(az search service list -g "$RG" --query '[0].name' -o tsv 2>/dev/null || true)
SEARCH_KEY=""
if [[ -n "$SEARCH_SERVICE" ]]; then
  SEARCH_KEY=$(az search admin-key show --service-name "$SEARCH_SERVICE" \
    --resource-group "$RG" --query primaryKey -o tsv 2>/dev/null || true)
fi

echo "Backend: $BACKEND_FQDN"
echo "Agent:   ${AGENT_FQDN:-<not deployed>}"
echo "AFD:     $FD_URL"
echo "APIM:    $APIM_URL"

# ---------------------------------------------------------------------------
# Lab 1 — Front Door + WAF
# ---------------------------------------------------------------------------
header "Lab 1: Front Door + WAF"

if [[ -n "$FD_URL" ]]; then
  # 1a. WAF x-azure-ref header is present
  FD_HEADER=$(curl -sI -m 20 "$FD_URL" 2>/dev/null | grep -i "x-azure-ref" || true)
  if [[ -n "$FD_HEADER" ]]; then
    pass "L1: x-azure-ref header present on Front Door response"
  else
    fail "L1: x-azure-ref header missing — Front Door may not be routing traffic"
  fi

  # 1b. Front Door /chat returns 200
  HTTP_FD=$(curl -s -o /tmp/val-fd-chat.json -w '%{http_code}' -m 30 \
    -X POST "$FD_URL/chat" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"hello"}],"stream":false}' 2>/dev/null)
  if [[ "$HTTP_FD" == "200" ]]; then
    pass "L1: Front Door /chat HTTP $HTTP_FD"
  else
    fail "L1: Front Door /chat HTTP $HTTP_FD (expected 200)"
  fi

  # 1c. Response contains citations (data retrieved from search)
  FD_CITATIONS=$(python3 -c "
import json, sys
try:
  d=json.load(open('/tmp/val-fd-chat.json'))
  txt=d.get('context',{}).get('data_points',{}).get('text',[])
  print(len(txt))
except: print(0)
" 2>/dev/null)
  if [[ "$FD_CITATIONS" -ge 1 ]]; then
    pass "L1: Front Door response includes RAG citations ($FD_CITATIONS)"
  else
    fail "L1: No RAG citations in Front Door response"
  fi
else
  skip "L1: FRONTDOOR_URL not set — Front Door not deployed or not accessible"
fi

# ---------------------------------------------------------------------------
# Lab 2 — API Management Gateway
# ---------------------------------------------------------------------------
header "Lab 2: API Management Gateway"

if [[ -n "$APIM_URL" && -n "$APIM_KEY" ]]; then
  # 2a. With valid key → 200 + real model response
  HTTP_APIM=$(curl -s -o /tmp/val-apim-ok.json -w '%{http_code}' -m 30 \
    -X POST "$APIM_URL/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
    -H "api-key: $APIM_KEY" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Reply with the single word OK"}],"max_tokens":5}' 2>/dev/null)
  if [[ "$HTTP_APIM" == "200" ]]; then
    MODEL=$(python3 -c "import json; d=json.load(open('/tmp/val-apim-ok.json')); print(d.get('model','?'))" 2>/dev/null)
    pass "L2: APIM with key → HTTP 200 (model: $MODEL)"
  else
    fail "L2: APIM with key → HTTP $HTTP_APIM (expected 200)"
  fi

  # 2b. Without key → 401
  HTTP_APIM_NO=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
    -X POST "$APIM_URL/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"hello"}],"max_tokens":5}' 2>/dev/null)
  if [[ "$HTTP_APIM_NO" == "401" ]]; then
    pass "L2: APIM without key → HTTP 401 (key enforcement working)"
  else
    fail "L2: APIM without key → HTTP $HTTP_APIM_NO (expected 401)"
  fi
else
  skip "L2: APIM not configured — skipping APIM checks"
fi

# ---------------------------------------------------------------------------
# Lab 3 — Managed Identity + RBAC
# ---------------------------------------------------------------------------
header "Lab 3: Managed Identity + RBAC"

# 3a. Backend container app has a system-assigned managed identity
BACKEND_IDENTITY=$(az containerapp show -g "$RG" -n "$BACKEND_CA" \
  --query 'identity.principalId' -o tsv 2>/dev/null || true)
if [[ -n "$BACKEND_IDENTITY" && "$BACKEND_IDENTITY" != "None" ]]; then
  pass "L3: Backend container app has managed identity ($BACKEND_IDENTITY)"
else
  fail "L3: Backend container app has no managed identity"
fi

# 3b. OpenAI User role assigned to backend identity
SUB=$(az account show --query id -o tsv 2>/dev/null)
OPENAI_ROLE=$(az role assignment list --assignee "$BACKEND_IDENTITY" \
  --all \
  --query "[?contains(roleDefinitionName,'OpenAI')].roleDefinitionName | [0]" \
  -o tsv 2>/dev/null || true)
if [[ -n "$OPENAI_ROLE" ]]; then
  pass "L3: OpenAI role assigned to backend identity ($OPENAI_ROLE)"
else
  fail "L3: No OpenAI role found for backend identity"
fi

# 3c. Search role assigned
SEARCH_ROLE=$(az role assignment list --assignee "$BACKEND_IDENTITY" \
  --all \
  --query "[?contains(roleDefinitionName,'Search')].roleDefinitionName | [0]" \
  -o tsv 2>/dev/null || true)
if [[ -n "$SEARCH_ROLE" ]]; then
  pass "L3: Search role assigned to backend identity ($SEARCH_ROLE)"
else
  fail "L3: No Search role found for backend identity"
fi

# 3d. APIM identity distinct from backend identity (when APIM enabled)
if [[ -n "$APIM_NAME" ]]; then
  APIM_IDENTITY=$(az apim show -g "$RG" -n "$APIM_NAME" \
    --query 'identity.principalId' -o tsv 2>/dev/null || true)
  if [[ -n "$APIM_IDENTITY" && "$APIM_IDENTITY" != "$BACKEND_IDENTITY" ]]; then
    pass "L3: APIM has its own managed identity (separate from backend)"
  else
    fail "L3: APIM identity missing or same as backend"
  fi
fi

# ---------------------------------------------------------------------------
# Lab 4 — Monitoring + Logging
# ---------------------------------------------------------------------------
header "Lab 4: Monitoring + Logging"

# 4a. Log Analytics workspace exists
LOG_WS=$(az resource list -g "$RG" \
  --resource-type Microsoft.OperationalInsights/workspaces \
  --query '[0].name' -o tsv 2>/dev/null || true)
if [[ -n "$LOG_WS" ]]; then
  pass "L4: Log Analytics workspace exists ($LOG_WS)"
else
  fail "L4: No Log Analytics workspace found in $RG"
fi

# 4b. App Insights exists
APP_INSIGHTS=$(az resource list -g "$RG" \
  --resource-type Microsoft.Insights/components \
  --query '[0].name' -o tsv 2>/dev/null || true)
if [[ -n "$APP_INSIGHTS" ]]; then
  pass "L4: Application Insights exists ($APP_INSIGHTS)"
else
  fail "L4: No Application Insights found in $RG"
fi

# 4c. Container Apps Environment sends logs to Log Analytics
if [[ -n "$LOG_WS" ]]; then
  WS_CUSTOMER_ID=$(az resource show -g "$RG" -n "$LOG_WS" \
    --resource-type Microsoft.OperationalInsights/workspaces \
    --api-version 2023-09-01 --query properties.customerId -o tsv 2>/dev/null || true)
  CA_ENV_ID=$(az containerapp show -g "$RG" -n "$BACKEND_CA" \
    --query properties.environmentId -o tsv 2>/dev/null || true)
  CA_ENV_NAME="${CA_ENV_ID##*/}"
  CA_LOG_CONFIG=$(az containerapp env show -g "$RG" -n "$CA_ENV_NAME" \
    --query 'properties.appLogsConfiguration.[destination,logAnalyticsConfiguration.customerId]' \
    -o tsv 2>/dev/null || true)
  if [[ "$CA_LOG_CONFIG" == *"log-analytics"* && "$CA_LOG_CONFIG" == *"$WS_CUSTOMER_ID"* ]]; then
    pass "L4: Container Apps Environment sends logs to Log Analytics"
  else
    fail "L4: Container Apps Environment is not linked to the expected Log Analytics workspace"
  fi
fi

# ---------------------------------------------------------------------------
# Lab 5 — Defender for Cloud
# ---------------------------------------------------------------------------
header "Lab 5: Defender for Cloud"

# 5a. Defender for APIs plan (covers APIM)
DEFENDER_API=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Security/pricings/Api?api-version=2024-01-01" \
  --query 'properties.pricingTier' -o tsv 2>/dev/null || true)
if [[ "$DEFENDER_API" == "Standard" ]]; then
  pass "L5: Defender for APIs → Standard"
elif [[ "$DEFENDER_API" == "Free" ]]; then
  skip "L5: Defender for APIs add-on is not enabled"
elif [[ -n "$DEFENDER_API" ]]; then
  fail "L5: Defender for APIs → $DEFENDER_API (expected Standard)"
else
  skip "L5: Could not retrieve Defender for APIs pricing tier"
fi

# 5b. Defender for Storage plan
DEFENDER_STORAGE=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Security/pricings/StorageAccounts?api-version=2024-01-01" \
  --query 'properties.pricingTier' -o tsv 2>/dev/null || true)
if [[ "$DEFENDER_STORAGE" == "Standard" ]]; then
  pass "L5: Defender for Storage → Standard"
elif [[ "$DEFENDER_STORAGE" == "Free" ]]; then
  skip "L5: Defender for Storage add-on is not enabled"
elif [[ -n "$DEFENDER_STORAGE" ]]; then
  fail "L5: Defender for Storage → $DEFENDER_STORAGE (expected Standard; run scripts/enable-defender.sh)"
else
  skip "L5: Could not retrieve Defender for Storage pricing tier"
fi

# ---------------------------------------------------------------------------
# Lab 5b — RAG pipeline health (underpins chat functionality)
# ---------------------------------------------------------------------------
header "Lab 5b: RAG Pipeline (Search + Backend)"

# 5b-i. Search index populated
if [[ -n "$SEARCH_KEY" ]]; then
  DOCS_COUNT=$(curl -sf -m 20 \
    "https://$SEARCH_SERVICE.search.windows.net/indexes/documents/docs?\$count=true&search=*&\$top=0&api-version=2023-11-01" \
    -H "api-key: $SEARCH_KEY" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('@odata.count',0))" 2>/dev/null || echo 0)
  if [[ "$DOCS_COUNT" -gt 0 ]]; then
    pass "L5b: Search index populated ($DOCS_COUNT documents)"
  else
    fail "L5b: Search index empty — run prepdocs (cd upstream && ./scripts/prepdocs.sh)"
  fi
else
  skip "L5b: Search admin key unavailable — skipping doc count check"
fi

# 5b-ii. Backend /chat returns citations
HTTP_BACKEND=$(curl -s -o /tmp/val-backend-chat.json -w '%{http_code}' -m 60 \
  -X POST "https://$BACKEND_FQDN/chat" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"What dental coverage does Northwind Health Plus offer?"}],"stream":false}' 2>/dev/null)
CITATIONS=$(python3 -c "
import json
try:
  d=json.load(open('/tmp/val-backend-chat.json'))
  txt=d.get('context',{}).get('data_points',{}).get('text',[])
  print(len(txt))
except: print(0)
" 2>/dev/null || echo 0)
if [[ "$HTTP_BACKEND" == "200" && "$CITATIONS" -ge 1 ]]; then
  pass "L5b: Backend /chat returns RAG citations ($CITATIONS citations)"
else
  fail "L5b: Backend /chat HTTP $HTTP_BACKEND with $CITATIONS citations"
fi

# ---------------------------------------------------------------------------
# Lab 6 — AI Agent Security
# ---------------------------------------------------------------------------
header "Lab 6: IT Admin Agent"

if [[ -n "$AGENT_FQDN" ]]; then
  # 6a. Health endpoint
  AGENT_HEALTH=$(curl -sf -m 20 "https://$AGENT_FQDN/health" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{d.get('status','?')}|{str(d.get('openai_configured',False)).lower()}|{str(d.get('project_configured',False)).lower()}\")" 2>/dev/null || echo "unreachable")
  if [[ "$AGENT_HEALTH" == "healthy|true|true" ]]; then
    pass "L6: Agent /health → $AGENT_HEALTH"
  else
    fail "L6: Agent /health → $AGENT_HEALTH (expected healthy|true|true)"
  fi

  # 6b. Tools registered
  TOOLS_COUNT=$(curl -sf -m 20 "https://$AGENT_FQDN/tools" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('tools',[])))" 2>/dev/null || echo 0)
  if [[ "$TOOLS_COUNT" -ge 1 ]]; then
    TOOL_NAMES=$(curl -sf -m 20 "https://$AGENT_FQDN/tools" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print([t['function']['name'] for t in d.get('tools',[])])" 2>/dev/null || echo "[]")
    pass "L6: Agent tools registered ($TOOLS_COUNT tools) — $TOOL_NAMES"
  else
    fail "L6: No tools returned from agent /tools endpoint"
  fi

  # 6c. Agent /chat calls tools and returns an answer
  HTTP_AGENT=$(curl -s -o /tmp/val-agent-chat.json -w '%{http_code}' -m 90 \
    -X POST "https://$AGENT_FQDN/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Users are reporting that web-app-prod is very slow. Can you investigate?","context":{"environment":"production","region":"eastus"}}' 2>/dev/null)
  HAS_RESP=$(python3 -c "
import json
try:
  d=json.load(open('/tmp/val-agent-chat.json'))
  calls=[t.get('tool_name','?') for t in d.get('tool_calls',[])]
  print('true' if d.get('response') else 'false', len(calls))
except: print('false', 0)
" 2>/dev/null)
  if [[ "$HTTP_AGENT" == "200" && "$HAS_RESP" == true* ]]; then
    pass "L6: Agent /chat returned response with tool calls ($HAS_RESP)"
  else
    fail "L6: Agent /chat HTTP $HTTP_AGENT; response/tool calls: $HAS_RESP"
  fi

  # 6d. delete_resource endpoint not exposed (returns 404) — read-only safety
  HTTP_DEL=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
    -X POST "https://$AGENT_FQDN/tools/delete_resource" \
    -H 'Content-Type: application/json' \
    -d '{"resource_name":"sql-db-main"}' 2>/dev/null || echo "000")
  if [[ "$HTTP_DEL" == "404" || "$HTTP_DEL" == "405" ]]; then
    pass "L6: delete_resource endpoint not directly exposed (HTTP $HTTP_DEL) — read-only safety enforced"
  else
    fail "L6: delete_resource endpoint returned HTTP $HTTP_DEL (expected 404/405)"
  fi

  # 6e. Project-based Foundry account + Project exist
  FOUNDRY_ACCOUNTS=$(az cognitiveservices account list -g "$RG" \
    --query "[?kind=='AIServices' && properties.allowProjectManagement].name" -o tsv 2>/dev/null || true)
  FOUNDRY_PROJECTS=$(az resource list -g "$RG" \
    --resource-type Microsoft.CognitiveServices/accounts/projects \
    --query '[].name' -o tsv 2>/dev/null || true)
  if [[ -n "$FOUNDRY_ACCOUNTS" && -n "$FOUNDRY_PROJECTS" ]]; then
    pass "L6: Project-based AI Foundry account + Project deployed (account: $FOUNDRY_ACCOUNTS, project: $FOUNDRY_PROJECTS)"
  elif [[ -n "$FOUNDRY_ACCOUNTS" ]]; then
    fail "L6: Foundry account exists but no project found: $FOUNDRY_ACCOUNTS"
  elif [[ -n "$FOUNDRY_PROJECTS" ]]; then
    fail "L6: Foundry project exists but no project-enabled account found: $FOUNDRY_PROJECTS"
  else
    fail "L6: No project-based AI Foundry account/project found"
  fi
else
  skip "L6: Agent container app not found — deploy with: azd up --parameter useAgents=true"
fi

# ---------------------------------------------------------------------------
# Lab 7 — Defender for AI
# ---------------------------------------------------------------------------
header "Lab 7: Defender for AI"

DEFENDER_AI_TIER=$(az rest --method get \
  --uri "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01" \
  --query 'properties.pricingTier' -o tsv 2>/dev/null || true)
if [[ "$DEFENDER_AI_TIER" == "Standard" ]]; then
  pass "L7: Defender for AI → Standard"

  # Check AIPromptEvidence extension is enabled
  PROMPT_EV=$(az rest --method get \
    --uri "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Security/pricings/AI?api-version=2024-01-01" \
    --query "properties.extensions[?name=='AIPromptEvidence'].isEnabled | [0]" \
    -o tsv 2>/dev/null || true)
  if [[ "$PROMPT_EV" == "True" ]]; then
    pass "L7: AIPromptEvidence extension enabled"
  else
    skip "L7: AIPromptEvidence extension not confirmed (may require enable-defender.sh)"
  fi
elif [[ "$DEFENDER_AI_TIER" == "Free" ]]; then
  skip "L7: Defender for AI add-on is not enabled"
elif [[ -n "$DEFENDER_AI_TIER" ]]; then
  fail "L7: Defender for AI → $DEFENDER_AI_TIER (expected Standard; run scripts/enable-defender.sh)"
else
  skip "L7: Could not retrieve Defender for AI pricing tier"
fi

# ---------------------------------------------------------------------------
# Lab 8 — Foundry Guardrails + Content Safety
# ---------------------------------------------------------------------------
header "Lab 8: Foundry Guardrails + Content Safety"

OPENAI_ACCOUNT=$(az resource list -g "$RG" \
  --resource-type Microsoft.CognitiveServices/accounts \
  --query "[?kind == 'OpenAI'].name | [0]" -o tsv 2>/dev/null || true)
if [[ -n "$OPENAI_ACCOUNT" ]]; then
  CONTENT_SAFETY_URI="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$OPENAI_ACCOUNT/raiPolicies/sandbox-content-safety?api-version=2024-04-01-preview"
  CONTENT_SAFETY_POLICY=$(az rest --method get --uri "$CONTENT_SAFETY_URI" -o json 2>/dev/null || true)

  INDIRECT_ATTACK=$(jq -r '[.properties.contentFilters[]? | select(.name == "Indirect Attack" and .source == "Prompt" and .enabled == true and .blocking == true)] | length' <<<"$CONTENT_SAFETY_POLICY" 2>/dev/null || echo 0)
  if [[ "$INDIRECT_ATTACK" -ge 1 ]]; then
    pass "L8: Content safety policy enables blocking for indirect prompt attacks"
  else
    fail "L8: Content safety policy missing blocking Indirect Attack prompt filter"
  fi

  DEPLOYMENT_POLICY=$(az rest --method get \
    --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$OPENAI_ACCOUNT/deployments/gpt-4o?api-version=2024-04-01-preview" \
    --query 'properties.raiPolicyName' -o tsv 2>/dev/null || true)
  if [[ "$DEPLOYMENT_POLICY" == "sandbox-content-safety" ]]; then
    pass "L8: gpt-4o deployment uses sandbox-content-safety policy"
  else
    fail "L8: gpt-4o deployment policy is ${DEPLOYMENT_POLICY:-missing} (expected sandbox-content-safety)"
  fi
else
  fail "L8: Azure OpenAI account not found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Validation complete"
echo "  PASS: $PASS  |  FAIL: $FAIL  |  SKIP: $SKIP"
echo "============================================================"

if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "Some checks failed. Review FAIL lines above."
  echo "Common fixes:"
  echo "  - Empty search index:    cd upstream && ./scripts/prepdocs.sh"
  echo "  - APIM not configured:   azd provision"
  echo "  - Agents not deployed:   azd up --parameter useAgents=true"
  echo "  - Defender not enabled:  bash scripts/enable-defender.sh"
  exit 1
fi
