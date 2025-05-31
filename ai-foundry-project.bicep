@description('Create the Azure AI Agent service.')
// TEMPORARILY COMMENTED OUT - CREATE MANUALLY IN PORTAL
/*
resource aiAgentService 'capabilityHosts' = {
  name: 'projectagents'
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: ['${aiSearchConnection.name}']
    storageConnections: ['${storageConnection.name}']
    threadStorageConnections: ['${threadStorageConnection.name}']
  }
  dependsOn: [
    applicationInsightsConnection  // Single thread changes to the project, else conflict errors tend to happen
  ]
}
*/

@description('Create project connection to Bing grounding data. Useful for future agents that get created.')
resource bingGroundingConnection 'connections' = {
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
    applicationInsightsConnection  // Deploy after application insights connection is configured
  ]
} 
