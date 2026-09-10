// agent-api.bicep - Container App for IT Admin Agent API
// Deploys a FastAPI application that exposes the IT Admin troubleshooting agent

@description('Location for all resources')
param location string

@description('Tags to apply to all resources')
param tags object = {}

@description('Name of the Container App')
param containerAppName string

@description('Container Apps Environment ID')
param containerAppsEnvId string

@description('Container Registry login server')
param containerRegistryLoginServer string

@description('Container image name (set by azd deploy)')
param imageName string = ''

@description('Application Insights connection string')
param applicationInsightsConnectionString string

@description('Azure OpenAI endpoint')
param openAiEndpoint string

@description('Azure OpenAI deployment name for the agent')
param openAiDeploymentName string

@description('AI Foundry Project endpoint for Agent Service')
param projectEndpoint string

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Container Registry name for ACR pull role assignment')
param containerRegistryName string

// Container image - use placeholder during initial provision, real image after azd deploy
var containerImage = !empty(imageName) ? imageName : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// AcrPull role definition ID
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// Reference to existing Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

// User-assigned managed identity for ACR pull
resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${containerAppName}-acr-identity'
  location: location
  tags: tags
}

// Grant AcrPull role to the identity BEFORE creating Container App
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, acrPullIdentity.id, acrPullRoleId)
  scope: containerRegistry
  properties: {
    principalId: acrPullIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Container App for Agent API
resource agentApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'agent' })
  dependsOn: [acrPullRoleAssignment]  // Wait for ACR pull permissions
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: containerRegistryLoginServer
          identity: acrPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'agent-api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiEndpoint
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: openAiDeploymentName
            }
            {
              name: 'AI_PROJECT_ENDPOINT'
              value: projectEndpoint
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Diagnostic settings - only metrics since log categories aren't supported for Container Apps
resource agentAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'agent-api-diagnostics'
  scope: agentApp
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
output containerAppName string = agentApp.name
output containerAppFqdn string = agentApp.properties.configuration.ingress.fqdn
output identityPrincipalId string = agentApp.identity.principalId
output acrPullIdentityPrincipalId string = acrPullIdentity.properties.principalId
output acrPullIdentityId string = acrPullIdentity.id
output agentApiUrl string = 'https://${agentApp.properties.configuration.ingress.fqdn}'
output imageName string = containerImage
