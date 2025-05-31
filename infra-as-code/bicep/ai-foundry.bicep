targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

@description('Hub resource group name')
param hubResourceGroupName string

@description('Agent subnet resource ID')
param agentSubnetResourceId string

@description('Private endpoint subnet resource ID')
param privateEndpointSubnetResourceId string

@description('User principal ID for portal access')
param aiFoundryPortalUserPrincipalId string

var aiFoundryName = 'aif${baseName}'

// Existing resources
resource cognitiveServicesLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
  scope: resourceGroup(hubResourceGroupName)
}

resource aiFoundryLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
  scope: resourceGroup(hubResourceGroupName)
}

resource azureOpenAiLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.openai.azure.com'
  scope: resourceGroup(hubResourceGroupName)
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup(hubResourceGroupName)
}

// Azure AI Foundry
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiFoundryName
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: aiFoundryName
    allowProjectManagement: true
    disableLocalAuth: true
    networkAcls: {
      bypass: 'None'
      ipRules: []
      defaultAction: 'Deny'
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Disabled'
    networkInjections: [{
      scenario: 'agent'
      subnetArmId: agentSubnetResourceId
      useMicrosoftManagedNetwork: false
    }]
  }

  resource model 'deployments' = {
    name: 'gpt-4o'
    sku: { capacity: 14, name: 'GlobalStandard' }
    properties: {
      model: { format: 'OpenAI', name: 'gpt-4o', version: '2024-08-06' }
      versionUpgradeOption: 'NoAutoUpgrade'
    }
  }
}

// Role assignment
resource cognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundry.id, cognitiveServicesUserRole.id, aiFoundryPortalUserPrincipalId)
  scope: aiFoundry
  properties: {
    roleDefinitionId: cognitiveServicesUserRole.id
    principalId: aiFoundryPortalUserPrincipalId
    principalType: 'User'
  }
}

// Private endpoint
resource aiFoundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-foundry'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-ai-foundry'
    privateLinkServiceConnections: [{
      name: 'aifoundry'
      properties: {
        privateLinkServiceId: aiFoundry.id
        groupIds: ['account']
      }
    }]
  }

  resource dnsGroup 'privateDnsZoneGroups' = {
    name: 'aifoundry'
    properties: {
      privateDnsZoneConfigs: [
        { name: 'aifoundry', properties: { privateDnsZoneId: aiFoundryLinkedPrivateDnsZone.id } }
        { name: 'azureopenai', properties: { privateDnsZoneId: azureOpenAiLinkedPrivateDnsZone.id } }
        { name: 'cognitiveservices', properties: { privateDnsZoneId: cognitiveServicesLinkedPrivateDnsZone.id } }
      ]
    }
  }
}

// Diagnostics
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: aiFoundry
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      { category: 'Audit', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'RequestResponse', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'AzureOpenAIRequestUsage', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'Trace', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
  }
}

// ---- Outputs ----

output aiFoundryName string = aiFoundry.name
