extension microsoftGraph

@secure()
param clientSecret string

resource app 'Microsoft.Graph/applications@v1.0' = {
  displayName: 'azd-custom-01'
  uniqueName: 'azd-custom-01'
  //Not supported
  //passwordCredentials: [
  //  {
  //    displayName: 'AspireSecret'
  //    endDateTime: '2025-02-05T00:00:00.00Z'
  //  }
  //]
}

output tenantId string = tenant().tenantId
output clientId string = app.appId
output clientSecret string = clientSecret
