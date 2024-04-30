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

@description('The resource ID of the subscription vending provided spoke in this subscription.')
@minLength(50)
param existingResourceIdForSpokeVirtualNetwork string

@description('The resource ID of the subscription vending provided Internet UDR in this subscription. Leave blank if platform team performs Internet routing another way.')
param existingResourceIdForUdrForInternetTraffic string = ''

@description('The IP range of the hub-provided Azure Bastion subnet range. Needed for workload to limit access in NSGs.')
@minLength(10)
param bastionSubnetAddresses string

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
module monitoringModule 'monitoring.bicep' = {
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
  }
}

// Deploy storage account with private endpoint
module storageModule 'storage.bicep' = {
  name: 'storageDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGrouName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy key vault with private endpoint
module keyVaultModule 'keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGrouName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    apiKey: 'key'
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy container registry with private endpoint
module acrModule 'acr.bicep' = {
  name: 'acrDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGrouName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy application insights
module appInsightsModule 'applicationinsignts.bicep' = {
  name: 'appInsightsDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
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
    virtualNetworkResourceGrouName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    keyVaultName: keyVaultModule.outputs.keyVaultName
  }
}

// Deploy the gpt 3.5 model within the Azure OpenAI service deployed above.
module openaiModels 'openai-models.bicep' = {
  name: 'openaiModelsDeploy'
  scope: rgWorkload
  params: {
    openaiName: openaiModule.outputs.openAiResourceName
  }
}

// Deploy machine learning workspace with private endpoint and private DNS zone
module mlwModule 'machinelearning.bicep' = {
  name: 'mlwDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGrouName: rgSpoke.name
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    applicationInsightsName: appInsightsModule.outputs.applicationInsightsName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    mlStorageAccountName: storageModule.outputs.mlDeployStorageName
    containerRegistryName: 'cr${baseName}'
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
    openAiResourceName: openaiModule.outputs.openAiResourceName
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
    virtualNetworkResourceGrouName: rgSpoke.name
    appGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    gatewayCertSecretUri: keyVaultModule.outputs.gatewayCertSecretUri
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
}

// Deploy the web apps for the front end demo ui and the containerised promptflow endpoint
module webappModule 'webapp.bicep' = {
  name: 'webappDeploy'
  scope: rgWorkload
  params: {
    location: rgWorkload.location
    baseName: baseName
    publishFileName: publishFileName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    storageName: storageModule.outputs.appDeployStorageName
    vnetName: networkModule.outputs.vnetName
    virtualNetworkResourceGrouName: rgSpoke.name
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: monitoringModule.outputs.logWorkspaceName
  }
  dependsOn: [
    openaiModule
    acrModule
  ]
}
