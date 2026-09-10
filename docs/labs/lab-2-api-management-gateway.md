# Lab 2: API Management AI Gateway

**Objective:** Verify that Azure API Management is acting as an AI Gateway between the application and Azure OpenAI. Understand managed identity authentication, retry policies, and how to inspect gateway traffic.

**Time:** ~25 minutes

**Requires:** Base deployment

---

## Exercise 1: Explore APIM in the Portal

1. In the Azure Portal, go to your resource group (`rg-<your-env-name>`).
2. Find and click on the **API Management service** (named `apim-*`).
3. On the **Overview** page, note:
   - **Gateway URL** — this is the proxy endpoint all OpenAI traffic flows through
   - **SKU** — `BasicV2` (balances cost, features, and provisioning speed)
4. Under **APIs** in the left menu, click **APIs**. You'll see an API named **openai**.
5. Click **openai** → browse the operations listed (chat completions, embeddings, etc.).

**Key takeaway:** APIM acts as a gateway that intercepts all traffic between the chat app and Azure OpenAI.

---

## Exercise 2: Inspect APIM Policies

Policies are the core of APIM's AI Gateway behavior. They control authentication, URL rewriting, and retry logic.

1. Still in the APIM resource, go to **APIs** → **openai**.
2. Click **All operations** to see the base policy applied to all routes.
3. Click the **`</>`** (Policy editor) icon in the **Inbound processing** section.
4. Review the XML policy. Look for:
   - `<authentication-managed-identity resource="https://cognitiveservices.azure.com" />` — APIM authenticates to Azure OpenAI using its own managed identity (no API keys!)
   - `<retry>` — Automatic retry logic for 429 (rate limit) and 5xx errors
   - `<set-header name="api-key" exists-action="delete">` — Strips the client's subscription key before forwarding to Azure OpenAI

5. Click on individual operations (e.g., **chat-completions-openai-sdk**) to see operation-specific policies. The SDK operation **rewrites the URL** — it extracts the `model` field from the request body and routes to `/deployments/{model}/chat/completions`.

**Key takeaway:** The app sends requests in OpenAI SDK format; APIM transparently rewrites them to Azure OpenAI format and handles authentication.

---

## Exercise 3: Verify APIM's Managed Identity

1. In APIM, go to **Security** → **Managed identities** in the left menu.
2. Confirm **System assigned** is set to **On** — this is the identity APIM uses to authenticate to Azure OpenAI.
3. Copy the **Object ID** shown.
4. Now navigate to the **Azure OpenAI** resource in your resource group (named `cog-*`).
5. Go to **Access control (IAM)** → **Role assignments**.
6. Find the APIM identity's Object ID in the list — it should have the role **Cognitive Services OpenAI Contributor**.

**Key takeaway:** APIM uses its own managed identity to call Azure OpenAI. The chat app sends a subscription key to APIM, but APIM replaces it with a managed identity token before forwarding. No API keys are ever sent to Azure OpenAI.

---

## Exercise 4: Generate Traffic and View Gateway Logs

1. Open the chat web app and ask several questions (e.g., "What is Northwind Health Plus?", "What are the deductibles?", "Tell me about PerksPlus").
2. Wait 2-5 minutes for logs to ingest.
3. In the Azure Portal, go to your **Log Analytics workspace** (named `log-*`).
4. Click **Logs** and run this KQL query:

   ```kusto
   AzureDiagnostics
   | where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
   | where Category == "GatewayLogs"
   | project TimeGenerated,
       method = requestMethod_s,
       url = url_s,
       status = responseCode_d,
       duration = totalTime_d,
       backendUrl = backendUrl_s,
       backendStatus = backendResponseCode_d
   | order by TimeGenerated desc
   | take 10
   ```

**What to look for:**
- `backendUrl`: Points to your Azure OpenAI endpoint (proves APIM is proxying)
- `status` vs `backendStatus`: Should both be 200
- `duration`: Total time including APIM overhead + Azure OpenAI response time
- Multiple rows — each question in the chat app generates embedding + chat completion calls

---

## Exercise 5: Test Access Control

Verify that APIM enforces authentication — you can't call it without a valid subscription key.

1. In APIM, go to **APIs** → **openai** → select any operation.
2. Click the **Test** tab at the top.
3. APIM pre-fills the subscription key. Click **Send** — you should get a 200 response.
4. Now clear the `api-key` header value and click **Send** again — you should get **401 Unauthorized**.

**Key takeaway:** APIM requires a valid subscription key to accept requests. Without it, traffic is rejected before it ever reaches Azure OpenAI.

<details>
<summary>Optional: CLI equivalent</summary>

```bash
APIM_NAME=$(az apim list -g "$RG" --query "[0].name" -o tsv)
APIM_URL="https://${APIM_NAME}.azure-api.net"
APIM_KEY=$(az apim subscription keys list \
  -g "$RG" --service-name "$APIM_NAME" \
  --subscription-id internal-apps --query primaryKey -o tsv)

# With subscription key (should succeed)
curl -sS -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "api-key: ${APIM_KEY}" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' | jq .choices[0].message.content

# Without subscription key (should fail with 401)
curl -sS -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-06-01" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' | jq .
```

</details>

---

## What You Learned

- APIM sits between the app and Azure OpenAI, acting as a security gateway
- APIM authenticates to Azure OpenAI using **managed identity**, not API keys
- The app authenticates to APIM using a **subscription key**
- APIM rewrites OpenAI SDK-style URLs to Azure OpenAI format
- Retry policies handle rate limits (429s) automatically
- All gateway traffic is logged and queryable in Log Analytics

## Next Lab

Continue to [Lab 3: Managed Identity & RBAC](lab-3-managed-identity-rbac.md) to explore the zero-secrets identity architecture.
