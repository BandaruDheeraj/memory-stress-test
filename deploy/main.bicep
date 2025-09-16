param appName string = 'memory-stress-tester'
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
  sku: {
    name: appServicePlanSku
  }
  tags: tags
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: resourceGroup().location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: resourceGroup().location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: appServicePlanSku != 'B1' && appServicePlanSku != 'F1' // AlwaysOn not available on Free/Basic B1
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      healthCheckPath: '/health'
      appSettings: enableApplicationInsights ? [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
      ] : [
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
      ]
      autoHealEnabled: true
      autoHealRules: {
        triggers: {
          requests: {
            count: 20
            timeInterval: '00:01:00'
          }
          statusCodes: [
            {
              status: 500
              subStatus: 0
              count: 5
              timeInterval: '00:01:00'
            }
          ]
        }
        actions: {
          actionType: 'Recycle'
          minProcessExecutionTime: '00:01:00'
        }
      }
    }
  }
  tags: tags
}

output appServiceName string = webApp.name
output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output applicationInsightsName string = enableApplicationInsights ? appInsightsName : ''
output applicationInsightsConnectionString string = enableApplicationInsights ? reference(applicationInsights.id, '2020-02-02').ConnectionString : ''
