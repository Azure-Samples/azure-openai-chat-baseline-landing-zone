targetScope = 'resourceGroup'

/*
  Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('Domain name to use for App Gateway')
param customDomainName string

param gatewayCertSecretUri string

// existing resource name params 
param vnetName string

@description('The name of the resource group containing the spoke virtual network.')
@minLength(1)
param virtualNetworkResourceGroupName string

param appGatewaySubnetName string
param appName string
param keyVaultName string
param logWorkspaceName string

//variables
var appGatewayName = 'agw-${baseName}'
var appGatewayManagedIdentityName = 'id-${appGatewayName}'
var appGatewayPublicIpName = 'pip-${baseName}'
var appGatewayFqdn = 'fe-${baseName}'
var wafPolicyName = 'waf-${baseName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName
  scope: resourceGroup(virtualNetworkResourceGroupName)

  resource appGatewaySubnet 'subnets' existing = {
    name: appGatewaySubnetName
  }
}

resource webApp 'Microsoft.Web/sites@2022-09-01' existing = {
  name: appName
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logWorkspaceName
}

// Built-in Azure RBAC role that is applied to a Key Vault to grant with secrets content read privileges. Granted to both Key Vault and our workload's identity.
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

// ---- App Gateway resources ----

// Managed Identity for Application Gateway. 
resource appGatewayManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appGatewayManagedIdentityName
  location: location
}

// Grant the Azure Application Gateway managed identity with Key Vault secrets role permissions; this allows pulling certificates.
module appGatewaySecretsUserRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: 'appGatewaySecretsUserRoleAssignmentDeploy'
  params: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: appGatewayManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

//External IP for App Gateway
resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2022-11-01' = {
  name: appGatewayPublicIpName
  location: location
  zones: ['1', '2', '3']
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: appGatewayFqdn
    }
  }
}

//WAF policy definition
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-05-01' = {
  name: wafPolicyName
  location: location
  properties: {
    policySettings: {
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

//App Gateway
resource appGateway 'Microsoft.Network/applicationGateways@2022-11-01' = {
  name: appGatewayName
  location: location
  zones: ['1', '2', '3']
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGatewayManagedIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    sslPolicy: {
      policyType: 'Custom'
      cipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
      minProtocolVersion: 'TLSv1_2'
    }

    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: vnet::appGatewaySubnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    probes: [
      {
        name: 'probe-web${baseName}'
        properties: {
          protocol: 'Https'
          path: '/favicon.ico'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
              '401'
              '403'
            ]
          }
        }
      }
    ]
    firewallPolicy: {
      id: wafPolicy.id
    }
    enableHttp2: false
    sslCertificates: [
      {
        name: '${appGatewayName}-ssl-certificate'
        properties: {
          keyVaultSecretId: gatewayCertSecretUri
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'pool-${appName}'
        properties: {
          backendAddresses: [
            {
              fqdn: webApp.properties.defaultHostName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'WebAppBackendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, 'probe-web${baseName}')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'WebAppListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              appGatewayName,
              'appGwPublicFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port-443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/sslCertificates',
              appGatewayName,
              '${appGatewayName}-ssl-certificate'
            )
          }
          hostName: 'www.${customDomainName}'
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'WebAppRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'WebAppListener')
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              appGatewayName,
              'pool-${appName}'
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              appGatewayName,
              'WebAppBackendHttpSettings'
            )
          }
        }
      }
    ]
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 3
    }
  }
  dependsOn: [
    appGatewaySecretsUserRoleAssignmentModule
  ]
}

//Application Gateway diagnostic settings
resource appGatewayDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${appGateway.name}-diagnosticSettings'
  scope: appGateway
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
