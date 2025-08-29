param appName string = 'memory-stress-tester'
param environment string = 'dev'
param appServicePlanSku string = 'B1'
param enableApplicationInsights bool = false
param defaultMemoryThresholdMB int = 1024
param maxAllowedMemoryThresholdMB int = 4096
param tags object = {}

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var planName = '${appName}-${environment}-${uniqueSuffix}'
var webAppName = '${appName}-${environment}-${uniqueSuffix}'

// SKU selection logic based on memory requirements
var skuMemoryMap = {
  B1: 1750  // ~1.75 GB
  B2: 3500  // ~3.5 GB  
  B3: 7000  // ~7 GB
  S1: 1750  // ~1.75 GB
  S2: 3500  // ~3.5 GB
  S3: 7000  // ~7 GB
  P1V2: 3500  // ~3.5 GB
  P2V2: 7000  // ~7 GB
  P3V2: 14000 // ~14 GB
}

var selectedSku = contains(skuMemoryMap, appServicePlanSku) && skuMemoryMap[appServicePlanSku] >= maxAllowedMemoryThresholdMB 
  ? appServicePlanSku 
  : maxAllowedMemoryThresholdMB <= 1750 
    ? 'B1' 
    : maxAllowedMemoryThresholdMB <= 3500 
      ? 'B2' 
      : 'B3'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: resourceGroup().location
  tags: tags
  sku: {
    name: selectedSku
  }
  properties: {
    reserved: false
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: '${appName}-${environment}-insights-${uniqueSuffix}'
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
      appSettings: union([
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
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: environment
        }
      ], enableApplicationInsights ? [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: reference(applicationInsights.id).ConnectionString
        }
      ] : [])
    }
  }
}

output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output selectedSku string = selectedSku
output actualMemoryCapacityMB int = skuMemoryMap[selectedSku]
output configuredMaxThresholdMB int = maxAllowedMemoryThresholdMB
output isDriftResolved bool = skuMemoryMap[selectedSku] >= maxAllowedMemoryThresholdMB
output applicationInsightsConnectionString string = enableApplicationInsights ? reference(applicationInsights.id).ConnectionString : 'Not configured'
