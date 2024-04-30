targetScope = 'resourceGroup'

/*
  Deploy subnets and NSGs
*/

// @description('This is the base name for each Azure resource name (6-8 chars)')
// param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('Name of the existing virtual network (spoke) in this resource group.')
@minLength(1)
param existingSpokeVirtualNetworkName string

@description('Name of the existing Internet UDR in this resource group. This should be blank for VWAN deployments.')
param existingUdrForInternetTrafficName string = ''

@description('The IP address space for the Azure Bastion instances in the hub. This is use for jump box (if deployed) and build agents.')
@minLength(10)
param bastionSubnetAddresses string

// variables
// var vnetName = 'vnet-${baseName}'
// var ddosPlanName = 'ddos-${baseName}'

// WARNING: You'll need to set these based off of what address space your platform team provided you.
var appServicesSubnetPrefix = '11.0.0.0/24'
var appGatewaySubnetPrefix = '11.0.1.0/24'
var privateEndpointsSubnetPrefix = '11.0.2.0/27'
var agentsSubnetPrefix = '11.0.2.32/27'
var jumpboxSubnetPrefix = '11.0.2.128/28'
var trainingSubnetPrefix = '11.0.3.0/24'
var scoringSubnetPrefix = '11.0.4.0/24'

//--- Routing ----

// Hub firewall UDR
resource hubFirewallUdr 'Microsoft.Network/routeTables@2022-11-01' existing = if(existingUdrForInternetTrafficName != '') {
  name: existingUdrForInternetTrafficName
  scope: resourceGroup()
}

// TODO
/*resource AppGWHubUdr 'Microsoft.Network/routeTables@2022-11-01' =
  if (paramFirewallNVAIpAddress != '') {
    name: 'udr-appgw-hub-firewall'
    location: location
    properties: {
      routes: [
        {
          name: 'routeToVnet'
          properties: {
            addressPrefix: vnetAddressPrefix
            nextHopType: 'VirtualAppliance'
            nextHopIpAddress: paramFirewallNVAIpAddress
          }
        }
      ]
    }
  }*/

// ---- Networking resources ----

// DDoS Protection Plan
// TODO
/*resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2022-11-01' =
  if (enableDdosProtection) {
    name: ddosPlanName
    location: location
    properties: {}
  }*/

// Virtual network and subnets
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: existingSpokeVirtualNetworkName
  location: location

  properties: {
    subnets: [
      {
        //App services plan subnet
        name: 'snet-appServicePlan'
        properties: {
          addressPrefix: appServicesSubnetPrefix
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
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
      {
        // App Gateway subnet
        name: 'snet-appGateway'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
          networkSecurityGroup: {
            id: appGatewaySubnetNsg.id
          }

          //routeTable: TODO
        }
      }
      {
        // Private endpoints subnet
        name: 'snet-privateEndpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointsSubnetNsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
      {
        // Build agents subnet
        name: 'snet-agents'
        properties: {
          addressPrefix: agentsSubnetPrefix
          networkSecurityGroup: {
            id: agentsSubnetNsg.id
          }
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
      {
        // Jump box VMs subnet
        name: 'snet-jumpbox'
        properties: {
          addressPrefix: jumpboxSubnetPrefix
          networkSecurityGroup: {
            id: jumpboxSubnetNsg.id
          }
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
      {
        // Training subnet
        name: 'snet-training'
        properties: {
          addressPrefix: trainingSubnetPrefix
          networkSecurityGroup: {
            id: trainingSubnetNsg.id
          }
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
      {
        // Scoring subnet
        name: 'snet-scoring'
        properties: {
          addressPrefix: scoringSubnetPrefix
          networkSecurityGroup: {
            id: scoringSubnetNsg.id
          }
          routeTable: hubFirewallUdr != null
            ? {
                id: hubFirewallUdr.id
              }
            : null
        }
      }
    ]
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: 'snet-appGateway'
  }

  resource appServiceSubnet 'subnets' existing = {
    name: 'snet-appServicePlan'
  }

  resource privateEnpointsSubnet 'subnets' existing = {
    name: 'snet-privateEndpoints'
  }

  resource agentsSubnet 'subnets' existing = {
    name: 'snet-agents'
  }

  resource jumpBoxSubnet 'subnets' existing = {
    name: 'snet-jumpbox'
  }

  resource trainingSubnet 'subnets' existing = {
    name: 'snet-training'
  }

  resource scoringSubnet 'subnets' existing = {
    name: 'snet-scoring'
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
          destinationAddressPrefix: appGatewaySubnetPrefix
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
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
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
          sourceAddressPrefix: appGatewaySubnetPrefix
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
          sourceAddressPrefix: appServicesSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
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
          sourceAddressPrefix: appServicesSubnetPrefix
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
          sourceAddressPrefix: privateEndpointsSubnetPrefix
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
          sourceAddressPrefix: appGatewaySubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Training subnet NSG
resource trainingSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-trainingSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the training subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: trainingSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Scoring subnet NSG
resource scoringSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-scoringSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllOutBound'
        properties: {
          description: 'Deny outbound traffic from the scoring subnet. Note: adjust rules as needed after adding resources to the subnet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: scoringSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Jump box subnet NSG 
resource jumpboxSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-jumpboxSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Jumpbox.In.Allow.SshRdp'
        properties: {
          description: 'Allow inbound RDP and SSH from the Bastion Host subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: bastionSubnetAddresses
          destinationPortRanges: [
            '22'
            '3389'
          ]
          destinationAddressPrefix: jumpboxSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Jumpbox.Out.Allow.PrivateEndpoints'
        properties: {
          description: 'Allow outbound traffic from the jumpbox subnet to the Private Endpoints subnet.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpboxSubnetPrefix
          destinationAddressPrefix: privateEndpointsSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Jumpbox.Out.Allow.Internet'
        properties: {
          description: 'Allow outbound traffic from all VMs to Internet'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpboxSubnetPrefix
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
          sourceAddressPrefix: jumpboxSubnetPrefix
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

@description('The name of the app gatewaysubnet.')
output appGatewaySubnetName string = vnet::appGatewaySubnet.name

@description('The name of the private endpoints subnet.')
output privateEndpointsSubnetName string = vnet::privateEnpointsSubnet.name

@description('The name of the private endpoints subnet.')
output jumpboxSubnetName string = vnet::jumpBoxSubnet.name

@description('The name of the private endpoints subnet.')
output scoringSubnetName string = vnet::trainingSubnet.name

@description('The name of the private endpoints subnet.')
output trainingSubnetName string = vnet::scoringSubnet.name

@description('The DNS servers that were configured on the virtual network.')
output vnetDNSServers array = vnet.properties.dhcpOptions.dnsServers
