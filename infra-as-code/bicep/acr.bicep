targetScope = 'resourceGroup'

/*
  Deploy container registry with private endpoint
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The zone redundancy of the ACR.')
param zoneRedundancy string = 'Enabled'

// existing resource name params 
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGrouName string

param privateEndpointsSubnetName string
param logWorkspaceName string

//variables
var acrName = 'cr${baseName}'
var acrPrivateEndpointName = 'pep-${acrName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGrouName)

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }  
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logWorkspaceName
}

resource acrResource 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    networkRuleSet: {
      defaultAction: 'Deny'
    }
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: zoneRedundancy
  }
}

//ACR diagnostic settings
resource acrResourceDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${acrResource.name}-diagnosticSettings'
  scope: acrResource
  properties: {
    workspaceId: logWorkspace.id
    logs: [
        {
            categoryGroup: 'allLogs'
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

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: acrPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: acrPrivateEndpointName
        properties: {
          groupIds: [
            'registry'
          ]
          privateLinkServiceId: acrResource.id
        }
      }
    ]
  }
}

@description('Output the login server property for later use')
output loginServer string = acrResource.properties.loginServer
