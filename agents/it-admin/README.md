# IT Admin Agent

An AI-powered troubleshooting agent for IT administrators. This agent helps diagnose and resolve infrastructure issues by gathering system information, analyzing metrics and logs, and providing actionable recommendations.

## Overview

The IT Admin Agent demonstrates:
- **Azure AI Foundry integration** - Uses a project-based AI Foundry account and Project for agent management
- **API gateway protection** - APIM publishes the agent at `/it-agent` and requires a subscription key
- **Tool calling** - Agent uses tools to gather information about systems
- **Multi-step reasoning** - Diagnoses issues through iterative investigation
- **Mock data** - Realistic Azure infrastructure data for demonstration

## Architecture

```
                       curl/Postman/Developer Portal
                              │
                              ▼
                       API Management (/it-agent) ──▶ IT Admin Agent API (Container App)
                              ▲                         │                │
                              │                         ▼                ▼
                              └──────────── API Management       Tool Functions / AI Foundry
                                (/openai, managed identity)     (Mock Data)
                                       │
                                       ▼
                                   Azure OpenAI (GPT-4o)
```

## Deployment

`azd up` provisions:
- Project-based AI Foundry account and Project
- Agent API Container App
- APIM `/it-agent` API, operations, and `ai-gateway` product link
- Published APIM developer portal
- Required role assignments

## API Reference

The paths below are relative to the `AGENT_API_URL` azd output and require the
`Ocp-Apim-Subscription-Key` header. Browse the same operations at the
`APIM_DEVELOPER_PORTAL_URL` azd output.

### Health Check

```bash
GET /health
```

Returns:
```json
{
  "status": "healthy",
  "timestamp": "2024-02-05T10:30:00Z",
  "openai_configured": true,
  "project_configured": true
}
```

### List Available Tools

```bash
GET /tools
```

Returns the list of tools the agent can use.

### Chat with Agent

```bash
POST /chat
Content-Type: application/json

{
  "message": "A user reports that web-app-prod is slow. Can you investigate?",
  "conversation_id": "optional-for-follow-up",
  "context": {
    "environment": "production",
    "region": "eastus"
  }
}
```

Response:
```json
{
  "response": "I've investigated web-app-prod and found several issues...",
  "conversation_id": "conv_20240205103045123456",
  "tool_calls": [
    {
      "tool_name": "get_system_metrics",
      "arguments": {"resource_name": "web-app-prod", "metric_type": "all"},
      "result": {...}
    }
  ]
}
```

### Call Tool Directly (Debug)

```bash
POST /tools/{tool_name}
Content-Type: application/json

{
  "resource_name": "web-app-prod",
  "metric_type": "cpu"
}
```

### Clear Conversation

```bash
DELETE /conversations/{conversation_id}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `get_system_config` | Get configuration of an Azure resource (SKU, settings, deployment details) |
| `get_system_metrics` | Get performance metrics (CPU, memory, latency, requests, errors) |
| `get_recent_logs` | Get recent log entries, optionally filtered by severity |
| `get_service_health` | Check Azure service health for known issues in a region |
| `get_recent_changes` | Get recent deployments and configuration changes |
| `check_dependencies` | List upstream and downstream dependencies |
| `get_resource_details` | Get comprehensive resource details (RG, subscription, tags) |

## Mock Data

The agent uses mock data to simulate a realistic Azure environment with intentional issues:

### Mock Resources

- `web-app-prod` - Container App with high CPU (simulated issue)
- `sql-db-main` - SQL Database with high latency (simulated issue)
- `api-gateway` - API Management with error spike (simulated issue)
- `redis-cache-prod` - Redis Cache (healthy)
- `storage-prod` - Storage Account (healthy)

### Simulated Issues

1. **web-app-prod**: CPU at ~85%, memory at ~70%
2. **sql-db-main**: P95 latency ~2 seconds + Azure service health incident
3. **api-gateway**: Elevated 500/502/503 errors

## Extending the Agent

### Adding New Tools

1. Add tool definition to `tools/__init__.py`:

```python
TOOL_DEFINITIONS.append({
    "type": "function",
    "function": {
        "name": "my_new_tool",
        "description": "Description of what the tool does",
        "parameters": {
            "type": "object",
            "properties": {
                "param1": {"type": "string", "description": "..."}
            },
            "required": ["param1"]
        }
    }
})
```

2. Implement the function:

```python
def my_new_tool(param1: str) -> Dict[str, Any]:
    # Implementation
    return {"result": "..."}
```

3. Register in `TOOL_FUNCTIONS` and import in `app.py`.

### Adding Mock Data

Edit `MOCK_RESOURCES` in `tools/__init__.py` to add new resources:

```python
MOCK_RESOURCES["my-new-resource"] = {
    "type": "resource_type",
    "resource_group": "rg-production",
    "config": {...},
    "dependencies": {...}
}
```

### Connecting to Real Azure Resources

To connect to real Azure resources instead of mock data:

1. Create a real tool implementation using Azure SDK:

```python
from azure.mgmt.monitor import MonitorManagementClient
from azure.identity import DefaultAzureCredential

def get_real_metrics(resource_id: str, metric_type: str):
    credential = DefaultAzureCredential()
    client = MonitorManagementClient(credential, subscription_id)
    # Query real metrics...
```

2. Replace mock function in `TOOL_FUNCTIONS`.

## Security Considerations

### Current State (Demo)

- Uses public endpoints
- Mock data only (no real resource access)
- Managed identity for Azure OpenAI

### Production Recommendations

- Enable private endpoints for AI Foundry and Container Apps
- Implement proper authentication (API keys, OAuth, etc.)
- Add rate limiting
- Enable audit logging to Log Analytics
- Add content safety filters
- Implement tool access controls (which tools can be called)
- Add human-in-the-loop for sensitive operations

## Tests

Run the agent unit/regression suite from this directory:

```bash
python -m pytest tests/ -v --tb=short
```

Test files:
- `tests/test_api.py` — FastAPI health, tools, tool invocation, chat, content type, conversation, and destructive-tool safety coverage
- `tests/test_tools.py` — tool schema, mock resource data, tool handler, edge case, and agentic scenario coverage
- `tests/conftest.py` — shared pytest fixtures for chat requests, tool arguments, and mock resource lists

## Local Development

```bash
cd agents/it-admin

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export AZURE_OPENAI_ENDPOINT="https://your-openai.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4o"

# Run locally
uvicorn app:app --reload --port 8080
```

## Troubleshooting

### Agent returns generic responses

- Check `AZURE_OPENAI_ENDPOINT` is set
- Check `AZURE_OPENAI_DEPLOYMENT` matches your model deployment name
- View logs: `az containerapp logs show -n ca-agent-xxx -g rg-xxx --type console`

### Tool calls failing

- Check tool is registered in `TOOL_FUNCTIONS`
- View tool call details in response `tool_calls` array

### Authentication errors

- Ensure Container App managed identity has "Cognitive Services OpenAI User" role
- Check role assignment propagation (can take a few minutes)
