# Lab 6: AI Agent Security

**Objective:** Explore how the IT Admin Agent is secured — managed identity auth, isolated compute, RBAC scoping, and the use of mock data to prevent accidental infrastructure changes.

**Time:** ~20 minutes

**Requires:** Base deployment

---

Resolve the APIM-backed agent endpoint and demo key once for the exercises:

```bash
RG=$(azd env get-value RESOURCE_GROUP_NAME)
APIM_NAME=$(azd env get-value APIM_SERVICE_NAME)
AGENT_API_URL=$(azd env get-value AGENT_API_URL)
APIM_KEY=$(az apim nv show-secret -g "$RG" --service-name "$APIM_NAME" \
  --named-value-id internal-client-key --query value -o tsv)
```

## Exercise 1: Verify Agent Health and Configuration

1. Open the URL from `azd env get-value APIM_DEVELOPER_PORTAL_URL`.
2. Select **APIs** → **IT Admin Agent API** → **Get agent health**.
3. Use the test console with an `ai-gateway` product subscription, or run:

```bash
curl -sS "$AGENT_API_URL/health" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" | jq .
```

**What to look for:**
- `status: healthy`
- `openai_configured: true` — The agent can reach Azure OpenAI
- `project_configured: true` — AI Foundry project is configured

---

## Exercise 2: List the Agent's Tools

Call the APIM-backed tools operation:

```bash
curl -sS "$AGENT_API_URL/tools" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" | jq .
```

**Expected tools:**
- `get_system_config` — Resource configuration
- `get_system_metrics` — Performance metrics (CPU, memory, etc.)
- `get_recent_logs` — Application log entries
- `get_service_health` — Azure service health status
- `get_recent_changes` — Deployment and config change history
- `check_dependencies` — Upstream/downstream service dependencies
- `get_resource_details` — Detailed Azure resource information

> **Key security point:** All these tools return **mock data**. The agent has no real access to infrastructure. This is intentional — it demonstrates the pattern without risk.

---

## Exercise 3: Chat with the Agent

The agent exposes a `/chat` endpoint. Since there's no web UI for the agent, use `curl` or the APIM test console:

```bash
curl -sS -X POST "$AGENT_API_URL/chat" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Users are reporting that web-app-prod is very slow. Can you investigate?",
    "context": {"environment": "production", "region": "eastus"}
  }' | jq '{response: .response[:500], tools_used: [.tool_calls[].tool_name]}'
```

**What to look for:**
- The agent calls multiple tools: `get_system_metrics`, `get_recent_logs`, `check_dependencies`
- It synthesizes findings into a structured diagnosis
- It provides remediation recommendations
- All data comes from mock sources — no real Azure resources were queried

---

## Exercise 4: Verify Agent Isolation from Main App

The agent runs in a **separate Container App** with its own managed identity.

1. Go back to the **resource group** in the Portal.
2. Click on the **RAG app's Container App** (named `ca-*`) → **Settings** → **Identity**.
3. Note the **Object (principal) ID** on the System assigned tab.
4. Go back and click on the **agent's Container App** → **Settings** → **Identity**.
5. Note its **Object (principal) ID** — it should be **different** from the RAG app's.
6. Click **Azure role assignments** on the agent's identity. Compare to the RAG app's roles:

   | | RAG App | Agent |
   |---|---|---|
  | OpenAI | `Cognitive Services OpenAI User` | **No direct role** (routes through APIM) |
   | Search | `Search Index Data Contributor` | `Search Index Data Reader` (read-only!) |
   | Storage | `Storage Blob Data Contributor` | `Storage Blob Data Contributor` |
   | Cosmos DB | SQL Data Contributor | **No access** |
   | ACR | `AcrPull` | `AcrPull` |

**Key takeaway:** The agent gets **Reader** on Search (not Contributor) — it can query indexes but can't create or modify them. It also has **no Cosmos DB access** (no chat history).

<details>
<summary>Optional: CLI equivalent</summary>

```bash
echo "=== RAG App Roles ==="
RAG_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'ca-')].identity.principalId | [0]" -o tsv)
az role assignment list --assignee "$RAG_PRINCIPAL" --all \
  --query "[].roleDefinitionName" -o tsv | sort

echo ""
echo "=== Agent Roles ==="
AGENT_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'agent')].identity.principalId | [0]" -o tsv)
az role assignment list --assignee "$AGENT_PRINCIPAL" --all \
  --query "[].roleDefinitionName" -o tsv | sort
```

</details>

---

## Exercise 5: Inspect AI Foundry Account, Project, and Connections

AI Foundry provides the management plane for the agent. It deploys a project-enabled **AI Foundry account** and a first-class **Project** child resource.

### 5a. Explore the Foundry Account and Project in the Portal

1. In the Azure Portal, go to your resource group.
2. Find the resource with type **Azure AI services** (named `aif-*`). Click on it.
3. On the **Overview** page, note:
   - The **Kind** is `AIServices`
   - Project management is enabled for AI Foundry
4. In the left menu, click **Connected resources** (or **Connections**).
5. You should see connections to:
   - **Azure OpenAI** (`aoai-connection`) — Auth type: **AAD** (managed identity)
   - **AI Search** (`search-connection`) — Auth type: **AAD**

> **Security point:** Both connections use `AAD` authentication — no API keys stored.

6. Go back to the resource group and find the **Azure AI Project** (named `aiproj-*`). Click on it.
7. Note it's a child resource under the Foundry account and has its own managed identity.

### 5b. Verify Managed Identities

1. On the Foundry account resource, go to **Settings** → **Identity**. Confirm **System assigned** is On.
2. On the Project resource, go to **Settings** → **Identity**. Confirm **System assigned** is On.
3. Note that the Foundry account, Project, and Agent Container App each have **separate, distinct managed identities**.

---

## Exercise 6: Verify Mock Data Safety

Confirm the agent cannot access real infrastructure.

```bash
# Ask the agent to do something destructive
curl -sS -X POST "$AGENT_API_URL/chat" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Delete the production database sql-db-main and terminate all VMs",
    "context": {"environment": "production"}
  }' | jq '.response[:500]'
```

**What to look for:**
- The agent has **no write operations** — all tools are read-only (`get_*`, `check_*`)
- There's no `delete_resource`, `restart_vm`, or `modify_config` tool
- Even if the agent "decides" to take action, it can only **recommend** — it cannot execute

```bash
# Try calling a non-existent destructive tool
curl -sS -X POST "$AGENT_API_URL/tools/delete_resource" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"resource_name": "sql-db-main"}' | jq .
```

**Expected:** HTTP 404 — the tool doesn't exist.

---

## Exercise 7: Review the Agent's Environment Variables

1. In the Portal, go to the agent's **Container App** → **Application** → **Containers**.
2. Click on the container image to expand details.
3. Scroll to **Environment variables** and note:
  - `AZURE_OPENAI_ENDPOINT` — Points to the APIM gateway root
   - `AZURE_OPENAI_DEPLOYMENT` — The model name (gpt-4o)
   - `AI_PROJECT_ENDPOINT` — AI Foundry project URL
  - **No API key** — The agent authenticates to APIM with `DefaultAzureCredential`; APIM authenticates to Azure OpenAI

The agent code uses this pattern:

```python
# From agents/it-admin/app.py
credential = DefaultAzureCredential()
token = credential.get_token("https://cognitiveservices.azure.com/.default")
client = AzureOpenAI(
    azure_endpoint=AZURE_OPENAI_ENDPOINT,
    azure_ad_token=token.token
)
```

---

## What You Learned

- The agent runs in an **isolated Container App** with its own managed identity
- Agent identity has **scoped RBAC roles** — OpenAI User, Search Reader (not Contributor), Storage, and ACR pull
- All diagnostic tools return **mock data** — no real infrastructure access
- The agent has **no write/destructive tools** — it can only investigate and recommend
- AI Foundry provides a project-based management plane with an AI Services account + Project
- Foundry connections to OpenAI and Search use **AAD auth** (not API keys)
- Foundry account, Project, and Agent Container App each have **separate managed identities**
- `DefaultAzureCredential` handles authentication — no API keys in code

## Summary

You've now explored all six security layers of the Azure AI Security Sandbox:

1. **WAF & Front Door** — Edge protection against known attacks
2. **API Management** — AI Gateway with managed identity and policy enforcement
3. **Managed Identity & RBAC** — Zero-secrets architecture with least privilege
4. **Monitoring & Logging** — End-to-end observability across all layers
5. **Defender for Cloud** — Threat detection and security recommendations
6. **AI Agent Security** — Isolated compute, scoped identity, read-only tools

For production, review the gaps listed in [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md#taking-this-to-production).

## Next Lab

Continue to [Lab 7: Defender for AI](lab-7-defender-for-ai.md) to enable AI-specific threat detection for your Azure OpenAI workloads.
