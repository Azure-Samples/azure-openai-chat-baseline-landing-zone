targetScope = 'resourceGroup'

/*
  Reference existing subnets and create NSGs for workload
*/

@description('The resource group location')
param location string = resourceGroup().location

@description('Name of the existing virtual network (spoke) in this resource group.')
@minLength(1)
param existingSpokeVirtualNetworkName string

@description('Name of the existing Internet UDR in this resource group. This should be blank for VWAN deployments.')
param existingUdrForInternetTrafficName string = ''

@description('The IP range of the hub-provided Azure Bastion subnet range. Needed for workload to limit access in NSGs. For example, 10.0.1.0/26')
@minLength(9)
param bastionSubnetAddresses string

@description('Address space for the existing app services subnet.')
@minLength(9)
param appServicesSubnetAddressPrefix string

@description('Address space for the existing app gateway subnet.')
@minLength(9)
param appGatewaySubnetAddressPrefix string

@description('Address space for the existing private endpoints subnet.')
@minLength(9)
param privateEndpointsSubnetAddressPrefix string

@description('Address space for the existing build agents subnet.')
@minLength(9)
param agentsSubnetAddressPrefix string

//--- Routing ----

// Hub firewall UDR
resource hubFirewallUdr 'Microsoft.Network/routeTables@2022-11-01' existing = if(existingUdrForInternetTrafficName != '') {
  name: existingUdrForInternetTrafficName
  scope: resourceGroup()
}

// ---- Networking resources ----

// Reference existing virtual network and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: existingSpokeVirtualNetworkName
  scope: resourceGroup()

  resource appServiceSubnet 'subnets' existing = {
    name: 'snet-appServices'
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: 'snet-appGateway'
  }

  resource privateEndpointsSubnet 'subnets' existing = {
    name: 'snet-privateEndpoints'
  }

  resource agentsSubnet 'subnets' existing = {
    name: 'snet-buildAgents'
  }

  resource aiAgentsEgressSubnet 'subnets' existing = {
    name: 'snet-aiAgentsEgress'
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

// Build agents subnet NSG
resource agentsSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-agentsSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Agents.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from AI Agent egress subnet to Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: agentsSubnetAddressPrefix
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
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
          sourceAddressPrefix: agentsSubnetAddressPrefix
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
          sourceAddressPrefix: agentsSubnetAddressPrefix
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

@description('The name of the app gateway subnet.')
output appGatewaySubnetName string = vnet::appGatewaySubnet.name

@description('The name of the private endpoints subnet.')
output privateEndpointsSubnetName string = vnet::privateEndpointsSubnet.name

@description('The DNS servers that were configured on the virtual network.')
output vnetDNSServers array = vnet.properties.dhcpOptions.dnsServers

@description('The name of the build agent subnet.')
output agentSubnetName string = vnet::agentsSubnet.name

@description('The resource ID of the agents egress subnet.')
output agentsEgressSubnetResourceId string = vnet::aiAgentsEgressSubnet.id

@description('The resource ID of the private endpoints subnet.')
output privateEndpointsSubnetResourceId string = vnet::privateEndpointsSubnet.id
