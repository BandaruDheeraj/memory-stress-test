# Infrastructure as Code (IaC) Configuration

## Overview
This document describes the Azure infrastructure configuration for the Memory Stress Tester application, addressing the configuration drift incident reported on 2025-08-29.

## Issue Resolution
**Incident**: Severe CPU Spike & Memory Drop on iac-drift-demo
- **Root Cause**: Configuration drift between deployed Azure resource and IaC baseline
- **Resolution**: Updated Bicep template to properly use parameter files for environment-specific configurations

## Infrastructure Components

### App Service Plan
- **SKU Configuration**: Environment-specific (B1 for dev, S1 for staging/prod)
- **Auto-scaling**: Configured based on SKU (Basic: 1 worker, Standard+: 2 workers)
- **Performance**: Standard SKU provides better CPU and memory allocation to handle load spikes

### Web Application
- **Runtime**: .NET 8.0
- **Health Check**: `/api/memory/status` endpoint for monitoring
- **Always On**: Enabled for non-Basic SKUs to prevent cold starts
- **Auto-heal**: Configured for Standard+ SKUs with triggers for:
  - High request count (100 requests/minute)
  - Slow requests (10 requests taking >1 minute)
  - HTTP 500 errors (10 errors in 5 minutes)

### Application Insights (Optional)
- **Conditional Deployment**: Only enabled for staging and production environments
- **Integration**: Automatic configuration with connection strings and instrumentation keys
- **Monitoring**: Provides comprehensive application performance monitoring

## Environment Configurations

### Development (`parameters.dev.json`)
```json
{
  "appServicePlanSku": "B1",
  "enableApplicationInsights": false,
  "defaultMemoryThresholdMB": 512,
  "maxAllowedMemoryThresholdMB": 2048
}
```

### Staging (`parameters.staging.json`)
```json
{
  "appServicePlanSku": "S1",
  "enableApplicationInsights": true,
  "defaultMemoryThresholdMB": 1024,
  "maxAllowedMemoryThresholdMB": 3072
}
```

### Production (`parameters.prod.json`)
```json
{
  "appServicePlanSku": "S1",
  "enableApplicationInsights": true,
  "defaultMemoryThresholdMB": 1024,
  "maxAllowedMemoryThresholdMB": 4096
}
```

## Configuration Settings
The application automatically receives memory threshold configurations through app settings:
- `MemorySettings__DefaultThresholdMB`: Default memory allocation threshold
- `MemorySettings__MaxAllowedThresholdMB`: Maximum allowed threshold for safety

## Deployment
Use the provided deployment scripts with environment-specific parameters:

**Bash:**
```bash
./deploy/deploy.sh -e prod -g rg-memory-tester-prod -s <subscription-id>
```

**PowerShell:**
```powershell
.\deploy\deploy.ps1 -Environment prod -ResourceGroupName rg-memory-tester-prod -SubscriptionId <subscription-id>
```

## Monitoring and Alerts
With the updated configuration:
1. **Application Insights** (staging/prod) provides comprehensive monitoring
2. **Health checks** ensure application responsiveness
3. **Auto-heal** automatically recovers from error conditions
4. **Proper SKU sizing** prevents resource exhaustion that caused the original incident

## Drift Prevention
To prevent future configuration drift:
1. Always use the parameter files for environment-specific settings
2. Deploy using the provided scripts rather than manual Azure portal changes
3. Regularly compare deployed resources against IaC templates
4. Monitor Application Insights for performance anomalies

## Troubleshooting
If experiencing similar CPU/memory issues:
1. Check if deployed SKU matches parameter file configuration
2. Verify Application Insights is enabled for monitoring
3. Confirm auto-heal settings are properly configured
4. Review health check endpoint functionality