/*
//todo-preignite: document exemption from
// "Enforce recommended guardrails for Customer Managed Keys",
// "Encryption for storage services should be enforced for Storage Accounts"
// "Storage Accounts should use a container delete retention policy" policy initiative
// "Azure Machine Learning workspaces should use user-assigned managed identity
// "Azure Machine Learning workspaces should enable V1LegacyMode to support network isolation backward compatibility"
// "Virtual machines and virtual machine scale sets should have encryption at host enabled"

//todo-preignite: Comply with Storage Accounts should restrict CORS rules, Allowed Copy scope should be restricted for Storage Accounts, Network ACL bypass option should be restricted for Storage Accounts
//todo-postignite: Compliance with "Subnets should be private" policy
//todo-postignite: Compliance with "Managed disks should disable public network access"
//todo-postignite: Compliance with "Deploy Azure Monitor Baseline Alerts for Web"
*/

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

@description('The resource ID of the subscription vending provided spoke in your application landging zone subscription. For example, /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/rg-app-networking/providers/Microsoft.Network/virtualNetworks/vnet-app000-spoke0')
@minLength(114)
param existingResourceIdForSpokeVirtualNetwork string

@description('The resource ID of the subscription vending provided Internet UDR in your application landging zone subscription. Leave blank if platform team performs Internet routing another way. For example, /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/rg-app-networking/providers/Microsoft.Network/routeTables/udr-to-hub')
param existingResourceIdForUdrForInternetTraffic string = ''

@description('The IP range of the hub-provided Azure Bastion subnet range. Needed for workload to limit access in NSGs. For example, 10.0.1.0/26')
@minLength(9)
param bastionSubnetAddresses string

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
param agentsSubnetAddressPrefix string

@description('Address space within the existing spoke\'s available address space to be used for jump boxes.')
@minLength(9)
param jumpBoxSubnetAddressPrefix string

@description('Assign your user some roles to support fluid access when working in AI Studio')
@maxLength(37)
@minLength(36)
param yourPrincipalId string

// ---- Parameters required to set to make it non availability zone compliant ----

var existingResourceGroupNameForSpokeVirtualNetwork = split(existingResourceIdForSpokeVirtualNetwork, '/')[4]
var existingSpokeVirtualNetworkName = split(existingResourceIdForSpokeVirtualNetwork, '/')[8]
var existingUdrForInternetTrafficName = split(existingResourceIdForUdrForInternetTraffic, '/')[8]

// ---- Target Resource Groups ----

resource rgWorkload 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: workloadResourceGroupName
}

resource rgSpoke 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: existingResourceGroupNameForSpokeVirtualNetwork
}

// Deploy Log Analytics workspace
module monitoringModule 'applicationinsignts.bicep' = {
  name: 'workloadMonitoring'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
  }
}

// Deploy subnets and NSGs
module networkModule 'network.bicep' = {
  name: 'networkDeploy'
  scope: rgSpoke
  params: {
    location: rgSpoke.location
    existingSpokeVirtualNetworkName: existingSpokeVirtualNetworkName
    existingUdrForInternetTrafficName: existingUdrForInternetTrafficName
    bastionSubnetAddresses: bastionSubnetAddresses
    appServicesSubnetAddressPrefix: appServicesSubnetAddressPrefix
    appGatewaySubnetAddressPrefix: appGatewaySubnetAddressPrefix
    privateEndpointsSubnetAddressPrefix: privateEndpointsSubnetAddressPrefix
    agentsSubnetAddressPrefix: agentsSubnetAddressPrefix
    jumpBoxSubnetAddressPrefix: jumpBoxSubnetAddressPrefix
  }
}

// Deploy Azure Storage account with private endpoint and private DNS zone
module storageModule 'storage.bicep' = {
  name: 'storageDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    yourPrincipalId: yourPrincipalId
  }
}

// Deploy Azure Key Vault with private endpoint and private DNS zone
module keyVaultModule 'keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy Azure Container Registry with private endpoint and private DNS zone
module acrModule 'acr.bicep' = {
  name: 'acrDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    buildAgentSubnetName: networkModule.outputs.agentSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy Azure OpenAI service with private endpoint
module openaiModule 'openai.bicep' = {
  name: 'openaiDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy Azure AI Studio with private networking
module aiStudioModule 'machinelearning.bicep' = {
  name: 'aiStudioDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    applicationInsightsName: monitoringModule.outputs.applicationInsightsName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    aiStudioStorageAccountName: storageModule.outputs.mlDeployStorageName
    containerRegistryName: 'cr${baseName}'
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    openAiResourceName: openaiModule.outputs.openAiResourceName
    yourPrincipalId: yourPrincipalId
  }
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module gatewayModule 'gateway.bicep' = {
  name: 'gatewayDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    customDomainName: customDomainName
    appName: webappModule.outputs.appName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    appGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    gatewayCertSecretKey: keyVaultModule.outputs.gatewayCertSecretKey
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy the web apps for the front end demo UI and the containerised promptflow endpoint
module webappModule 'webapp.bicep' = {
  name: 'webappDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    managedOnlineEndpointResourceId: aiStudioModule.outputs.managedOnlineEndpointResourceId
    acrName: acrModule.outputs.acrName
    publishFileName: publishFileName
    openAIName: openaiModule.outputs.openAiResourceName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    storageName: storageModule.outputs.appDeployStorageName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGroupName: rgSpoke.name
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}
