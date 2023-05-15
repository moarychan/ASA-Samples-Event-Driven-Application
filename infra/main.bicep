targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Relative Path of ASA Jar')
param relativePath string

param asaServicePlanName string
param logAnalyticsName string = ''
param applicationInsightsName string = ''
param applicationInsightsDashboardName string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var keyVaultName = '${abbrs.keyVaultVaults}${resourceToken}'
var serviceBusNamespaceName = '${environmentName}-${abbrs.serviceBusNamespaces}${resourceToken}'
var asaInstanceName = '${environmentName}-${abbrs.springApps}${resourceToken}'
var asaManagedEnvironmentName = '${environmentName}-${abbrs.appContainerAppsManagedEnvironment}${resourceToken}'
var appName = 'simple-event-driven-app'
var serviceBusConnectionStringSecretName = 'SERVICE-BUS-CONNECTION-STRING'
var tags = {
  'azd-env-name': environmentName
  'spring-cloud-azure': 'true'
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}-${resourceToken}'
  location: location
  tags: tags
}

module keyVault 'modules/keyvault/keyvault.bicep' = if (!(asaServicePlanName == 'StandardGen2')) {
  name: '${deployment().name}--kv'
  scope: resourceGroup(rg.name)
  params: {
  	keyVaultName: keyVaultName
  	location: location
	tags: tags
	principalId: principalId
  }
}

module serviceBus 'modules/servicebus/servicebus.bicep' = {
  name: '${deployment().name}--sb'
  scope: resourceGroup(rg.name)
  params: {
    serviceBusNamespaceName: serviceBusNamespaceName
    location: location
    tags: tags
    keyVaultName: (asaServicePlanName == 'StandardGen2') ? '' : keyVault.outputs.name
    asaServicePlanName: asaServicePlanName
    secretName: serviceBusConnectionStringSecretName
    subscriptionId: subscription().id
    resourceGroupName: rg.name
  }
}

module springApps 'modules/springapps/springapps.bicep' = {
  name: '${deployment().name}--asa'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    appName: appName
    tags: union(tags, { 'azd-service-name': appName })
    asaInstanceName: asaInstanceName
    asaServicePlanName: asaServicePlanName
    asaManagedEnvironmentName: asaManagedEnvironmentName
    relativePath: relativePath
    keyVaultName: (asaServicePlanName == 'StandardGen2') ? '' : keyVault.outputs.name
    appInsightName: monitoring.outputs.applicationInsightsName
    laWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceId
    serviceBusNamespaceId: serviceBus.outputs.serviceBusNamespaceId
    serviceBusNamespaceApiVersion: serviceBus.outputs.serviceBusNamespaceApiVersion
  }
}

module apiKeyVaultAccess './modules/keyvault/keyvault-access.bicep' = if (!(asaServicePlanName == 'StandardGen2')) {
  name: 'api-keyvault-access'
  scope: resourceGroup(rg.name)
  params: {
    keyVaultName: (asaServicePlanName == 'StandardGen2') ? '' : keyVault.outputs.name
    principalId: springApps.outputs.identityPrincipalId
  }
}

// Monitor application with Azure Monitor
module monitoring './modules/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

output AZURE_KEY_VAULT_NAME string = (asaServicePlanName == 'StandardGen2') ? '' : keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = (asaServicePlanName == 'StandardGen2') ? '' : keyVault.outputs.endpoint