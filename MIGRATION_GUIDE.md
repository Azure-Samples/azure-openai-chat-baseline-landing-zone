# Complete Azure AI Agent Service Migration Guide - Mini Azure Platform Landing Zone

## CRITICAL CHANGES OVERVIEW

### ARCHITECTURE TRANSFORMATION
- **FROM**: Azure OpenAI + Azure ML Studio + ACR
- **TO**: Azure AI Foundry + Azure AI Agent Service + Dependencies
- **NETWORK**: 10.x.x.x → 192.168.x.x (MANDATORY for AI Agent Service)

## PART 1: WHAT TO REMOVE

### 1. REMOVE: Azure Container Registry (`acr.bicep`)
**ENTIRE FILE DELETED** - No longer needed for AI Agent Service

### 2. REMOVE: Azure OpenAI (`openai.bicep`) 
**ENTIRE FILE DELETED** - Replaced by Azure AI Foundry

### 3. REMOVE: Azure ML Studio (`ai-studio.bicep`)
**ENTIRE FILE DELETED** - Replaced by Azure AI Foundry

### 4. REMOVE: Training/Scoring Infrastructure
**DELETED FROM network.bicep**:
- `snet-training` subnet
- `snet-scoring` subnet
- Related NSG rules for training/scoring

### 5. REMOVE: Old Network Configuration
**DELETED FROM network.bicep**:
```bicep
// OLD - REMOVE THESE
var virtualNetworkAddressPrefix = '10.0.0.0/16'
var appGatewaySubnetPrefix = '10.0.1.0/24'
var appServicesSubnetPrefix = '10.0.0.0/24'
var privateEndpointsSubnetPrefix = '10.0.2.0/27'
var buildAgentsSubnetPrefix = '10.0.2.32/27'
var bastionSubnetPrefix = '10.0.2.64/26'
var jumpBoxSubnetPrefix = '10.0.2.128/28'
```

### 6. REMOVE: Old Module References in main.bicep
**DELETE THESE MODULES**:
```bicep
// REMOVE - No longer needed
module deployAzureContainerRegistry 'acr.bicep' = { ... }
module deployOpenAI 'openai.bicep' = { ... }
module deployAzureMLStudio 'ai-studio.bicep' = { ... }
```

## PART 2: WHAT TO ADD

### 1. ADD: New Network Configuration (`network.bicep`)
**REPLACE OLD NETWORK RANGES**:
```bicep
// NEW - 192.168.x.x ranges (MANDATORY)
var virtualNetworkAddressPrefix = '192.168.0.0/16'
var appGatewaySubnetPrefix = '192.168.1.0/24'
var appServicesSubnetPrefix = '192.168.0.0/24'
var privateEndpointsSubnetPrefix = '192.168.2.0/27'
var buildAgentsSubnetPrefix = '192.168.2.32/27'
var bastionSubnetPrefix = '192.168.2.64/26'
var jumpBoxSubnetPrefix = '192.168.2.128/28'
var aiAgentsEgressSubnetPrefix = '192.168.3.0/24'  // NEW
var azureFirewallSubnetPrefix = '192.168.4.0/26'   // NEW
var azureFirewallManagementSubnetPrefix = '192.168.4.64/26' // NEW
```

### 2. ADD: New Subnets (`network.bicep`)
**ADD THESE SUBNETS**:
```bicep
// Azure AI Agent Egress Subnet
{
  name: 'snet-agentsEgress'
  properties: {
    addressPrefix: aiAgentsEgressSubnetPrefix
    delegations: [{
      name: 'Microsoft.App/environments'
      properties: { serviceName: 'Microsoft.App/environments' }
    }]
    networkSecurityGroup: { id: azureAiAgentServiceSubnetNsg.id }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
    routeTable: { id: egressRouteTable.id }
  }
}

// Azure Firewall Subnet
{
  name: 'AzureFirewallSubnet'
  properties: {
    addressPrefix: azureFirewallSubnetPrefix
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Azure Firewall Management Subnet
{
  name: 'AzureFirewallManagementSubnet'
  properties: {
    addressPrefix: azureFirewallManagementSubnetPrefix
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}
```

### 3. ADD: Azure Firewall (`network.bicep`)
**ADD COMPLETE FIREWALL CONFIGURATION**:
```bicep
// Azure Firewall
resource azureFirewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'fw-${baseName}'
  location: location
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Standard' }
    ipConfigurations: [{
      name: 'configuration'
      properties: {
        publicIPAddress: { id: firewallPublicIp.id }
        subnet: { id: '${virtualNetwork.id}/subnets/AzureFirewallSubnet' }
      }
    }]
    managementIpConfiguration: {
      name: 'managementConfiguration'
      properties: {
        publicIPAddress: { id: firewallManagementPublicIp.id }
        subnet: { id: '${virtualNetwork.id}/subnets/AzureFirewallManagementSubnet' }
      }
    }
    networkRuleCollections: [{
      name: 'AllowAzureAIAgentEgress'
      properties: {
        priority: 100
        action: { type: 'Allow' }
        rules: [{
          name: 'AllowHTTPS'
          protocols: ['TCP']
          sourceAddresses: [aiAgentsEgressSubnetPrefix]
          destinationAddresses: ['*']
          destinationPorts: ['443']
        }]
      }
    }]
  }
}

// Firewall Public IPs
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-fw-${baseName}'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource firewallManagementPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-fw-mgmt-${baseName}'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// Route Table for Egress
resource egressRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-egress-${baseName}'
  location: location
  properties: {
    routes: [{
      name: 'DefaultRoute'
      properties: {
        addressPrefix: '0.0.0.0/0'
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
      }
    }]
  }
}
```

### 4. ADD: Enhanced NSG for AI Agents (`network.bicep`)
```bicep
resource azureAiAgentServiceSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-agentsEgressSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Agents.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from AI Agent egress subnet to Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsEgressSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Agents.Out.AllowTcp443.Internet'
        properties: {
          description: 'Allow outbound traffic from AI Agent egress subnet to Internet on 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: aiAgentsEgressSubnetPrefix
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny all other outbound traffic from Azure AI Agent subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: aiAgentsEgressSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}
```

### 5. ADD: Private DNS Zones (`network.bicep`)
**ADD ALL NEW DNS ZONES**:
```bicep
var privateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurewebsites.net'
]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in privateDnsZones: {
  name: zone
  location: 'global'
}]

resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zone, i) in privateDnsZones: {
  name: '${zone}/link-to-${virtualNetwork.name}'
  parent: privateDnsZone[i]
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: virtualNetwork.id }
  }
}]
```

### 6. ADD: Subnet Renames (`network.bicep`)
**RENAME EXISTING SUBNETS**:
```bicep
// OLD: snet-agents → NEW: snet-buildAgents
// OLD: snet-jumpbox → NEW: snet-jumpBoxes
```

## PART 3: NEW INFRASTRUCTURE FILES TO CREATE

### 1. CREATE: `ai-foundry.bicep`
**COMPLETE NEW FILE**:
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

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
}

resource aiFoundryLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
}

resource azureOpenAiLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.openai.azure.com'
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
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
    #disable-next-line BCP036
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

output aiFoundryName string = aiFoundry.name
```

### 2. CREATE: `ai-agent-service-dependencies.bicep`
**ORCHESTRATION FILE**:
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Debug user principal ID')
param debugUserPrincipalId string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

@description('Private endpoint subnet resource ID')
param privateEndpointSubnetResourceId string

// Deploy Storage
module deployAgentStorageAccount 'ai-agent-blob-storage.bicep' = {
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

// Deploy Cosmos DB
module deployCosmosDbThreadStorageAccount 'cosmos-db.bicep' = {
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

// Deploy AI Search
module deployAzureAISearchService 'ai-search.bicep' = {
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    debugUserPrincipalId: debugUserPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

output cosmosDbAccountName string = deployCosmosDbThreadStorageAccount.outputs.cosmosDbAccountName
output storageAccountName string = deployAgentStorageAccount.outputs.storageAccountName
output aiSearchName string = deployAzureAISearchService.outputs.aiSearchName
```

### 3. CREATE: `ai-search.bicep`
**COMPLETE NEW FILE**:
```bicep
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

var aiSearchName = 'srch${baseName}'

// Existing resources
resource aiSearchLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.search.windows.net'
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
    authOptions: {
      aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' }
    }
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
  name: 'pe-ai-search'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-ai-search'
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
      privateDnsZoneConfigs: [{
        name: 'aisearch'
        properties: { privateDnsZoneId: aiSearchLinkedPrivateDnsZone.id }
      }]
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
```

### 4. CREATE: `cosmos-db.bicep`
**COMPLETE NEW FILE**:
```bicep
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

var cosmosDbAccountName = 'cosmos${baseName}'

// Existing resources
resource cosmosDbLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
}

resource cosmosDbAccountReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
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
  name: 'pe-cosmos-db'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-cosmos-db'
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
```

### 5. CREATE: `ai-agent-blob-storage.bicep`
**COMPLETE NEW FILE**:
```bicep
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

var storageAccountName = 'st${baseName}${uniqueString(resourceGroup().id, baseName)}'

// Existing resources
resource storageLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.core.windows.net'
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
  name: 'pe-storage'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetResourceId }
    customNetworkInterfaceName: 'nic-storage'
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
```

### 6. CREATE: `bing-grounding.bicep`
**SIMPLE NEW FILE**:
```bicep
targetScope = 'resourceGroup'

@description('Deploy Bing account for Internet grounding.')
#disable-next-line BCP081
resource bingAccount 'Microsoft.Bing/accounts@2025-05-01-preview' = {
  name: 'bing-grounding'
  location: 'global'
  kind: 'Bing.Search.v7'
  sku: { name: 'S1' }
  properties: {}
}

output bingAccountName string = bingAccount.name
```

### 7. CREATE: `ai-foundry-project.bicep`
**COMPLETE NEW FILE**:
```bicep
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
param existingWebApplicationInsightsResourceName string

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
  name: existingWebApplicationInsightsResourceName
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
  }
  kind: 'project'

  // Connections
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
```

## PART 4: UPDATE MAIN.BICEP

### REMOVE from main.bicep:
```bicep
// DELETE THESE MODULES
module deployAzureContainerRegistry 'acr.bicep' = { ... }
module deployOpenAI 'openai.bicep' = { ... }
module deployAzureMLStudio 'ai-studio.bicep' = { ... }
```

### ADD to main.bicep:
```bicep
// ADD THESE NEW MODULES
@description('Deploy Azure AI Foundry with Azure AI Agent capability.')
module deployAzureAIFoundry 'ai-foundry.bicep' = {
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    agentSubnetResourceId: deployVirtualNetwork.outputs.agentsEgressSubnetResourceId
    privateEndpointSubnetResourceId: deployVirtualNetwork.outputs.privateEndpointsSubnetResourceId
    aiFoundryPortalUserPrincipalId: yourPrincipalId
  }
}

@description('Deploy Azure AI Agent dependencies.')
module deployAIAgentServiceDependencies 'ai-agent-service-dependencies.bicep' = {
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    debugUserPrincipalId: yourPrincipalId
    privateEndpointSubnetResourceId: deployVirtualNetwork.outputs.privateEndpointsSubnetResourceId
  }
}

@description('Deploy Bing account for Internet grounding.')
module deployBingAccount 'bing-grounding.bicep' = {}

@description('Deploy Azure AI Foundry project.')
module deployAzureAiFoundryProject 'ai-foundry-project.bicep' = {
  params: {
    location: location
    existingAiFoundryName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAISearchAccountName: deployAIAgentServiceDependencies.outputs.aiSearchName
    existingCosmosDbAccountName: deployAIAgentServiceDependencies.outputs.cosmosDbAccountName
    existingStorageAccountName: deployAIAgentServiceDependencies.outputs.storageAccountName
    existingBingAccountName: deployBingAccount.outputs.bingAccountName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
  }
}
```

### UPDATE Log Analytics in main.bicep:
```bicep
// CHANGE FROM:
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'log-${baseName}'
  // ...
}

// CHANGE TO:
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'log-workload'
  // ...
}
```

## PART 5: UPDATE WEB-APP.BICEP

### REMOVE Environment Variables:
```bicep
// DELETE THESE
{ name: 'ChatApiOptions__ChatApiEndpoint', value: '...' }
{ name: 'ChatApiOptions__ChatApiKey', value: '...' }
{ name: 'ChatApiOptions__ChatInputName', value: '...' }
{ name: 'ChatApiOptions__ChatOutputName', value: '...' }
```

### ADD Environment Variables:
```bicep
// ADD THESE
{ name: 'ChatApiOptions__AIProjectEndpoint', value: 'https://${aiFoundryProjectName}.${location}.api.azureml.ms' }
{ name: 'ChatApiOptions__BingSearchConnectionId', value: bingSearchConnectionId }
{ name: 'ChatApiOptions__BingSearchResultsCount', value: '5' }
{ name: 'ChatApiOptions__BingSearchResultsTimeRange', value: 'Week' }
{ name: 'ChatApiOptions__DefaultModel', value: 'gpt-4o' }
```

## DEPLOYMENT CHECKLIST

### Pre-Deployment:
- [ ] Delete ACR, OpenAI, and AI Studio bicep files
- [ ] Update network.bicep with new IP ranges (192.168.x.x)
- [ ] Create all new bicep files listed above
- [ ] Update main.bicep module references
- [ ] Update web-app.bicep environment variables

### Deployment:
- [ ] Deploy infrastructure: `az deployment group create --template-file main.bicep`
- [ ] Verify all private endpoints are connected
- [ ] Test Azure Firewall egress rules
- [ ] Validate AI Foundry project connections

### Post-Deployment:
- [ ] Test AI Agent functionality in Azure AI Foundry portal
- [ ] Verify internet grounding through Bing Search
- [ ] Validate all logging and monitoring
- [ ] Test web application (if applicable)

## CRITICAL NOTES

1. **NETWORK CHANGE IS MANDATORY**: Azure AI Agent Service requires 192.168.x.x ranges
2. **NO ROLLBACK**: This is a complete architectural change - plan accordingly
3. **REGION SUPPORT**: Ensure your region supports Azure AI Foundry and AI Agent Service
4. **COST IMPACT**: New services (Cosmos DB, AI Search, Storage, Firewall) will increase costs
5. **SECURITY**: All services use private endpoints and managed identity authentication 