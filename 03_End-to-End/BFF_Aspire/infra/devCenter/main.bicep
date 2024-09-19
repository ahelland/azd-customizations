targetScope = 'subscription'

param location string

@description('Tags retrieved from parameter file.')
param resourceTags object = {}
@description('Name of DevBox definition.')
param definitionName string = 'DevBox-8-32'
@description('DevBox definition SKU.')
param definitionSKU string = 'general_i_8c32gb256ssd_v2'
@description('DevBox definition storage type.')
param definitionStorageType string = 'ssd_256gb'

resource rg_devc 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-azd-devcenter'
  location: location
  tags: resourceTags
}

resource rg_vnet 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: 'rg-azd-level-2'
}

param vnetName string = 'aca-azd-weu'
resource vnet 'Microsoft.Network/virtualNetworks@2023-06-01' existing = {
  scope: rg_vnet
  name: vnetName
}

module devCenter '../modules/devcenters/devcenter/main.bicep' = {
  scope: rg_devc
  name: 'azd-devcenter'
  params: {
    location: location
    devCenterName: 'azd-devCenter'
    definitionName: definitionName
    definitionSKU: definitionSKU
    definitionStorageType: definitionStorageType
    image: 'microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win11-m365-gen2'
    networkConnectionId: networkConnection.outputs.id    
  }
}

module devProject '../modules/devcenters/project/main.bicep' = {
  scope: rg_devc
  name: 'azd-devProject'
  params: {
    devBoxDefinitionName: definitionName
    devCenterId: devCenter.outputs.devCenterId
    devPoolName: 'azd-devBoxPool'
    location: location
    networkConnectionName: devCenter.outputs.devCenterAttachedNetwork
    projectName: 'azd-devProject'
    deploymentTargetId: subscription().id
  }
}

//Add permissions for the dev environment identity to modify the vnet
var networkContributorRole = resourceId('Microsoft.Authorization/roleAssignments','4d97b98b-1d4f-4787-a291-c67834d212e7')
resource networkRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(rg_devc.id,devCenter.name,networkContributorRole)
  properties: {
    principalId: devProject.outputs.devEnvironmentManagedId
    roleDefinitionId: networkContributorRole
    principalType: 'ServicePrincipal'
  }
}

//Connect the Dev Center to the custom vnet
module networkConnection '../modules/devcenters/network-connection/main.bicep' = {
  scope: rg_devc
  name: 'azd-devcenter-network-connection'
  params: {
    connectionName: 'azd-devcenter-network-connection'
    location: location
    snetId: vnet.properties.subnets[0].id
  }
}
