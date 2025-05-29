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

var storageAccountName = 'st${baseName}${uniqueString(resourceGroup().id, baseName)}'

// Existing resources
resource storageLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.core.windows.net'
  scope: resourceGroup(hubResourceGroupName)
}

resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Disabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    networkAcls: {
      bypass: 'None'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      keySource: 'Microsoft.Storage'
      services: {
        file: { keyType: 'Account', enabled: true }
        blob: { keyType: 'Account', enabled: true }
      }
    }
    accessTier: 'Hot'
  }

  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
      changeFeed: { enabled: false }
      restorePolicy: { enabled: false }
      containerDeleteRetentionPolicy: { enabled: true, days: 7 }
      cors: { corsRules: [] }
      deleteRetentionPolicy: { allowPermanentDelete: false, enabled: true, days: 7 }
      isVersioningEnabled: false
    }
  }
}

// Role assignment
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageBlobDataContributorRole.id, debugUserPrincipalId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// Private endpoint
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-storage-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-storage-${baseName}'
    privateLinkServiceConnections: [{
      name: 'storage'
      properties: {
        privateLinkServiceId: storageAccount.id
        groupIds: ['blob']
      }
    }]
  }

  resource dnsGroup 'privateDnsZoneGroups' = {
    name: 'storage'
    properties: {
      privateDnsZoneConfigs: [{
        name: 'storage'
        properties: { privateDnsZoneId: storageLinkedPrivateDnsZone.id }
      }]
    }
  }
}

// Diagnostics
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: storageAccount::blobServices
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      { category: 'StorageRead', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'StorageWrite', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'StorageDelete', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
    metrics: [{ category: 'Transaction', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
  }
}

output storageAccountName string = storageAccount.name 
