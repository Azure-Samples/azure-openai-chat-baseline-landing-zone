targetScope = 'resourceGroup'

/*
  Deploy storage account with private endpoint
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

// existing resource name params
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string

param privateEndpointsSubnetName string

@description('The name of the workload\'s existing Log Analytics workspace.')
param logWorkspaceName string

@maxLength(37)
@minLength(36)
param yourPrincipalId string

// variables
var appDeployStorageName = 'st${baseName}'
var appDeployStoragePrivateEndpointName = 'pep-${appDeployStorageName}'

var mlStorageName = 'stml${baseName}'
var mlBlobStoragePrivateEndpointName = 'pep-blob-${mlStorageName}'
var mlFileStoragePrivateEndpointName = 'pep-file-${mlStorageName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logWorkspaceName
}

@description('Built-in Role: [Storage Blob Data Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor)')
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

// ---- Storage resources ----
resource appDeployStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: appDeployStorageName
  location: location
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    allowedCopyScope: 'AAD'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    minimumTlsVersion: 'TLS1_2'
    isHnsEnabled: false
    isSftpEnabled: false
    isLocalUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
  }
  resource blobService 'blobServices' = {
    name: 'default'

    // Storage container in which the Chat UI App's "Run from Zip" will be sourced
    resource deployContainer 'containers' = {
      name: 'deploy'
      properties: {
        publicAccess: 'None'
      }
    }
  }
}

// Enable App Service deployment Storage Account blob diagnostic settings
resource appDeployStorageDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: appDeployStorage::blobService
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs' // All logs is a good choice for production on this resource.
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    logAnalyticsDestinationType: null
  }
}

@description('Assign your user the ability to manage prompt flow state files from blob storage. This is needed to execute the prompt flow from within in Azure AI Studio.')
resource blobStorageContributorForUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appDeployStorage::blobService::deployContainer
  name: guid(appDeployStorage::blobService::deployContainer.id, yourPrincipalId, storageBlobDataContributorRole.id)
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalType: 'User'
    principalId: yourPrincipalId  // Part of the deployment guide requires you to upload the web app to this storage container. Assigning that data plane permission here.
  }
}

resource appDeployStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: appDeployStoragePrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: appDeployStoragePrivateEndpointName
        properties: {
          groupIds: [
            'blob'
          ]
          privateLinkServiceId: appDeployStorage.id
        }
      }
    ]
  }
}

resource mlStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: mlStorageName
  location: location
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    allowedCopyScope: 'AAD'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
  resource Blob 'blobServices' existing = {
    name: 'default'
  }
  resource File 'fileServices' existing = {
    name: 'default'
  }
}

// Enable Machine Learning Storage Account blob diagnostic settings
resource mlStorageBlobDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: mlStorage::Blob
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'  // All logs is a good choice for production on this resource.
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    logAnalyticsDestinationType: null
  }
}

// Enable Machine Learning Storage Account file diagnostic settings
resource mlStorageFileDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: mlStorage::File
  properties: {
    workspaceId: logWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'  // All logs is a good choice for production on this resource.
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    logAnalyticsDestinationType: null
  }
}

@description('Azure Machine Learning Blob Storage Private Endpoint')
resource mlBlobStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: mlBlobStoragePrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: mlBlobStoragePrivateEndpointName
        properties: {
          groupIds: [
            'blob'
          ]
          privateLinkServiceId: mlStorage.id
        }
      }
    ]
  }
}

@description('Azure Machine Learning File Storage Private Endpoint')
resource mlFileStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: mlFileStoragePrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: mlFileStoragePrivateEndpointName
        properties: {
          groupIds: [
            'file'
          ]
          privateLinkServiceId: mlStorage.id
        }
      }
    ]
  }
}

@description('The name of the appDeploy storage account.')
output appDeployStorageName string = appDeployStorage.name

@description('The name of the ML storage account.')
output mlDeployStorageName string = mlStorage.name
