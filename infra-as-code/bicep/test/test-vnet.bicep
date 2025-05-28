targetScope = 'resourceGroup'

@description('The region in which the test infrastructure will be deployed.')
param location string = resourceGroup().location

@description('Base name for test resources')
param baseName string = 'test'

// Create minimal test VNet for landing zone testing with Azure Firewall subnet
resource testVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${baseName}-spoke'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    dhcpOptions: {
      dnsServers: [] // Will be updated after firewall deployment
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.1.255.0/26'
        }
      }
    ] // Additional subnets will be created by the landing zone deployment
  }
}

// Public IP for Azure Firewall
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-azfw-${baseName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Firewall with DNS proxy enabled
resource azureFirewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: 'azfw-${baseName}'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'configuration'
        properties: {
          publicIPAddress: {
            id: firewallPublicIp.id
          }
          subnet: {
            id: '${testVnet.id}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
    additionalProperties: {
      'Network.DNS.EnableProxy': 'true' // Enable DNS proxy
    }
  }
}

// Update VNet DNS settings to point to Azure Firewall (separate deployment to avoid circular dependency)
resource testVnetDnsUpdate 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${baseName}-spoke'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    dhcpOptions: {
      dnsServers: [azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress] // Point to Azure Firewall DNS proxy
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.1.255.0/26'
        }
      }
    ]
  }
  dependsOn: [
    azureFirewall
  ]
}

// Create a basic UDR that routes traffic through Azure Firewall
resource testUdr 'Microsoft.Network/routeTables@2024-01-01' = {
  name: 'udr-${baseName}-internet'
  location: location
  properties: {
    routes: [
      {
        name: 'DefaultRouteToFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// Create basic private DNS zones that would normally be managed by platform team
var privateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.blob.core.windows.net'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurewebsites.net'
]

resource testPrivateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in privateDnsZones: {
  name: zone
  location: 'global'
  properties: {}
}]

// Create VNet links for each DNS zone
resource testPrivateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in privateDnsZones: {
  name: '${zone}-link'
  parent: testPrivateDnsZones[i]
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: testVnetDnsUpdate.id // Use the updated VNet reference
    }
  }
}]

// Outputs for use in landing zone deployment
output vnetResourceId string = testVnetDnsUpdate.id
output vnetName string = testVnetDnsUpdate.name
output udrResourceId string = testUdr.id
output resourceGroupName string = resourceGroup().name
output azureFirewallPrivateIP string = azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress 
