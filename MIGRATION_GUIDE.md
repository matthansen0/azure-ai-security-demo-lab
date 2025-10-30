# Migration Guide: Current Approach to CAIRA

This guide helps existing users understand the differences between the current bash script approach and the proposed CAIRA-based Terraform implementation.

## Overview

The Azure AI Security Demo Lab is assessing a migration from:
- **Current**: Bash scripts + azd (Azure Developer CLI) + upstream dependency
- **Proposed**: CAIRA (Composable AI Reference Architecture) with Terraform

## Why Migrate?

1. **Reduced Upstream Dependency**: Less reliance on `azure-search-openai-demo` repository changes
2. **Infrastructure as Code**: Declarative, version-controlled infrastructure
3. **Built-in Security**: Enterprise-grade security patterns from CAIRA
4. **Better Maintainability**: Modular, reusable components
5. **Professional Foundation**: Aligned with Microsoft's recommended practices

See [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md) for detailed analysis.

## Current Status

⚠️ **ASSESSMENT PHASE** ⚠️

The CAIRA implementation is currently in the assessment and proof-of-concept phase. The existing bash script approach remains the recommended deployment method until the migration is complete.

## Current Approach (Existing)

### How It Works

1. Uses bash scripts to orchestrate deployment
2. Clones upstream `azure-search-openai-demo` repository
3. Uses `azd up` to deploy infrastructure
4. Applies security configurations via additional bash scripts
5. Manages state with local `.env` files

### Key Commands

```bash
# Deploy the sample
./deploy-sample-and-secure.sh --env azure-ai-search-demo

# Apply security hardening
./azureAISecurityDeploy.sh

# Cleanup
./cleanup.sh azure-ai-search-demo
```

### Strengths

- ✅ Simple to use (bash scripts)
- ✅ Interactive prompts
- ✅ Comprehensive security coverage
- ✅ Proven and functional

### Limitations

- ❌ Dependent on upstream repository structure
- ❌ Imperative approach (harder to test)
- ❌ Manual state management
- ❌ Limited modularity

## Proposed CAIRA Approach (Future)

### How It Will Work

1. Define infrastructure in Terraform configuration files
2. Use CAIRA modules for AI services, networking, security
3. Deploy with `terraform apply`
4. Manage state automatically with Terraform backend
5. Version control all infrastructure changes

### Key Commands (Planned)

```bash
# Initialize Terraform
cd terraform
terraform init

# Plan deployment
terraform plan -var-file="environments/dev/terraform.tfvars"

# Deploy infrastructure
terraform apply -var-file="environments/dev/terraform.tfvars"

# Destroy infrastructure
terraform destroy -var-file="environments/dev/terraform.tfvars"
```

### Strengths

- ✅ Declarative infrastructure as code
- ✅ Independent from upstream repositories
- ✅ Built-in security patterns
- ✅ Modular and reusable
- ✅ Automatic state management
- ✅ Better testing and validation

### Considerations

- ⚠️ Requires Terraform knowledge
- ⚠️ Different workflow from current approach
- ⚠️ Initial setup more complex

## Resource Mapping

| Current | CAIRA Equivalent |
|---------|------------------|
| `./deploy-sample-and-secure.sh` | `terraform apply` |
| `./azureAISecurityDeploy.sh` | Integrated in Terraform config |
| `./cleanup.sh` | `terraform destroy` |
| `.azd_state.env` | Terraform state file |
| `.defender_state.env` | Terraform state file |
| Bash script logic | Terraform configuration |

## Feature Comparison

| Feature | Current | CAIRA |
|---------|---------|-------|
| Azure OpenAI | azd deployment | CAIRA AI Services module |
| Azure AI Search | azd deployment | CAIRA AI Search module |
| App Service | azd deployment | Terraform azurerm_linux_web_app |
| Cosmos DB | azd deployment | Terraform azurerm_cosmosdb_account |
| Storage | azd deployment | CAIRA Storage module |
| Front Door + WAF | Bash + az CLI | Terraform azurerm_cdn_* |
| Defender for AI | Bash + ARM API | Terraform azurerm_security_* |
| Defender for Storage | Bash + ARM API | Terraform with advanced config |
| Key Vault | azd deployment | CAIRA Key Vault module |
| RBAC | Manual/limited | Built-in with CAIRA |
| Private Endpoints | Not included | Available in CAIRA standard/private |

## Timeline and Phasing

### Phase 1: Assessment (Current)
**Status**: ✅ Complete

- Research CAIRA capabilities
- Analyze current implementation
- Document findings and recommendations
- Create proof-of-concept structure

### Phase 2: Implementation (Future)
**Status**: 🔲 Not Started

- Create Terraform modules
- Implement CAIRA integration
- Configure security features
- Test deployment scenarios

### Phase 3: Documentation (Future)
**Status**: 🔲 Not Started

- Complete migration guide
- Update README
- Create deployment tutorials
- Write troubleshooting guide

### Phase 4: Transition (Future)
**Status**: 🔲 Not Started

- Run parallel deployments
- Validate feature parity
- Gather user feedback
- Archive old scripts

## Migration Path Options

### Option 1: Wait for Complete Implementation (Recommended)

**Best for**: Most users

- Continue using current bash script approach
- Wait for CAIRA implementation to be completed and tested
- Migrate when stable and documented

**Timeline**: Wait for project team announcement

### Option 2: Parallel Evaluation

**Best for**: Advanced users, contributors

- Keep using bash scripts for production
- Experiment with CAIRA POC in parallel
- Provide feedback to project team

**Timeline**: Now (experimental)

### Option 3: Early Adoption

**Best for**: Terraform experts, early adopters

- Start using CAIRA approach once available
- Help identify issues and improvements
- Contribute back to the project

**Timeline**: After Phase 2 complete

## Prerequisites for CAIRA Approach

### Required Tools

1. **Terraform**: >= 1.5.0
   ```bash
   # Install Terraform
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **Azure CLI**: Latest version
   ```bash
   # Already installed in current devcontainer
   az --version
   ```

3. **Git**: For cloning CAIRA modules
   ```bash
   git --version
   ```

### Optional Tools

1. **Terraform Docs**: For generating documentation
2. **TFLint**: For Terraform linting
3. **Checkov**: For security scanning

## FAQs

### Q: When will CAIRA implementation be available?

**A**: The project is currently in the assessment phase. A timeline will be announced after the assessment is approved and implementation is planned.

### Q: Will the current bash scripts be removed?

**A**: Not immediately. The bash scripts will be maintained until the CAIRA implementation is stable and fully documented. They may be archived in a separate branch for reference.

### Q: Can I use both approaches?

**A**: Yes, during the transition period, both approaches will be available. However, they manage infrastructure differently, so use one or the other for a given environment, not both together.

### Q: What if I'm already using the current approach?

**A**: Continue using it. The current approach is fully functional and supported. Migration guidance will be provided when CAIRA implementation is ready.

### Q: Do I need to learn Terraform?

**A**: For the CAIRA approach, yes. However, we'll provide comprehensive documentation, examples, and automation scripts to minimize the learning curve.

### Q: Will CAIRA implementation have the same security features?

**A**: Yes, and more. The CAIRA approach will include all current security features plus additional capabilities like:
- Private endpoints (in standard/private architectures)
- Enhanced RBAC
- Network isolation
- Azure Policy integration

### Q: What about costs?

**A**: The underlying Azure resources are the same, so operational costs remain similar. There may be minimal additional costs for Terraform state storage (~$1-2/month).

### Q: Can I contribute to the CAIRA implementation?

**A**: Absolutely! Contributions are welcome. See the main README for contribution guidelines.

## Getting Help

- **Issues**: Report issues on GitHub
- **Discussions**: Join GitHub Discussions for questions
- **Documentation**: See [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md) for detailed information

## Related Documentation

- [CAIRA_ASSESSMENT.md](./CAIRA_ASSESSMENT.md) - Comprehensive assessment
- [terraform/README.md](./terraform/README.md) - Terraform POC documentation
- [README.md](./README.md) - Main project documentation
- [CAIRA Repository](https://github.com/microsoft/caira) - Upstream CAIRA project

---

**Document Version**: 1.0  
**Last Updated**: October 30, 2024  
**Status**: Assessment Phase
