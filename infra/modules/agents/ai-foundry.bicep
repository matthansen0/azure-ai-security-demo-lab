// ai-foundry.bicep - Azure AI Foundry account and project for Agent Service
// Deploys the foundation for Azure AI Agent Service

@description('Location for all resources')
param location string

@description('Tags to apply to all resources')
param tags object = {}

@description('Name of the AI Foundry account')
param accountName string

@description('Name of the AI Foundry Project')
param projectName string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Existing Azure OpenAI account name to connect to')
param openAiAccountName string

@description('Existing Azure OpenAI endpoint')
param openAiEndpoint string

@description('Existing Azure AI Search service name to connect to')
param searchServiceName string

@description('Existing Azure AI Search endpoint')
param searchEndpoint string

@description('Set to true if a soft-deleted Foundry resource with the same name exists and should be restored')
param restoreSoftDeletedAccount bool = false

// AI Foundry account (project-based Foundry resource)
resource account 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
  name: accountName
  location: location
  tags: union(tags, { 'azd-service-name': 'ai-foundry' })
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled' // For demo purposes; use private endpoints in production
    restore: restoreSoftDeletedAccount
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// AI Foundry Project (first-class child resource under the Foundry account)
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: union(tags, { 'azd-service-name': 'ai-foundry-project' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Project for IT Admin troubleshooting agents'
    displayName: 'IT Admin Agent Project'
  }
}

// Connection to existing Azure OpenAI
resource openAiConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: project
  name: 'aoai-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAiEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: resourceId('Microsoft.CognitiveServices/accounts', openAiAccountName)
    }
  }
}

// Connection to existing Azure AI Search
resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-10-01-preview' = {
  parent: project
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: searchEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: resourceId('Microsoft.Search/searchServices', searchServiceName)
    }
  }
}

// Diagnostic settings for Foundry account
resource accountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'foundry-diagnostics'
  scope: account
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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

// Diagnostic settings for Foundry project
resource projectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'project-diagnostics'
  scope: project
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Outputs
output accountId string = account.id
output accountName string = account.name
output accountPrincipalId string = account.identity.principalId
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId

// Project endpoint for Agent Service API
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
