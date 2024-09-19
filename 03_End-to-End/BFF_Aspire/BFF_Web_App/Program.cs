using BFF_Web_App;
using BFF_Web_App.Client.Pages;
using BFF_Web_App.Client.Weather;
using BFF_Web_App.Components;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.FluentUI.AspNetCore.Components;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http;
using Yarp.ReverseProxy.Transforms;
using Microsoft.Identity.Web;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Extensions.Configuration;
using Microsoft.Identity.Abstractions;
using Microsoft.Extensions.Azure;

var builder = WebApplication.CreateBuilder(args);

var tenantId        = builder.Configuration.GetValue<string>("TenantId");
var clientId        = builder.Configuration.GetValue<string>("ClientId");
var clientSecret    = builder.Configuration.GetValue<string>("ClientSecret");
var identitifierUri = builder.Configuration.GetValue<string>("IdentifierUri");
var keyvaultUrl     = builder.Configuration.GetValue<string>("KeyVaultUrl") ?? "noVault";
var keyvaultSecret  = builder.Configuration.GetValue<string>("KeyVaultSecret") ?? "noVault";

builder.AddServiceDefaults();

// https://github.com/AzureAD/microsoft-identity-web/wiki/Certificates
builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddCookie("MicrosoftOidc")
    .AddMicrosoftIdentityWebApp(microsoftIdentityOptions =>
    {
        if (builder.Environment.IsDevelopment())
        {
            microsoftIdentityOptions.ClientCredentials = new CredentialDescription[] {
            CertificateDescription.FromStoreWithDistinguishedName("CN=MySelfSignedCertificate",System.Security.Cryptography.X509Certificates.StoreLocation.CurrentUser)};
        }
        else
        {
            microsoftIdentityOptions.ClientCredentials = new CredentialDescription[] {
            CertificateDescription.FromKeyVault(keyvaultUrl,keyvaultSecret)};
        }
        
        microsoftIdentityOptions.ClientId = clientId;

        microsoftIdentityOptions.SignInScheme = CookieAuthenticationDefaults.AuthenticationScheme;
        microsoftIdentityOptions.CallbackPath = new PathString("/signin-oidc");
        microsoftIdentityOptions.SignedOutCallbackPath = new PathString("/signout-callback-oidc");
        microsoftIdentityOptions.Scope.Add($"{identitifierUri}/Weather.Get");
        microsoftIdentityOptions.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0/";

        microsoftIdentityOptions.ResponseType = OpenIdConnectResponseType.Code;
        microsoftIdentityOptions.MapInboundClaims = false;
        microsoftIdentityOptions.TokenValidationParameters.NameClaimType = JwtRegisteredClaimNames.Name;
        microsoftIdentityOptions.TokenValidationParameters.RoleClaimType = "role";
    }).EnableTokenAcquisitionToCallDownstreamApi(confidentialClientApplicationOptions =>
    {
        confidentialClientApplicationOptions.Instance = "https://login.microsoftonline.com/";
        confidentialClientApplicationOptions.TenantId = tenantId;
        confidentialClientApplicationOptions.ClientId = clientId;
    
    })
  .AddInMemoryTokenCaches();

builder.Services.ConfigureCookieOidcRefresh("Cookies", OpenIdConnectDefaults.AuthenticationScheme);

builder.Services.AddAuthorization();

builder.Services.AddCascadingAuthenticationState();

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents()
    .AddInteractiveWebAssemblyComponents();
builder.Services.AddFluentUIComponents();

builder.Services.AddScoped<AuthenticationStateProvider, PersistingAuthenticationStateProvider>();

builder.Services.AddHttpForwarderWithServiceDiscovery();
builder.Services.AddHttpContextAccessor();

builder.Services.AddHttpClient<IWeatherForecaster, ServerWeatherForecaster>(httpClient =>
{
    httpClient.BaseAddress = new("https://weatherapi");
});

var app = builder.Build();

app.MapDefaultEndpoints();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseWebAssemblyDebugging();
}
else
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();

    //To make https work
    app.UseForwardedHeaders(new ForwardedHeadersOptions
    {
        ForwardedHeaders = ForwardedHeaders.XForwardedProto
    });
}

app.UseHttpsRedirection();

app.UseStaticFiles();
app.UseAntiforgery();

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddInteractiveWebAssemblyRenderMode()
    .AddAdditionalAssemblies(typeof(BFF_Web_App.Client._Imports).Assembly);

if (app.Environment.IsDevelopment())
{
    app.MapForwarder("/weather-forecast", "https://localhost:5041", transformBuilder =>
    {
        transformBuilder.AddRequestTransform(async transformContext =>
        {
            var accessToken = await transformContext.HttpContext.GetTokenAsync("access_token");
            transformContext.ProxyRequest.Headers.Authorization = new("Bearer", accessToken);
        });
    }).RequireAuthorization();
}
else
{
    app.MapForwarder("/weather-forecast", "http://weatherapi", transformBuilder =>
    {
        transformBuilder.AddRequestTransform(async transformContext =>
        {
            var accessToken = await transformContext.HttpContext.GetTokenAsync("access_token");
            transformContext.ProxyRequest.Headers.Authorization = new("Bearer", accessToken);
        });
    }).RequireAuthorization();
}

app.MapGroup("/authentication").MapLoginAndLogout();

app.Run();
