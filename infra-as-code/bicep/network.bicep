targetScope = 'resourceGroup'

/*
  Deploy subnets and NSGs
*/

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('Name of the existing virtual network (spoke) in this resource group.')
@minLength(1)
param existingSpokeVirtualNetworkName string

@description('Name of the existing Internet UDR in this resource group. This should be blank for VWAN deployments.')
param existingUdrForInternetTrafficName string = ''

@description('The IP range of the hub-provided Azure Bastion subnet range. Needed for workload to limit access in NSGs. For example, 10.0.1.0/26')
@minLength(9)
param bastionSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for Azure App Services.')
@minLength(9)
param appServicesSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for Azure Azure Application Gateway.')
@minLength(9)
param appGatewaySubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for the workload\'s private endpoints.')
@minLength(9)
param privateEndpointsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for build agents.')
@minLength(9)
param buildAgentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for agents.')
@minLength(9)
param agentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for jump boxes.')
@minLength(9)
param jumpBoxSubnetAddressPrefix string


//--- Routing ----

// Hub firewall UDR
resource hubFirewallUdr 'Microsoft.Network/routeTables@2022-11-01' existing = if(existingUdrForInternetTrafficName != '') {
  name: existingUdrForInternetTrafficName
}

// ---- Networking resources ----

// Virtual network and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: existingSpokeVirtualNetworkName

  resource appServiceSubnet 'subnets' = {
    name: 'snet-appServicePlan'
    properties: {
      addressPrefix: appServicesSubnetAddressPrefix
      networkSecurityGroup: {
        id: appServiceSubnetNsg.id
      }
      delegations: [
        {
          name: 'delegation'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ]
      routeTable: {
        id: hubFirewallUdr.id
      }
    }
  }

  resource appGatewaySubnet 'subnets' = {
    name: 'snet-appGateway'
    properties: {
      addressPrefix: appGatewaySubnetAddressPrefix
      networkSecurityGroup: {
        id: appGatewaySubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
    dependsOn: [
      appServiceSubnet // Single thread these
    ]
  }

  resource privateEnpointsSubnet 'subnets' = {
    name: 'snet-privateEndpoints'
    properties: {
      addressPrefix: privateEndpointsSubnetAddressPrefix
      networkSecurityGroup: {
        id: privateEndpointsSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Enabled' // Route Table and NSGs
      privateLinkServiceNetworkPolicies: 'Enabled'
      defaultOutboundAccess: false // This subnet should never be the source of egress traffic.
      routeTable: {
        id: hubFirewallUdr.id
      }
    }
    dependsOn: [
      appGatewaySubnet // Single thread these
    ]
  }

  resource buildAgentsSubnet 'subnets' = {
    name: 'snet-buildAgents'
    properties: {
      addressPrefix: buildAgentsSubnetAddressPrefix
      networkSecurityGroup: {
        id: buildAgentsSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      defaultOutboundAccess: false // Force your build agent traffic through your firewall.
      routeTable: {
        id: hubFirewallUdr.id
      }
    }
    dependsOn: [
      privateEnpointsSubnet // Single thread these
    ]
  }

  resource agentsSubnet 'subnets' = {
    name: 'snet-agentsEgress'
    properties: {
      addressPrefix: agentsSubnetAddressPrefix
      networkSecurityGroup: {
        id: agentsSubnetNsg.id
      }
      delegations: [
        {
          name: 'Microsoft.App/environments'
          properties: {
            serviceName: 'Microsoft.App/environments'
          }
        }
      ]
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      defaultOutboundAccess: false // Force agent traffic through your firewall.
      routeTable: {
        id: hubFirewallUdr.id
      }
    }
    dependsOn: [
      buildAgentsSubnet // Single thread these
    ]
  }

  resource jumpBoxSubnet 'subnets' = {
    name: 'snet-jumpBoxes'
    properties: {
      addressPrefix: jumpBoxSubnetAddressPrefix
      networkSecurityGroup: {
        id: jumpBoxSubnetNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      defaultOutboundAccess: false // Force agent traffic through your firewall.
      routeTable: {
        id: hubFirewallUdr.id
      }
    }
    dependsOn: [
      agentsSubnet // Single thread these
    ]
  }
}

// App Gateway subnet NSG
resource appGatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appGatewaySubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppGw.In.Allow.ControlPlane'
        properties: {
          description: 'Allow inbound Control Plane (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow443.Internet'
        properties: {
          description: 'Allow ALL inbound web traffic on port 443'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appGatewaySubnetAddressPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AppGw.In.Allow.LoadBalancer'
        properties: {
          description: 'Allow inbound traffic from azure load balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
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
      {
        name: 'AppGw.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from the App Gateway subnet to Azure Monitor'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// App Service subnet NSG
resource appServiceSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-appServicesSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AppPlan.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the app service subnet to the private endpoints subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: appServicesSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AppPlan.Out.Allow.AzureMonitor'
        properties: {
          description: 'Allow outbound traffic from App service to the AzureMonitor ServiceTag.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appServicesSubnetAddressPrefix
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Private endpoints subnet NSG
resource privateEndpointsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-privateEndpointsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the private endpoints subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: privateEndpointsSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The build agents subnet NSG')
resource buildAgentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-buildAgentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the build agents subnet. Note: adjust rules as needed based on the resources added to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: buildAgentsSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Build agents subnet NSG
resource agentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-agentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the build agents subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: appGatewaySubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The Jump box subnet NSG')
resource jumpBoxSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-jumpBoxesSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'JumpBox.In.Allow.SshRdp'
        properties: {
          description: 'Allow inbound RDP and SSH from the Bastion Host subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: bastionSubnetAddressPrefix
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefix: jumpBoxSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'JumpBox.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the jump box subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'JumpBox.Out.Allow.Internet'
        properties: {
          description: 'Allow outbound traffic from all VMs to Internet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpBoxSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

@description('The name of the spoke vnet.')
output vnetName string = vnet.name

@description('The name of the app service plan subnet.')
output appServicesSubnetName string = vnet::appServiceSubnet.name
@description('The id of the app service plan subnet.')
output appServicesSubnetResourceId string = vnet::appServiceSubnet.id

@description('The name of the app gatewaysubnet.')
output appGatewaySubnetName string = vnet::appGatewaySubnet.name
@description('The id of the app gatewaysubnet.')
output appGatewaySubnetResourceId string = vnet::appGatewaySubnet.id

@description('The name of the private endpoints subnet.')
output privateEndpointSubnetName string = vnet::privateEnpointsSubnet.name
@description('The id of the private endpoint subnet.')
output privateEndpointSubnetResourceId string = vnet::privateEnpointsSubnet.id

@description('The name of the agent subnet.')
output agentSubnetName string = vnet::agentsSubnet.name
@description('The id of the agent subnet.')
output agentSubnetResourceId string = vnet::agentsSubnet.id

@description('The DNS servers that were configured on the virtual network.')
output vnetDNSServers array = vnet.properties.dhcpOptions.dnsServers
