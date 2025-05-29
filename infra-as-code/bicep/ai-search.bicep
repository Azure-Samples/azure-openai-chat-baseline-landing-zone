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

var aiSearchName = 'srch${baseName}'

// Existing resources
resource aiSearchLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.search.windows.net'
  scope: resourceGroup(hubResourceGroupName)
}

resource searchServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  scope: subscription()
}

resource searchIndexDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

// AI Search
resource aiSearch 'Microsoft.Search/searchServices@2025-02-01-preview' = {
  name: aiSearchName
  location: location
  sku: { name: 'standard' }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    networkRuleSet: { ipRules: [] }
    encryptionWithCmk: { enforcement: 'Unspecified' }
    disableLocalAuth: true
    semanticSearch: 'standard'
  }
}

// Role assignments
resource searchServiceContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, searchServiceContributorRole.id, debugUserPrincipalId)
  scope: aiSearch
  properties: {
    roleDefinitionId: searchServiceContributorRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

resource searchIndexDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, searchIndexDataContributorRole.id, debugUserPrincipalId)
  scope: aiSearch
  properties: {
    roleDefinitionId: searchIndexDataContributorRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// Private endpoint
resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-search-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-ai-search-${baseName}'
    privateLinkServiceConnections: [{
      name: 'aisearch'
      properties: {
        privateLinkServiceId: aiSearch.id
        groupIds: ['searchService']
      }
    }]
  }

  resource dnsGroup 'privateDnsZoneGroups' = {
    name: 'aisearch'
    properties: {
      privateDnsZoneConfigs: [
        { name: 'aisearch', properties: { privateDnsZoneId: aiSearchLinkedPrivateDnsZone.id } }
      ]
    }
  }
}

// Diagnostics
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: aiSearch
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [{ category: 'OperationLogs', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
    metrics: [{ category: 'AllMetrics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
  }
}

output aiSearchName string = aiSearch.name
output aiSearchEndpoint string = 'https://${aiSearch.name}.search.windows.net/' 
