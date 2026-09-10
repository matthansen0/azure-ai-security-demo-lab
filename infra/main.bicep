// main.bicep - Azure AI Security Sandbox Infrastructure
// Deploys a complete RAG application with enterprise security controls

targetScope = 'subscription'

@description('Name of the environment (used for resource naming)')
@minLength(1)
@maxLength(20)
param environmentName string

@description('Primary location for all resources')
param location string

@description('Azure OpenAI location (may differ from primary location due to model availability)')
param openAiLocation string = location

@description('Tags to apply to all resources')
param tags object = {}

@description('Set to true to restore a soft-deleted OpenAI resource with the same name')
param restoreSoftDeletedOpenAi bool = false

@description('API Management SKU')
@allowed(['BasicV2', 'StandardV2'])
param apimSku string = 'BasicV2'

@description('Container Registry name (optional - auto-generated if not provided)')
param containerRegistryName string = ''

@description('Id of the user or app running the deployment (used for prepdocs RBAC)')
param principalId string = ''

@description('Type of principal (User for interactive deployments, ServicePrincipal for CI/CD)')
@allowed(['User', 'ServicePrincipal'])
param principalType string = 'User'

// Generate unique suffix for globally unique resource names
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var abbrs = loadJsonContent('abbreviations.json')

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: union(tags, { 'azd-env-name': environmentName })
}

// Monitoring (Log Analytics + App Insights) - deployed first so other resources can reference it
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
  }
}

// Container Registry for remote builds
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'containerRegistry'
  scope: rg
  params: {
    name: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Storage Account
module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    location: location
    tags: tags
    storageAccountName: '${abbrs.storageStorageAccounts}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Cosmos DB for chat history
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'cosmosDb'
  scope: rg
  params: {
    location: location
    tags: tags
    cosmosDbAccountName: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Azure AI Services (OpenAI + AI Search)
module aiServices 'modules/ai-services.bicep' = {
  name: 'aiServices'
  scope: rg
  params: {
    location: location
    openAiLocation: openAiLocation
    tags: tags
    openAiAccountName: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    searchServiceName: '${abbrs.searchSearchServices}${resourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    restoreSoftDeletedOpenAi: restoreSoftDeletedOpenAi
  }
}

// Azure API Management - AI Gateway
// Deployed BEFORE Container Apps so the gateway URL can be passed to the app
module apiManagement 'modules/api-management.bicep' = {
  name: 'apiManagement'
  scope: rg
  params: {
    location: location
    tags: tags
    apimServiceName: '${abbrs.apiManagementService}${resourceToken}'
    skuName: apimSku
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    applicationInsightsInstrumentationKey: monitoring.outputs.applicationInsightsInstrumentationKey
    openAiEndpoint: aiServices.outputs.openAiEndpoint
  }
}

// Role assignment for APIM managed identity to access Azure OpenAI
module apimRoleAssignments 'modules/role-assignments.bicep' = {
  name: 'apimRoleAssignments'
  scope: rg
  params: {
    principalId: apiManagement.outputs.apimIdentityPrincipalId
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchServiceName: aiServices.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
  }
}

// Container Apps - Main RAG application
// APIM routes OpenAI traffic through the AI Gateway.
module containerApps 'modules/container-apps.bicep' = {
  name: 'containerApps'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvName: '${abbrs.appManagedEnvironments}${resourceToken}'
    containerAppName: '${abbrs.appContainerApps}${resourceToken}'
    containerRegistryName: containerRegistry.outputs.name
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    resourceGroupName: rg.name
    azureSubscriptionId: subscription().subscriptionId
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    openAiEndpoint: aiServices.outputs.openAiEndpoint
    openAiDeploymentName: aiServices.outputs.chatDeploymentName
    openAiEmbeddingDeploymentName: aiServices.outputs.embeddingDeploymentName
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchEndpoint: aiServices.outputs.searchEndpoint
    searchServiceName: aiServices.outputs.searchServiceName
    searchIndexName: 'documents'
    storageAccountName: storage.outputs.storageAccountName
    storageBlobEndpoint: storage.outputs.blobEndpoint
    cosmosDbEndpoint: cosmosDb.outputs.cosmosDbEndpoint
    cosmosDbDatabaseName: cosmosDb.outputs.databaseName
    cosmosDbContainerName: cosmosDb.outputs.containerName
    // AI Gateway routing: All Azure OpenAI access goes through APIM for rate limiting, token tracking, and observability.
    apimOpenAiEndpoint: '${apiManagement.outputs.apimGatewayUrl}/${apiManagement.outputs.openAiApiPath}'
    apimSubscriptionKey: apiManagement.outputs.internalSubscriptionKey
  }
}

// Role assignments for Container App managed identity
module containerAppRoleAssignments 'modules/role-assignments.bicep' = {
  name: 'containerAppRoleAssignments'
  scope: rg
  params: {
    principalId: containerApps.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchServiceName: aiServices.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
  }
}

// Role assignments for deploying user (needed for prepdocs to upload blobs and create indexes)
module deployingUserRoleAssignments 'modules/role-assignments.bicep' = if (!empty(principalId)) {
  name: 'deployingUserRoleAssignments'
  scope: rg
  params: {
    principalId: principalId
    principalType: principalType
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchServiceName: aiServices.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
  }
}

// Front Door with WAF
module frontDoor 'modules/front-door.bicep' = {
  name: 'frontDoor'
  scope: rg
  params: {
    tags: tags
    frontDoorProfileName: '${abbrs.cdnProfiles}${resourceToken}'
    frontDoorEndpointName: 'ep-${resourceToken}'
    wafPolicyName: 'waf${resourceToken}'
    originHostName: containerApps.outputs.containerAppFqdn
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// ============ IT Admin Agent Infrastructure ============

// AI Foundry account and project for Agent Service
var foundryResourceToken = toLower(uniqueString(subscription().id, environmentName, location, 'foundry-v1'))

module aiFoundry 'modules/agents/ai-foundry.bicep' = {
  name: 'aiFoundry'
  scope: rg
  params: {
    location: location
    tags: tags
    accountName: '${abbrs.aiFoundryAccounts}${foundryResourceToken}'
    projectName: '${abbrs.machineLearningProject}${foundryResourceToken}'
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    openAiAccountName: aiServices.outputs.openAiAccountName
    openAiEndpoint: aiServices.outputs.openAiEndpoint
    searchServiceName: aiServices.outputs.searchServiceName
    searchEndpoint: aiServices.outputs.searchEndpoint
    restoreSoftDeletedAccount: restoreSoftDeletedOpenAi
  }
}

// Agent API Container App
module agentApi 'modules/agents/agent-api.bicep' = {
  name: 'agentApi'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppName: '${abbrs.appContainerApps}agent-${resourceToken}'
    containerAppsEnvId: containerApps.outputs.containerAppsEnvironmentId
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    containerRegistryName: containerRegistry.outputs.name
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    // AzureOpenAI appends /openai/deployments/... to this gateway root.
    openAiEndpoint: apiManagement.outputs.apimGatewayUrl
    openAiDeploymentName: aiServices.outputs.chatDeploymentName
    projectEndpoint: aiFoundry.outputs.projectEndpoint
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Role assignments for Agent infrastructure
module agentRoleAssignments 'modules/agents/agent-role-assignments.bicep' = {
  name: 'agentRoleAssignments'
  scope: rg
  params: {
    foundryAccountPrincipalId: aiFoundry.outputs.accountPrincipalId
    projectPrincipalId: aiFoundry.outputs.projectPrincipalId
    agentApiPrincipalId: agentApi.outputs.identityPrincipalId
    openAiAccountName: aiServices.outputs.openAiAccountName
    searchServiceName: aiServices.outputs.searchServiceName
    storageAccountName: storage.outputs.storageAccountName
  }
}

// Publish the agent API through APIM after both resources exist. This module also
// permits only the agent managed identity to use the OpenAI chat operation.
module agentApiManagement 'modules/agents/agent-api-management.bicep' = {
  name: 'agentApiManagement'
  scope: rg
  params: {
    apimServiceName: apiManagement.outputs.apimServiceName
    apimGatewayUrl: apiManagement.outputs.apimGatewayUrl
    agentApiBackendUrl: agentApi.outputs.agentApiUrl
    agentApiPrincipalId: agentApi.outputs.identityPrincipalId
    tenantId: tenant().tenantId
  }
}

// Defender for Cloud enablement is intentionally NOT performed in the core deployment.
// Use the post-deploy add-on script: ./scripts/enable-defender.sh --confirm


// Outputs
output RESOURCE_GROUP_NAME string = rg.name
output AZURE_LOCATION string = location
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

// Container Registry outputs (needed for azd deploy)
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer

// Container Apps outputs
output CONTAINER_APP_NAME string = containerApps.outputs.containerAppName
output CONTAINER_APP_FQDN string = containerApps.outputs.containerAppFqdn
output APP_INTERNAL_URL string = 'https://${containerApps.outputs.containerAppFqdn}'

// Primary public URL (Front Door)
output APP_PUBLIC_URL string = 'https://${frontDoor.outputs.frontDoorEndpointHostName}'

// Front Door outputs
output FRONTDOOR_ENDPOINT string = frontDoor.outputs.frontDoorEndpointHostName
output FRONTDOOR_URL string = 'https://${frontDoor.outputs.frontDoorEndpointHostName}'
output FRONTDOOR_PROFILE_NAME string = frontDoor.outputs.frontDoorProfileName
output FRONTDOOR_ENDPOINT_NAME string = frontDoor.outputs.frontDoorEndpointName

// AI Services outputs
output AZURE_OPENAI_ENDPOINT string = aiServices.outputs.openAiEndpoint
output AZURE_OPENAI_SERVICE string = aiServices.outputs.openAiAccountName
output AZURE_OPENAI_CHAT_DEPLOYMENT string = aiServices.outputs.chatDeploymentName
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = aiServices.outputs.embeddingDeploymentName
output AZURE_SEARCH_ENDPOINT string = aiServices.outputs.searchEndpoint
output AZURE_SEARCH_SERVICE string = aiServices.outputs.searchServiceName

// Storage outputs
output AZURE_STORAGE_ACCOUNT string = storage.outputs.storageAccountName
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint

// Cosmos DB outputs
output AZURE_COSMOSDB_ENDPOINT string = cosmosDb.outputs.cosmosDbEndpoint

// API Management outputs
output APIM_GATEWAY_URL string = apiManagement.outputs.apimGatewayUrl
output APIM_SERVICE_NAME string = apiManagement.outputs.apimServiceName
output APIM_DEVELOPER_PORTAL_URL string = apiManagement.outputs.developerPortalUrl
output AZURE_OPENAI_VIA_APIM string = '${apiManagement.outputs.apimGatewayUrl}/${apiManagement.outputs.openAiApiPath}'

// AI Gateway routing status - indicates if Container App routes through APIM
output AI_GATEWAY_ENABLED bool = true
output CONTAINER_APP_OPENAI_ENDPOINT string = containerApps.outputs.configuredOpenAiEndpoint

// Agent outputs
output AGENT_ENABLED bool = true
output AGENT_API_URL string = agentApiManagement.outputs.agentApiUrl
output AGENT_API_VIA_APIM string = agentApiManagement.outputs.agentApiUrl
output AGENT_CONTAINER_APP_URL string = agentApi.outputs.agentApiUrl
output AGENT_API_NAME string = agentApi.outputs.containerAppName
output AI_FOUNDRY_ACCOUNT_NAME string = aiFoundry.outputs.accountName
output AI_FOUNDRY_PROJECT_NAME string = aiFoundry.outputs.projectName
output AI_FOUNDRY_PROJECT_ENDPOINT string = aiFoundry.outputs.projectEndpoint
