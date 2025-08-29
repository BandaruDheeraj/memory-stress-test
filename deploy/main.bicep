// Parameters
param appName string = 'iac-drift-demo'
param environment string = 'prod'
param appServicePlanSku string = 'S1'
param enableApplicationInsights bool = true
param defaultMemoryThresholdMB int = 1024
param maxAllowedMemoryThresholdMB int = 4096
param tags object = {}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var planName = '${appName}-plan-${environment}'
var webAppName = appName
var stagingSlotName = 'staging'
var appInsightsName = '${appName}-insights-${environment}'

// App Service Plan with appropriate sizing for production workloads
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: resourceGroup().location
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'S1' ? 'Standard' : 'Basic'
    capacity: 1
  }
  properties: {
    reserved: false
  }
  tags: tags
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: resourceGroup().location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
  tags: tags
}

// Web App with proper configuration
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: resourceGroup().location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__CleanupIntervalSeconds'
          value: '30'
        }
      ]
      alwaysOn: true
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
    }
    httpsOnly: true
  }
  tags: tags
}

// Staging slot for blue-green deployments
resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = if (environment != 'dev') {
  name: stagingSlotName
  parent: webApp
  location: resourceGroup().location
  properties: {
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
        {
          name: 'MemorySettings__DefaultThresholdMB'
          value: string(defaultMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__MaxAllowedThresholdMB'
          value: string(maxAllowedMemoryThresholdMB)
        }
        {
          name: 'MemorySettings__CleanupIntervalSeconds'
          value: '30'
        }
      ]
      alwaysOn: true
    }
  }
  tags: tags
}

// Auto-scaling rules to handle resource spikes
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (appServicePlanSku != 'B1') {
  name: '${appName}-autoscale-${environment}'
  location: resourceGroup().location
  properties: {
    name: '${appName}-autoscale-${environment}'
    targetResourceUri: appServicePlan.id
    enabled: true
    profiles: [
      {
        name: 'Default'
        capacity: {
          minimum: '1'
          maximum: '3'
          default: '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
  tags: tags
}

// Outputs
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output stagingSlotUrl string = environment != 'dev' ? 'https://${webApp.name}-${stagingSlotName}.azurewebsites.net' : ''
output appServiceName string = webApp.name
output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output applicationInsightsName string = enableApplicationInsights ? appInsights.name : ''
output applicationInsightsConnectionString string = enableApplicationInsights ? appInsights.properties.ConnectionString : ''
