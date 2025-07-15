targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Assign your user some roles to support access to the Azure AI Agent dependencies for troubleshooting post deployment')
@maxLength(36)
@minLength(36)
param debugUserPrincipalId string

@description('The resource group name of the spoke virtual network')
param spokeResourceGroupName string

@description('The resource ID for the subnet that private endpoints in the workload should surface in.')
@minLength(1)
param privateEndpointSubnetResourceId string

// ---- New resources ----

@description('This is the log sink for all Azure Diagnostics in the workload.')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'log-workload'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    forceCmkForQuery: false
    workspaceCapping: {
      dailyQuotaGb: 10 // Production readiness change: In production, tune this value to ensure operational logs are collected, but a reasonable cap is set.
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Deploy Azure Storage account for the Azure AI Agent service (dependency). This is used for binaries uploaded within threads or as "knowledge" uploaded as part of an agent.')
module deployAgentStorageAccount 'ai-agent-blob-storage.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    spokeResourceGroupName: spokeResourceGroupName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

@description('Deploy Azure Cosmos DB account for the Azure AI Agent service (dependency). This is used for storing agent definitions and threads.')
module deployCosmosDbThreadStorageAccount 'cosmos-db.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    spokeResourceGroupName: spokeResourceGroupName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

@description('Deploy Azure AI Search instance for the Azure AI Agent service (dependency). This is used when a user uploads a file to the agent, and the agent needs to search for information in that file.')
module deployAzureAISearchService 'ai-search.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    spokeResourceGroupName: spokeResourceGroupName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

// @description('Create a managed identity for deployment scripts to wait for capability hosts.')
// resource deploymentScriptManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
//   name: 'id-${baseName}-deployment-script'
//   location: location
// }

// @description('Assign the managed identity Contributor role for deployment script operations.')
// resource deploymentScriptRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(deploymentScriptManagedIdentity.id, resourceGroup().id, 'Contributor')
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
//     principalId: deploymentScriptManagedIdentity.properties.principalId
//     principalType: 'ServicePrincipal'
//   }
// }

// ---- Outputs ----

output cosmosDbAccountName string = deployCosmosDbThreadStorageAccount.outputs.cosmosDbAccountName
output storageAccountName string = deployAgentStorageAccount.outputs.storageAccountName
output aiSearchName string = deployAzureAISearchService.outputs.aiSearchName
// output deploymentScriptManagedIdentityId string = deploymentScriptManagedIdentity.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
