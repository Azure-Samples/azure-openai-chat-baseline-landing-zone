targetScope = 'resourceGroup'

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

//variables
var openaiName = 'oai-${baseName}'
var openaiPrivateEndpointName = 'pep-${openaiName}'

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

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-06-01-preview' = {
  name: openaiName
  location: location
  kind: 'OpenAI'
  properties: {
    customSubDomainName: 'oai${baseName}'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
    disableLocalAuth: true
    restrictOutboundNetworkAccess: true
    allowedFqdnList: []
  }
  sku: {
    name: 'S0'
  }

  @description('Fairly aggressive filter that attempts to block prompts and completions that are likely unprofessional. Tune to your specific requirements.')
  resource blockingFilter 'raiPolicies' = {
    name: 'blocking-filter'
    properties: {
#disable-next-line BCP073 // TODO (P5): can we remove type?
      type: 'UserManaged'
      basePolicyName: 'Microsoft.Default'
      mode: 'Default'
      contentFilters: [
        /* PROMPT FILTERS */
        {
          name: 'hate'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Prompt'
        }
        {
          name: 'sexual'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Prompt'
        }
        {
          name: 'selfharm'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Prompt'
        }
        {
          name: 'violence'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Prompt'
        }
        {
          name: 'jailbreak'
          blocking: true
          enabled: true
          source: 'Prompt'
        }
        {
          name: 'profanity'
          blocking: true
          enabled: true
          source: 'Prompt'
        }
        /* COMPLETION FILTERS */
        {
          name: 'hate'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Completion'
        }
        {
          name: 'sexual'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Completion'
        }
        {
          name: 'selfharm'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Completion'
        }
        {
          name: 'violence'
          blocking: true
          enabled: true
          severityThreshold: 'Low'
          source: 'Completion'
        }
        {
          name: 'profanity'
          blocking: true
          enabled: true
          source: 'Completion'
        }
      ]
    }
  }

  @description('Add a gpt-3.5 turbo deployment.')
  resource gpt35 'deployments' = {
    name: 'gpt35'
    sku: {
      name: 'Standard'
      capacity: 25
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: 'gpt-35-turbo'
        version: '0125' // If your selected region or quota doesn't support this version, please change it to a supported value.

                        // az cognitiveservices model list -l YOUR_REGION --query "sort([?model.name == 'gpt-35-turbo' && kind == 'OpenAI'].model.version)" -o tsv
      }
      raiPolicyName: openAiAccount::blockingFilter.name
      versionUpgradeOption: 'NoAutoUpgrade'  // Always pin your dependencies, be intentional about updates.
    }
  }
}

//OpenAI diagnostic settings
resource openAIDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: openAiAccount
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

resource openaiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: openaiPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: openaiPrivateEndpointName
        properties: {
          groupIds: [
            'account'
          ]
          privateLinkServiceId: openAiAccount.id
        }
      }
    ]
  }
  dependsOn: [
    openAiAccount::blockingFilter
    openAiAccount::gpt35
  ]
}

// ---- Outputs ----

output openAiResourceName string = openAiAccount.name
