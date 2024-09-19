using Aspire.Hosting;
using Aspire.Hosting.Azure;

var builder = DistributedApplication.CreateBuilder(args);

//To use appsettings.json
//var tenantId     = builder.AddParameter("TenantId");
//var clientId     = builder.AddParameter("ClientId");
//var clientSecret = builder.AddParameter("ClientSecret",secret:true);

var appRegistration = builder.AddBicepTemplate(
    name: "Graph",
    bicepFile: "../infra/Graph/app-registration.bicep"
);

var tenantId = appRegistration.GetOutput("tenantId");
var clientId = appRegistration.GetOutput("clientId");
var clientSecret = appRegistration.GetSecretOutput("clientSecret");

var weatherapi = builder.AddProject<Projects.WeatherAPI>("weatherapi")
    .WithEnvironment("TenantId",tenantId)
    .WithEnvironment("ClientId",clientId);

builder.AddProject<Projects.BFF_Web_App>("bff-web-app")
    .WithReference(weatherapi)
    .WithEnvironment("TenantId", tenantId)
    .WithEnvironment("ClientId", clientId)
    .WithEnvironment("ClientSecret", clientSecret);

builder.Build().Run();
