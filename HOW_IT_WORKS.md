# How This Actually Works

You deployed a bunch of Azure resources with `azd up`. Here's what they do, why we configured them this way, and what you should understand before taking this to production.

> **The goal of this document:** After reading this, you should be able to reproduce this setup from scratch, customize it for your needs, or explain it to your security team.

---

## Table of Contents

- [The Big Picture](#the-big-picture)
- [Layer 1: The Edge (Front Door + WAF)](#layer-1-the-edge-front-door--waf)
- [Layer 2: The AI Gateway (API Management)](#layer-2-the-ai-gateway-api-management)
- [Layer 3: The Application (Container Apps)](#layer-3-the-application-container-apps)
- [Layer 4: The AI Brain (Azure OpenAI)](#layer-4-the-ai-brain-azure-openai)
- [Layer 5: The Knowledge Base (AI Search + Storage)](#layer-5-the-knowledge-base-ai-search--storage)
- [Layer 6: The Memory (Cosmos DB)](#layer-6-the-memory-cosmos-db)
- [Layer 7: Identity & Access (Managed Identity + RBAC)](#layer-7-identity--access-managed-identity--rbac)
- [Layer 8: Observability (Logging & Monitoring)](#layer-8-observability-logging--monitoring)
- [Layer 9: AI Agents (Optional)](#layer-9-ai-agents-optional)
- [Putting It All Together](#putting-it-all-together)

---

## The Big Picture

When a user asks "What's in my health plan?", here's the journey:

```
User → Front Door (WAF scans) → Container App → APIM (gateway policies) → Azure OpenAI
                                      ↓
                               AI Search ← finds relevant docs from Storage
```

Every hop adds security controls. Let's walk through each one.

---

## Layer 1: The Edge (Front Door + WAF)

**File:** [infra/modules/front-door.bicep](infra/modules/front-door.bicep)

### What We Deployed

- **Azure Front Door Premium** - Global CDN and reverse proxy
- **Web Application Firewall (WAF)** - Layer 7 protection

### Why This Configuration

**Premium SKU (not Standard):** We need Premium because WAF is only available on Premium tier. Yes, it costs more (~$35/mo base), but you can't have enterprise-grade edge security without it.

**WAF in Detection Mode:** Here's the thing - WAF rules are notoriously trigger-happy. We default to Detection mode so you can see what *would* be blocked without actually breaking your app. We learned this the hard way when Prevention mode blocked legitimate API requests with JSON payloads.

```bicep
// front-door.bicep, line 23-25
param wafMode string = 'Detection'  // Change to 'Prevention' for production
```

**What WAF catches:**
- SQL injection attempts
- Cross-site scripting (XSS)
- Bot traffic (scrapers, crawlers)
- Protocol violations
- Known attack patterns (OWASP Top 10)

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `wafMode` | `Detection` | `Detection` = log only, `Prevention` = block |
| `originResponseTimeoutSeconds` | `60` | How long to wait for backend |
| `probeIntervalInSeconds` | `120` | Health check frequency |

### Tradeoffs & Alternatives

**Why not just use Container Apps' built-in ingress?** You could! Set `useAFD=false` and skip this layer entirely. You lose:
- Global edge caching (latency)
- WAF protection (security)
- DDoS protection (availability)
- Custom domains with managed certs (convenience)

For development, skipping AFD saves ~$45/mo and 10-15 minutes deploy time.

**Why not Azure Application Gateway?** App Gateway is regional, Front Door is global. For AI apps with users worldwide, Front Door's edge presence matters. If you're single-region and need more advanced WAF tuning, App Gateway is worth considering.

### 🎓 Learn More

- [Azure Front Door documentation](https://learn.microsoft.com/azure/frontdoor/)
- [WAF tuning best practices](https://learn.microsoft.com/azure/web-application-firewall/afds/waf-front-door-tuning)
- [When to use Prevention vs Detection](https://learn.microsoft.com/azure/web-application-firewall/afds/waf-front-door-policy-settings)

---

## Layer 2: The AI Gateway (API Management)

**File:** [infra/modules/api-management.bicep](infra/modules/api-management.bicep)

This is where it gets interesting for AI specifically.

### What We Deployed

- **Azure API Management** - Acting as an "AI Gateway"
- **Custom policies** - Auth, retry logic (and optional rate limiting / token tracking)

### Why This Configuration

**The problem with raw Azure OpenAI access:** If you let your app talk directly to Azure OpenAI, you have no centralized control over:
- Who's using how many tokens
- Rate limiting per user/app
- Retry logic for 429s
- Audit logging of prompts/responses

APIM solves all of this by sitting between your app and Azure OpenAI.

**BasicV2 SKU (not Consumption):**
- **BasicV2** (~$180/mo) - Provisions in 5-10 minutes, has all features we need.
- **StandardV2** (~$360/mo) - More capacity, same features.
- **Consumption** - Cheapest per-call pricing but missing features (no VNet, limited policies).

We use BasicV2 because it has the right balance of features, cost, and provisioning speed.

### The AI Gateway Policies (The Good Stuff)

Here's what the APIM policies do in the default, known-good configuration:

**1. Managed Identity Auth (no API keys!)**
```xml
<authentication-managed-identity resource="https://cognitiveservices.azure.com" />
```
APIM uses its managed identity to authenticate to Azure OpenAI. Your app never sees an API key.

**2. Retry Logic**
```xml
<retry condition="@(context.Response.StatusCode == 429)" count="3" interval="10" />
```
Azure OpenAI returns 429 when you hit rate limits. APIM automatically retries with backoff.

**Optional add-ons (recommended for production, add incrementally):**

- Rate limiting / quotas
- Token usage extraction & logging
- Request/response tracing

These are powerful, but APIM policy expressions can be finicky: a policy expression failure can return HTTP 500 even if the backend (Azure OpenAI) returns HTTP 200. If you see APIM 500 with an `activityId`, use the Log Analytics workflow documented in [AGENTS.md](AGENTS.md) to find `ExpressionValueValidationFailure` and the failing policy section.

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `skuName` | `BasicV2` | APIM tier - affects cost and provisioning time |
| `retry count` | `3` | How many times to retry 429s |

### Tradeoffs & Alternatives

**Why not just use Azure OpenAI's built-in rate limiting?** You can, but it's per-deployment, not per-user. APIM lets you create subscriptions per team/app and track usage individually.

**Why not use Azure AI Gateway (preview)?** Great question! Azure has a native AI Gateway feature in preview. It's simpler but less flexible. APIM gives you full policy control - you can add semantic caching, prompt logging, content filtering, etc.

**Skip APIM entirely?** Set `useAPIM=false`. Your app talks directly to Azure OpenAI. Faster deploys, lower cost, less control.

### 🎓 Learn More

- [AI gateway in Azure API Management](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [Token counting with APIM](https://learn.microsoft.com/azure/api-management/azure-openai-token-limit-policy)
- [APIM policy reference](https://learn.microsoft.com/azure/api-management/api-management-policies)

---

## Layer 3: The Application (Container Apps)

**File:** [infra/modules/container-apps.bicep](infra/modules/container-apps.bicep)

### What We Deployed

- **Container Apps Environment** - The managed Kubernetes cluster (you don't see the K8s)
- **Container App** - Your RAG application container

### Why This Configuration

**Container Apps vs App Service vs AKS:**
- **App Service** - PaaS, simple, but less container-native
- **AKS** - Full Kubernetes control, but you manage everything
- **Container Apps** - Kubernetes under the hood, but managed. Sweet spot for AI apps.

We chose Container Apps because:
1. Auto-scaling (including scale-to-zero for cost)
2. No cluster management
3. Native container support (azd builds and pushes images)
4. Built-in ingress with TLS

**System-Assigned Managed Identity:** The container app gets its own identity. We use this for RBAC instead of connection strings/keys.

```bicep
identity: {
  type: 'SystemAssigned'
}
```

**The APIM routing magic:** Look at this conditional logic:

```bicep
var useApimGateway = !empty(apimOpenAiEndpoint) && !empty(apimSubscriptionKey)
var resolvedOpenAiEndpoint = openAiEndpoint
var apimOpenAiBaseUrlV1 = useApimGateway ? '${apimOpenAiEndpoint}/v1' : ''
```

If APIM is deployed, the upstream app uses `OPENAI_HOST=azure_custom` + `AZURE_OPENAI_CUSTOM_URL=https://.../openai/v1` as the OpenAI SDK `base_url`, while still keeping `AZURE_OPENAI_ENDPOINT` pointed at the real Azure OpenAI resource. If APIM is not deployed, the app talks directly to Azure OpenAI.

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `targetPort` | `8000` | Port your app listens on |
| `external` | `true` | Publicly accessible |
| `minReplicas` | `0` | Scale to zero when idle (cost savings) |
| `maxReplicas` | `10` | Maximum scale-out |

### Tradeoffs & Alternatives

**Why not Azure Functions?** Functions are great for event-driven workloads. RAG apps typically need persistent connections (WebSockets for streaming), longer execution times, and more control over the runtime. Container Apps fits better.

**Why build from ACR instead of deploy a pre-built image?** We clone `azure-search-openai-demo` at build time so you always get the latest. The tradeoff is longer initial deploy. You could pin to a specific version or use a pre-built image for faster, more predictable deploys.

### 🎓 Learn More

- [Container Apps documentation](https://learn.microsoft.com/azure/container-apps/)
- [Scaling rules](https://learn.microsoft.com/azure/container-apps/scale-app)
- [Managed identity in Container Apps](https://learn.microsoft.com/azure/container-apps/managed-identity)

---

## Layer 4: The AI Brain (Azure OpenAI)

**File:** [infra/modules/ai-services.bicep](infra/modules/ai-services.bicep)

### What We Deployed

- **Azure OpenAI account** - The Cognitive Services resource
- **GPT-4o deployment** - For chat/completions
- **text-embedding-3-small deployment** - For vector embeddings

### Why This Configuration

**GPT-4o (not GPT-4 Turbo or GPT-3.5):** 
- GPT-4o is the latest multimodal model with the best price/performance
- Faster than GPT-4 Turbo
- Cheaper than GPT-4 Turbo
- If you need to cut costs, swap to GPT-3.5 Turbo (significant quality drop)

**text-embedding-3-small (not ada-002 or text-embedding-3-large):**
- Better quality than ada-002
- Cheaper than text-embedding-3-large
- For most RAG use cases, "small" is sufficient

**Capacity settings:**
```bicep
sku: {
  name: 'Standard'
  capacity: 10  // 10K tokens per minute for chat
}
```

The `capacity` is in thousands of tokens per minute. 10 = 10K TPM. Increase for production.

**The soft-delete gotcha:** Azure OpenAI has enforced soft-delete (90 days). If you delete and redeploy with the same name:

```bicep
param restoreSoftDeletedOpenAi bool = false  // Set true to restore
```

This is why our `postdown` hook purges soft-deleted resources.

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `capacity` (GPT-4o) | `10` | 10K tokens per minute |
| `capacity` (embeddings) | `50` | 50K tokens per minute |
| `raiPolicyName` | `sandbox-content-safety` | Blocking Foundry guardrail policy derived from `Microsoft.DefaultV2` |
| `publicNetworkAccess` | `Enabled` | Public endpoints (for demo) |

The chat deployment uses an explicit policy for harmful-content categories, direct prompt attacks (`Jailbreak`), and indirect document attacks (`Indirect Attack`). These controls are integrated into Azure OpenAI and surfaced under **Guardrails + controls** in Microsoft Foundry; a separate Content Safety resource is not required for deployment-level filtering.

The indirect-attack filter requires Microsoft's document embedding and formatting convention. The upstream RAG prompt does not currently use that convention, so the configured filter is not an end-to-end guarantee for retrieved documents. See [Lab 8](docs/labs/lab-8-foundry-guardrails.md) for the boundary and verification steps.

### Tradeoffs & Alternatives

**Why not private endpoints?** We're using public endpoints for simplicity. In production, you'd enable private endpoints and route through VNet. This adds complexity (VNet integration for Container Apps, private DNS) but eliminates public attack surface.

**Why Azure OpenAI vs OpenAI directly?** Enterprise features:
- Data residency (your prompts stay in Azure region)
- VNet integration
- Managed identity auth
- Azure's SLA and support

### 🎓 Learn More

- [Azure OpenAI models](https://learn.microsoft.com/azure/ai-services/openai/concepts/models)
- [Quotas and limits](https://learn.microsoft.com/azure/ai-services/openai/quotas-limits)
- [Content filtering](https://learn.microsoft.com/azure/ai-services/openai/concepts/content-filter)

---

## Layer 5: The Knowledge Base (AI Search + Storage)

**Files:** [infra/modules/ai-services.bicep](infra/modules/ai-services.bicep) (AI Search), [infra/modules/storage.bicep](infra/modules/storage.bicep)

### What We Deployed

- **Azure AI Search (Basic tier)** - Vector + full-text search
- **Azure Storage Account** - Document storage

### Why This Configuration

**AI Search is the RAG backbone:** When someone asks a question, the app:
1. Converts the question to a vector (embedding)
2. Searches AI Search for similar documents
3. Returns top results to GPT-4o as context

**Basic tier (not Free or Standard):**
- **Free** - 50MB storage, no SLA. Fine for testing.
- **Basic** (~$75/mo) - 2GB storage, partitioning. Good for sandbox.
- **Standard** - More storage, replicas, availability. For production.

**Storage with delete retention:**
```bicep
deleteRetentionPolicy: {
  enabled: true
  days: 7
}
```

Soft delete for blobs - recover from accidental deletions.

**Defender for Storage (optional add-on):**

This repo does **not** enable Defender by default during `azd up`. To enable Defender for Cloud plans and apply Defender for Storage advanced settings (malware scanning + sensitive data discovery), run:

```bash
./scripts/enable-defender.sh --confirm
```

The storage-specific configuration is applied via:
- [infra/addons/defender/storage-settings.bicep](infra/addons/defender/storage-settings.bicep)

This scans uploaded files for malware and can help detect sensitive data. Important since users might upload documents.

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `searchIndexName` | `documents` | The index name your app queries |
| `storageSku` | `Standard_LRS` | Storage redundancy |
| `allowBlobPublicAccess` | `false` | No anonymous blob access |

### Tradeoffs & Alternatives

**Why not Cosmos DB for vectors?** Cosmos DB now supports vector search. AI Search is purpose-built for search (hybrid, semantic ranking, facets). Use Cosmos DB if you need a single database for vectors + operational data.

**Why not Pinecone/Weaviate/Qdrant?** These are excellent vector DBs. We use AI Search because:
- Native Azure integration (managed identity, private endpoints)
- Hybrid search (vectors + keywords)
- Semantic ranking
- No external dependencies

### 🎓 Learn More

- [AI Search vector search](https://learn.microsoft.com/azure/search/vector-search-overview)
- [RAG with AI Search](https://learn.microsoft.com/azure/search/retrieval-augmented-generation-overview)
- [Defender for Storage](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-storage-introduction)

---

## Layer 6: The Memory (Cosmos DB)

**File:** [infra/modules/cosmos-db.bicep](infra/modules/cosmos-db.bicep)

### What We Deployed

- **Cosmos DB account** (Serverless)
- **Database** named `chatdb`
- **Container** named `conversations`

### Why This Configuration

**Serverless (not Provisioned throughput):**
```bicep
capabilities: [
  { name: 'EnableServerless' }
]
```

Pay per request, not per hour. For a sandbox with sporadic usage, serverless is dramatically cheaper. The tradeoff: no SLA, and you can get throttled under heavy load.

**Session consistency:**
```bicep
consistencyPolicy: {
  defaultConsistencyLevel: 'Session'
}
```

"Session" means a user sees their own writes immediately. It's the sweet spot between performance and consistency for chat apps.

**Partition key is `/userId`:**
```bicep
partitionKey: {
  paths: ['/userId']
}
```

Each user's conversations are co-located. Efficient queries within a user's history, scales across users.

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `databaseName` | `chatdb` | Database name |
| `containerName` | `conversations` | Container for chat history |
| `defaultTtl` | `-1` | No expiration (keep forever) |

### Tradeoffs & Alternatives

**Why not PostgreSQL/Redis/MongoDB?** All valid! Cosmos DB gives:
- Global distribution (if you need it later)
- Automatic indexing
- Serverless option
- Native Azure integration

For a simple chat history, PostgreSQL would work fine and might be cheaper at scale.

### 🎓 Learn More

- [Cosmos DB serverless](https://learn.microsoft.com/azure/cosmos-db/serverless)
- [Choosing a consistency level](https://learn.microsoft.com/azure/cosmos-db/consistency-levels)
- [Partition key design](https://learn.microsoft.com/azure/cosmos-db/partitioning-overview)

---

## Layer 7: Identity & Access (Managed Identity + RBAC)

**File:** [infra/modules/role-assignments.bicep](infra/modules/role-assignments.bicep)

### What We Deployed

No resources - just role assignments. But this is arguably the most important security layer.

### Why This Configuration

**Zero secrets in code.** Look at the role assignments:

```bicep
// Container App → Azure OpenAI
var cognitiveServicesOpenAIUserRole = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// Container App → AI Search
var searchIndexDataContributorRole = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'

// Container App → Storage
var storageBlobDataContributorRole = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
```

The Container App's managed identity gets these roles. The app authenticates using `DefaultAzureCredential()` - no connection strings, no API keys.

**Why this matters:**
- No secrets to rotate
- No secrets to leak
- No secrets in environment variables
- Audit trail of access in Azure AD

**APIM also gets managed identity:**
```bicep
identity: {
  type: 'SystemAssigned'
}
```

APIM authenticates to Azure OpenAI using its own identity. The APIM subscription key is for *your app to APIM*, not for APIM to OpenAI.

### The Roles We Assign

| Identity | Resource | Role | Why |
|----------|----------|------|-----|
| Container App | Azure OpenAI | Cognitive Services OpenAI User | Call the models |
| Container App | AI Search | Search Index Data Contributor | Read/write index data |
| Container App | AI Search | Search Service Contributor | Create indexes |
| Container App | Storage | Storage Blob Data Contributor | Read/write documents |
| Container App | Cosmos DB | Cosmos DB Data Contributor | Read/write chat history |
| APIM | Azure OpenAI | Cognitive Services OpenAI Contributor | Proxy requests to OpenAI |

### Tradeoffs & Alternatives

**Why not just use API keys?** You could set `AZURE_OPENAI_API_KEY` as an environment variable. But:
- Keys don't have granular permissions
- Keys are long-lived secrets
- Keys can be leaked in logs, repos, screenshots
- Key rotation is manual

Managed identity is strictly better for Azure-to-Azure communication.

### 🎓 Learn More

- [Managed identities overview](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview)
- [RBAC for Azure OpenAI](https://learn.microsoft.com/azure/ai-services/openai/how-to/role-based-access-control)
- [DefaultAzureCredential](https://learn.microsoft.com/azure/developer/python/sdk/authentication-overview)

---

## Layer 8: Observability (Logging & Monitoring)

**File:** [infra/modules/monitoring.bicep](infra/modules/monitoring.bicep)

### What We Deployed

- **Log Analytics Workspace** - Central log store
- **Application Insights** - APM for the app
- **Diagnostic settings on every resource**

### Why This Configuration

**Every resource logs to Log Analytics.** Look at any module:

```bicep
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [...]
    metrics: [...]
  }
}
```

This isn't optional for security. You need logs for:
- Incident response
- Compliance audits
- Cost analysis
- Performance troubleshooting

**What's logged:**
- Front Door: WAF logs, access logs
- APIM: Gateway logs, request/response bodies
- Azure OpenAI: Audit logs (prompts, completions)
- Container Apps: Console logs, system logs
- Storage: Read/write operations
- Cosmos DB: Data plane operations

### Key Settings You Should Know

| Setting | Value | What It Does |
|---------|-------|--------------|
| `retentionInDays` | `30` | Default log retention |
| `sampling percentage` | `100` | No sampling (capture everything) |

### Tradeoffs & Alternatives

**Log retention costs money.** 30 days is cheap. For compliance, you might need 1-7 years - consider archiving to Storage.

**Consider Azure Sentinel** for security analytics if you're running this in production. It sits on top of Log Analytics and adds threat detection.

### 🎓 Learn More

- [Log Analytics overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview)
- [Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [Kusto query language (KQL)](https://learn.microsoft.com/azure/data-explorer/kusto/query/)

---

## Layer 9: AI Agents (Optional)

**Files:** [infra/modules/agents/](infra/modules/agents/), [agents/it-admin/](agents/it-admin/)

### What We Deployed

When you run `azd up --parameter useAgents=true`, you get:

- **AI Foundry account + Project** - Project-based management plane for AI agents
- **IT Admin Agent Container App** - FastAPI application with GPT-4o tool-calling agent
- **RBAC** - Managed identity roles for agent → OpenAI, agent → AI Foundry

### Why This Configuration

**Project-based AI Foundry pattern:** Azure AI Foundry now uses a project-enabled AI Services account with first-class Project child resources. The account is the shared Foundry resource, and the Project provides the per-application management boundary for the IT Admin Agent.

**Separate Container App:** The agent runs in its own Container App, isolated from the main RAG application. This gives independent scaling, deployments, and identity.

**Tool-calling architecture:** The agent uses GPT-4o's function calling capability to invoke diagnostic tools:

```
User: "Why is the web app slow?"
  → Agent calls get_system_metrics()
  → Agent calls get_recent_logs()
  → Agent calls check_dependencies()
  → Agent synthesizes findings into diagnosis
```

Currently uses **mock data** for safety - no real infrastructure access. In production, you'd replace mock tools with real Azure Monitor queries, `az` CLI calls, etc.

### The Agent's Tools

| Tool | Purpose | What It Returns |
|------|---------|----------------|
| `get_system_config` | Host/OS/resource info | CPU cores, memory, OS version |
| `get_system_metrics` | Real-time performance | CPU%, memory%, disk%, network |
| `get_recent_logs` | Application logs | Recent log entries with severity |
| `get_service_health` | Dependency status | Health of DB, cache, APIs |
| `get_recent_changes` | Change history | Recent deployments and config changes |
| `check_dependencies` | Package status | Installed packages and versions |
| `get_resource_details` | Azure resource info | Resource type, SKU, status |

### How It's Secured

- **Managed identity** - Agent Container App authenticates to OpenAI via RBAC, not API keys
- **No real infrastructure access** - Mock data prevents accidental changes
- **Isolated compute** - Runs in separate Container App with its own identity
- **RBAC scoped** - Agent identity only gets the roles it needs:
  - `Cognitive Services OpenAI User` on the OpenAI resource
  - `Azure AI Developer` on the AI Foundry project
  - `AcrPull` on the container registry

### Key Settings You Should Know

| Parameter | Default | What It Does |
|-----------|---------|--------------|
| `useAgents` | `false` | Deploy agent infrastructure |
| `minReplicas` | `1` | Agent always-on (no cold start) |
| `maxReplicas` | `3` | Max scale-out |
| `targetPort` | `8000` | FastAPI listen port |

### Tradeoffs & Alternatives

**Why not Azure AI Agent Service (hosted)?** Azure AI Agent Service can host agents for you. We use a self-hosted Container App because:
- Full control over the runtime and dependencies
- Custom tool implementations
- Easier to debug and iterate
- No additional service costs beyond the Container App

**Why mock data instead of real tools?** Safety first. An agent with real `az` CLI access could accidentally modify infrastructure. Mock data demonstrates the pattern without risk. Swap in real tools when you have proper guardrails (read-only roles, approval workflows, audit logging).

**Why AI Foundry instead of just OpenAI directly?** AI Foundry adds:
- Centralized project management
- Evaluation and testing capabilities
- Connection management for multiple AI services
- Future: agent orchestration, prompt flow integration

For a single agent, direct OpenAI access works fine. AI Foundry pays off when you have multiple agents, evaluation pipelines, or team collaboration needs.

### 🎓 Learn More

- [Azure AI Foundry documentation](https://learn.microsoft.com/azure/ai-studio/)
- [OpenAI function calling](https://platform.openai.com/docs/guides/function-calling)
- [Container Apps with managed identity](https://learn.microsoft.com/azure/container-apps/managed-identity)

---

## Putting It All Together

### The Request Flow (Detailed)

1. **User** types "What's in my Northwind Health Plus plan?"
2. **Front Door** receives request, WAF scans for attacks → passes
3. **Container App** receives request, sends question to...
4. **APIM** rate-checks, adds managed identity auth, forwards to...
5. **Azure OpenAI** (embedding model) creates vector for the question
6. **Container App** queries **AI Search** with the vector
7. **AI Search** returns top 5 matching document chunks
8. **Container App** builds prompt with context + question, sends to...
9. **APIM** again (rate-check, auth), forwards to...
10. **Azure OpenAI** (GPT-4o) generates response
11. **APIM** logs token usage, returns response
12. **Container App** saves to **Cosmos DB**, returns to user
13. **Front Door** returns response to user

**Everything is logged.** You can trace this entire flow in Log Analytics.

### Optional: The Agent Flow

If you deployed with `useAgents=true`, there's a separate flow for the IT Admin Agent:

1. **User** sends POST to agent endpoint: "Why is the web app slow?"
2. **Agent Container App** receives request
3. **Agent** calls GPT-4o with tool definitions
4. **GPT-4o** decides which tools to call (e.g., `get_system_metrics`, `get_recent_logs`)
5. **Agent** executes tool calls (mock data), returns results to GPT-4o
6. **GPT-4o** synthesizes diagnosis from tool results
7. **Agent** returns structured response with diagnosis + recommendations

The agent runs independently from the RAG app - different Container App, different identity, different use case.

### What You Should Do Next

1. **Run `azd up`** and deploy this yourself
2. **Query Log Analytics** - find your first request's journey
3. **Change WAF to Prevention mode** and see what breaks
4. **Disable APIM** (`useAPIM=false`) and compare the architecture
5. **Add a document** and query it
6. **Check costs** in Azure Cost Management after a few days

### Taking This to Production

This sandbox is NOT production-ready. Here's what you'd add:

| Gap | Production Solution |
|-----|---------------------|
| Public endpoints | Private endpoints + VNet |
| No auth on app | Azure AD / Entra ID authentication |
| Single region | Multi-region with Front Door failover |
| Basic search tier | Standard tier with replicas |
| WAF Detection mode | Prevention mode (after tuning) |
| 30-day logs | Long-term retention + Sentinel |
| No backup | Cosmos DB backup, blob versioning |

---

## Questions?

If something in this doc is unclear or wrong, please open an issue. The goal is for you to *actually understand* what you deployed, not just have a running system.

Happy building! 🚀
