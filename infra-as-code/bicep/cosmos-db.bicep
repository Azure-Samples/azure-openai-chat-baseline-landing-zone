targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The name of the workload\'s existing Log Analytics workspace.')
@minLength(4)
param logAnalyticsWorkspaceName string

@description('The resource group name of the spoke where the VNet exists')
param spokeResourceGroupName string

@description('Assign your user some roles to support access to the Azure AI Agent dependencies for troubleshooting post deployment')
@maxLength(36)
@minLength(36)
param debugUserPrincipalId string

@description('The resource ID for the subnet that private endpoints in the workload should surface in.')
@minLength(1)
param privateEndpointSubnetResourceId string

// ---- Existing resources ----

// Cosmos DB Account Reader Role
resource cosmosDbAccountReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8'
  scope: subscription()
}

@description('Existing: Log sink for Azure Diagnostics.')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup()
}

// ---- New resources ----

@description('Deploy an Azure Cosmos DB account. This is a BYO dependency for the Azure AI Agent service. It\'s used to store threads and agent definitions.')
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: 'cdb-ai-agent-threads-${baseName}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: 'Disabled'
    enableFreeTier: false
    ipRules: []
    virtualNetworkRules: []
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []
    diagnosticLogSettings: {
      enableFullTextQuery: 'False'
    }
    enableBurstCapacity: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false // Some subscriptions do not have quota to support zone redundancy. If you encounter an error, set this to false.
      }
    ]
    databaseAccountOfferType: 'Standard'
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: {
        tier: 'Continuous7Days'   // You have seven days of continuous backup to address point-in-time restore needs.
      }
    }
  }

  @description('Built-in Cosmos DB Data Contributor role that can be assigned to Entra identities to grant data access on a Cosmos DB database.')
  resource dataContributorRole 'sqlRoleDefinitions' existing = {
    name: '00000000-0000-0000-0000-000000000002'
  }

  @description('Assign your own user to access the enterprise_memory database contents for troubleshooting purposes. Not required for normal usage.')
  resource userToCosmos 'sqlRoleAssignments' = {
    name: guid(debugUserPrincipalId, dataContributorRole.id, cosmosDbAccount.id)
    properties: {
      roleDefinitionId: cosmosDbAccount::dataContributorRole.id
      principalId: debugUserPrincipalId
      scope: cosmosDbAccount.id
    }
    dependsOn: [
      assignDebugUserToCosmosAccountReader
    ]
  }
}

@description('Capture platform logs for the Cosmos DB account.')
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: cosmosDbAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'PartitionKeyRUConsumption'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'ControlPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'DataPlaneRequests5M'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'DataPlaneRequests15M'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Private endpoints

resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-agent-threads'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    customNetworkInterfaceName: 'nic-ai-agent-threads'
    privateLinkServiceConnections: [
      {
        name: 'ai-agent-cosmosdb'
        properties: {
          privateLinkServiceId: cosmosDbAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}


// Role assignments

resource assignDebugUserToCosmosAccountReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(debugUserPrincipalId, cosmosDbAccountReaderRole.id, cosmosDbAccount.id)
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDbAccountReaderRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// ---- Outputs ----

output cosmosDbAccountName string = cosmosDbAccount.name
