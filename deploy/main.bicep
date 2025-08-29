param appName string = 'memory-stress-tester'
param environment string = 'dev'
param appServicePlanSku string = 'B1'
param enableApplicationInsights bool = false
param defaultMemoryThresholdMB int = 1024
param maxAllowedMemoryThresholdMB int = 4096
param tags object = {}

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var planName = '${appName}-${uniqueSuffix}'
var webAppName = '${appName}-${uniqueSuffix}'
var appInsightsName = '${appName}-insights-${uniqueSuffix}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: resourceGroup().location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: resourceGroup().location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: resourceGroup().location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: concat([
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: environment
        }
      ], enableApplicationInsights ? [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ] : [])
    }
  }
}

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output appServicePlanName string = appServicePlan.name
output appServicePlanSku string = appServicePlan.sku.name
output appInsightsName string = enableApplicationInsights ? appInsights.name : ''
output appInsightsInstrumentationKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
