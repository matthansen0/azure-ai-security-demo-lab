# Lab 3: Managed Identity & RBAC

**Objective:** Verify the zero-secrets identity architecture. Understand how managed identities replace API keys and how RBAC role assignments control access between services.

**Time:** ~20 minutes

**Requires:** Base deployment

---

## Exercise 1: Identify All Managed Identities

Every service-to-service connection uses managed identity instead of connection strings or API keys.

1. In the Azure Portal, go to your resource group (`rg-<your-env-name>`).
2. Click on the **Container App** resource (named `ca-*`).
3. In the left menu, go to **Settings** → **Identity**.
4. Confirm the **System assigned** tab shows **Status: On** and note the **Object (principal) ID**.
5. Go back to the resource group. Click on the **API Management** resource (named `apim-*`).
6. Go to **Security** → **Managed identities**. Confirm **System assigned** is **On**.
7. If agents are deployed: Find the second Container App (the agent API) and check its identity too.

**Key takeaway:** Each service has its own distinct managed identity — no shared credentials.

---

## Exercise 2: Map the Container App's Role Assignments

The Container App needs access to multiple backend services. Verify each role assignment.

1. Navigate to the **Container App** (named `ca-*`) → **Settings** → **Identity**.
2. Click the **Azure role assignments** button. This opens a view of every role this identity holds.
3. Verify you see the following roles:

   | Role | Resource | Purpose |
   |------|----------|---------|
   | `Cognitive Services OpenAI User` | Azure OpenAI | Call GPT-4o and embedding models |
   | `Search Index Data Contributor` | AI Search | Read/write search index data |
   | `Search Service Contributor` | AI Search | Create and manage indexes |
   | `Storage Blob Data Contributor` | Storage Account | Read/write document blobs |

**Alternative:** You can also verify role assignments from the target resource side. Go to any backend resource (e.g., the Azure OpenAI resource `cog-*`) → **Access control (IAM)** → **Role assignments** — you should see the Container App's identity listed.

> **Note:** Cosmos DB uses its own RBAC system (SQL role assignments), not ARM role definitions. We verify that separately in Exercise 3.

<details>
<summary>Optional: CLI equivalent</summary>

```bash
CA_PRINCIPAL=$(az containerapp list -g "$RG" \
  --query "[?contains(name, 'ca-')].identity.principalId | [0]" -o tsv)

az role assignment list --assignee "$CA_PRINCIPAL" --all \
  --query "[].{role: roleDefinitionName, scope: scope}" -o table
```

</details>

---

## Exercise 3: Verify Cosmos DB SQL Role Assignment

Cosmos DB has its own RBAC system separate from Azure ARM roles.

1. In the Azure Portal, go to the **Azure Cosmos DB** account (named `cosmos-*`).
2. In the left menu, go to **Settings** → **Identity and access (IAM)** (or **Keys** to note that the app doesn't use keys).
3. Cosmos DB SQL-level role assignments aren't shown in the Portal IAM blade. Use the CLI to verify:

```bash
COSMOS_NAME=$(az cosmosdb list -g "$RG" --query "[0].name" -o tsv)

az cosmosdb sql role assignment list \
  --account-name "$COSMOS_NAME" -g "$RG" \
  --query "[].{principalId: principalId, roleDefinitionId: roleDefinitionId}" -o table
```

**What to look for:**
- The Container App's principal ID should appear
- Role definition ID ending in `00000000-0000-0000-0000-000000000002` is the **Cosmos DB Built-in Data Contributor**

> **Why CLI here?** Cosmos DB SQL role assignments are a separate system from ARM RBAC. They don't appear in the Portal's IAM blade — the CLI is the best way to inspect them.

---

## Exercise 4: Verify No API Keys Are Used

One of the key security features is that no API keys exist in environment variables.

1. Go to the **Container App** (named `ca-*`).
2. In the left menu, go to **Application** → **Containers**.
3. Click on the container image name to expand its details.
4. Scroll to the **Environment variables** section.
5. Look through the variables and note:
   - `AZURE_OPENAI_ENDPOINT` — The endpoint URL (not a secret)
   - `AZURE_OPENAI_CHAT_DEPLOYMENT` — Model deployment name (not a secret)
   - **No** `AZURE_OPENAI_API_KEY` — the app uses managed identity instead
  - `OPENAI_HOST=azure_custom` and an APIM subscription key (for app → APIM auth only, stored as a secret reference)

**Key takeaway:** The app authenticates to Azure OpenAI, AI Search, Storage, and Cosmos DB using `DefaultAzureCredential` (managed identity) — no API keys anywhere.

<details>
<summary>Optional: CLI equivalent</summary>

```bash
CA_NAME=$(az containerapp list -g "$RG" --query "[?contains(name, 'ca-')].name | [0]" -o tsv)

# List all env var names (no values for secret refs)
az containerapp show -n "$CA_NAME" -g "$RG" \
  --query "properties.template.containers[0].env[].name" -o tsv | sort

# Confirm no direct OpenAI API key
az containerapp show -n "$CA_NAME" -g "$RG" \
  --query "properties.template.containers[0].env[?contains(name, 'OPENAI_API_KEY')]" -o json
# Should return []
```

</details>

---

## Exercise 5: Verify APIM's Identity and Roles

APIM authenticates to Azure OpenAI using its own managed identity, separate from the Container App.

1. Go to the **API Management** resource (named `apim-*`).
2. Navigate to **Security** → **Managed identities**.
3. Under **System assigned**, click **Azure role assignments**.
4. Verify you see **Cognitive Services OpenAI Contributor** scoped to the Azure OpenAI resource.

**Key takeaway:** APIM has its own, separate identity. Compromising the Container App doesn't give access to APIM's identity or vice versa.

---

## Exercise 6: Verify the Deploying User's Roles

Your user identity also has role assignments — these are needed for the `postprovision` hook that populates the search index.

1. In the Azure Portal, go to your **resource group** (`rg-<your-env-name>`).
2. Click **Access control (IAM)** → **Role assignments**.
3. Search for your own name or email in the role assignments list.
4. You should see the same roles as the Container App:
   - `Cognitive Services OpenAI User`
   - `Search Index Data Contributor` / `Search Service Contributor`
   - `Storage Blob Data Contributor`

**Why?** These let the `prepdocs` script upload documents and create search indexes during `azd up`. In production, you'd remove user-level assignments after initial setup.

---

## Exercise 7: Understand the Authentication Chain

Trace how authentication flows through the entire architecture:

```
User → Front Door → Container App → APIM → Azure OpenAI
         (no auth)   (managed ID)  (sub key) (managed ID)
```

| Hop | Authentication Method | Notes |
|-----|----------------------|-------|
| User → Front Door | None (public) | In production, add Azure AD auth |
| Front Door → Container App | Direct routing | AFD origin connection |
| Container App → APIM | Subscription key | Stored as Container App secret |
| APIM → Azure OpenAI | Managed identity | APIM strips sub key, adds bearer token |
| Container App → AI Search | Managed identity | `DefaultAzureCredential` |
| Container App → Storage | Managed identity | `DefaultAzureCredential` |
| Container App → Cosmos DB | Managed identity | Cosmos SQL role assignment |

> **Key insight:** API keys only exist at the APIM subscription level (app → APIM). All backend service communication uses managed identity. If a Container App is compromised, the attacker only has access to the specific roles assigned — not admin access to any service.

---

## What You Learned

- Every Azure service uses a **system-assigned managed identity** for authentication
- The Container App has 4 role assignments covering OpenAI, Search, Storage, and Cosmos DB
- APIM has its own separate identity for calling Azure OpenAI
- No API keys for Azure OpenAI exist anywhere in the deployment
- Cosmos DB uses its own SQL RBAC system (separate from ARM RBAC)
- The deploying user also gets role assignments for the setup scripts
- Compromising one identity doesn't give access to all services (least privilege)

## Next Lab

Continue to [Lab 4: Monitoring & Log Analytics](lab-4-monitoring-logging.md) to trace a request end-to-end through all layers.
