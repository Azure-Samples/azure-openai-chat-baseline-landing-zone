targetScope = 'resourceGroup'

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The region in which this architecture is deployed.')
@minLength(1)
param location string = resourceGroup().location

@description('The resource ID of the subscription vending provided spoke in your application landging zone subscription. For example, /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/rg-app-networking/providers/Microsoft.Network/virtualNetworks/vnet-app000-spoke0')
@minLength(114)
param existingResourceIdForSpokeVirtualNetwork string

@description('Specifies the name of the administrator account on the Windows jump box. Cannot end in "."\n\nDisallowed values: "administrator", "admin", "user", "user1", "test", "user2", "test1", "user3", "admin1", "1", "123", "a", "actuser", "adm", "admin2", "aspnet", "backup", "console", "david", "guest", "john", "owner", "root", "server", "sql", "support", "support_388945a0", "sys", "test2", "test3", "user4", "user5".\n\nDefault: vmadmin')
@minLength(4)
@maxLength(20)
param jumpBoxAdminName string = 'vmadmin'

@description('Specifies the password of the administrator account on the Windows jump box.\n\nComplexity requirements: 3 out of 4 conditions below need to be fulfilled:\n- Has lower characters\n- Has upper characters\n- Has a digit\n- Has a special character\n\nDisallowed values: "abc@123", "P@$$w0rd", "P@ssw0rd", "P@ssword123", "Pa$$word", "pass@word1", "Password!", "Password1", "Password22", "iloveyou!"')
@secure()
@minLength(8)
@maxLength(123)
param jumpBoxAdminPassword string

@description('Set to true to opt-out of deployment telemetry.')
param telemetryOptOut bool = false

// ---- Variables ----

var jumpBoxName = 'jmp-${baseName}'
var existingResourceGroupNameForSpokeVirtualNetwork = split(existingResourceIdForSpokeVirtualNetwork, '/')[4]
var existingSpokeVirtualNetworkName = split(existingResourceIdForSpokeVirtualNetwork, '/')[8]
var varCuaid = '54b6da01-930f-45ca-87eb-773dc3943863' // Customer Usage Attribution Id

// ---- Existing resources ----

@description('Existing virtual network for the solution.')
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: existingSpokeVirtualNetworkName
  scope: resourceGroup(existingResourceGroupNameForSpokeVirtualNetwork)

  resource jumpBoxSubnet 'subnets' existing = {
    name: 'snet-jumpBoxes'
  }
}

@description('Existing Log Analyitics workspace, used as the common log sink for the workload.')
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'log-${baseName}'
}

// New resources

@description('Default VM Insights DCR rule, to be applied to the jump box.')
resource virtualMachineInsightsDcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-${jumpBoxName}'
  location: location
  kind: 'Windows'
  properties: {
    description: 'Standard data collection rule for VM Insights'
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\VMInsights\\DetailedMetrics'
          ]
        }
      ]
      extensions: [
        {
          name: 'DependencyAgentDataSource'
          extensionName: 'DependencyAgent'
          streams: [
            'Microsoft-ServiceMap'
          ]
          extensionSettings: {}
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: logWorkspace.name
          workspaceResourceId: logWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
          'Microsoft-ServiceMap'
        ]
        destinations: [
          logWorkspace.name
        ]
      }
    ]
  }
}

@description('VM will only receive a private IP.')
resource jumpBoxPrivateNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'nic-${jumpBoxName}'
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
          subnet: {
            id: virtualNetwork::jumpBoxSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          publicIPAddress: null
          applicationSecurityGroups: []
        }
      }
    ]
  }
}

@description('The Azure ML and Azure OpenAI portal experiences are only able to be accessed from the virtual network, this jump box gives you access to those UIs.')
resource jumpBoxVirtualMachine 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'vm-${jumpBoxName}'
  location: location
  zones: pickZones('Microsoft.Compute', 'virtualMachines', location, 1)
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    additionalCapabilities: {
      hibernationEnabled: false
      ultraSSDEnabled: false
    }
    applicationProfile: null
    availabilitySet: null
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: null
      }
    }
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3'
    }
    licenseType: 'Windows_Client'
    networkProfile: {
      networkInterfaces: [
        {
          id: jumpBoxPrivateNic.id
        }
      ]
    }
    osProfile: {
      computerName: jumpBoxName
      adminUsername: jumpBoxAdminName
      adminPassword: jumpBoxAdminPassword
      allowExtensionOperations: true
      windowsConfiguration: {
        enableAutomaticUpdates: true
        enableVMAgentPlatformUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
        provisionVMAgent: true
      }
    }
    priority: 'Regular'
    scheduledEventsProfile: {
      osImageNotificationProfile: {
        enable: true
      }
      terminateNotificationProfile: {
        enable: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      dataDisks: []
      diskControllerType: 'SCSI'
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadOnly'
        deleteOption: 'Delete'
        diffDiskSettings: null
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        encryptionSettings: {
          enabled: false
        }
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

  @description('Support remote admin password changes.')
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

  @description('Enable Azure Monitor Agent for observability though VM Insights.')
  resource amaExtension 'extensions' = {
    name: 'AzureMonitorWindowsAgent'
    location: location
    properties: {
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      publisher: 'Microsoft.Azure.Monitor'
      type: 'AzureMonitorWindowsAgent'
      typeHandlerVersion: '1.21'
    }
  }

  @description('Dependency Agent for service map support in Azure Monitor Agent.')
  resource amaDependencyAgent 'extensions' = {
    name: 'DependencyAgentWindows'
    location: location
    properties: {
      autoUpgradeMinorVersion: true
      enableAutomaticUpgrade: true
      publisher: 'Microsoft.Azure.Monitoring.DependencyAgent'
      type: 'DependencyAgentWindows'
      typeHandlerVersion: '9.10'
      settings: {
        enableAMA: 'true'
      }
    }
  }
}

@description('Associate jump box with Azure Monitor Agent VM Insights DCR.')
resource jumpBoxDcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'dcra-vminsights'
  scope: jumpBoxVirtualMachine
  properties: {
    dataCollectionRuleId: virtualMachineInsightsDcr.id
    description: 'VM Insights DCR association with the jump box.'
  }
  dependsOn: [
    jumpBoxVirtualMachine::amaDependencyAgent
  ]
}

// Optional Deployment for Customer Usage Attribution
module customerUsageAttributionModule '../customerUsageAttribution/cuaIdResourceGroup.bicep' = if (!telemetryOptOut) {
  #disable-next-line no-loc-expr-outside-params // Only to ensure telemetry data is stored in same location as deployment. See https://github.com/Azure/ALZ-Bicep/wiki/FAQ#why-are-some-linter-rules-disabled-via-the-disable-next-line-bicep-function for more information
  name: 'pid-${varCuaid}-${uniqueString(resourceGroup().location)}'
  params: {}
}
