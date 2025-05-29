targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

@description('Debug user principal ID')
param debugUserPrincipalId string

@description('Private endpoint subnet resource ID')
param privateEndpointSubnetResourceId string

@description('Hub resource group name for private DNS zones')
param hubResourceGroupName string

var cosmosDbAccountName = 'cosmos${baseName}'

// Existing resources
resource cosmosDbLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
  scope: resourceGroup(hubResourceGroupName)
}

resource cosmosDbAccountReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(hubResourceGroupName)
}

// Cosmos DB
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  identity: { type: 'SystemAssigned' }
  properties: {
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []
    ipRules: []
    virtualNetworkRules: []
    capabilities: [{ name: 'EnableServerless' }]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }

  resource enterpriseMemoryDatabase 'sqlDatabases' = {
    name: 'enterprise_memory'
    properties: { resource: { id: 'enterprise_memory' } }
  }
}

// Role assignment
resource cosmosDbAccountReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosDbAccount.id, cosmosDbAccountReaderRole.id, debugUserPrincipalId)
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDbAccountReaderRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// Private endpoint
resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-cosmos-db-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-cosmos-db-${baseName}'
    privateLinkServiceConnections: [{
      name: 'cosmosdb'
      properties: {
        privateLinkServiceId: cosmosDbAccount.id
        groupIds: ['Sql']
      }
    }]
  }

  resource dnsGroup 'privateDnsZoneGroups' = {
    name: 'cosmosdb'
    properties: {
      privateDnsZoneConfigs: [{
        name: 'cosmosdb'
        properties: { privateDnsZoneId: cosmosDbLinkedPrivateDnsZone.id }
      }]
    }
  }
}

// Diagnostics
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: cosmosDbAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      { category: 'DataPlaneRequests', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'QueryRuntimeStatistics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'PartitionKeyStatistics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'PartitionKeyRUConsumption', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'ControlPlaneRequests', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
    metrics: [{ category: 'Requests', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
  }
}

output cosmosDbAccountName string = cosmosDbAccount.name
