targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Existing Azure AI Foundry account name')
param existingAiFoundryName string

@description('Existing AI Search account name')
param existingAISearchAccountName string

@description('Existing Cosmos DB account name')
param existingCosmosDbAccountName string

@description('Existing Storage account name')
param existingStorageAccountName string

@description('Existing Bing account name')
param existingBingAccountName string

@description('Existing Application Insights name')
param existingApplicationInsightsName string

@description('Existing Key Vault name')
param existingKeyVaultName string

var aiFoundryProjectName = 'aifp-workload'

// Existing resources
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: existingAiFoundryName
}

resource aiSearch 'Microsoft.Search/searchServices@2025-02-01-preview' existing = {
  name: existingAISearchAccountName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: existingCosmosDbAccountName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: existingStorageAccountName
}

#disable-next-line BCP081
resource bingAccount 'Microsoft.Bing/accounts@2025-05-01-preview' existing = {
  name: existingBingAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: existingApplicationInsightsName
}

resource keyVault 'Microsoft.KeyVault/vaults@2025-02-01-preview' existing = {
  name: existingKeyVaultName
}

// AI Foundry Project
resource aiFoundryProject 'Microsoft.MachineLearningServices/workspaces@2025-04-01-preview' = {
  name: aiFoundryProjectName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    friendlyName: aiFoundryProjectName
    description: 'Azure AI Foundry project for the workload'
    hubResourceId: aiFoundry.id
    applicationInsights: applicationInsights.id
    storageAccount: storageAccount.id
    keyVault: keyVault.id
  }
  kind: 'project'

  // Connections for AI Agent Service
  resource aiSearchConnection 'connections' = {
    name: 'aisearch-connection'
    properties: {
      category: 'CognitiveSearch'
      target: 'https://${aiSearch.name}.search.windows.net/'
      authType: 'AAD'
      isSharedToAll: true
      metadata: { ApiType: 'Azure', ResourceId: aiSearch.id }
    }
  }

  resource cosmosDbConnection 'connections' = {
    name: 'cosmosdb-connection'
    properties: {
      category: 'CosmosDb'
      target: cosmosDbAccount.properties.documentEndpoint
      authType: 'AAD'
      isSharedToAll: true
      metadata: { ResourceId: cosmosDbAccount.id }
    }
  }

  resource storageConnection 'connections' = {
    name: 'storage-connection'
    properties: {
      category: 'AzureBlob'
      target: 'https://${storageAccount.name}.blob.core.windows.net/'
      authType: 'AAD'
      isSharedToAll: true
      metadata: { ResourceId: storageAccount.id }
    }
  }

  resource bingSearchConnection 'connections' = {
    name: 'bing-grounding-connection'
    properties: {
      category: 'BingSearch'
      target: 'https://api.bing.microsoft.com/'
      authType: 'ApiKey'
      isSharedToAll: true
      credentials: { key: bingAccount.listKeys().key1 }
      metadata: { ApiType: 'Bing', ResourceId: bingAccount.id }
    }
  }
}

output aiFoundryProjectName string = aiFoundryProject.name
output bingSearchConnectionId string = aiFoundryProject::bingSearchConnection.name
output managedOnlineEndpointResourceId string = '' // Placeholder for backward compatibility 
