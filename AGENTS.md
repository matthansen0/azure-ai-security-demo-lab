# Instructions for AI Coding Agents

This file provides context for AI agents (GitHub Copilot, Claude, Cursor, etc.) working on this Azure AI Security Sandbox repository.

**Always keep this file up to date with any changes to the codebase or development process.**

## Project Purpose

This is a **security-focused reference architecture** demonstrating enterprise-grade patterns for deploying Azure OpenAI applications. It wraps the standard `azure-search-openai-demo` RAG application with production security controls.

**Key differentiator:** This is NOT just another RAG demo - it's a security sandbox showing how to properly protect AI workloads in enterprise environments.

## Architecture Overview

```
User → Azure Front Door (WAF) → Azure API Management (AI Gateway) → Container Apps → Azure OpenAI
                                         ↓
                              Azure AI Search ← Sample Data (Northwind Health PDFs)
```

### Security Layers
1. **Azure Front Door** - Global edge with WAF protection (default: Detection mode)
2. **API Management** - AI Gateway with managed identity auth + retry logic (optional rate limiting/token tracking)
3. **Container Apps** - Isolated compute with managed identity
4. **Private Endpoints** - (Optional) Network isolation for backend services
5. **RBAC** - Least-privilege role assignments, no API keys

## Code Layout

> **⚠️ Multiple Project Roots:** This workspace contains TWO project roots:
> 1. **`/` (this repo)** - Security infrastructure and configuration (edit freely)
> 2. **`/upstream/`** - Git submodule of `azure-search-openai-demo` (**read-only, do not modify**)
>
> The upstream submodule has its own `AGENTS.md` - ignore it when working on this project.

### Infrastructure (`/infra`)
- `main.bicep` - Main orchestration, parameters, outputs
- `main.parameters.json` - azd parameter mappings
- `modules/` - Modular Bicep components:
  - `ai-services.bicep` - Azure OpenAI with model deployments
  - `api-management.bicep` - **AI Gateway** with policies (auth + retry; optional rate limiting/token logging)
  - `app-service.bicep` - Container Apps environment and app
  - `container-apps.bicep` - Container Apps with managed identity
  - `container-registry.bicep` - ACR for container images
  - `cosmos-db.bicep` - Chat history storage
  - `front-door.bicep` - AFD + WAF policy
  - `monitoring.bicep` - Log Analytics + App Insights
  - `role-assignments.bicep` - RBAC for managed identities
  - `security.bicep` - DEPRECATED (Defender settings moved to add-on)
  - `subscription-security.bicep` - DEPRECATED (subscription-wide Defender plans moved to add-on)
  - `storage.bicep` - Blob storage for documents
- `modules/agents/` - **AI Agent infrastructure (optional)**:
  - `ai-foundry.bicep` - Project-based AI Foundry account + Project for Agent Service
  - `agent-api.bicep` - Container App for agent API
  - `agent-role-assignments.bicep` - RBAC for agent managed identities

### IT Admin Agent (`/agents/it-admin`)
- `app.py` - FastAPI application with agent logic
- `tools/__init__.py` - Tool definitions and mock implementations
- `Dockerfile` - Container build for agent API
- `README.md` - Agent documentation and API reference
- `tests/test_api.py` - API/unit regression tests for health, tools, chat, and safety endpoints
- `tests/test_tools.py` - Unit/regression tests for tool definitions, mock resources, and tool handlers
- `tests/conftest.py` - Shared pytest fixtures for agent API/tool tests
- **Deploy with:** `azd up --parameter useAgents=true`


### Optional Defender Add-on

This repo intentionally makes **no Defender for Cloud changes** during `azd up`. To enable Defender after deployment:

- Enable relevant Defender plans (except Defender for AI) and apply Defender for Storage advanced settings:
  - [scripts/enable-defender.sh](scripts/enable-defender.sh)
- Roll back subscription-wide plan changes made by the enable script:
  - [scripts/disable-defender.sh](scripts/disable-defender.sh)

State tracking is written locally under `.defender/` (ignored by git).

### Application (`/app`)
- `backend/Dockerfile` - Container build configuration

### Upstream Submodule (`/upstream`)
- Git submodule pointing to `azure-search-openai-demo`
- Used for prepdocs scripts and sample data
- **Do not modify files in upstream/** - it's a git submodule

> **⚠️ Container Image Build Behavior:**
> The Dockerfile clones `azure-search-openai-demo` **from GitHub at build time** - it does NOT use the local `/upstream` submodule. This means:
> - The deployed container always has the latest `main` branch code
> - Local changes to `/upstream` won't affect the deployed app
> - To understand app behavior, read `/upstream` code (it matches what's deployed)
> - To customize the app, you'd need to modify the Dockerfile to copy local code instead

### Documentation (`/docs`)
- `issues/` - Tracked issues and enhancement documentation
- `labs/` - Hands-on lab guides for exploring each security layer

## Key Files to Understand

| File | Purpose |
|------|---------|
| `azure.yaml` | azd configuration, hooks (postprovision, postdown) |
| `infra/main.bicep` | All configurable parameters live here |
| `infra/modules/api-management.bicep` | AI Gateway policies - auth + retry (optional rate limits/token logging) |
| `infra/modules/front-door.bicep` | WAF rules and mode configuration |
| `infra/modules/agents/ai-foundry.bicep` | Project-based AI Foundry account + Project for agents |
| `.github/workflows/ci.yml` | Pull-request gate for Bicep, shell, preflight, and agent tests |
| `.github/scripts/lab_rot_watch.py` | Weekly high-signal checks for lab/validator parity and confirmed broken links |
| `scripts/preflight-check.sh` | Regional Search and exact OpenAI model/SKU/quota validation |
| `scripts/prepdocs-search-only.py` | Policy-aware Search ingestion fallback when Blob public access is disabled |
| `agents/it-admin/app.py` | IT Admin Agent FastAPI application |
| `agents/it-admin/tools/__init__.py` | Agent tools + mock data |
| `docs/labs/lab-7-defender-for-ai.md` | Lab guide for Defender for AI enablement |


## Common Operations

### Deploy the Solution
```bash
azd up                           # Full deployment (no agents)
azd up --parameter useAPIM=false  # Skip APIM for faster iteration
azd up --parameter useAgents=true # Deploy with IT Admin Agent
```


### Populate Search Index
The `postprovision` hook in `azure.yaml` automatically runs prepdocs after provisioning.
It stages data outside the read-only submodule and uses `scripts/prepdocs-search-only.py` when Azure Policy disables the Storage public endpoint.
Manual run:
```bash
cd upstream && ./scripts/prepdocs.sh
```

### Validate All Functionality

Run the comprehensive end-to-end validation script after any `azd up`. It automatically discovers all resources from the active azd environment and checks every component and lab claim.

```bash
bash scripts/validate.sh
```

Or to validate a specific named environment:

```bash
bash scripts/validate.sh my-env-name
```

The script tests each lab's core claims and prints `PASS / FAIL / SKIP` for each check:

| Lab | What it validates |
|-----|-------------------|
| **Lab 1** | Front Door WAF (`x-azure-ref` header), `/chat` HTTP 200, RAG citations returned end-to-end |
| **Lab 2** | APIM with valid key → 200, APIM without key → 401 |
| **Lab 3** | Managed identity exists on backend + agent apps, correct RBAC roles assigned (OpenAI, Search, Cosmos) |
| **Lab 4** | Log Analytics workspace + App Insights exist in resource group |
| **Lab 5** | Defender for APIs + Defender for Storage at Standard tier; search index populated (758 docs); backend RAG returns citations |
| **Lab 6** | Agent `/health` healthy, 7 tools registered, `/chat` invokes tools and returns investigation response, `delete_resource` not directly exposed (read-only safety), project-based Foundry account + Project deployed |
| **Lab 7** | Defender for AI at Standard tier, AIPromptEvidence extension enabled |
| **Lab 8** | Explicit Foundry guardrail policy enables blocking for indirect prompt attacks and is bound to the `gpt-4o` deployment |

SKIP is shown for checks that require Defender enablement (`scripts/enable-defender.sh`) or optional features not deployed (e.g., agents when `useAgents=false`).

**When to run this:**
- After `azd up` to confirm a fresh environment is healthy
- After any infra change to catch regressions
- When asked to "test all functionality" or "validate the deployment"

### Run Offline CI Checks

The GitHub Actions workflow runs these checks for pull requests and pushes to `main`:

```bash
./.venv-tests/bin/python -m pytest agents/it-admin/tests -q
python .github/scripts/test_lab_rot_watch.py
bash scripts/tests/preflight-check.test.sh
bash -n scripts/*.sh scripts/tests/*.sh
python -m py_compile scripts/prepdocs-search-only.py .github/scripts/lab_rot_watch.py
az bicep build --file infra/main.bicep --outfile /tmp/azure-ai-security-sandbox-main.json
```

The weekly lab-rot watcher is intentionally limited to reproducible learner-facing failures. API-version age, mutable dependency policy, image digest pinning, and broad SDK constraints are maintenance decisions and do not create lab-rot issues by themselves.

The live preprovision hook also validates Search quota, exact model versions, Standard SKU availability, and available capacity for both `gpt-4o` and `text-embedding-3-small`.

### Run Agent Unit/Regression Tests

The Azure Developer CLI preprovision hook runs these tests automatically before deployment. To run them manually:

```bash
python3 -m venv .venv-tests
./.venv-tests/bin/pip install -q pytest pytest-asyncio httpx -r ./agents/it-admin/requirements.txt
cd agents/it-admin
../../.venv-tests/bin/python -m pytest tests/ -v --tb=short
```

Agent test coverage:

| File | Coverage |
|------|----------|
| `agents/it-admin/tests/test_api.py` | FastAPI health, tools, tool invocation, chat, content type, conversation, and destructive-tool safety behavior |
| `agents/it-admin/tests/test_tools.py` | Tool schema, mock resource data, handler behavior, edge cases, and agentic investigation scenarios |
| `agents/it-admin/tests/conftest.py` | Shared fixtures for chat requests, tool arguments, and mock resource lists |

### Test the Application (Manual Quick Checks)

```bash
# Get the Front Door URL
azd env get-value FRONTDOOR_URL

# Test a RAG query through Front Door
curl -s -X POST "$(azd env get-value FRONTDOOR_URL)/chat" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is Northwind Health Plus?"}],"stream":false}' | jq .output_text
```

**Expected responses:**
- Container App direct: Full RAG response with citations
- APIM direct: Short OpenAI response (no RAG context)
- Front Door: Same as Container App (full RAG response)

### Tear Down (with soft-delete purge)
```bash
azd down --force --purge  # Purges APIM, Azure OpenAI, and the Foundry account
```

> **Note:** `azd down` can sometimes be flaky. If resources aren't deleted, use:
> ```bash
> az group delete -n rg-<env-name> --yes --no-wait
> ```

### Finding Resources by Token

All resources in an environment share a unique token (e.g., `yemy7aspuew3e`). To find resources:
```bash
# Get the token from any resource name
az resource list -g rg-<env> --query "[].name" -o tsv | head -1 | sed 's/.*-//'

# Or from azd env
azd env get-values | grep -i token
```

## Environment Variables

Set via `azd env set <KEY> <VALUE>`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `AZURE_LOCATION` | (required) | Deployment region (see validated list below) |
| `AZURE_ENV_NAME` | (required) | Environment name prefix |
| `AZURE_PRINCIPAL_ID` | (auto) | Deploying user's Object ID (set by azd) |
| `AZURE_PRINCIPAL_TYPE` | `User` | `User` for interactive, `ServicePrincipal` for CI/CD |
| `USE_APIM` | `true` | Enable AI Gateway |
| `APIM_SKU` | `BasicV2` | APIM SKU (BasicV2, StandardV2) |
| `WAF_MODE` | `Detection` | WAF mode (Detection, Prevention) |
| `USE_AGENTS` | `false` | Deploy IT Admin Agent + AI Foundry infrastructure |
| `SKIP_PREFLIGHT` | `false` | Set to `true` to bypass Search and exact model/SKU/quota preflight checks |

### Validated regions

These regions have all required services (Azure AI Search basic, Azure OpenAI `gpt-4o`, `text-embedding-3-small`, APIM BasicV2) confirmed available:

| Region | Geo |
|---|---|
| `eastus` | US |
| `eastus2` | US |
| `canadaeast` | Canada |
| `japaneast` | Asia Pacific |
| `australiaeast` | Asia Pacific |

> Regions like `westus3`, `southcentralus`, `swedencentral`, and `uksouth` have `gpt-4o` but **lack `text-embedding-3-small`** and will fail mid-deploy.
>
> If deployment fails with `InsufficientResourcesAvailable` (physical capacity, not quota), switch regions:
> ```bash
> azd down --force --purge
> azd env set AZURE_LOCATION <region>
> azd up
> ```

## RBAC Architecture

The core deployment creates role assignments for two principals:
1. **Backend Container App managed identity** - Runtime access (OpenAI, Search, Storage, Cosmos)
2. **Deploying user** - Prepdocs access (uploads blobs, creates search indexes)

When `useAgents=true`, it also assigns least-privilege roles to:
3. **Agent API Container App managed identity** - OpenAI, Search read, and Storage access
4. **Foundry account managed identity** - Connected OpenAI, Search, and Foundry access
5. **Foundry Project managed identity** - Connected OpenAI, Search read, and Foundry developer access

This dual-assignment pattern ensures:
- The app runs with least-privilege managed identity
- The postprovision hook can populate the search index
- Works from Cloud Shell, Codespaces, or local VS Code

## Adding New Security Controls

When adding new security features:

1. **Create a new Bicep module** in `infra/modules/`
2. **Wire it up in `main.bicep`** - add parameters, module reference, outputs
3. **Add diagnostic settings** - all resources should log to Log Analytics
4. **Use managed identity** - avoid API keys where possible
5. **Document in README** - update architecture diagram and "What Gets Deployed"
6. **Update this file** - keep AGENTS.md current

## Deployment Timing Reference

| Resource | Typical Time |
|----------|--------------|
| Most resources | < 30 seconds |
| Cosmos DB | ~1-2 minutes |
| APIM (BasicV2) | ~5-10 minutes |
| AI Foundry account + Project | ~2-3 minutes |
| Agent Container App | ~3-5 minutes |
| Front Door | ~10-15 minutes |
| AFD WAF propagation | ~30-45 minutes |

## Things to Avoid

- ❌ **Don't use API keys** - Use managed identity authentication
- ❌ **Don't modify `/upstream`** - It's a git submodule
- ❌ **Don't skip WAF** - Even in Detection mode, it provides visibility
- ❌ **Don't hardcode secrets** - Use Key Vault or azd env variables
- ❌ **Don't forget diagnostic settings** - All resources need logging
- ❌ **Don't use Consumption APIM** - Missing features needed for AI Gateway
- ❌ **Don't give agents write access to real infrastructure** - Use mock data or read-only roles

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| 403 from Front Door | Check WAF mode (should be Detection for dev) |
| "I don't know" responses | Search index empty - run prepdocs |
| APIM soft-delete conflict | `az apim deletedservice purge --location <loc> --service-name <name>` |
| Cognitive Services conflict | `az cognitiveservices account purge --location <loc> --name <name> -g <rg>` |
| Container not starting | Check ACR image exists, check Container Apps logs |
| `openai.AuthenticationError` | APIM enabled but `OPENAI_HOST` not set to `azure_custom` - redeploy with latest `container-apps.bicep` |
| `openai.NotFoundError` | See "APIM + OpenAI SDK Integration" section below |
| APIM `internal-client-key` not found | Ensure `openAiApiPolicy` has `dependsOn: [internalClientKeyNamedValue]` |

## APIM Policy Gotchas (Learned the Hard Way)

### APIM `500` + `ExpressionValueValidationFailure`

If APIM returns HTTP 500 with a body like:
`{"statusCode":500,"message":"Internal server error","activityId":"..."}`

…and Container Apps surfaces it as `openai.InternalServerError`, it can be a *policy expression* failing (not Azure OpenAI).

Symptoms in Log Analytics (APIM `GatewayLogs`):

- `lastError_reason_s`: `ExpressionValueValidationFailure`
- `lastError_message_s`: `Expression value is invalid. The value field is required.`
- `lastError_section_s`: `inbound` or `outbound`

Important: APIM may successfully call Azure OpenAI (HTTP 200) and then still return 500 if an outbound policy expression fails (for example, response body parsing/token counting).

### How to Debug APIM 500s Quickly

1. Get the `activityId` from the APIM 500 response body.
2. Query Log Analytics `AzureDiagnostics` for the matching `CorrelationId`.

This dev container sometimes has a broken `az monitor` module. Work around it by using Log Analytics Query REST API:

```bash
# 1) Get workspace customerId (workspaceId)
WS_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<wsName>"
WORKSPACE_ID=$(az rest --method get --uri "https://management.azure.com${WS_ID}?api-version=2023-09-01" --query properties.customerId -o tsv)

# 2) Query AzureDiagnostics for the APIM correlationId
TOKEN=$(az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv)
CID="<activityId-from-500-body>"
QUERY="AzureDiagnostics | where ResourceProvider == 'MICROSOFT.APIMANAGEMENT' | where CorrelationId == '${CID}' | project TimeGenerated, lastError_section_s, lastError_reason_s, lastError_message_s, traceRecords_s, errors_s | take 1"
curl -sS -X POST "https://api.loganalytics.io/v1/workspaces/${WORKSPACE_ID}/query" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg q "$QUERY" '{query:$q}')" | jq
```

If you see `ExpressionValueValidationFailure`, simplify the policy to the essentials (auth + forward + managed identity) and re-introduce tracing/rate-limit/token parsing incrementally with APIM-supported expression patterns.

### APIM Named Value `{{internal-client-key}}` Not Found

**Error during `azd up`:**
```
ValidationError: Error in element 'when' on line 20, column 8: Cannot find a property 'internal-client-key'
```

**Cause:** The API policy XML references `{{internal-client-key}}` (a named value), but APIM validates policies at deployment time. If the named value resource doesn't exist yet, validation fails.

**Fix:** Add explicit `dependsOn` to ensure the named value is created before the policy:
```bicep
resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: openAiApi
  name: 'policy'
  dependsOn: [internalClientKeyNamedValue]  // <-- Critical!
  properties: { ... }
}
```

Bicep's implicit dependency resolution doesn't work here because the policy XML is a raw string—Bicep doesn't parse `{{...}}` references inside it.

## APIM + OpenAI SDK Integration (Critical!)

> **✅ FIXED (Jan 2026):** The Container App now correctly sets `OPENAI_HOST=azure_custom` and `AZURE_OPENAI_CUSTOM_URL` when APIM is enabled. The app uses `AsyncAzureOpenAI` client which constructs Azure-style URLs (`/deployments/{name}/chat/completions`), so APIM routes correctly without needing URL rewrite policies.
>
> **⚠️ STILL PENDING:** If you want to support generic OpenAI SDK clients that send `/chat/completions` (without deployment in path), you'd need to add an APIM operation with URL rewrite policy. This is NOT required for the current implementation.

This section documents non-obvious behavior when routing OpenAI SDK requests through APIM.

### URL Path Architecture

The upstream `azure-search-openai-demo` uses `OPENAI_HOST=azure_custom` mode with the generic `AsyncOpenAI` client (NOT `AsyncAzureOpenAI`). This has important implications:

**OpenAI SDK URL format** (what the app sends):

```text
POST {base_url}/chat/completions
Body: {"model": "gpt-4o", "messages": [...]}
```

**Azure OpenAI URL format** (what Azure expects):

```text
POST {endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2024-06-01
```

**APIM must bridge this gap** by rewriting URLs in its inbound policy.

### Container App Environment Variables for APIM

When `useAPIM=true`, `container-apps.bicep` **automatically configures** these env vars:

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENAI_HOST` | `azure_custom` | Tells app to use custom URL (auto-set) |
| `AZURE_OPENAI_CUSTOM_URL` | `https://apim-xxx.azure-api.net/openai/v1` | APIM gateway base URL (auto-set) |
| `AZURE_OPENAI_API_KEY_OVERRIDE` | APIM subscription key | Authentication to APIM (auto-set from secret) |

**Common mistakes:**
- ❌ `https://apim.../openai/openai` - duplicate path segment
- ❌ `https://apim.../openai` - missing `/v1` (SDK base_url expects `/openai/v1`)
- ✅ `https://apim.../openai/v1` - correct base URL

### APIM Policy for URL Rewriting

The APIM inbound policy must extract the `model` from the request body and rewrite to Azure format:

```xml
<inbound>
    <!-- Extract model from request body -->
    <set-variable name="requestBody" value="@(context.Request.Body.As<JObject>(preserveContent: true))" />
    <set-variable name="model" value="@((string)((JObject)context.Variables["requestBody"])["model"] ?? "gpt-4o")" />
    
    <!-- Rewrite URL to Azure OpenAI format -->
    <rewrite-uri template="@("/deployments/" + (string)context.Variables["model"] + "/chat/completions")" />
    <set-query-parameter name="api-version" exists-action="override">
        <value>2024-06-01</value>
    </set-query-parameter>
</inbound>
```

### Authentication Flow

```
Container App                    APIM                         Azure OpenAI
     |                            |                                |
     |--- api-key: <sub-key> ---->|                                |
     |                            |--- Authorization: Bearer --->  |
     |                            |    (managed identity token)    |
```

- **Container App → APIM**: Uses APIM subscription key (`api-key` header)
- **APIM → Azure OpenAI**: Uses APIM's managed identity (bearer token)
- APIM deletes incoming `api-key` and adds `Authorization: Bearer <token>`

### Debugging APIM Issues

1. **Test APIM directly** (bypassing Container App):
   ```bash
   # Get subscription key
   az apim subscription keys list --resource-group rg-<env> \
     --service-name apim-<token> --subscription-id internal-apps --query primaryKey -o tsv
   
   # Test Azure-style URL (should work)
   curl -X POST "https://apim-xxx.azure-api.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
     -H "api-key: <subscription-key>" \
     -H "Content-Type: application/json" \
     -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
   
   # Test OpenAI-style URL (requires URL rewrite policy)
   curl -X POST "https://apim-xxx.azure-api.net/openai/chat/completions" \
     -H "api-key: <subscription-key>" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
   ```

2. **Check Container App logs**:
   ```bash
   az containerapp logs show -n ca-<token> -g rg-<env> --type console --tail 50
   ```
   
   Look for:
   - `"OPENAI_HOST is azure_custom"` - confirms custom URL mode
   - `"AZURE_OPENAI_API_KEY_OVERRIDE found"` - confirms API key auth (good)
   - `"Using Azure credential (passwordless)"` - means API key NOT found (bad for APIM)

3. **Check Container App env vars**:
   ```bash
   az containerapp show -n ca-<token> -g rg-<env> \
     --query "properties.template.containers[0].env" -o table
   ```

### Common Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `AuthenticationError` | `OPENAI_HOST` not set to `azure_custom` when APIM enabled | Run `azd provision` to update Container App with correct env vars |
| `NotFoundError` from OpenAI SDK | URL path wrong or APIM can't route | Check `AZURE_OPENAI_CUSTOM_URL` is set correctly |
| `DeploymentNotFound` | Wrong deployment name | Check `AZURE_OPENAI_CHAT_DEPLOYMENT` matches actual deployment |
| 401 Unauthorized | APIM managed identity missing role | Add "Cognitive Services OpenAI User" role to APIM identity |
| 404 from APIM | No matching operation/route | Verify APIM has `openai` API with correct backend |
| `"Using Azure credential"` in logs | `AZURE_OPENAI_API_KEY_OVERRIDE` empty/missing | Check secret reference in Container App |

## Related Documentation

- [README.md](README.md) - User-facing documentation
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - Deep dive into every component and why
