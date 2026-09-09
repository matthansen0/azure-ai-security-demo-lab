# Responsible AI Mapping

This document maps the Azure AI Security Sandbox to Microsoft's six Responsible AI principles. It describes controls and evidence that exist in this reference architecture, along with gaps that an organization must address before production use.

This mapping is implementation guidance, not a compliance certification or a substitute for a use-case-specific Responsible AI Impact Assessment.

## Scope

The mapping covers the RAG web application, optional IT Admin Agent, Azure infrastructure, deployment automation, validation scripts, and labs in this repository. It does not assess the read-only upstream application as an independently governed product.

## Control Mapping

| Principle | Implemented controls | Evidence and verification | Remaining production responsibility |
|---|---|---|---|
| **Fairness** | The sandbox uses general-purpose models and does not make eligibility, employment, health, or other consequential decisions. Azure OpenAI applies the `Microsoft.DefaultV2` safety policy to the chat deployment. | Review the deployment in `infra/modules/ai-services.bicep`; exercise model safety behavior using Lab 7. | Define affected groups and allocation harms for the intended use case. Build representative evaluation datasets and test response quality across relevant groups before deployment. |
| **Reliability and safety** | Azure OpenAI content filters, Prompt Shields for direct attacks, APIM retries, WAF detection, preflight capacity checks, offline regression tests, and end-to-end validation reduce known failure modes. Agent tools are mock, read-only operations and destructive tools are not exposed. | Run the offline CI commands in `README.md`, then `bash scripts/validate.sh` after deployment. Complete Labs 1, 2, 6, and 7. | Define service-level objectives, failure and escalation behavior, adversarial evaluations, human review requirements, and incident response. Evaluate indirect prompt injection from retrieved documents separately. |
| **Privacy and security** | Managed identities and RBAC protect service-to-service access. WAF, APIM, Defender add-ons, diagnostic settings, and optional sensitive-data discovery provide layered controls. Secrets are not stored in application code. | Complete Labs 1 through 5 and inspect role assignments, gateway behavior, and logs. Review `infra/modules/role-assignments.bicep`. | Add end-user authentication and authorization, private networking where required, data minimization and retention policies, privacy review, and controls for personal or regulated data. |
| **Inclusiveness** | The web application provides a browser-based conversational interface and the API accepts text requests. No user profile is required by the model. | Review the deployed application with representative users and assistive technologies. | Perform accessibility and inclusive-design testing with the target population. Define supported languages, interaction modes, and accommodations; the sandbox makes no accessibility conformance claim. |
| **Transparency** | Architecture documentation, labs, citations in RAG responses, explicit mock-tool results, and documented production gaps explain the system's behavior and boundaries. | Review `HOW_IT_WORKS.md`, the lab guides, and the IT Admin Agent response schema and tool-call output. | Publish user-facing notice covering AI use, data handling, limitations, content filtering, appeal or feedback paths, and when a human is responsible for a decision. |
| **Accountability** | Infrastructure as code, source control, CI checks, diagnostic logs, validation scripts, least-privilege role assignments, and reversible Defender enablement provide traceable technical ownership. | Review pull-request checks and deployment outputs; inspect Log Analytics and Defender alerts using Labs 4, 5, and 7. | Assign business, model, data, security, privacy, and incident owners. Establish approval gates, periodic review, change management, audit retention, and a process for reporting and remediating harms. |

## Required Production Assessments

Before adapting this sandbox for a real workload:

1. Complete a Responsible AI Impact Assessment for the specific users, data, decisions, and deployment context.
2. Define measurable quality, safety, fairness, groundedness, and security criteria.
3. Build representative normal, edge-case, and adversarial evaluation datasets.
4. Record identified harms, mitigations, residual risks, owners, and approval decisions.
5. Re-run evaluations after model, prompt, retrieval, tool, policy, or data changes.
6. Publish a transparency note and an operational feedback and incident process.

## Related Guidance

- [Microsoft Responsible AI principles](https://www.microsoft.com/ai/principles-and-approach)
- [Microsoft Responsible AI Standard](https://www.microsoft.com/ai/responsible-ai-resources)
- [Responsible AI Impact Assessment Guide](https://www.microsoft.com/ai/responsible-ai-resources)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)