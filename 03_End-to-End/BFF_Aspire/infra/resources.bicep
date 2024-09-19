@description('The location used for all deployed resources')
param location string = resourceGroup().location
@description('Id of the user or app to assign application roles')
param principalId string = ''
@description('The id of the virtual network to use.')
param vnetId string
@description('The resource group containing DNS zones.')
param dnsRGName string

@description('Tags that will be applied to all resources')
param tags object = {}

var resourceToken = uniqueString(resourceGroup().id)

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${resourceToken}'
  location: location
  tags: tags
}

module containerRegistry 'modules/containers/container-registry/main.bicep' = {
  name: replace('acr-${resourceToken}', '-', '')
  params: {
    resourceTags: tags
    acrName: replace('acr-${resourceToken}', '-', '')
    acrSku: 'Premium'
    adminUserEnabled: false
    anonymousPullEnabled: false 
    location: location
    managedIdentity: 'SystemAssigned'
    publicNetworkAccess: 'Enabled'
  }
}

//Private endpoints (two required for ACR)
module peAcr 'acr-pe-endpoints.bicep' = {
  name: 'pe-acr'
  params: {
    resourceTags: tags
    location: location
    peName: 'pe-acr'
    serviceConnectionGroupIds: 'registry'
    serviceConnectionId: containerRegistry.outputs.id
    snetId: '${vnetId}/subnets/snet-pe-01'
  }
}

module acr_dns_pe_0 'modules/network/private-dns-record-a/main.bicep' = {
  scope: resourceGroup(dnsRGName)
  name: 'dns-a-acr-region'
  params: {
    ipAddress: peAcr.outputs.ip_0
    recordName: '${containerRegistry.outputs.acrName}.${location}.data'
    zone: 'privatelink.azurecr.io'
  }
}

module acr_dns_pe_1 'modules/network/private-dns-record-a/main.bicep' = {
  scope: resourceGroup(dnsRGName)
  name: 'dns-a-acr-root'
  params: {
    ipAddress: peAcr.outputs.ip_1
    recordName: containerRegistry.outputs.acrName
    zone: 'privatelink.azurecr.io'
  }
}

resource vault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: 'kv-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name:  'standard'
      family:  'A'
    }
    accessPolicies: []
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
    tenantId: tenant().tenantId
  }
}

//Key Vault Secrets User        - 4633458b-17de-408a-b874-0445c86b69e6
//Key Vault Secrets Officer     - b86a8fe4-44ce-4948-aee5-eccb2c155cd7
//Key Vault Certificate Officer - a4417e6f-fecd-4de8-b567-7b0420556985
resource kvMiRoleAssignmentCertificates 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, managedIdentity.id, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985'))
  scope: vault
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId:  subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')
  }
}

resource kvMiRoleAssignmentSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, managedIdentity.id, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'))
  scope: vault
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId:  subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  }
}

resource scopeACR 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistry.name
}

resource caeMiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.name, managedIdentity.id, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d'))
  scope: scopeACR
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId:  subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-${resourceToken}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
  tags: tags
}

module containerAppEnvironment 'modules/containers/container-environment/main.bicep' = {
  name: 'cae-${resourceToken}'
  params: {
    resourceTags: tags
    location: location
    environmentName: 'cae-${resourceToken}'
    snetId: '${vnetId}/subnets/snet-cae-01'
    //true for connecting CAE to snet (with private IPs)
    //false for public IPs
    vnetInternal: true
  }
}

module dnsZone 'modules/network/private-dns-zone/main.bicep' = {
  //scope: rg_cae
  name: '${containerAppEnvironment.name}-dns'
  params: {
    resourceTags: tags
    registrationEnabled: false
    zoneName: containerAppEnvironment.outputs.defaultDomain
    vnetName: 'cae'
    vnetId: vnetId
  }
}

module webappDns 'modules/network/private-dns-record-a/main.bicep' = {
  //scope: rg_ca
  name: 'bff-web-app'
  params: {
    ipAddress: containerAppEnvironment.outputs.staticIp
    recordName: 'bff-web-app'
    zone: containerAppEnvironment.outputs.defaultDomain
  }
  dependsOn: [
    dnsZone
  ]
}

resource scopeCAE 'Microsoft.App/managedEnvironments@2024-02-02-preview' existing = {
  name: 'cae-${resourceToken}'
}

resource explicitContributorUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerAppEnvironment.name, principalId, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c'))
  scope: scopeCAE
  properties: {
    principalId: principalId
    roleDefinitionId:  subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

output MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.properties.clientId
output MANAGED_IDENTITY_NAME string = managedIdentity.name
output MANAGED_IDENTITY_PRINCIPAL_ID string = managedIdentity.properties.principalId
output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalyticsWorkspace.name
output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = logAnalyticsWorkspace.id
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_MANAGED_IDENTITY_ID string = managedIdentity.id
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppEnvironment.name
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = containerAppEnvironment.outputs.id
output AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN string = containerAppEnvironment.outputs.defaultDomain
output KEYVAULT_URL string = vault.properties.vaultUri
output KEYVAULT_NAME string = vault.name
