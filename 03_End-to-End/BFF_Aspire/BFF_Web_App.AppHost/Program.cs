using Aspire.Hosting;
using Aspire.Hosting.Azure;

var builder = DistributedApplication.CreateBuilder(args);

//Replace with a verified domain in your tenant
var identifierUri = "api://contoso.com";

//var appRegistration = builder.AddBicepTemplate(
//    name: "Graph",
//    bicepFile: "../infra/Graph/app-registration.bicep"
//)
//    .WithParameter("identifierUri", identifierUri)
//    .WithParameter("subjectName", "CN=bff.contoso.com")
//    .WithParameter("keyVaultName")
//    .WithParameter("certificateName")
//    .WithParameter("uamiName")
//    .WithParameter("caeDomainName");

//var tenantId       = appRegistration.GetOutput("tenantId");
//var clientId       = appRegistration.GetOutput("clientId");
//var keyVaultUrl    = appRegistration.GetOutput("keyVaultUrl");
//var keyVaultSecret = appRegistration.GetOutput("keyVaultSecret");

var tenantId        = builder.AddParameter("TenantId");
var clientId        = builder.AddParameter("ClientId");
var keyVaultUrl     = builder.AddParameter("keyVaultUrl");
var keyVaultSecret  = builder.AddParameter("keyVaultSecret");

var weatherapi = builder.AddProject<Projects.WeatherAPI>("weatherapi")
    .WithEnvironment("TenantId", tenantId)
    .WithEnvironment("ClientId", clientId)
    .WithEnvironment("IdentifierUri", identifierUri);

builder.AddProject<Projects.BFF_Web_App>("bff-web-app")
    .WithReference(weatherapi)
    .WithExternalHttpEndpoints()
    .WithEnvironment("TenantId", tenantId)
    .WithEnvironment("ClientId", clientId)
    .WithEnvironment("IdentifierUri", identifierUri)
    .WithEnvironment("KeyVaultUrl", keyVaultUrl)
    .WithEnvironment("KeyVaultSecret", keyVaultSecret);

builder.Build().Run();
