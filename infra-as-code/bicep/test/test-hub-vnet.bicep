targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed.')
param location string = resourceGroup().location

@description('Base name for hub resources')
@minLength(3)
@maxLength(8)
param hubBaseName string = 'hub'

@description('Log Analytics workspace name for the hub')
param logAnalyticsWorkspaceName string = 'log-hub'

@description('Jump box admin username')
@minLength(4)
@maxLength(20)
param jumpBoxAdminName string = 'vmadmin'

@description('Jump box admin password')
@secure()
@minLength(8)
@maxLength(123)
param jumpBoxAdminPassword string

// Hub VNet configuration
var hubVirtualNetworkAddressPrefix = '10.0.0.0/16'
var azureFirewallSubnetPrefix = '10.0.1.0/26'
var azureFirewallManagementSubnetPrefix = '10.0.1.64/26'
var bastionSubnetPrefix = '10.0.2.0/26'
var jumpBoxSubnetPrefix = '10.0.2.64/27'
var dnsResolverInboundSubnetPrefix = '10.0.3.0/28'
var dnsResolverOutboundSubnetPrefix = '10.0.3.16/28'

var hubVirtualNetworkName = 'vnet-${hubBaseName}'

// Private DNS zones required for AI services
var privateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurewebsites.net'
]

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: { dailyQuotaGb: -1 }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Hub Virtual Network
resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVirtualNetworkName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [hubVirtualNetworkAddressPrefix] }
    dhcpOptions: { dnsServers: ['10.0.1.4'] } // Points to Azure Firewall for DNS proxy
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: azureFirewallSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: {
          addressPrefix: azureFirewallManagementSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-jumpBoxes'
        properties: {
          addressPrefix: jumpBoxSubnetPrefix
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          routeTable: { id: egressRouteTable.id }
        }
      }
    ]
  }
}

// Route Table for egress traffic through firewall (initial with placeholder)
resource egressRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'udr-internet-to-firewall'
  location: location
  properties: {
    routes: [
      {
        name: 'internet-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: '10.0.1.4' // Placeholder, will be updated
        }
      }
    ]
  }
}

// Private DNS Zones
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in privateDnsZones: {
  name: zone
  location: 'global'
}]

// Link private DNS zones to hub VNet
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zone, i) in privateDnsZones: {
  name: 'link-to-${hubVirtualNetworkName}'
  parent: privateDnsZone[i]
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: hubVirtualNetwork.id }
  }
}]

// Azure Firewall Public IPs
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-firewall-egress-00'
  location: location
  sku: { name: 'Standard', tier: 'Regional' }
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, 3)
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource firewallManagementPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-firewall-mgmt-00'
  location: location
  sku: { name: 'Standard', tier: 'Regional' }
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, 3)
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// Azure Firewall Policy
resource azureFirewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: 'fw-egress-policy'
  location: location
  properties: {
    sku: { tier: 'Basic' }
    threatIntelMode: 'Alert'
    
  }

  resource networkRules 'ruleCollectionGroups' = {
    name: 'DefaultNetworkRuleCollectionGroup'
    properties: {
      priority: 200
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'jump-box-egress'
          priority: 1000
          action: { type: 'Allow' }
          rules: [
            {
              ruleType: 'NetworkRule'
              name: 'allow-dependencies'
              ipProtocols: ['Any']
              sourceAddresses: [jumpBoxSubnetPrefix]
              destinationAddresses: ['*']
              destinationPorts: ['*']
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'spoke-egress'
          priority: 1100
          action: { type: 'Allow' }
          rules: [
            {
              ruleType: 'NetworkRule'
              name: 'allow-spoke-dependencies'
              ipProtocols: ['Any']
              sourceAddresses: ['192.168.0.0/16'] // Spoke VNet range
              destinationAddresses: ['*']
              destinationPorts: ['*']
            }
          ]
        }
      ]
    }
  }

  resource applicationRules 'ruleCollectionGroups' = {
    name: 'DefaultApplicationRuleCollectionGroup'
    properties: {
      priority: 300
      ruleCollections: [
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'jump-box-egress'
          priority: 1000
          action: { type: 'Allow' }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'allow-dependencies'
              protocols: [
                { protocolType: 'Https', port: 443 }
                { protocolType: 'Http', port: 80 }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: ['*']
              targetUrls: []
              terminateTLS: false
              sourceAddresses: [jumpBoxSubnetPrefix]
              destinationAddresses: []
              httpHeadersToInsert: []
            }
          ]
        }
        {
          ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
          name: 'spoke-egress'
          priority: 1100
          action: { type: 'Allow' }
          rules: [
            {
              ruleType: 'ApplicationRule'
              name: 'allow-spoke-dependencies'
              protocols: [
                { protocolType: 'Https', port: 443 }
              ]
              fqdnTags: []
              webCategories: []
              targetFqdns: ['*']
              targetUrls: []
              terminateTLS: false
              sourceAddresses: ['192.168.0.0/16'] // Spoke VNet range
              destinationAddresses: []
              httpHeadersToInsert: []
            }
          ]
        }
      ]
    }
    dependsOn: [networkRules]
  }
}

// Azure Firewall
resource azureFirewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'fw-egress'
  location: location
  zones: pickZones('Microsoft.Network', 'azureFirewalls', location, 3)
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Basic' }
    threatIntelMode: 'Alert'
    managementIpConfiguration: {
      name: firewallManagementPublicIp.name
      properties: {
        publicIPAddress: { id: firewallManagementPublicIp.id }
        subnet: { id: '${hubVirtualNetwork.id}/subnets/AzureFirewallManagementSubnet' }
      }
    }
    ipConfigurations: [
      {
        name: firewallPublicIp.name
        properties: {
          publicIPAddress: { id: firewallPublicIp.id }
          subnet: { id: '${hubVirtualNetwork.id}/subnets/AzureFirewallSubnet' }
        }
      }
    ]
    firewallPolicy: { id: azureFirewallPolicy.id }
  }
  dependsOn: [
    azureFirewallPolicy::applicationRules
    azureFirewallPolicy::networkRules
  ]
}

// Bastion Public IP
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-bastion'
  location: location
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, 3)
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    ddosSettings: { ddosProtectionPlan: null, protectionMode: 'VirtualNetworkInherited' }
    deleteOption: 'Delete'
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Bastion
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bastion-${hubBaseName}'
  location: location
  sku: { name: 'Basic' }
  properties: {
    disableCopyPaste: false
    enableFileCopy: false
    enableIpConnect: false
    enableKerberos: false
    enableShareableLink: false
    enableTunneling: false
    enableSessionRecording: false
    scaleUnits: 2
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: bastionPublicIp.id }
          subnet: { id: '${hubVirtualNetwork.id}/subnets/AzureBastionSubnet' }
        }
      }
    ]
  }
}

// Jump Box NIC
resource jumpBoxPrivateNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-jumpbox'
  location: location
  properties: {
    nicType: 'Standard'
    auxiliaryMode: 'None'
    auxiliarySku: 'None'
    enableIPForwarding: false
    enableAcceleratedNetworking: false
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          primary: true
          subnet: { id: '${hubVirtualNetwork.id}/subnets/snet-jumpBoxes' }
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          publicIPAddress: null
          applicationSecurityGroups: []
        }
      }
    ]
  }
}

// VM Insights DCR
resource virtualMachineInsightsDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-jumpbox'
  location: location
  kind: 'Windows'
  properties: {
    description: 'Standard data collection rule for VM Insights'
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: ['Microsoft-InsightsMetrics']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: ['\\VMInsights\\DetailedMetrics']
        }
      ]
      extensions: [
        {
          name: 'DependencyAgentDataSource'
          extensionName: 'DependencyAgent'
          streams: ['Microsoft-ServiceMap']
          extensionSettings: {}
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: logAnalyticsWorkspace.name
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-InsightsMetrics', 'Microsoft-ServiceMap']
        destinations: [logAnalyticsWorkspace.name]
      }
    ]
  }
}

// Jump Box VM
resource jumpBoxVirtualMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-jumpbox'
  location: location
  zones: pickZones('Microsoft.Compute', 'virtualMachines', location, 1)
  identity: { type: 'SystemAssigned' }
  properties: {
    additionalCapabilities: { hibernationEnabled: false, ultraSSDEnabled: false }
    applicationProfile: null
    availabilitySet: null
    diagnosticsProfile: { bootDiagnostics: { enabled: true, storageUri: null } }
    hardwareProfile: { vmSize: 'Standard_D2s_v3' }
    licenseType: 'Windows_Client'
    networkProfile: { networkInterfaces: [{ id: jumpBoxPrivateNic.id }] }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: jumpBoxAdminName
      adminPassword: jumpBoxAdminPassword
      allowExtensionOperations: true
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: { patchMode: 'AutomaticByOS', assessmentMode: 'ImageDefault' }
        provisionVMAgent: true
      }
    }
    priority: 'Regular'
    scheduledEventsProfile: {
      osImageNotificationProfile: { enable: true }
      terminateNotificationProfile: { enable: true }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    storageProfile: {
      dataDisks: []
      diskControllerType: 'SCSI'
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadOnly'
        deleteOption: 'Delete'
        diffDiskSettings: null
        managedDisk: { storageAccountType: 'Premium_LRS' }
        encryptionSettings: { enabled: false }
        osType: 'Windows'
        diskSizeGB: 127
      }
      imageReference: {
        offer: 'windows-11'
        publisher: 'MicrosoftWindowsDesktop'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
    }
  }

  resource vmAccessExtension 'extensions' = {
    name: 'enablevmAccess'
    location: location
    properties: {
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: false
      publisher: 'Microsoft.Compute'
      type: 'VMAccessAgent'
      typeHandlerVersion: '2.0'
      settings: {}
    }
  }

  resource amaExtension 'extensions' = {
    name: 'AzureMonitorWindowsAgent'
    location: location
    properties: {
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      typeHandlerVersion: '1.34'
    }
  }

  resource amaDependencyAgent 'extensions' = {
    name: 'DependencyAgentWindows'
    location: location
    properties: {
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      publisher: 'Microsoft.Azure.Monitoring.DependencyAgent'
      type: 'DependencyAgentWindows'
      typeHandlerVersion: '9.10'
      settings: { enableAMA: 'true' }
    }
  }
}

// DCR Association
resource jumpBoxDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcra-vminsights'
  scope: jumpBoxVirtualMachine
  properties: {
    dataCollectionRuleId: virtualMachineInsightsDcr.id
    description: 'VM Insights DCR association with the jump box.'
  }
  dependsOn: [jumpBoxVirtualMachine::amaDependencyAgent]
}

// Diagnostics
resource azureDiagnosticsBastion 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: bastion
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'BastionAuditLogs'
        enabled: true
        retentionPolicy: { enabled: false, days: 0 }
      }
    ]
  }
}

resource azureDiagnosticsFirewall 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: azureFirewall
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'AzureFirewallApplicationRule', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AzureFirewallNetworkRule', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AzureFirewallDnsProxy', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWNetworkRule', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWApplicationRule', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWNatRule', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWThreatIntel', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWIdpsSignature', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWDnsQuery', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWFqdnResolveFailure', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWFatFlow', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWFlowTrace', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWApplicationRuleAggregation', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWNetworkRuleAggregation', enabled: true, retentionPolicy: { days: 0, enabled: false } }
      { category: 'AZFWNatRuleAggregation', enabled: true, retentionPolicy: { days: 0, enabled: false } }
    ]
  }
}

resource azureDiagnosticsDcr 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: virtualMachineInsightsDcr
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'LogErrors'
        categoryGroup: null
        enabled: true
        retentionPolicy: { days: 0, enabled: false }
      }
    ]
  }
}

// Update route table with actual firewall IP after firewall is deployed
resource updateRouteTableWithFirewallIp 'Microsoft.Resources/deployments@2024-03-01' = {
  name: 'updateRouteTable'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: [
        {
          type: 'Microsoft.Network/routeTables'
          apiVersion: '2024-05-01'
          name: egressRouteTable.name
          location: location
          properties: {
            routes: [
              {
                name: 'internet-to-firewall'
                properties: {
                  addressPrefix: '0.0.0.0/0'
                  nextHopType: 'VirtualAppliance'
                  nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
                }
              }
            ]
          }
        }
      ]
    }
  }
  dependsOn: [azureFirewall]
}

// Private DNS Resolver
resource privateDnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: 'dnsresolver-${hubBaseName}'
  location: location
  properties: {
    virtualNetwork: { id: hubVirtualNetwork.id }
  }
}

resource dnsResolverInboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: 'inbound-endpoint'
  parent: privateDnsResolver
  location: location
  properties: {
    ipConfigurations: [{
      privateIpAllocationMethod: 'Static'
      privateIpAddress: '10.0.3.4'
      subnet: { id: '${hubVirtualNetwork.id}/subnets/snet-dnsResolverInbound' }
    }]
  }
}

resource dnsResolverOutboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  name: 'outbound-endpoint'
  parent: privateDnsResolver
  location: location
  properties: {
    subnet: { id: '${hubVirtualNetwork.id}/subnets/snet-dnsResolverOutbound' }
  }
}

resource dnsForwardingRuleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: 'ruleset-${hubBaseName}'
  location: location
  properties: {
    dnsResolverOutboundEndpoints: [
      { id: dnsResolverOutboundEndpoint.id }
    ]
  }
}

// Update VNet DNS settings to point to DNS Resolver after it's deployed
resource updateVnetDnsSettings 'Microsoft.Resources/deployments@2024-03-01' = {
  name: 'updateVnetDnsSettings'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: [
        {
          type: 'Microsoft.Network/virtualNetworks'
          apiVersion: '2024-05-01'
          name: hubVirtualNetwork.name
          location: location
          properties: {
            addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
            dhcpOptions: {
              dnsServers: [dnsResolverInboundEndpoint.properties.ipConfigurations[0].privateIpAddress]
            }
            subnets: hubVirtualNetwork.properties.subnets
          }
        }
      ]
    }
  }
  dependsOn: [dnsResolverInboundEndpoint]
}

// Outputs
output hubVirtualNetworkName string = hubVirtualNetwork.name
output hubVirtualNetworkId string = hubVirtualNetwork.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output azureFirewallPrivateIp string = azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
output egressRouteTableId string = egressRouteTable.id
output privateDnsZoneIds object = {
  cognitiveservices: privateDnsZone[0].id
  aiservices: privateDnsZone[1].id
  openai: privateDnsZone[2].id
  search: privateDnsZone[3].id
  blob: privateDnsZone[4].id
  cosmosdb: privateDnsZone[5].id
  keyvault: privateDnsZone[6].id
  websites: privateDnsZone[7].id
}
output dnsResolverInboundEndpointIp string = dnsResolverInboundEndpoint.properties.ipConfigurations[0].privateIpAddress 

