targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for spoke resources')
@minLength(3)
@maxLength(8)
param spokeBaseName string = 'spoke'

@description('Hub VNet resource ID for peering')
param hubVirtualNetworkId string

@description('Hub VNet name for peering')
param hubVirtualNetworkName string

@description('Route table resource ID from hub for egress routing')
param egressRouteTableId string

@description('Private DNS zone resource IDs from hub')
param privateDnsZoneIds object

// Spoke VNet configuration (192.168.x.x required for AI Agent Services)
var spokeVirtualNetworkAddressPrefix = '192.168.0.0/16'
var appGatewaySubnetPrefix = '192.168.1.0/24'
var appServicesSubnetPrefix = '192.168.0.0/24'
var privateEndpointsSubnetPrefix = '192.168.2.0/27'
var buildAgentsSubnetPrefix = '192.168.2.32/27'
var aiAgentsEgressSubnetPrefix = '192.168.3.0/24'

var spokeVirtualNetworkName = 'vnet-${spokeBaseName}'

// NSG for AI Agents Egress Subnet
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

// Spoke Virtual Network
resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spokeVirtualNetworkName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [spokeVirtualNetworkAddressPrefix] }
    dhcpOptions: { dnsServers: ['10.0.1.4'] } // Points to hub firewall for DNS
    subnets: [
      {
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: egressRouteTableId }
        }
      }
      {
        name: 'snet-appServices'
        properties: {
          addressPrefix: appServicesSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Web/serverFarms'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: egressRouteTableId }
        }
      }
      {
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: egressRouteTableId }
        }
      }
      {
        name: 'snet-buildAgents'
        properties: {
          addressPrefix: buildAgentsSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: egressRouteTableId }
        }
      }
      {
        name: 'snet-agentsEgress'
        properties: {
          addressPrefix: aiAgentsEgressSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App/environments'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
          networkSecurityGroup: { id: azureAiAgentServiceSubnetNsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
          routeTable: { id: egressRouteTableId }
        }
      }
    ]
  }
}

// VNet Peering: Spoke to Hub
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-to-${hubVirtualNetworkName}'
  parent: spokeVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: { id: hubVirtualNetworkId }
  }
}

// VNet Peering: Hub to Spoke (deployed in hub resource group)
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${hubVirtualNetworkName}/peer-to-${spokeVirtualNetworkName}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

// Link private DNS zones from hub to spoke VNet
resource privateDnsZoneVnetLinkCognitiveServices 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkAiServices 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.services.ai.azure.com/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkOpenAi 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.openai.azure.com/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkSearch 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.search.windows.net/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.blob.core.windows.net/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkCosmosDb 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.documents.azure.com/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkKeyVault 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

resource privateDnsZoneVnetLinkWebsites 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'privatelink.azurewebsites.net/link-to-${spokeVirtualNetworkName}'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetwork.id }
  }
}

// Outputs
output spokeVirtualNetworkName string = spokeVirtualNetwork.name
output spokeVirtualNetworkId string = spokeVirtualNetwork.id
output appGatewaySubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-appGateway'
output appServicesSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-appServices'
output privateEndpointsSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-privateEndpoints'
output buildAgentsSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-buildAgents'
output agentsEgressSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-agentsEgress' 
