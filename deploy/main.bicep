param appName string = 'memory-stress-tester'
param appServicePlanSku string = 'B1'
param appServicePlanCapacity int = 1
param alwaysOn bool = false
param minTlsVersion string = '1.2'

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var planName = '${appName}-${uniqueSuffix}'
var webAppName = '${appName}-${uniqueSuffix}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: resourceGroup().location
  sku: {
    name: appServicePlanSku
    capacity: appServicePlanCapacity
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: resourceGroup().location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      alwaysOn: alwaysOn
      minTlsVersion: minTlsVersion
    }
  }
}

output webAppName string = webApp.name
output appServiceName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
