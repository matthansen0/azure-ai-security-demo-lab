# 🤖 Azure AI Security Demo Lab 🔐

[![Open in GitHub Codespaces](https://img.shields.io/static/v1?style=for-the-badge&label=GitHub+Codespaces&message=Open&color=brightgreen&logo=github)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=matthansen0%2Fazure-ai-security-demo-lab&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json&location=WestUs2)
[![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https%3A%2F%2Fgithub.com%2Fmatthansen0%2Fazure-ai-security-demo-lab)

## ✨ Overview

> [!WARNING]  
> This repo is still under development, and has not yet reached v1.0 release.

> [!NOTE]  
> 🔍 **CAIRA Assessment In Progress**: We're evaluating a redesign using [Microsoft CAIRA (Composable AI Reference Architecture)](https://github.com/microsoft/caira) to improve maintainability and reduce upstream dependencies. See [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md) for details.

This repo provides automation to deploy AI Workloads on Azure using Azure OpenAI and supporting resources, and to enable key Azure Security configurations. This automation uses the fantastic work built by the [Azure Search OpenAI Demo](https://github.com/Azure-Samples/azure-search-openai-demo) samples repo and builds additional security components. We swap the frontend to use Azure App Service, and also enable the flags for conversation history, which requires Cosmos DB and Entra ID.

After we deploy the *azure-search-openai-demo* environment, we run the automation to leverage some bolt-on, and some build-in security:

- Deploy Azure Front Door + WAF in front of Azure App Service
- Enable Azure Defender for App Service
- Enable Azure Defender for Storage
- Enable Azure Defender for AI
- Enable Azure Defender for Cosmos DB

## 🏗️ Architecture (high level)

```text
Users / Browser
	|
	v
Azure Front Door (WAF)
	|
	v
Azure App Service (Web)
   /        |         \
  v         v          v
Azure OpenAI   Azure AI Search   Azure Storage
	(API)             (Index)         (Blobs)
								  |
								  v
						 Azure Cosmos DB
						  (Chat History)
```

## 🔐 Security features summary

| Component | Purpose | AI Relevance |
|---|---|---|
| Azure Front Door + WAF | Global edge entry (anycast), TLS offload, path-based routing; WAF managed rules (OWASP), optional bot/rate limits | Protects AI app ingress and mitigates prompt injection/abuse at the edge |
| Defender for Storage | On-upload malware scanning, sensitive data discovery (PII/PCI/PHI), anomaly detection; alerts in Defender for Cloud | Safeguards training data, embeddings, and user uploads |
| Defender for AI | Model, and prompt-aware threat detection for Azure OpenAI; monitors misuse, exfil attempts, and known attack patterns | Detects abuse/attacks specific to AI workloads |
| Defender for App Service | Runtime threat detection for App Service: suspicious requests, process anomalies, brute-force and exploitation attempts | Monitors the AI app runtime and API surface |
| Defender for Cosmos DB | Threat detection: SQL injection, anomalous access, data exfiltration patterns on databases/containers | Protects chat history and semantic cache |

## Instructions

### 🚀 Quick Start (3 steps)

1️⃣ Open in Codespaces or VS Code Dev Container by clicking a badge above.

2️⃣ Deploy the sample from a terminal in the dev container (regions are selected interactively).

```bash
chmod +x *.sh; ./deploy-sample-and-secure.sh --env azure-ai-search-demo
```

3️⃣ Apply security hardening (includes Front Door + WAF by default)

```bash
./azureAISecurityDeploy.sh
 ```

*If azd environment resource group auto-detection fails, the script will prompt for the resource group name. You can still run it explicitly with `./azureAISecurityDeploy.sh <RESOURCE_GROUP_NAME>`.*


> [!NOTE]  
> 💡 If prompted for subscription-wide enablement (App Services or Cosmos DBs), you may accept to enable them now. This creates a local state file `.defender_state.env` so cleanup can revert the change later if desired.

## 📝 To-Do List

### Architecture and Foundation
- [x] Assess CAIRA (Composable AI Reference Architecture) for redesign - See [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md)
- [ ] Implement CAIRA-based Terraform infrastructure
- [ ] Create a real architecture diagram that's not ASCII
- [ ] Migrate from bash scripts to Infrastructure as Code (Terraform)

### Security Features
- [x] Add Azure Front Door + WAF
- [ ] Add APIM with [Defender for APIs](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-apis-introduction)
- [ ] Integrate [Data-Aware Threat Protection and Security Posture](https://learn.microsoft.com/azure/defender-for-cloud/concept-data-aware-security) features
- [ ] Build SQL data source and enable [Defender for SQL](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-sql-introduction)
- [ ] Deploy Microsoft Purview for Data Classification, and DLP
- [ ] Integrate Azure AI Content Safety in [application code](https://learn.microsoft.com/azure/ai-services/content-safety/overview)
- [ ] Add [Data and AI security dashboard](https://learn.microsoft.com/en-us/azure/defender-for-cloud/data-aware-security-dashboard-overview)

### Documentation and Usability
- [ ] Add user guides for walking through verifying each aspect of the solution's security measures
- [ ] Create comprehensive Terraform deployment documentation
- [ ] Build automated testing for infrastructure deployments

## 🧹 Cleanup / Deletion

Run the cleanup script from this repo:

```bash
./cleanup.sh azure-ai-search-demo
```

What it does:

- Purges the entire azure-search-openai-sample app
- Removes the additional Azure Front Door deployment
- Offers to revert any subscription-wide Defender plan changes that were enabled by the secure step (App Services, Cosmos DBs) back to Free.

## 📖 Additional Resources

### Architecture and Design
- [CAIRA Assessment and Redesign Recommendation](./CAIRA_ASSESSMENT.md) - Evaluation of CAIRA for this project
- [Migration Guide](./MIGRATION_GUIDE.md) - Understanding the current vs. CAIRA approach
- [Azure OpenAI Landing Zone Reference Architecture](https://techcommunity.microsoft.com/blog/azurearchitectureblog/azure-openai-landing-zone-reference-architecture/3882102)
- [Azure AI Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/ai/)

### Security Resources
- [Azure Security Collation](https://github.com/matthansen0/azure-security-collation)
- [Microsoft Defender for Cloud Documentation](https://learn.microsoft.com/azure/defender-for-cloud/)
- [Azure AI Security Best Practices](https://learn.microsoft.com/azure/ai-services/openai/concepts/security)

### CAIRA and Infrastructure as Code
- [Microsoft CAIRA Repository](https://github.com/microsoft/caira)
- [Azure Verified Modules](https://aka.ms/avm)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## 🤝 Contributing

Contributions are welcome! If you have suggestions, bug reports, or improvements, please open an issue or submit a pull request. For major changes, please open an issue first to discuss what you would like to change.
