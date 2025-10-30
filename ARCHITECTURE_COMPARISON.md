# Architecture Comparison: Current vs. CAIRA Approach

## Current Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     User / Developer                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│               Bash Scripts (Orchestration)                      │
│  • deploy-sample-and-secure.sh                                  │
│  • azureAISecurityDeploy.sh                                     │
│  • cleanup.sh                                                   │
└────────────────┬──────────────────┬─────────────────────────────┘
                 │                  │
                 ▼                  ▼
┌────────────────────────┐  ┌──────────────────────────────┐
│  Clone Upstream Repo   │  │  Azure CLI (az) + ARM API    │
│  azure-search-openai-  │  │  • Create Front Door + WAF   │
│  demo                  │  │  • Enable Defender plans     │
└────────────┬───────────┘  │  • Configure access rules    │
             │              └──────────┬───────────────────┘
             ▼                         │
┌─────────────────────────┐            │
│  azd (Azure Dev CLI)    │            │
│  • azd init             │            │
│  • azd up               │            │
│  • azd down             │            │
└────────────┬────────────┘            │
             │                         │
             └─────────────┬───────────┘
                           ▼
          ┌────────────────────────────────────┐
          │      Azure Resources Created       │
          │  • Azure OpenAI                    │
          │  • Azure AI Search                 │
          │  • App Service                     │
          │  • Cosmos DB                       │
          │  • Storage Account                 │
          │  • Front Door + WAF                │
          │  • Defender plans enabled          │
          └────────────────────────────────────┘
```

## Issues with Current Approach

1. **Upstream Dependency**: Changes in `azure-search-openai-demo` can break deployment
2. **Manual Patching**: Need to inject code (e.g., ProxyHeadersMiddleware)
3. **State Management**: Multiple `.env` files to track state
4. **Limited Testing**: Hard to validate changes before applying
5. **Imperative**: Scripts execute commands sequentially

---

## Proposed CAIRA Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     User / Developer                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         Terraform Configuration Files (Declarative)             │
│  • main.tf - Core infrastructure definition                     │
│  • variables.tf - Input parameters                              │
│  • outputs.tf - Output values                                   │
│  • terraform.tfvars - Environment-specific values               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Terraform Engine                             │
│  • terraform init - Initialize providers & modules              │
│  • terraform plan - Preview changes                             │
│  • terraform apply - Create/update resources                    │
│  • terraform destroy - Remove resources                         │
└───────────┬────────────────┬────────────────┬───────────────────┘
            │                │                │
            ▼                ▼                ▼
┌─────────────────┐  ┌──────────────┐  ┌────────────────────┐
│  CAIRA Modules  │  │ Azure Verified│ │ Custom Security   │
│  • AI Services  │  │ Modules (AVM) │ │ Modules           │
│  • Networking   │  │ • Key Vault   │ │ • Front Door+WAF  │
│  • Storage      │  │ • Storage     │ │ • Defender Plans  │
│  • AI Foundry   │  │ • Cosmos DB   │ │ • RBAC Config     │
└─────────────────┘  └──────────────┘  └────────────────────┘
            │                │                │
            └────────────────┴────────────────┘
                             │
                             ▼
            ┌────────────────────────────────┐
            │   Azure Resource Manager API   │
            └────────────────┬───────────────┘
                             │
                             ▼
          ┌────────────────────────────────────┐
          │      Azure Resources Created       │
          │  • Azure OpenAI (via CAIRA)        │
          │  • Azure AI Search (via CAIRA)     │
          │  • App Service (Terraform)         │
          │  • Cosmos DB (Terraform)           │
          │  • Storage Account (CAIRA)         │
          │  • Front Door + WAF (Terraform)    │
          │  • Defender plans (Terraform)      │
          │  • Key Vault (CAIRA)               │
          │  • RBAC (CAIRA)                    │
          │  • Private Endpoints (optional)    │
          └────────────────────────────────────┘
                             │
                             ▼
          ┌────────────────────────────────────┐
          │      Terraform State Backend       │
          │  • Azure Storage (state file)      │
          │  • State locking (prevents race)   │
          │  • Version history                 │
          └────────────────────────────────────┘
```

## Benefits of CAIRA Approach

1. ✅ **Independent**: No upstream repository dependency
2. ✅ **Declarative**: Define desired state, not steps
3. ✅ **State Management**: Automatic with Terraform
4. ✅ **Validation**: Preview changes with `terraform plan`
5. ✅ **Modular**: Reusable components
6. ✅ **Security Built-in**: CAIRA and AVM include security patterns
7. ✅ **Version Control**: All infrastructure in git
8. ✅ **Testable**: Can validate before applying
9. ✅ **Scalable**: Easy to add environments (dev/staging/prod)

---

## Side-by-Side Comparison

| Aspect | Current Approach | CAIRA Approach |
|--------|------------------|----------------|
| **Language** | Bash scripts | Terraform (HCL) |
| **Paradigm** | Imperative | Declarative |
| **Upstream Dependency** | High (azure-search-openai-demo) | None (self-contained) |
| **State Management** | Manual (.env files) | Automatic (Terraform state) |
| **Preview Changes** | No | Yes (terraform plan) |
| **Modularity** | Limited | High (modules) |
| **Reusability** | Low | High |
| **Security Patterns** | Manual configuration | Built-in (CAIRA/AVM) |
| **Testing** | Manual | Automated (plan/validate) |
| **Version Control** | Scripts only | Scripts + state |
| **Idempotency** | Partial | Full |
| **Learning Curve** | Low (bash) | Medium (Terraform) |
| **Maintainability** | Lower | Higher |
| **CI/CD Integration** | Limited | Excellent |

---

## Migration Path

```
Current State (v0.x)                 Transition                    Future State (v2.0+)
┌────────────────────┐               ┌──────────────┐              ┌────────────────────┐
│  Bash Scripts      │               │   Parallel   │              │  CAIRA + Terraform │
│  + azd             │    ────────►  │   Approach   │  ────────►   │                    │
│  + Upstream Repo   │               │   (Both)     │              │  No Upstream Dep   │
└────────────────────┘               └──────────────┘              └────────────────────┘
      Current                        Assessment Phase                   Target
```

---

## Resource Architecture Comparison

### Current Architecture (What Gets Deployed)

```
┌───────────────────────────────────────────────────────────────┐
│                      Azure Subscription                       │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Resource Group (from azd)                  │ │
│  │                                                         │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │ │
│  │  │ Azure OpenAI │  │  AI Search   │  │  App Service │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │ │
│  │  │  Cosmos DB   │  │   Storage    │  │  Key Vault   │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │ │
│  │  ┌──────────────┐                                     │ │
│  │  │ Log Analytics│                                     │ │
│  │  └──────────────┘                                     │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │         Additional Resources (from scripts)             │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  Azure Front Door + WAF (Premium)                │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │        Subscription-wide Defender Plans                 │ │
│  │  • Defender for AI                                      │ │
│  │  • Defender for Storage                                 │ │
│  │  • Defender for App Services (subscription)             │ │
│  │  • Defender for Cosmos DB (subscription)                │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### CAIRA Architecture (Proposed)

```
┌───────────────────────────────────────────────────────────────┐
│                      Azure Subscription                       │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │         Resource Group (Terraform Managed)              │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │      CAIRA AI Services Module           │           │ │
│  │  │  • Azure OpenAI (with RBAC)             │           │ │
│  │  │  • AI Search (with managed identity)    │           │ │
│  │  │  • Key Vault integration                │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │      CAIRA Storage Module               │           │ │
│  │  │  • Storage Account (encrypted)          │           │ │
│  │  │  • Cosmos DB (with RBAC)                │           │ │
│  │  │  • Private endpoints (optional)         │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │      Application Platform               │           │ │
│  │  │  • App Service (managed identity)       │           │ │
│  │  │  • App Insights                         │           │ │
│  │  │  • Log Analytics Workspace              │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │      Security Module (Custom)           │           │ │
│  │  │  • Front Door + WAF Premium             │           │ │
│  │  │  • Defender for AI (resource-level)     │           │ │
│  │  │  • Defender for Storage (advanced)      │           │ │
│  │  │  • Access policies and RBAC             │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────┐           │ │
│  │  │   Networking Module (Optional)          │           │ │
│  │  │  • VNet (for private deployment)        │           │ │
│  │  │  • Subnets (app, data, endpoints)       │           │ │
│  │  │  • NSGs and route tables                │           │ │
│  │  │  • Private DNS zones                    │           │ │
│  │  └─────────────────────────────────────────┘           │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │        Subscription-wide Defender Plans (Optional)      │ │
│  │  • Defender for App Services (Terraform managed)        │ │
│  │  • Defender for Cosmos DB (Terraform managed)           │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

Key Differences:
- All resources defined in Terraform
- Modular structure using CAIRA patterns
- Built-in RBAC and security
- Optional private networking
- Managed identities throughout
- Declarative state management

---

For more details, see:
- [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md) - Full assessment
- [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) - Migration path
- [terraform/README.md](./terraform/README.md) - POC documentation
