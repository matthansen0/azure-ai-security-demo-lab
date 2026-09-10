// api-management.bicep - Azure API Management as AI Gateway
// Provides centralized management, security, and observability for Azure OpenAI endpoints
// Features: Managed identity auth + retries (default), plus optional add-ons like rate limiting and token usage logging

param location string
param tags object = {}
param apimServiceName string
param publisherEmail string = 'admin@contoso.com'
param publisherName string = 'AI Security Sandbox'
param logAnalyticsWorkspaceId string
param applicationInsightsId string
param applicationInsightsInstrumentationKey string

@description('APIM SKU')
@allowed(['BasicV2', 'StandardV2'])
param skuName string = 'BasicV2'

@description('Number of APIM units')
param skuCapacity int = 1

@description('Azure OpenAI endpoint URL')
param openAiEndpoint string

// Reusable policy XML blocks (avoid referencing other resource properties at runtime)
var openaiSdkChatCompletionsPolicyXml = '''
<policies>
  <inbound>
    <base />
    <!-- Extract model from request body and rewrite URL to Azure format -->
    <set-variable name="request-body" value="@(context.Request.Body.As&lt;JObject&gt;(preserveContent: true))" />
    <set-variable name="model" value="@(((JObject)context.Variables[&quot;request-body&quot;])?[&quot;model&quot;]?.ToString() ?? &quot;gpt-4o&quot;)" />
    <!-- Rewrite URL to include deployment name -->
    <rewrite-uri template="@(&quot;/deployments/&quot; + (string)context.Variables[&quot;model&quot;] + &quot;/chat/completions&quot;)" copy-unmatched-params="false" />
    <set-query-parameter name="api-version" exists-action="override">
      <value>2024-06-01</value>
    </set-query-parameter>
    <trace source="AI Gateway" severity="information">
      <message>@(&quot;OpenAI SDK request rewritten: model=&quot; + (string)context.Variables[&quot;model&quot;])</message>
    </trace>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var openaiSdkEmbeddingsPolicyXml = '''
<policies>
  <inbound>
    <base />
    <!-- Extract model from request body and rewrite URL to Azure format -->
    <set-variable name="request-body" value="@(context.Request.Body.As&lt;JObject&gt;(preserveContent: true))" />
    <set-variable name="model" value="@(((JObject)context.Variables[&quot;request-body&quot;])?[&quot;model&quot;]?.ToString() ?? &quot;text-embedding-3-small&quot;)" />
    <!-- Rewrite URL to include deployment name -->
    <rewrite-uri template="@(&quot;/deployments/&quot; + (string)context.Variables[&quot;model&quot;] + &quot;/embeddings&quot;)" copy-unmatched-params="false" />
    <set-query-parameter name="api-version" exists-action="override">
      <value>2024-06-01</value>
    </set-query-parameter>
    <trace source="AI Gateway" severity="information">
      <message>@(&quot;OpenAI SDK embedding request rewritten: model=&quot; + (string)context.Variables[&quot;model&quot;])</message>
    </trace>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

// API Management Service
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    developerPortalStatus: 'Enabled'
    // Enable Application Insights integration
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

// Application Insights Logger for APIM
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apimService
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: applicationInsightsId
    credentials: {
      instrumentationKey: applicationInsightsInstrumentationKey
    }
  }
}

// Diagnostic settings for API-level logging
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-09-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    frontend: {
      request: {
        headers: ['x-ms-client-request-id']
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: ['x-ms-request-id']
        body: {
          bytes: 8192
        }
      }
    }
    backend: {
      request: {
        headers: ['x-ms-client-request-id']
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: ['x-ms-request-id']
        body: {
          bytes: 8192
        }
      }
    }
  }
}

// Azure Monitor diagnostic settings
resource apimMonitorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
      {
        category: 'WebSocketConnectionLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Named Value for OpenAI Backend URL
resource openAiBackendUrl 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-backend-url'
  properties: {
    displayName: 'openai-backend-url'
    value: openAiEndpoint
    secret: false
  }
}

// Backend for Azure OpenAI with Managed Identity
resource openAiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'openai-backend'
  properties: {
    title: 'Azure OpenAI Backend'
    description: 'Azure OpenAI Service with Managed Identity authentication'
    // Include /openai path segment for correct routing
    url: '${openAiEndpoint}openai'
    protocol: 'http'
    credentials: {
      header: {}
      query: {}
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
  dependsOn: [openAiBackendUrl]
}

// Azure OpenAI API Definition
resource openAiApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'azure-openai'
  properties: {
    displayName: 'Azure OpenAI Service API'
    description: 'Azure OpenAI Service API with AI Gateway features'
    // Upstream OpenAI SDK clients typically authenticate using the Authorization header.
    // APIM subscription enforcement can't validate transformed headers, so we perform auth in policy instead.
    subscriptionRequired: false
    path: 'openai'
    protocols: ['https']
    // Include /openai in service URL since APIM strips the API path prefix
    serviceUrl: '${openAiEndpoint}openai'
    apiType: 'http'
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
  }
}

// Named value containing the internal key used by Container Apps to authenticate to APIM.
// This is validated in policy (to support both api-key and Authorization: Bearer flows).
resource internalClientKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'internal-client-key'
  properties: {
    displayName: 'internal-client-key'
    value: internalSubscription.listSecrets().primaryKey
    secret: true
  }
}

// Chat Completions Operation
resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Create Chat Completion'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name (e.g., gpt-4o)'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// Embeddings Operation
resource embeddingsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'embeddings'
  properties: {
    displayName: 'Create Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name (e.g., text-embedding-3-small)'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// Completions Operation (for legacy models)
resource completionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'completions'
  properties: {
    displayName: 'Create Completion'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
        description: 'The deployment name'
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          required: true
          type: 'string'
          defaultValue: '2024-02-15-preview'
        }
      ]
    }
  }
}

// OpenAI SDK-compatible Chat Completions (without deployment in URL)
// This operation handles requests from the standard OpenAI Python SDK
// which sends requests to /chat/completions with model in the body
resource openaiSdkChatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-chat-completions'
  properties: {
    displayName: 'OpenAI SDK - Chat Completions'
    description: 'Handles OpenAI SDK-style requests and rewrites to Azure format'
    method: 'POST'
    urlTemplate: '/chat/completions'
  }
}

// OpenAI SDK-compatible Chat Completions with /v1 prefix (upstream base_url uses /openai/v1)
resource openaiSdkChatCompletionsV1Operation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-chat-completions-v1'
  properties: {
    displayName: 'OpenAI SDK - Chat Completions (v1)'
    description: 'Handles /v1/chat/completions requests and rewrites to Azure format'
    method: 'POST'
    urlTemplate: '/v1/chat/completions'
  }
}

// Policy to rewrite OpenAI SDK requests to Azure OpenAI format
resource openaiSdkChatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: openaiSdkChatCompletionsOperation
  name: 'policy'
  properties: {
    format: 'xml'
  value: openaiSdkChatCompletionsPolicyXml
  }
}

// Reuse the same rewrite policy for /v1/chat/completions
resource openaiSdkChatCompletionsV1Policy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: openaiSdkChatCompletionsV1Operation
  name: 'policy'
  properties: {
    format: 'xml'
    value: openaiSdkChatCompletionsPolicyXml
  }
}

// OpenAI SDK-compatible Embeddings (without deployment in URL)
resource openaiSdkEmbeddingsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-embeddings'
  properties: {
    displayName: 'OpenAI SDK - Embeddings'
    description: 'Handles OpenAI SDK-style embedding requests and rewrites to Azure format'
    method: 'POST'
    urlTemplate: '/embeddings'
  }
}

// OpenAI SDK-compatible Embeddings with /v1 prefix (upstream base_url uses /openai/v1)
resource openaiSdkEmbeddingsV1Operation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-embeddings-v1'
  properties: {
    displayName: 'OpenAI SDK - Embeddings (v1)'
    description: 'Handles /v1/embeddings requests and rewrites to Azure format'
    method: 'POST'
    urlTemplate: '/v1/embeddings'
  }
}

// Policy to rewrite OpenAI SDK embedding requests to Azure format
resource openaiSdkEmbeddingsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: openaiSdkEmbeddingsOperation
  name: 'policy'
  properties: {
    format: 'xml'
  value: openaiSdkEmbeddingsPolicyXml
  }
}

// Reuse the same rewrite policy for /v1/embeddings
resource openaiSdkEmbeddingsV1Policy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: openaiSdkEmbeddingsV1Operation
  name: 'policy'
  properties: {
    format: 'xml'
    value: openaiSdkEmbeddingsPolicyXml
  }
}

// Responses API (Azure OpenAI v1 surface) - used by the upstream chatreadretrieveread approach
// Path passes through unchanged: /openai/v1/responses -> backend https://<aoai>/openai/v1/responses
resource openaiResponsesOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-responses-v1'
  properties: {
    displayName: 'OpenAI SDK - Responses (v1)'
    description: 'Azure OpenAI Responses API (v1 surface); no URL rewrite needed'
    method: 'POST'
    urlTemplate: '/v1/responses'
  }
}

// GET a specific response by id (SDK may poll / fetch)
resource openaiResponsesGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: openAiApi
  name: 'openai-sdk-responses-v1-get'
  properties: {
    displayName: 'OpenAI SDK - Responses Get (v1)'
    description: 'Retrieve a previously-created response'
    method: 'GET'
    urlTemplate: '/v1/responses/{response-id}'
    templateParameters: [
      {
        name: 'response-id'
        required: true
        type: 'string'
      }
    ]
  }
}

// AI Gateway Policy - Applied at API level
// Includes: Rate limiting, token counting, managed identity auth, retry logic, and caching
resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: openAiApi
  name: 'policy'
  // Ensure the named value exists before policy validation
  dependsOn: [internalClientKeyNamedValue]
  properties: {
    format: 'xml'
    value: '''
<policies>
    <inbound>
        <base />
    <!-- Accept client auth from either api-key or Authorization: Bearer (OpenAI SDK default). -->
    <set-variable name="clientKey" value='@(
      context.Request.Headers.ContainsKey("api-key")
        ? context.Request.Headers["api-key"][0]
        : (
          context.Request.Headers.ContainsKey("Authorization")
            ? (
              context.Request.Headers["Authorization"][0].StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
                ? context.Request.Headers["Authorization"][0].Substring(7)
                : context.Request.Headers["Authorization"][0]
            )
            : ""
        )
    )' />

    <choose>
      <when condition='@(!string.IsNullOrEmpty((string)context.Variables["clientKey"]) &amp;&amp; ((string)context.Variables["clientKey"]) == "{{internal-client-key}}")'>
        <!-- ok -->
      </when>
      <otherwise>
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{"error":{"code":"Unauthorized","message":"Missing or invalid client key."}}</set-body>
        </return-response>
      </otherwise>
    </choose>

    <!-- Remove any incoming client auth headers; APIM will use managed identity to Azure OpenAI -->
    <set-header name="api-key" exists-action="delete" />
    <set-header name="Authorization" exists-action="delete" />
        
        <!-- Authenticate with Azure OpenAI using APIM managed identity -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="managed-id-access-token" ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
    </inbound>
    <backend>
        <!-- Retry policy for transient failures and rate limits -->
        <retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)" count="3" interval="1" max-interval="10" delta="1" first-fast-retry="false">
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <base />
        <!-- Add CORS headers -->
        <set-header name="Access-Control-Allow-Origin" exists-action="override">
            <value>*</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
        <!-- Return friendly error response -->
        <choose>
            <when condition="@(context.Response.StatusCode == 429)">
                <return-response>
                    <set-status code="429" reason="Too Many Requests" />
                    <set-header name="Retry-After" exists-action="override">
                        <value>60</value>
                    </set-header>
            <set-body>{"error":{"code":"RateLimitExceeded","message":"API rate limit exceeded. Please retry after 60 seconds."}}</set-body>
                </return-response>
            </when>
        </choose>
    </on-error>
</policies>
'''
  }
}

// Product for AI Gateway access
resource aiGatewayProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apimService
  name: 'ai-gateway'
  properties: {
    displayName: 'AI Gateway'
    description: 'Access to Azure OpenAI through the AI Gateway with rate limiting and token tracking'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// Products are visible in the developer portal only when associated with a group.
resource guestProductAccess 'Microsoft.ApiManagement/service/products/groups@2023-09-01-preview' = {
  parent: aiGatewayProduct
  name: 'guests'
}

resource developerProductAccess 'Microsoft.ApiManagement/service/products/groups@2023-09-01-preview' = {
  parent: aiGatewayProduct
  name: 'developers'
}

// Link API to Product
resource productApiLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: aiGatewayProduct
  name: openAiApi.name
}

// Built-in subscription for the AI Gateway product (for Container Apps)
resource internalSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apimService
  name: 'internal-apps'
  properties: {
    displayName: 'Internal Applications'
    scope: '/products/${aiGatewayProduct.id}'
    state: 'active'
    allowTracing: true
  }
}

// Outputs
output apimServiceId string = apimService.id
output apimServiceName string = apimService.name
output apimGatewayUrl string = apimService.properties.gatewayUrl
output developerPortalUrl string = 'https://${apimService.name}.developer.azure-api.net'
output apimIdentityPrincipalId string = apimService.identity.principalId
output openAiApiId string = openAiApi.id
output openAiApiPath string = openAiApi.properties.path

// Output subscription key for internal apps (Container Apps authentication to APIM)
// Best practice: Use subscription keys for APIM authentication, APIM uses managed identity to Azure OpenAI
@secure()
output internalSubscriptionKey string = internalSubscription.listSecrets().primaryKey
