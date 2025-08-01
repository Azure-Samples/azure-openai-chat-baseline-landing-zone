targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('The existing Azure AI Foundry account. This project will become a child resource of this account.')
@minLength(2)
param existingAiFoundryName string

@description('The existing Azure Cosmos DB account that is going to be used as the Azure AI Agent thread storage database (dependency).')
@minLength(3)
param existingCosmosDbAccountName string

@description('The existing Azure Storage account that is going to be used as the Azure AI Agent blob store (dependency).')
@minLength(3)
param existingStorageAccountName string

@description('The existing Azure AI Search account that is going to be used as the Azure AI Agent vector store (dependency).')
@minLength(1)
param existingAISearchAccountName string

@description('The existing Bing grounding data account that is available to Azure AI Agent agents in this project.')
@minLength(1)
param existingBingAccountName string

@description('The existing Application Insights instance to log token usage in this project.')
@minLength(1)
param existingWebApplicationInsightsResourceName string

// ---- Existing resources ----

@description('Existing Azure Cosmos DB account. Will be assigning Data Contributor role to the Azure AI Foundry project\'s identity.')
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: existingCosmosDbAccountName

  @description('Built-in Cosmos DB Data Contributor role that can be assigned to Entra identities to grant data access on a Cosmos DB database.')
  resource dataContributorRole 'sqlRoleDefinitions' existing = {
    name: '00000000-0000-0000-0000-000000000002'
  }
}

resource agentStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: existingStorageAccountName
}

resource azureAISearchService 'Microsoft.Search/searchServices@2025-02-01-preview' existing = {
  name: existingAISearchAccountName
}

resource azureAISearchServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  scope: subscription()
}

resource azureAISearchIndexDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  scope: subscription()
}

// Storage Blob Data Contributor
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

// Storage Blob Data Owner Role
resource storageBlobDataOwnerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  scope: subscription()
}

resource cosmosDbOperatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '230815da-be43-4aae-9cb4-875f7bd000aa'
  scope: subscription()
}

#disable-next-line BCP081
resource bingAccount 'Microsoft.Bing/accounts@2025-05-01-preview' existing = {
  name: existingBingAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: existingWebApplicationInsightsResourceName
}

// ---- New resources ----

@description('Existing Azure AI Foundry account. The project will be created as a child resource of this account.')
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing  = {
  name: existingAiFoundryName
}

// FIXED: Use explicit parent syntax instead of nested child resources
resource aiFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiFoundry
  name: 'projchat'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Chat using internet data in your Azure AI Agent.'
    displayName: 'Chat with Internet Data'
  }
}

// FIXED: Generate workspace ID after project is created - use guid() function as fallback
var workspaceIdAsGuid = guid(aiFoundryProject.id)

// Role assignments - moved outside project and removed from connection dependencies

resource projectDbCosmosDbOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, cosmosDbOperatorRole.id, cosmosDbAccount.id)
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDbOperatorRole.id
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, storageBlobDataContributorRole.id, agentStorageAccount.id)
  scope: agentStorageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectBlobDataOwnerConditionalAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, storageBlobDataOwnerRole.id, agentStorageAccount.id)
  scope: agentStorageAccount  
  properties: {
    principalId: aiFoundryProject.identity.principalId
    roleDefinitionId: storageBlobDataOwnerRole.id
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'})  AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${workspaceIdAsGuid}\'))'
  }
}

resource projectAISearchContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, azureAISearchServiceContributorRole.id, azureAISearchService.id)
  scope: azureAISearchService
  properties: {
    roleDefinitionId: azureAISearchServiceContributorRole.id
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectAISearchIndexDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, azureAISearchIndexDataContributorRole.id, azureAISearchService.id)
  scope: azureAISearchService
  properties: {
    roleDefinitionId: azureAISearchIndexDataContributorRole.id
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Project Connections - FIXED: Removed role assignment dependencies

@description('Create project connection to CosmosDB (thread storage); dependency for Azure AI Agent service.')
resource threadStorageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiFoundryProject
  name: cosmosDbAccount.name
  properties: {
    authType: 'AAD'
    category: 'CosmosDb'
    target: cosmosDbAccount.properties.documentEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDbAccount.id
      location: cosmosDbAccount.location
    }
  }
}

@description('Create project connection to the Azure Storage account; dependency for Azure AI Agent service.')
resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiFoundryProject
  name: agentStorageAccount.name
  properties: {
    authType: 'AAD'
    category: 'AzureStorageAccount'
    target: agentStorageAccount.properties.primaryEndpoints.blob
    metadata: {
      ApiType: 'Azure'
      ResourceId: agentStorageAccount.id
      location: agentStorageAccount.location
    }
  }
  dependsOn: [
    threadStorageConnection // Single thread these connections, else conflict errors tend to happen
  ]
}

@description('Create project connection to Azure AI Search; dependency for Azure AI Agent service.')
resource aiSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiFoundryProject
  name: azureAISearchService.name
  properties: {
    category: 'CognitiveSearch'
    target: azureAISearchService.properties.endpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: azureAISearchService.id
      location: azureAISearchService.location
    }
  }
  dependsOn: [
    storageConnection // Single thread these connections, else conflict errors tend to happen
  ]
}

@description('Connect this project to application insights for visualization of token usage.')
resource applicationInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiFoundryProject
  name:'appInsights-connection'
  properties: {
    authType: 'ApiKey'
    category: 'AppInsights'
    credentials: {
      key: applicationInsights.properties.ConnectionString
    }
    isSharedToAll: false
    target: applicationInsights.id
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsights.id
      location: applicationInsights.location
    }
  }
  dependsOn: [
    aiSearchConnection // Single thread these connections, else conflict errors tend to happen
  ]
}

// CosmosDB role assignments for the project - FIXED: Use account-level scope instead of container-level
resource projectCosmosDbDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-12-01-preview' = {
  parent: cosmosDbAccount
  name: guid(aiFoundryProject.id, cosmosDbAccount::dataContributorRole.id, 'account-level')
  properties: {
    roleDefinitionId: cosmosDbAccount::dataContributorRole.id
    principalId: aiFoundryProject.identity.principalId
    scope: cosmosDbAccount.id  // Account-level scope instead of container-level
  }
  dependsOn: [
    applicationInsightsConnection
  ]
}

@description('Create the Azure AI Agent service.')
resource aiAgentService 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: aiFoundryProject
  name: 'projectagents'
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: ['${aiSearchConnection.name}']
    storageConnections: ['${storageConnection.name}']
    threadStorageConnections: ['${threadStorageConnection.name}']
  }
  dependsOn: [
    projectCosmosDbDataContributor // Wait for all permissions to be set
  ]
}

@description('Create project connection to Bing grounding data. Useful for future agents that get created.')
resource bingGroundingConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiFoundryProject
  name: replace(existingBingAccountName, '-', '')
  properties: {
    authType: 'ApiKey'
    target: bingAccount.properties.endpoint
    category: 'GroundingWithBingSearch'
    metadata: {
      type: 'bing_grounding'
      ApiType: 'Azure'
      ResourceId: bingAccount.id
      location: bingAccount.location
    }
    credentials: {
      key: bingAccount.listKeys().key1
    }
    isSharedToAll: false
  }
  dependsOn: [
    aiAgentService  // Deploy after the Azure AI Agent service is provisioned, not a dependency.
  ]
}

// ---- Outputs ----

output aiAgentProjectEndpoint string = aiFoundryProject.properties.endpoints['AI Foundry API']
