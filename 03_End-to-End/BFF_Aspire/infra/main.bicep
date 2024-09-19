targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention, the name of the resource group for your application will use this name, prefixed with rg-')
param environmentName string

@minLength(1)
@description('The location used for all deployed resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('The resource group for the network infrastructure.')
param networkRGName string = 'rg-azd-level-2'

@description('The name of the virtual network to attach resources to.')
param vnetName string = 'aca-azd-weu'

resource rg_vnet 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: networkRGName
}
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  scope: rg_vnet
  name: vnetName
}

var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  scope: rg
  name: 'resources'
  params: {
    location: location
    vnetId: vnet.id
    dnsRGName: networkRGName
    tags: tags
    principalId: principalId
  }
}

module Graph 'Graph/app-registration.bicep' = {
  name: 'Graph'
  scope: rg
  params: {
    location: location
    uamiName: resources.outputs.MANAGED_IDENTITY_NAME
    keyVaultName: resources.outputs.KEYVAULT_NAME
    certificateName: 'cert-${uniqueString('kv')}'
    subjectName: 'CN=bff.contoso.com'
    //Replace contoso with a verified domain in your tenant
    identifierUri: 'api://contoso.com'
    caeDomainName: resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN
  }
}

output MANAGED_IDENTITY_CLIENT_ID string = resources.outputs.MANAGED_IDENTITY_CLIENT_ID
output MANAGED_IDENTITY_NAME string = resources.outputs.MANAGED_IDENTITY_NAME
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = resources.outputs.AZURE_LOG_ANALYTICS_WORKSPACE_NAME
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT
output AZURE_CONTAINER_REGISTRY_MANAGED_IDENTITY_ID string = resources.outputs.AZURE_CONTAINER_REGISTRY_MANAGED_IDENTITY_ID
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_NAME
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_ID
output AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN string = resources.outputs.AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN
output GRAPH_CLIENTID string = Graph.outputs.clientId
output GRAPH_TENANTID string = Graph.outputs.tenantId
output GRAPH_IDENTIFIER_URI string = Graph.outputs.identifierUri
output KEYVAULT_URL string = resources.outputs.KEYVAULT_URL
output KEYVAULT_SECRET string = Graph.outputs.keyVaultSecret
