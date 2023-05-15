param location string
param asaInstanceName string
param asaManagedEnvironmentName string
param appName string
param tags object = {}
param relativePath string
param keyVaultName string
param appInsightName string
param laWorkspaceResourceId string
param asaServicePlanName string
param serviceBusNamespaceId string
param serviceBusNamespaceApiVersion string

var servicePlanMappings = {
  Basic: {
    name: 'B0'
    tier: 'Basic'
  }
  Standard: {
    name: 'S0'
    tier: 'Standard'
  }
  StandardGen2: {
    name: 'S0'
    tier: 'StandardGen2'
  }
  Enterprise: {
    name: 'E0'
    tier: 'Enterprise'
  }
}

var identity = {
  type: 'SystemAssigned'
}

var secrets = [
  {
    name: 'SERVICE-BUS-CONNECTION-STRING'
    value: listKeys('${serviceBusNamespaceId}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespaceApiVersion).primaryConnectionString
  }
]

var environmentVariables = {
  AZURE_KEY_VAULT_ENDPOINT: keyVault.properties.vaultUri
}

var standardGen2EnvironmentVariables = {
  spring_cloud_azure_keyvault_secret_propertysourceenabled: 'false'
}

resource asaInstance 'Microsoft.AppPlatform/Spring@2023-01-01-preview' = {
  name: asaInstanceName
  location: location
  tags: tags
  sku: servicePlanMappings[asaServicePlanName]
  properties: {
      managedEnvironmentId: (asaServicePlanName == 'StandardGen2') ? asaManagedEnvironment.id : null
  }
}

resource asaManagedEnvironment 'Microsoft.App/managedEnvironments@2022-10-01' = if (asaServicePlanName == 'StandardGen2') {
  name: asaManagedEnvironmentName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
  }
  properties: {
      appLogsConfiguration: {
        destination: 'log-analytics'
        logAnalyticsConfiguration: {
          customerId: reference(laWorkspaceResourceId, '2022-10-01').customerId
          sharedKey: listKeys(laWorkspaceResourceId, '2022-10-01').primarySharedKey
        }
      }
    }
}

resource asaApp 'Microsoft.AppPlatform/Spring/apps@2023-01-01-preview' = {
  name: appName
  location: location
  parent: asaInstance
  identity: (asaServicePlanName == 'StandardGen2') ? null : identity
  properties: {
    secrets: (asaServicePlanName == 'StandardGen2') ? secrets : null
  }
}

// resource asaDeployment 'Microsoft.AppPlatform/Spring/apps/deployments@2023-01-01-preview' = {
//   name: 'default'
//   parent: asaApp
//   properties: {
//     active: true
//     source: {
//       type: 'Jar'
//       relativePath: relativePath
//       runtimeVersion: 'Java_17'
//     }
//     deploymentSettings: {
//       resourceRequests: {
//         cpu: '1'
//         memory: '2Gi'
//       }
//       environmentVariables: (asaServicePlanName == 'StandardGen2') ? standardGen2EnvironmentVariables : environmentVariables
//     }
//   }
// }

resource springAppsMonitoringSettings 'Microsoft.AppPlatform/Spring/monitoringSettings@2023-01-01-preview' = {
  name: 'default' // The only supported value is 'default'
  parent: asaInstance
  properties: {
    traceEnabled: true
    appInsightsInstrumentationKey: applicationInsights.properties.InstrumentationKey
  }
}

resource springAppsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!(asaServicePlanName == 'StandardGen2')) {
  name: 'monitoring'
  scope: asaInstance
  properties: {
    workspaceId: laWorkspaceResourceId
    logs: [
      {
        category: 'ApplicationConsole'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }
    ]
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (!(empty(appInsightName))) {
  name: appInsightName
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = if (!(empty(keyVaultName))) {
  name: keyVaultName
}

output identityPrincipalId string = (asaServicePlanName == 'StandardGen2') ? '' : asaApp.identity.principalId
output name string = asaApp.name
output uri string = 'https://${asaApp.properties.url}'