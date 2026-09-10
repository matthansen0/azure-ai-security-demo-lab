# Troubleshooting and Operations

## Validation and CI

The [CI workflow](../.github/workflows/ci.yml) compiles Bicep, checks shell syntax, tests regional preflight behavior, and runs the IT Admin Agent test suite on pull requests and pushes to `main`. The `azd up` preprovision hook also runs the preflight and agent tests.

Run the offline checks manually:

```bash
python3 -m venv .venv-tests
./.venv-tests/bin/pip install -q pytest pytest-asyncio httpx -r ./agents/it-admin/requirements.txt
cd agents/it-admin
../../.venv-tests/bin/python -m pytest tests/ -v --tb=short
cd ../..
bash scripts/tests/preflight-check.test.sh
bash -n scripts/*.sh scripts/tests/*.sh
az bicep build --file infra/main.bicep --outfile /tmp/azure-ai-security-sandbox-main.json
```

The agent test suite is in `agents/it-admin/tests/`: `test_api.py` covers API behavior, `test_tools.py` covers tool behavior, and `conftest.py` supplies shared fixtures.

After deployment, run `bash scripts/validate.sh` for end-to-end lab validation. The postprovision hook stages sample data outside the read-only upstream submodule; when Storage public access is disabled by policy, `scripts/prepdocs-search-only.py` indexes Search without Blob page uploads.

## Other azd Commands

```bash
azd provision
azd deploy
azd env list
azd monitor
```

## Defender Plans

Defender enablement is not part of `azd up`. The add-on makes subscription-wide billing and coverage changes, so use it only with approval for the target subscription.

```bash
./scripts/enable-defender.sh --confirm
./scripts/disable-defender.sh --confirm
```

The add-on enables plans for Containers, APIs, Storage, and Cosmos DB, and applies Storage malware scanning and sensitive-data discovery settings to the sandbox account. It writes rollback state under `.defender/`.

Defender for AI availability and plan names vary by subscription. Inspect available plans, then configure an appropriate `additionalPricingPlanNames` value in `infra/addons/defender/main.bicep`. See [Defender for AI status](issues/defender-for-ai.md).

## Bicep Tooling in Codespaces

If Bicep has no validation or provisioning reports that Bicep is unavailable:

1. Confirm the `ms-azuretools.vscode-bicep` extension is installed.
2. Rebuild the Codespace to reinstall extensions.
3. Run `az bicep install --upgrade`.

## Soft-Deleted Azure OpenAI

Azure OpenAI soft-deletes resources for 90 days. When redeploying the same environment, restore it:

```bash
azd env set restoreSoftDeletedOpenAi true
azd up
```

Or purge the matching resource before redeploying:

```bash
az cognitiveservices account list-deleted
az cognitiveservices account purge --name <name> --resource-group <rg> --location <location>
azd up
```

## Soft-Deleted API Management

API Management retains deleted services for 48 hours. Purge the matching service before using its name again:

```bash
az apim deletedservice list --subscription <subscription-id>
az apim deletedservice purge --service-name <name> --location <location>
azd up
```

## Container App Image Manifest Not Found

`MANIFEST_UNKNOWN` during provisioning can occur when `azd` sets an image tag before ACR receives it. The Bicep modules provision Container Apps from a public placeholder image, and `azd deploy` then pushes and applies the real images. Ensure the current modules do not consume `SERVICE_BACKEND_IMAGE_NAME` or `SERVICE_AGENT_IMAGE_NAME` during provisioning.