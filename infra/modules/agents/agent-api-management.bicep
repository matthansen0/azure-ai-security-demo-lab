// agent-api-management.bicep - APIM ingress and Azure OpenAI routing for the IT Admin Agent

param apimServiceName string
param apimGatewayUrl string
param agentApiBackendUrl string
param agentApiPrincipalId string
param tenantId string

var openIdConfigurationUrl = '${environment().authentication.loginEndpoint}${tenantId}/.well-known/openid-configuration'
var agentChatCompletionsPolicyXml = replace(replace('''
<policies>
  <inbound>
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
        <!-- Existing internal APIM client. -->
      </when>
      <otherwise>
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized" require-expiration-time="true" require-signed-tokens="true">
          <openid-config url="__OPENID_CONFIGURATION_URL__" />
          <audiences>
            <audience>https://cognitiveservices.azure.com</audience>
          </audiences>
          <required-claims>
            <claim name="oid" match="all">
              <value>__AGENT_API_PRINCIPAL_ID__</value>
            </claim>
          </required-claims>
        </validate-jwt>
      </otherwise>
    </choose>
    <set-header name="api-key" exists-action="delete" />
    <set-header name="Authorization" exists-action="delete" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="managed-id-access-token" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
    </set-header>
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
''', '__OPENID_CONFIGURATION_URL__', openIdConfigurationUrl), '__AGENT_API_PRINCIPAL_ID__', agentApiPrincipalId)
var agentApiPolicyXml = replace('''
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>__DEVELOPER_PORTAL_ORIGIN__</origin>
      </allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>GET</method>
        <method>POST</method>
        <method>DELETE</method>
      </allowed-methods>
      <allowed-headers>
        <header>content-type</header>
        <header>ocp-apim-subscription-key</header>
      </allowed-headers>
    </cors>
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
''', '__DEVELOPER_PORTAL_ORIGIN__', 'https://${apimServiceName}.developer.azure-api.net')

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

resource openAiApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' existing = {
  parent: apimService
  name: 'azure-openai'
}

resource chatCompletionsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' existing = {
  parent: openAiApi
  name: 'chat-completions'
}

// The agent authenticates to APIM with its managed identity. Internal applications
// continue to use the existing APIM subscription key through the same operation.
resource agentChatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: chatCompletionsOperation
  name: 'policy'
  properties: {
    format: 'xml'
    value: agentChatCompletionsPolicyXml
  }
}

resource agentApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'it-admin-agent'
  properties: {
    displayName: 'IT Admin Agent API'
    description: 'AI-powered IT infrastructure troubleshooting API'
    subscriptionRequired: true
    path: 'it-agent'
    protocols: ['https']
    serviceUrl: agentApiBackendUrl
    apiType: 'http'
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
  }
}

resource agentApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: agentApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: agentApiPolicyXml
  }
}

resource healthOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'health_check_health_get'
  properties: {
    displayName: 'Get agent health'
    method: 'GET'
    urlTemplate: '/health'
  }
}

resource toolsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'list_tools_tools_get'
  properties: {
    displayName: 'List agent tools'
    method: 'GET'
    urlTemplate: '/tools'
  }
}

resource chatOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'chat_chat_post'
  properties: {
    displayName: 'Chat with the IT Admin Agent'
    method: 'POST'
    urlTemplate: '/chat'
  }
}

resource callToolOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'call_tool_directly_tools__tool_name__post'
  properties: {
    displayName: 'Call an agent tool'
    method: 'POST'
    urlTemplate: '/tools/{tool_name}'
    templateParameters: [
      {
        name: 'tool_name'
        required: true
        type: 'string'
        description: 'Name of the tool to invoke'
      }
    ]
  }
}

resource clearConversationOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: agentApi
  name: 'clear_conversation_conversations__conversation_id__delete'
  properties: {
    displayName: 'Clear a conversation'
    method: 'DELETE'
    urlTemplate: '/conversations/{conversation_id}'
    templateParameters: [
      {
        name: 'conversation_id'
        required: true
        type: 'string'
        description: 'Conversation identifier'
      }
    ]
  }
}

resource aiGatewayProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' existing = {
  parent: apimService
  name: 'ai-gateway'
}

resource agentProductApiLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: aiGatewayProduct
  name: agentApi.name
}

output agentApiPath string = agentApi.properties.path
output agentApiUrl string = '${apimGatewayUrl}/${agentApi.properties.path}'