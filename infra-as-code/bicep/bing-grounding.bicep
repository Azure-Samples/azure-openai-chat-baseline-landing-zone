targetScope = 'resourceGroup'

@description('Deploy Bing account for Internet grounding.')
#disable-next-line BCP081
resource bingAccount 'Microsoft.Bing/accounts@2025-05-01-preview' = {
  name: 'bing-grounding'
  location: 'global'
  kind: 'Bing.Search.v7'
  sku: { name: 'S1' }
  properties: {}
}

output bingAccountName string = bingAccount.name 
