targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Assign your user some roles to support access to the Azure AI Agent dependencies for troubleshooting post deployment')
@maxLength(36)
@minLength(36)
param debugUserPrincipalId string

@description('The name of the workload\'s existing Log Analytics workspace.')
@minLength(4)
param logAnalyticsWorkspaceName string

@description('The resource ID for the subnet that private endpoints in the workload should surface in.')
@minLength(1)
param privateEndpointSubnetResourceId string

// ---- Existing resources ----

resource storageBlobDataOwnerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
  scope: resourceGroup()
}

// ---- New resources ----

resource agentStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: 'stagent${baseName}'
  location: location
  sku: {
    name: 'Standard_GZRS'
  }
  kind: 'StorageV2'
  properties: {
    allowedCopyScope: 'AAD'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    isLocalUserEnabled: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: false
    isSftpEnabled: false
    isNfsV3Enabled: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false // This Azure AI Agents service binary files scenario doesn't require double encryption, but if your scenario does, please enable.
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
      resourceAccessRules: []
    }
  }

  resource blob 'blobServices' existing = {
    name: 'default'
  }
}

// Role assignments

resource debugUserBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(debugUserPrincipalId, storageBlobDataOwnerRole.id, agentStorageAccount.id)
  scope: agentStorageAccount
  properties: {
    principalId: debugUserPrincipalId
    roleDefinitionId: storageBlobDataOwnerRole.id
    principalType: 'User'
  }
}


// Private endpoints

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-agent-storage'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    customNetworkInterfaceName: 'nic-ai-agent-storage'
    privateLinkServiceConnections: [
      {
        name: 'ai-agent-storage'
        properties: {
          privateLinkServiceId: agentStorageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// Azure diagnostics

resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: agentStorageAccount::blob
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'StorageRead'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'StorageWrite'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'StorageDelete'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Prevent Accidental Changes

resource agentStorageAccountLocks 'Microsoft.Authorization/locks@2020-05-01' = {
  scope: agentStorageAccount
  name: '${agentStorageAccount.name}-lock'
  properties: {
    level: 'CanNotDelete'
    notes: 'Prevent deleting; recovery not practical. Hard dependency for your AI Foundry Agent Service.'
    owners: []
  }
}

// ---- Outputs ----

output storageAccountName string = agentStorageAccount.name
