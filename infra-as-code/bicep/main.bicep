targetScope = 'subscription'

@description('Name of the resource group that all resources will be deployed into.')
@minLength(5)
param workloadResourceGroupName string

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Domain name to use for App Gateway')
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string

@description('The name of the web deploy file. The file should reside in a deploy container in the storage account. Defaults to chatui.zip')
param publishFileName string = 'chatui.zip'

// ---- Platform and application landing zone specific parameters ----

@description('Resource ID of the existing spoke virtual network')
param existingResourceIdForSpokeVirtualNetwork string

@description('Name of the existing spoke virtual network')
param existingSpokeVirtualNetworkName string

@description('Name of the existing spoke virtual network resource group')
param existingSpokeVirtualNetworkResourceGroupName string

@description('Name of the existing app gateway subnet')
param existingAppGatewaySubnetName string

@description('Name of the existing app services subnet')
param existingAppServicesSubnetName string

@description('Name of the existing private endpoints subnet')
param existingPrivateEndpointsSubnetName string

@description('Name of the existing build agents subnet')
param existingBuildAgentsSubnetName string

@description('Resource ID of the existing route table for build agents subnet')
param existingBuildAgentsSubnetUdrResourceId string

@description('Hub resource group name for private DNS zones')
param hubResourceGroupName string

@description('Your principal ID for role assignments')
param yourPrincipalId string

@description('Existing Application Insights resource name')
param existingWebApplicationInsightsResourceName string

// Use the spoke resource group directly - no separate workload resource group
resource rgSpoke 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: existingSpokeVirtualNetworkResourceGroupName
}

// Reference existing Application Insights instead of deploying new one
resource existingAppInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: existingWebApplicationInsightsResourceName
  scope: rgSpoke
}

// We'll get the Log Analytics workspace from the hub resource group
resource existingLogAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'log-hub'
  scope: resourceGroup(hubResourceGroupName)
}

// Deploy Key Vault in the spoke resource group
module deployKeyVault 'keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    baseName: baseName
    vnetName: existingSpokeVirtualNetworkName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: existingPrivateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    logWorkspaceName: existingLogAnalytics.name
    hubResourceGroupName: hubResourceGroupName
  }
}

// Deploy AI Agent Service Dependencies in the spoke resource group
module deployAIAgentServiceDependencies 'ai-agent-service-dependencies.bicep' = {
  name: 'aiAgentDependenciesDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    baseName: baseName
    debugUserPrincipalId: yourPrincipalId
    logAnalyticsWorkspaceName: existingLogAnalytics.name
    privateEndpointSubnetResourceId: '${existingResourceIdForSpokeVirtualNetwork}/subnets/${existingPrivateEndpointsSubnetName}'
    hubResourceGroupName: hubResourceGroupName
  }
}

// Deploy Azure AI Foundry in the spoke resource group
module deployAzureAIFoundry 'ai-foundry.bicep' = {
  name: 'aiFoundryDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    baseName: baseName
    logAnalyticsWorkspaceName: existingLogAnalytics.name
    agentSubnetResourceId: '${existingResourceIdForSpokeVirtualNetwork}/subnets/${existingBuildAgentsSubnetName}'
    privateEndpointSubnetResourceId: '${existingResourceIdForSpokeVirtualNetwork}/subnets/${existingPrivateEndpointsSubnetName}'
    aiFoundryPortalUserPrincipalId: yourPrincipalId
  }
}

// Deploy Bing grounding
module deployBingAccount 'bing-grounding.bicep' = {
  name: 'bingGroundingDeploy'
  scope: rgSpoke
}

// Deploy AI Foundry Project
module deployAzureAiFoundryProject 'ai-foundry-project.bicep' = {
  name: 'aiFoundryProjectDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    existingAiFoundryName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAISearchAccountName: deployAIAgentServiceDependencies.outputs.aiSearchName
    existingCosmosDbAccountName: deployAIAgentServiceDependencies.outputs.cosmosDbAccountName
    existingStorageAccountName: deployAIAgentServiceDependencies.outputs.storageAccountName
    existingBingAccountName: deployBingAccount.outputs.bingAccountName
    existingWebApplicationInsightsResourceName: existingWebApplicationInsightsResourceName
  }
  dependsOn: [
    deployAzureAIFoundry
    deployAIAgentServiceDependencies
    deployBingAccount
  ]
}

// Deploy Application Gateway in the spoke resource group
module deployApplicationGateway 'gateway.bicep' = {
  name: 'applicationGatewayDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    baseName: baseName
    customDomainName: customDomainName
    vnetName: existingSpokeVirtualNetworkName
    virtualNetworkResourceGroupName: rgSpoke.name
    appGatewaySubnetName: existingAppGatewaySubnetName
    appName: deployWebApp.outputs.appName
    keyVaultName: deployKeyVault.outputs.keyVaultName
    gatewayCertSecretKey: 'gateway-certificate'
    logWorkspaceName: existingLogAnalytics.name
  }
  dependsOn: [
    deployWebApp
    deployKeyVault
  ]
}

// Deploy Web App in the spoke resource group
module deployWebApp 'webapp.bicep' = {
  name: 'webAppDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    baseName: baseName
    logAnalyticsWorkspaceName: existingLogAnalytics.name
    publishFileName: publishFileName
    virtualNetworkName: existingSpokeVirtualNetworkName
    appServicesSubnetName: existingAppServicesSubnetName
    privateEndpointsSubnetName: existingPrivateEndpointsSubnetName
    existingWebAppDeploymentStorageAccountName: deployAIAgentServiceDependencies.outputs.storageAccountName
    existingWebApplicationInsightsResourceName: existingWebApplicationInsightsResourceName
    existingAzureAiFoundryResourceName: deployAzureAIFoundry.outputs.aiFoundryName
    bingSearchConnectionId: deployAzureAiFoundryProject.outputs.bingSearchConnectionId
  }
  dependsOn: [
    existingLogAnalytics
    deployAIAgentServiceDependencies
    deployAzureAIFoundry
    deployAzureAiFoundryProject
  ]
}
