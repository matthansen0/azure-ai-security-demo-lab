# 🧪 Lab Guides

Hands-on exercises for exploring and verifying the security controls in the Azure AI Security Sandbox. Each lab focuses on a specific security layer and walks you through real verification steps — primarily through the **Azure Portal** and the **chat web app**, with optional CLI equivalents for those who prefer the command line.

## Prerequisites

These labs assume the sandbox is **already deployed** with `azd up`. If you haven't deployed yet, see the [Quick Start](../../README.md#-quick-start) in the main README.

> **Lab 6 (AI Agent Security)** requires the optional agent infrastructure. If you need it, redeploy with `azd up --parameter useAgents=true`.

### Find Your Resources

1. Open the [Azure Portal](https://portal.azure.com)
2. Navigate to **Resource Groups** and find `rg-<your-environment-name>`
3. Bookmark this resource group — you'll use it throughout the labs

### Open the Chat Web App

Get your application URL and open it in a browser — you'll use it to generate traffic throughout the labs:

```bash
echo "$(azd env get-value APP_PUBLIC_URL)"
```

### Optional: CLI Setup

Some exercises include optional CLI commands. If you want to use them, load your environment variables first:

```bash
eval "$(azd env get-values | sed 's/^/export /')"
RG="rg-${AZURE_ENV_NAME}"
```

## Lab Overview

| Lab | Topic | Time | Requires |
|-----|-------|------|----------|
| [Lab 1](lab-1-waf-front-door.md) | WAF & Front Door | ~20 min | `useAFD=true` (default) |
| [Lab 2](lab-2-api-management-gateway.md) | API Management AI Gateway | ~25 min | `useAPIM=true` (default) |
| [Lab 3](lab-3-managed-identity-rbac.md) | Managed Identity & RBAC | ~20 min | Base deployment |
| [Lab 4](lab-4-monitoring-logging.md) | Monitoring & Log Analytics | ~30 min | Base deployment |
| [Lab 5](lab-5-defender-for-cloud.md) | Defender for Cloud | ~20 min | Base deployment + add-on script |
| [Lab 6](lab-6-ai-agent-security.md) | AI Agent Security | ~20 min | `useAgents=true` |
| [Lab 7](lab-7-defender-for-ai.md) | Defender for AI | ~25 min | Base deployment + add-on script |
| [Lab 8](lab-8-foundry-guardrails.md) | Foundry Guardrails and Content Safety | ~15 min | Base deployment |

## Recommended Order

The labs are designed to be completed in order, following the request flow through the architecture:

```
Lab 1 (Edge) → Lab 2 (Gateway) → Lab 3 (Identity) → Lab 4 (Observability) → Lab 5 (Defender) → Lab 6 (Agents) → Lab 7 (AI Threats) → Lab 8 (Guardrails)
```

However, each lab is self-contained and can be completed independently.

## Tips

- **Portal is primary.** Every exercise shows how to do it in the Azure Portal first, with CLI alternatives marked as optional.
- **Use the dev container** if you want to run CLI commands — all tools are pre-installed and authenticated.
- **WAF propagation takes time.** If you just deployed, WAF rule changes can take 30-45 minutes to take effect.
- **Log Analytics has ingestion delay.** Logs typically appear within 2-5 minutes of an event, but can take up to 10 minutes.
- **Costs add up.** Remember to `azd down --force --purge` when you're done with the labs.
