targetScope = 'subscription'

@description('Name of the resource group that all resources will be deployed into.')
@minLength(5)
param workloadResourceGroupName string

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Domain name to use for App Gateway')
@minLength(3)
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded.')
@secure()
@minLength(1)
param appGatewayListenerCertificate string

@description('The name of the web deploy file. The file should reside in a deploy container in the Azure Storage account. Defaults to chatui.zip')
@minLength(5)
param publishFileName string = 'chatui.zip'

// ---- Platform and application landing zone specific parameters ----

@description('The resource ID of the subscription vending provided spoke in your application landging zone subscription. For example, /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/rg-app-networking/providers/Microsoft.Network/virtualNetworks/vnet-app000-spoke0')
@minLength(114)
param existingResourceIdForSpokeVirtualNetwork string

@description('The resource ID of the subscription vending provided Internet UDR in your application landging zone subscription. Leave blank if platform team performs Internet routing another way. For example, /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/rg-app-networking/providers/Microsoft.Network/routeTables/udr-to-hub')
@minLength(110)
param existingResourceIdForUdrForInternetTraffic string

@description('Address space within the existing hub\'s available address space to be used for Jumboxes NSG ALLOW rules.')
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

@description('Address space within the existing spoke\'s available address space to be used for ai agents.')
@minLength(9)
param agentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for jump boxes.')
@minLength(9)
param jumpBoxSubnetAddressPrefix string

@description('Assign your user some roles to support fluid access when working in the AI Foundry portal.')
@maxLength(36)
@minLength(36)
param yourPrincipalId string

@description('Set to true to opt-out of deployment telemetry.')
param telemetryOptOut bool = false

// ---- Parameters required to set to make it non availability zone compliant ----

var existingResourceGroupNameForSpokeVirtualNetwork = split(existingResourceIdForSpokeVirtualNetwork, '/')[4]
var existingSpokeVirtualNetworkName = split(existingResourceIdForSpokeVirtualNetwork, '/')[8]
var existingUdrForInternetTrafficName = split(existingResourceIdForUdrForInternetTraffic, '/')[8]
var varCuaid = '58c6a07c-0380-404b-9642-1daaddeca33e' // Customer Usage Attribution Id

// ---- Target Resource Groups ----

resource rgSpoke 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: existingResourceGroupNameForSpokeVirtualNetwork
}

resource rgWorkload 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: workloadResourceGroupName
}

// Deploy subnets and NSGs
module networkModule 'network.bicep' = {
  name: 'networkDeploy'
  scope: rgSpoke
  params: {
    spokeResourceGroupName: rgSpoke.name
    existingSpokeVirtualNetworkName: existingSpokeVirtualNetworkName
    existingUdrForInternetTrafficName: existingUdrForInternetTrafficName
    bastionSubnetAddressPrefix: bastionSubnetAddressPrefix
    appServicesSubnetAddressPrefix: appServicesSubnetAddressPrefix
    appGatewaySubnetAddressPrefix: appGatewaySubnetAddressPrefix
    privateEndpointsSubnetAddressPrefix: privateEndpointsSubnetAddressPrefix
    buildAgentsSubnetAddressPrefix: buildAgentsSubnetAddressPrefix
    agentsSubnetAddressPrefix: agentsSubnetAddressPrefix
    jumpBoxSubnetAddressPrefix: jumpBoxSubnetAddressPrefix
  }
}

// ---- Application LZ new resources ----

@description('Deploy an example set of Azure Policies to help you govern your workload. Expand the policy set as desired.')
module applyAzurePolicies 'azure-policies.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
  }
}

// Deploy the Azure AI Foundry account and Azure AI Agent service components.

@description('Deploys the Azure AI Agent dependencies, Azure Storage, Azure AI Search, and Cosmos DB.')
module deployAIAgentServiceDependencies 'ai-agent-service-dependencies.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    debugUserPrincipalId: yourPrincipalId
    privateEndpointSubnetResourceId: networkModule.outputs.privateEndpointSubnetResourceId
  }
}

@description('Deploy Azure AI Foundry with Azure AI Agent capability. No projects yet deployed.')
module deployAzureAIFoundry 'ai-foundry.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
    agentSubnetResourceId: networkModule.outputs.agentSubnetResourceId
    privateEndpointSubnetResourceId: networkModule.outputs.privateEndpointSubnetResourceId
    aiFoundryPortalUserPrincipalId: yourPrincipalId
  }
}

@description('Deploy the Bing account for Internet grounding data to be used by agents in the Azure AI Agent service.')
module deployBingAccount 'bing-grounding.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
  }
}

// Deploy the Azure Web App resources for the chat UI.

@description('Deploy an Azure Storage account that is used by the Azure Web App for the deployed application code.')
module deployWebAppStorage 'web-app-storage.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
    spokeResourceGroupName: rgSpoke.name
    virtualNetworkName: networkModule.outputs.vnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointSubnetName
    debugUserPrincipalId: yourPrincipalId
  }
  dependsOn: []
}

@description('Deploy Azure Key Vault. In this architecture, it\'s used to store the certificate for the Application Gateway.')
module deployKeyVault 'key-vault.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
    spokeResourceGroupName: rgSpoke.name
    virtualNetworkName: networkModule.outputs.vnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
  }
}

@description('Deploy Application Insights. Used by the Azure Web App to monitor the deployed application and connected to the Azure AI Foundry project.')
module deployApplicationInsights 'application-insights.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
  }
}

@description('Deploy the web app for the front end demo UI. The web application will call into the Azure AI Agent service.')
module deployWebApp 'web-app.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
    spokeResourceGroupName: rgSpoke.name
    publishFileName: publishFileName
    virtualNetworkName: networkModule.outputs.vnetName
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointSubnetName
    existingWebAppDeploymentStorageAccountName: deployWebAppStorage.outputs.appDeployStorageName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
    existingAzureAiFoundryResourceName: deployAzureAIFoundry.outputs.aiFoundryName
  }
}

@description('Deploy an Azure Application Gateway with WAF and a custom domain name + TLS cert.')
module deployApplicationGateway 'application-gateway.bicep' = {
  scope: rgWorkload
  params: {
    baseName: baseName
    logAnalyticsWorkspaceName: deployAIAgentServiceDependencies.outputs.logAnalyticsWorkspaceName
    spokeResourceGroupName: rgSpoke.name
    customDomainName: customDomainName
    appName: deployWebApp.outputs.appName
    virtualNetworkName: networkModule.outputs.vnetName
    applicationGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: deployKeyVault.outputs.keyVaultName
    gatewayCertSecretKey: deployKeyVault.outputs.gatewayCertSecretKey
  }
}

// Optional Deployment for Customer Usage Attribution
module customerUsageAttributionModule 'customerUsageAttribution/cuaIdResourceGroup.bicep' = if (!telemetryOptOut) {
  #disable-next-line no-loc-expr-outside-params // Only to ensure telemetry data is stored in same location as deployment. See https://github.com/Azure/ALZ-Bicep/wiki/FAQ#why-are-some-linter-rules-disabled-via-the-disable-next-line-bicep-function for more information
  name: 'pid-${varCuaid}-${uniqueString(deployment().location)}'
  scope: rgWorkload
  params: {}
}

// ---- Outputs ----

@description('The name of the Azure AI Foundry account.')
output aiFoundryName string = deployAzureAIFoundry.outputs.aiFoundryName
@description('The name of the Cosmos DB account.')
output cosmosDbAccountName string = deployAIAgentServiceDependencies.outputs.cosmosDbAccountName
@description('The name of the Storage Account.')
output storageAccountName string = deployAIAgentServiceDependencies.outputs.storageAccountName
@description('The name of the AI Search account.')
output aiSearchAccountName string = deployAIAgentServiceDependencies.outputs.aiSearchName
@description('The name of the Bing account.')
output bingAccountName string = deployBingAccount.outputs.bingAccountName
@description('The name of the Application Insights resource.')
output webApplicationInsightsResourceName string = deployApplicationInsights.outputs.applicationInsightsName
