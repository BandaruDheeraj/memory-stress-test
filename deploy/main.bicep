// Basic Bicep template for Memory Stress Tester
// Parameters
param appName string = 'memory-stress-tester'
param appServicePlanSku string = 'B1'
param enableApplicationInsights bool = false
param defaultMemoryThresholdMB int = 1024
param maxAllowedMemoryThresholdMB int = 4096
param tags object = {}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var planName = '${appName}-${uniqueSuffix}'
var webAppName = '${appName}-${uniqueSuffix}'
var appInsightsName = '${appName}-insights-${uniqueSuffix}'

// App Service Plan with configurable SKU
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: resourceGroup().location
  sku: {
    name: appServicePlanSku
  }
  properties: {
    // Enable auto-scaling for Standard and Premium SKUs
    targetWorkerCount: appServicePlanSku == 'B1' || appServicePlanSku == 'B2' || appServicePlanSku == 'B3' ? 1 : 2
  }
  tags: tags
}

// Application Insights (conditional deployment)
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: resourceGroup().location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
  tags: tags
}

// Web App without Application Insights
resource webAppBasic 'Microsoft.Web/sites@2023-01-01' = if (!enableApplicationInsights) {
  name: webAppName
  location: resourceGroup().location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: appServicePlanSku != 'B1' && appServicePlanSku != 'B2' && appServicePlanSku != 'B3' ? true : false
      healthCheckPath: '/api/memory/status'
      appSettings: [
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
      ]
    }
  }
  tags: tags
}

// Web App with Application Insights
resource webAppWithInsights 'Microsoft.Web/sites@2023-01-01' = if (enableApplicationInsights) {
  name: webAppName
  location: resourceGroup().location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: appServicePlanSku != 'B1' && appServicePlanSku != 'B2' && appServicePlanSku != 'B3' ? true : false
      healthCheckPath: '/api/memory/status'
      appSettings: [
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
    }
  }
  tags: tags
  dependsOn: [applicationInsights]
}

// Auto-heal configuration for non-Basic SKUs
resource webAppConfigBasic 'Microsoft.Web/sites/config@2023-01-01' = if (!enableApplicationInsights && appServicePlanSku != 'B1' && appServicePlanSku != 'B2' && appServicePlanSku != 'B3') {
  name: 'web'
  parent: webAppBasic
  properties: {
    autoHealEnabled: true
    autoHealRules: {
      triggers: {
        requests: {
          count: 100
          timeInterval: '00:01:00'
        }
        slowRequests: {
          count: 10
          timeInterval: '00:01:00'
          timeTaken: '00:01:00'
        }
        statusCodes: [
          {
            status: 500
            subStatus: 0
            count: 10
            timeInterval: '00:05:00'
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

// Auto-heal configuration for non-Basic SKUs with Insights
resource webAppConfigWithInsights 'Microsoft.Web/sites/config@2023-01-01' = if (enableApplicationInsights && appServicePlanSku != 'B1' && appServicePlanSku != 'B2' && appServicePlanSku != 'B3') {
  name: 'web'
  parent: webAppWithInsights
  properties: {
    autoHealEnabled: true
    autoHealRules: {
      triggers: {
        requests: {
          count: 100
          timeInterval: '00:01:00'
        }
        slowRequests: {
          count: 10
          timeInterval: '00:01:00'
          timeTaken: '00:01:00'
        }
        statusCodes: [
          {
            status: 500
            subStatus: 0
            count: 10
            timeInterval: '00:05:00'
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

// Outputs
output appServiceName string = enableApplicationInsights ? webAppWithInsights.name : webAppBasic.name
output webAppName string = enableApplicationInsights ? webAppWithInsights.name : webAppBasic.name
output webAppUrl string = enableApplicationInsights ? 'https://${webAppWithInsights.properties.defaultHostName}' : 'https://${webAppBasic.properties.defaultHostName}'
output appServicePlanName string = appServicePlan.name
output appServicePlanSku string = appServicePlan.sku.name
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
