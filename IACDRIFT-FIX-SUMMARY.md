# IaC Drift Resolution - Memory Stress Tester

## Issue Summary
Fixed IaC drift between Bicep template and parameter files that caused the production App Service Plan to be manually scaled from B1 to S1 during a Sev0 incident.

## Root Cause
The `deploy/main.bicep` template had hardcoded values that ignored parameters specified in the parameter files:
- SKU was hardcoded as 'B1' instead of using the `appServicePlanSku` parameter
- Missing parameters that existed in parameter files but not in the template
- No Application Insights integration despite being configured in parameter files

## Changes Made

### 1. Updated main.bicep
- ✅ Added missing parameters: `appServicePlanSku`, `environment`, `enableApplicationInsights`, `defaultMemoryThresholdMB`, `maxAllowedMemoryThresholdMB`, `tags`
- ✅ Changed SKU configuration to use parameter: `sku: { name: appServicePlanSku }`
- ✅ Added conditional Application Insights resource
- ✅ Added application settings configuration for memory thresholds
- ✅ Added proper tagging support
- ✅ Enhanced outputs to include more deployment information

### 2. Updated parameters.dev.json
- ✅ Added all required parameters with appropriate dev environment values
- ✅ Set SKU to 'B1' for development
- ✅ Disabled Application Insights for dev environment
- ✅ Set lower memory thresholds for development

### 3. Created parameters.staging.json
- ✅ Added staging environment parameter file
- ✅ Set SKU to 'S1' for staging (matching production requirements)
- ✅ Enabled Application Insights for staging
- ✅ Set production-like memory thresholds

### 4. Verified parameters.prod.json
- ✅ Confirmed production parameters are correct with S1 SKU
- ✅ Application Insights enabled for production monitoring
- ✅ Production memory thresholds configured

## Configuration by Environment

| Parameter | Dev | Staging | Prod |
|-----------|-----|---------|------|
| SKU | B1 | S1 | S1 |
| App Insights | Disabled | Enabled | Enabled |
| Memory Threshold | 512 MB | 1024 MB | 1024 MB |
| Max Memory | 2048 MB | 4096 MB | 4096 MB |

## Validation
- ✅ Bicep template compiles successfully
- ✅ All parameter files validated
- ✅ Template now uses all parameters correctly
- ✅ No hardcoded values that could cause drift

## Impact
This fixes ensures that:
1. Production deployments will use S1 SKU as intended, preventing future manual scaling
2. Staging environment will match production configuration
3. Development environment remains cost-effective with B1 SKU
4. Application Insights is properly configured for monitoring
5. Memory settings are properly injected as environment variables

## Testing Required
Before deploying to production:
1. Deploy to dev environment first to validate changes
2. Verify application settings are correctly applied
3. Test that memory thresholds work as configured
4. Confirm Application Insights integration (staging/prod)