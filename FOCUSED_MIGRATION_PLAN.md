# Azure AI Agent Service Migration Plan - Focused Landing Zone Integration

## Current Landing Zone Components (KEEP AS-IS)

✅ **EXISTING INFRASTRUCTURE TO KEEP:**
- `applicationinsignts.bicep` - Log Analytics & Application Insights
- `network.bicep` - Subnets, NSGs, Private DNS zones
- `storage.bicep` - Storage account with private endpoint
- `keyvault.bicep` - Key Vault with private endpoint
- `gateway.bicep` - Application Gateway with WAF
- `webapp.bicep` - Web App with private networking

## Migration Strategy: REPLACE + ADD

### PHASE 1: REPLACE EXISTING AI COMPONENTS

#### 1.1 REMOVE: Azure Container Registry Module
**FILE TO DELETE:** `acr.bicep`
**REASON:** Not needed for Azure AI Agent Service

**ACTION IN main.bicep:**
```bicep
// DELETE THIS MODULE REFERENCE
module acrModule 'acr.bicep' = {
  name: 'acrDeploy'
  // ... entire module block
}
```

#### 1.2 REPLACE: Azure OpenAI Module  
**FILE TO MODIFY:** `openai.bicep` → **REPLACE WITH** `ai-foundry.bicep`
**REASON:** Azure AI Foundry replaces standalone OpenAI for Agent Service

**ACTION IN main.bicep:**
```bicep
// REPLACE THIS:
module openaiModule 'openai.bicep' = {
  name: 'openaiDeploy'
  // ...
}

// WITH THIS:
module aiFoundryModule 'ai-foundry.bicep' = {
  name: 'aiFoundryDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    yourPrincipalId: yourPrincipalId
  }
}
```

#### 1.3 REPLACE: Machine Learning Module
**FILE TO MODIFY:** `machinelearning.bicep` → **REPLACE WITH** `ai-foundry-project.bicep`
**REASON:** AI Foundry Project replaces ML Studio workspace

**ACTION IN main.bicep:**
```bicep
// REPLACE THIS:
module aiFoundryModule 'machinelearning.bicep' = {
  name: 'aiFoundryDeploy'
  // ...
}

// WITH THIS:
module aiFoundryProjectModule 'ai-foundry-project.bicep' = {
  name: 'aiFoundryProjectDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    existingAiFoundryName: aiFoundryModule.outputs.aiFoundryName
    existingApplicationInsightsName: monitoringModule.outputs.applicationInsightsName
    existingStorageAccountName: storageModule.outputs.mlDeployStorageName
    existingKeyVaultName: keyVaultModule.outputs.keyVaultName
  }
  dependsOn: [
    aiFoundryModule
    storageModule
    keyVaultModule
    monitoringModule
  ]
}
```

### PHASE 2: ADD NEW AI AGENT DEPENDENCIES

#### 2.1 ADD: AI Search Service
**NEW FILE:** `ai-search.bicep`
**PURPOSE:** Required for Azure AI Agent Service RAG capabilities

**ACTION IN main.bicep:**
```bicep
// ADD THIS NEW MODULE
module aiSearchModule 'ai-search.bicep' = {
  name: 'aiSearchDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    yourPrincipalId: yourPrincipalId
  }
}
```

#### 2.2 ADD: Cosmos DB for Thread Storage
**NEW FILE:** `cosmos-db.bicep`
**PURPOSE:** Required for Azure AI Agent conversation persistence

**ACTION IN main.bicep:**
```bicep
// ADD THIS NEW MODULE
module cosmosDbModule 'cosmos-db.bicep' = {
  name: 'cosmosDbDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    yourPrincipalId: yourPrincipalId
  }
}
```

#### 2.3 ADD: Bing Search for Internet Grounding
**NEW FILE:** `bing-grounding.bicep`
**PURPOSE:** Optional internet grounding capability

**ACTION IN main.bicep:**
```bicep
// ADD THIS NEW MODULE
module bingModule 'bing-grounding.bicep' = {
  name: 'bingDeploy'
  scope: rgWorkload
}
```

### PHASE 3: UPDATE EXISTING COMPONENTS

#### 3.1 UPDATE: Network Module
**FILE TO MODIFY:** `network.bicep`
**CHANGES NEEDED:**
- Add private DNS zones for new services
- Keep existing subnet structure (no IP range changes needed)

**ADDITIONS TO network.bicep:**
```bicep
// ADD THESE NEW PRIVATE DNS ZONES
var additionalPrivateDnsZones = [
  'privatelink.search.windows.net'        // AI Search
  'privatelink.documents.azure.com'       // Cosmos DB
  'privatelink.services.ai.azure.com'     // AI Foundry
]

// ADD TO EXISTING privateDnsZones array
var privateDnsZones = union(existingPrivateDnsZones, additionalPrivateDnsZones)
```

#### 3.2 UPDATE: Web App Module
**FILE TO MODIFY:** `webapp.bicep`
**CHANGES NEEDED:**
- Update environment variables to use AI Foundry instead of OpenAI
- Add new connection strings for AI Search and Cosmos DB

**ENVIRONMENT VARIABLE CHANGES:**
```bicep
// REPLACE OpenAI variables with AI Foundry
{ name: 'ChatApiOptions__AIFoundryEndpoint', value: aiFoundryModule.outputs.aiFoundryEndpoint }
{ name: 'ChatApiOptions__AISearchEndpoint', value: aiSearchModule.outputs.aiSearchEndpoint }
{ name: 'ChatApiOptions__CosmosDbEndpoint', value: cosmosDbModule.outputs.cosmosDbEndpoint }
```

## DETAILED FILE CHANGES

### NEW FILES TO CREATE

#### 1. `ai-foundry.bicep`
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Virtual network name')
param vnetName string

@description('Virtual network resource group name')
param virtualNetworkResourceGroupName string

@description('Private endpoints subnet name')
param privateEndpointsSubnetName string

@description('Log Analytics workspace name')
param logWorkspaceName string

@description('User principal ID for portal access')
param yourPrincipalId string

var aiFoundryName = 'aif${baseName}'

// Existing resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: privateEndpointsSubnetName
  parent: vnet
}

resource cognitiveServicesLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource aiFoundryLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logWorkspaceName
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

// Private endpoint
resource aiFoundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-foundry-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointsSubnet.id }
    customNetworkInterfaceName: 'nic-ai-foundry-${baseName}'
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
      { category: 'Trace', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
  }
}

output aiFoundryName string = aiFoundry.name
output aiFoundryEndpoint string = aiFoundry.properties.endpoint
```

#### 2. `ai-search.bicep`
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Virtual network name')
param vnetName string

@description('Virtual network resource group name')
param virtualNetworkResourceGroupName string

@description('Private endpoints subnet name')
param privateEndpointsSubnetName string

@description('Log Analytics workspace name')
param logWorkspaceName string

@description('User principal ID')
param yourPrincipalId string

var aiSearchName = 'srch${baseName}'

// Existing resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: privateEndpointsSubnetName
  parent: vnet
}

resource aiSearchLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.search.windows.net'
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logWorkspaceName
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

// Private endpoint
resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-search-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointsSubnet.id }
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
output aiSearchEndpoint string = 'https://${aiSearch.name}.search.windows.net/'
```

#### 3. `cosmos-db.bicep`
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for resources (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Virtual network name')
param vnetName string

@description('Virtual network resource group name')
param virtualNetworkResourceGroupName string

@description('Private endpoints subnet name')
param privateEndpointsSubnetName string

@description('Log Analytics workspace name')
param logWorkspaceName string

@description('User principal ID')
param yourPrincipalId string

var cosmosDbAccountName = 'cosmos${baseName}'

// Existing resources
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: privateEndpointsSubnetName
  parent: vnet
}

resource cosmosDbLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
  scope: resourceGroup(virtualNetworkResourceGroupName)
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logWorkspaceName
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

// Private endpoint
resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-cosmos-db-${baseName}'
  location: location
  properties: {
    subnet: { id: privateEndpointsSubnet.id }
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
output cosmosDbEndpoint string = cosmosDbAccount.properties.documentEndpoint
```

#### 4. `bing-grounding.bicep`
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

#### 5. `ai-foundry-project.bicep`
```bicep
targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Existing Azure AI Foundry account name')
param existingAiFoundryName string

@description('Existing Application Insights name')
param existingApplicationInsightsName string

@description('Existing Storage account name')
param existingStorageAccountName string

@description('Existing Key Vault name')
param existingKeyVaultName string

var aiFoundryProjectName = 'aifp-workload'

// Existing resources
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: existingAiFoundryName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: existingApplicationInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: existingStorageAccountName
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
}

output aiFoundryProjectName string = aiFoundryProject.name
```

## DEPLOYMENT SEQUENCE

### Step 1: Prepare Files
- [ ] Delete `acr.bicep`
- [ ] Create new files: `ai-foundry.bicep`, `ai-search.bicep`, `cosmos-db.bicep`, `bing-grounding.bicep`, `ai-foundry-project.bicep`
- [ ] Update `network.bicep` to add new private DNS zones
- [ ] Update `main.bicep` with new module references

### Step 2: Update main.bicep
- [ ] Remove ACR module reference
- [ ] Replace OpenAI module with AI Foundry module
- [ ] Replace ML module with AI Foundry Project module
- [ ] Add AI Search module
- [ ] Add Cosmos DB module
- [ ] Add Bing module

### Step 3: Deploy
```bash
az deployment sub create \
  --template-file main.bicep \
  --parameters @parameters.json \
  --location <your-location>
```

### Step 4: Validate
- [ ] Verify all private endpoints are connected
- [ ] Test AI Foundry portal access
- [ ] Validate web application functionality

## MINIMAL CHANGES APPROACH

This migration plan:
✅ **KEEPS** existing landing zone networking patterns
✅ **REUSES** existing subnets and private DNS zones
✅ **MAINTAINS** existing security posture
✅ **PRESERVES** existing monitoring and logging
✅ **ONLY CHANGES** what's necessary for AI Agent Service

No network IP range changes required - works with existing spoke configuration! 