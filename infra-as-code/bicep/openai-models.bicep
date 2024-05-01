targetScope = 'resourceGroup'

@description('This is the name of the existing Azure OpenAI service')
param openaiName string

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' existing = {
  name: openaiName

  resource blockingFilter 'raiPolicies' existing = {
    name: 'blocking-filter'
  }

  // TODO: Delete once verified no longer necessary

  
}
