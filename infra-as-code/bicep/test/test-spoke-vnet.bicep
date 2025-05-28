targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for spoke resources')
@minLength(3)
@maxLength(8)
param spokeBaseName string = 'spoke'

@description('Hub VNet resource ID for peering')
param hubVirtualNetworkId string

@description('Hub DNS Resolver inbound endpoint IP')
param hubDnsResolverIp string = '10.0.3.4'

@description('Hub firewall private IP for routing')
param hubFirewallPrivateIp string = '10.0.1.4'

// Spoke VNet configuration (using 192.168.x.x as required for AI Agent Service)
var spokeVirtualNetworkAddressPrefix = '192.168.0.0/16'
var appGatewaySubnetPrefix = '192.168.1.0/24'
var appServicesSubnetPrefix = '192.168.0.0/24'
var privateEndpointsSubnetPrefix = '192.168.2.0/27'
var buildAgentsSubnetPrefix = '192.168.2.32/27'
var aiAgentsEgressSubnetPrefix = '192.168.3.0/24'

var spokeVirtualNetworkName = 'vnet-${spokeBaseName}'

// Route Table for spoke traffic through hub firewall
resource spokeRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'udr-spoke-to-firewall'
  location: location
  properties: {
    routes: [
      {
        name: 'internet-to-hub-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: hubFirewallPrivateIp
        }
      }
      {
        name: 'hub-vnet-direct'
        properties: {
          addressPrefix: '10.0.0.0/16'
          nextHopType: 'VnetLocal'
        }
      }
    ]
  }
}

// NSG for AI Agents Egress Subnet
resource aiAgentsEgressNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-aiAgentsEgress'
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

// NSG for Private Endpoints Subnet
resource privateEndpointsNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-privateEndpoints'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
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
    ]
  }
}

// Spoke Virtual Network
resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spokeVirtualNetworkName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [spokeVirtualNetworkAddressPrefix] }
    dhcpOptions: { dnsServers: [hubDnsResolverIp] } // Points to hub DNS Resolver
    subnets: [
      {
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: spokeRouteTable.id }
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
          routeTable: { id: spokeRouteTable.id }
        }
      }
      {
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          networkSecurityGroup: { id: privateEndpointsNsg.id }
          routeTable: { id: spokeRouteTable.id }
        }
      }
      {
        name: 'snet-buildAgents'
        properties: {
          addressPrefix: buildAgentsSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: spokeRouteTable.id }
        }
      }
      {
        name: 'snet-aiAgentsEgress'
        properties: {
          addressPrefix: aiAgentsEgressSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App/environments'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
          networkSecurityGroup: { id: aiAgentsEgressNsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
          routeTable: { id: spokeRouteTable.id }
        }
      }
    ]
  }
}

// VNet Peering: Spoke to Hub
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-to-hub'
  parent: spokeVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: { id: hubVirtualNetworkId }
  }
}

// Outputs
output spokeVirtualNetworkName string = spokeVirtualNetwork.name
output spokeVirtualNetworkId string = spokeVirtualNetwork.id
output appServicesSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-appServices'
output privateEndpointsSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-privateEndpoints'
output buildAgentsSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-buildAgents'
output aiAgentsEgressSubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-aiAgentsEgress'
output appGatewaySubnetResourceId string = '${spokeVirtualNetwork.id}/subnets/snet-appGateway' 
