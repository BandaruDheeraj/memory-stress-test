// Monitoring and Alerting for IaC Drift Demo
// This template adds monitoring and alerting to prevent resource spikes

param appName string
param environment string
param actionGroupEmail string = ''
param enableAlerting bool = true

// Get reference to existing resources
resource webApp 'Microsoft.Web/sites@2023-01-01' existing = {
  name: appName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' existing = {
  name: '${appName}-plan-${environment}'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${appName}-insights-${environment}'
}

// Action Group for notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerting && actionGroupEmail != '') {
  name: '${appName}-alerts-${environment}'
  location: 'global'
  properties: {
    groupShortName: 'IaCDrift'
    enabled: true
    emailReceivers: [
      {
        name: 'SRE Team'
        emailAddress: actionGroupEmail
      }
    ]
  }
}

// CPU Alert Rule
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerting) {
  name: '${appName}-cpu-high-${environment}'
  location: 'global'
  properties: {
    description: 'Alert when CPU usage is high for sustained period'
    severity: 2
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPUHigh'
          metricName: 'CpuTime'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 300000 // 5 minutes of CPU time in 5-minute window
          timeAggregation: 'Total'
        }
      ]
    }
    actions: enableAlerting && actionGroupEmail != '' ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// Memory Alert Rule  
resource memoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerting) {
  name: '${appName}-memory-high-${environment}'
  location: 'global'
  properties: {
    description: 'Alert when memory usage spikes above normal baseline'
    severity: 2
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'MemoryHigh'
          metricName: 'MemoryWorkingSet'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 200000000 // 200MB working set
          timeAggregation: 'Average'
        }
      ]
    }
    actions: enableAlerting && actionGroupEmail != '' ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// HTTP 5xx Error Alert
resource httpErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerting) {
  name: '${appName}-http-errors-${environment}'
  location: 'global'
  properties: {
    description: 'Alert when HTTP 5xx errors spike (expected for memory stress app but should be monitored)'
    severity: 3
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxErrors'
          metricName: 'Http5xx'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 10 // More than 10 5xx errors in 5 minutes
          timeAggregation: 'Total'
        }
      ]
    }
    actions: enableAlerting && actionGroupEmail != '' ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// Application Insights Alert for Memory Stress Events
resource appInsightsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerting) {
  name: '${appName}-stress-test-alert-${environment}'
  location: 'global'
  properties: {
    description: 'Alert when stress tests are running - for operational awareness'
    severity: 4
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'StressTestActivity'
          metricName: 'requests/count'
          dimensions: [
            {
              name: 'request/name'
              operator: 'Include'
              values: ['POST /api/memory/stress-test']
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    actions: enableAlerting && actionGroupEmail != '' ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// Workbook for monitoring dashboard
resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid('${appName}-monitoring-${environment}')
  location: resourceGroup().location
  kind: 'shared'
  properties: {
    displayName: '${appName} Memory Stress Monitoring - ${environment}'
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# IaC Drift Demo - Memory Stress Monitoring\\n\\nThis dashboard monitors the memory stress testing application to detect resource spikes and operational issues.\\n\\n**Incident Context**: This dashboard was created following the 2025-08-29 incident where resource spikes (CPU: 3024 units, Memory: 307MB) were observed."
      },
      "name": "title"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests\\n| where timestamp > ago(1h)\\n| where name contains \"memory\"\\n| summarize Count = count() by name, bin(timestamp, 5m)\\n| render timechart",
        "size": 0,
        "title": "Memory API Requests (Last Hour)",
        "queryType": 0,
        "resourceType": "microsoft.insights/components"
      },
      "name": "apiRequests"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "performanceCounters\\n| where timestamp > ago(1h)\\n| where category == \"Memory\" or category == \"Processor\"\\n| summarize avg(value) by category, bin(timestamp, 5m)\\n| render timechart",
        "size": 0,
        "title": "Resource Usage Trends",
        "queryType": 0,
        "resourceType": "microsoft.insights/components"
      },
      "name": "resourceUsage"
    }
  ],
  "isLocked": false,
  "fallbackResourceIds": ["${appInsights.id}"]
}
'''
  }
}

outputs {
  actionGroupId: enableAlerting && actionGroupEmail != '' ? actionGroup.id : ''
  workbookId: workbook.id
}