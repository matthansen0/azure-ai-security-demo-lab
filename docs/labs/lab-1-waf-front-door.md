# Lab 1: WAF & Front Door

**Objective:** Verify that Azure Front Door and the Web Application Firewall (WAF) are protecting the application at the edge. Understand Detection vs Prevention modes and learn to read WAF logs.

**Time:** ~20 minutes

**Requires:** Base deployment

---

## Exercise 1: Verify Front Door Is Routing Traffic

1. Open the chat web app using your `APP_PUBLIC_URL` (from the [prerequisites](README.md#prerequisites)). You should see the chat interface load normally.
2. Ask a question like **"What is Northwind Health Plus?"** to confirm the app is working end-to-end.
3. Open your browser's **Developer Tools** (F12) → **Network** tab.
4. Reload the page and click on the main request.
5. In the **Response Headers**, look for `x-azure-ref` — this confirms the request went through Azure Front Door.

> **Tip:** You can also find the Container App's direct URL in the Portal. Go to your resource group → find the Container App → **Overview** → **Application Url**. Loading this URL bypasses Front Door entirely. Both serve the same app — Front Door adds caching, WAF, and global edge protection.

---

## Exercise 2: Inspect the WAF Policy Configuration

1. In the Azure Portal, go to your resource group (`rg-<your-env-name>`).
2. Find the resource of type **Front Door WAF policy** (named `waf-*`) and click on it.
3. Under **Settings** → **Policy settings**, note:
   - **Mode**: Should be `Detection` (logging only, not blocking)
4. Under **Settings** → **Managed rules**, note the active rule sets:
   - **Microsoft_DefaultRuleSet 2.1** — OWASP Core Rule Set covering SQL injection, XSS, protocol violations, etc.
   - **Microsoft_BotManagerRuleSet 1.1** — Bot detection rules
5. Click into `Microsoft_DefaultRuleSet` to browse the individual rule groups (SQLI, XSS, LFI, RFI, etc.).

**Key takeaway:** WAF provides broad protection out of the box with managed rule sets. Detection mode lets you observe what *would* be blocked before you turn on Prevention.

---

## Exercise 3: Trigger WAF Rules

Generate traffic that WAF rules are designed to catch. In Detection mode, these requests **pass through but are logged**.

1. In your browser's address bar, paste your Front Door URL with a SQL injection payload appended:
   ```
   https://<your-afd-endpoint>.azurefd.net/?id=1 OR 1=1--
   ```
   The page should still load (Detection mode doesn't block).

2. Try an XSS payload:
   ```
   https://<your-afd-endpoint>.azurefd.net/?q=<script>alert('xss')</script>
   ```

3. Try a path traversal:
   ```
   https://<your-afd-endpoint>.azurefd.net/../../etc/passwd
   ```

**Expected result:** All requests return normally (HTTP 200 or redirect). WAF logs the violations but does not block them in Detection mode.

> In Prevention mode, these same requests would return **HTTP 403 Forbidden**.

---

## Exercise 4: View WAF Logs in the Portal

After a few minutes (log ingestion delay), check what WAF detected.

1. In the Azure Portal, go to your resource group → find the **Log Analytics workspace** (named `log-*`).
2. Click **Logs** in the left menu. Dismiss the queries gallery if it appears.
3. Paste this KQL query and click **Run**:

   ```kusto
   AzureDiagnostics
   | where ResourceProvider == "MICROSOFT.CDN" or ResourceProvider == "MICROSOFT.NETWORK"
   | where Category has "WebApplicationFirewall"
   | project TimeGenerated, action_s, ruleName_s, host_s, requestUri_s, details_msg_s, policyMode_s
   | order by TimeGenerated desc
   | take 20
   ```

4. Review the results.

**What to look for:**
- `action_s`: `Detection` — logged, not blocked
- `ruleName_s`: The specific rule that matched (e.g., SQL injection, XSS)
- `requestUri_s`: The URL you tested with the malicious payload
- `policyMode_s`: `detection`

> **No results?** WAF logs can take 5-10 minutes to appear. Try running the query again after a few minutes.

---

## Exercise 5: Understand Detection vs Prevention

### Current Behavior (Detection)

| Malicious Request | HTTP Response | WAF Log Entry |
|---|---|---|
| SQL injection in URL | 200 (passes through) | `action: Detection` |
| XSS in query param | 200 (passes through) | `action: Detection` |
| Path traversal | 200 (passes through) | `action: Detection` |

### What Prevention Mode Would Do

| Malicious Request | HTTP Response | WAF Log Entry |
|---|---|---|
| SQL injection in URL | **403 (blocked)** | `action: Block` |
| XSS in query param | **403 (blocked)** | `action: Block` |
| Path traversal | **403 (blocked)** | `action: Block` |

> **Why not default to Prevention?** WAF rules can generate false positives. JSON API payloads sometimes trigger SQL injection rules. Detection mode lets you identify false positives before accidentally blocking legitimate traffic.

### Optional: Switch to Prevention Mode

You can test Prevention mode in the Portal:

1. Go to your **Front Door WAF policy** → **Settings** → **Policy settings**.
2. Change **Mode** from `Detection` to `Prevention`. Click **Save**.
3. Wait a few minutes for propagation.
4. Retry the SQL injection URL from Exercise 3 — you should now see a **403 Forbidden** block page.
5. **Switch back to Detection mode** when done to avoid blocking legitimate traffic.

<details>
<summary>Optional: CLI equivalent</summary>

```bash
# Switch to Prevention mode
az rest --method patch \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/${WAF_NAME}?api-version=2024-02-01" \
  --body '{"properties": {"policySettings": {"mode": "Prevention"}}}'

# Switch back to Detection mode
az rest --method patch \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}/providers/Microsoft.Network/FrontDoorWebApplicationFirewallPolicies/${WAF_NAME}?api-version=2024-02-01" \
  --body '{"properties": {"policySettings": {"mode": "Detection"}}}'
```

</details>

---

## What You Learned

- Front Door adds the `x-azure-ref` header to all proxied requests
- WAF in Detection mode logs threats without blocking them
- Both OWASP and Bot Manager rule sets are active
- WAF logs appear in Log Analytics under `FrontDoorWebApplicationFirewallLog`
- Switching between Detection and Prevention mode is a single setting change in the Portal

## Next Lab

Continue to [Lab 2: API Management AI Gateway](lab-2-api-management-gateway.md) to explore the AI Gateway layer.
