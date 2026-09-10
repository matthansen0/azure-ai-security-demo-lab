# Azure AI Security Sandbox

Security-focused reference architecture for an Azure OpenAI RAG application. It deploys Azure Front Door with WAF, API Management, Container Apps, Azure AI Search, Azure AI Foundry, and managed identities with least-privilege RBAC.

![Azure AI Security Sandbox Architecture](docs/architecture/architecture.png)

Explore the [interactive architecture diagram](https://matthansen0.github.io/azure-ai-security-sandbox/) or read [how the architecture works](HOW_IT_WORKS.md).

## Deploy

Prerequisites:

- Azure subscription with permission to create resources and role assignments
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Azure CLI

```bash
git clone --recurse-submodules https://github.com/matthansen0/azure-ai-security-sandbox.git
cd azure-ai-security-sandbox
az login
azd auth login
azd up
```

## Parameters

Set parameters before deployment with `azd env set <NAME> <VALUE>`.

| Parameter | Default | Values |
|---|---|---|
| `AZURE_LOCATION` | Required | `eastus`, `eastus2`, `canadaeast`, `japaneast`, `australiaeast` |
| `APIM_SKU` | `BasicV2` | `BasicV2`, `StandardV2` |
| `WAF_MODE` | `Detection` | `Detection`, `Prevention` |
| `SKIP_PREFLIGHT` | `false` | `true`, `false` |

## Tear Down

```bash
azd down --force --purge
```

## Documentation

- [Architecture and security controls](HOW_IT_WORKS.md)
- [Hands-on lab guides](docs/labs/README.md)
- [Responsible AI mapping](docs/responsible-ai.md)
- [Troubleshooting and operations](docs/troubleshooting.md)
- [Defender for AI status](docs/issues/defender-for-ai.md)
- [License](LICENSE)
