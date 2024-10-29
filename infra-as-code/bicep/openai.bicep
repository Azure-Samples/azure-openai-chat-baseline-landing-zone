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

param keyVaultName string

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

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName

  resource kvsGatewayPublicCert 'secrets' = {
    name: 'openai-key'
    properties: {
      value: openAiAccount.listKeys().key1
    }
  }
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openaiName
  location: location
  kind: 'OpenAI'
  properties: {
    customSubDomainName: 'oai${baseName}'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
    disableLocalAuth: false // Ideally you'd set this to 'true' and use Microsoft Entra ID. This is usually enforced through the policy 'Azure AI Services resources should have key access disabled (disable local authentication)'
  }
  sku: {
    name: 'S0'
  }

  @description('Fairly aggressive filter that attempts to block prompts and completions that are likely unprofessional. Tune to your specific requirements.')
  resource blockingFilter 'raiPolicies' = {
    name: 'blocking-filter'
    properties: {
      #disable-next-line BCP037
      type: 'UserManaged'
      basePolicyName: 'Microsoft.Default'
      mode: 'Default'
      contentFilters: [
        /* PROMPT FILTERS */
        {
          #disable-next-line BCP037
          name: 'hate'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Prompt'
        }
        {
          #disable-next-line BCP037
          name: 'sexual'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Prompt'
        }
        {
          #disable-next-line BCP037
          name: 'selfharm'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Prompt'
        }
        {
          #disable-next-line BCP037
          name: 'violence'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Prompt'
        }
        {
          #disable-next-line BCP037
          name: 'jailbreak'
          blocking: true
          enabled: true
          source: 'Prompt'
        }
        {
          #disable-next-line BCP037
          name: 'profanity'
          blocking: true
          enabled: true
          source: 'Prompt'
        }
        /* COMPLETION FILTERS */
        {
          #disable-next-line BCP037
          name: 'hate'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Completion'
        }
        {
          #disable-next-line BCP037
          name: 'sexual'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Completion'
        }
        {
          #disable-next-line BCP037
          name: 'selfharm'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Completion'
        }
        {
          #disable-next-line BCP037
          name: 'violence'
          blocking: true
          enabled: true
          allowedContentLevel: 'Low'
          source: 'Completion'
        }
        {
          #disable-next-line BCP037
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
        version: '0613' // If your region or quota doesn't support this version, please change it to a supported value.
      }
      raiPolicyName: openAiAccount::blockingFilter.name
      versionUpgradeOption: 'NoAutoUpgrade' // Always pin your dependencies, be intentional about updates.
    }
  }
}

//OpenAI diagnostic settings
resource openAIDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${openAiAccount.name}-diagnosticSettings'
  scope: openAiAccount
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
}

// ---- Outputs ----

output openAiResourceName string = openAiAccount.name
