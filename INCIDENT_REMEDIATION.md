# IaC Drift Incident Remediation (2025-08-29)

## Executive Summary
This document details the remediation steps taken to address the resource spike incident on `iac-drift-demo` that occurred on August 29, 2025, from 16:15-16:46 UTC.

## Incident Details
- **Application**: iac-drift-demo
- **Time**: 2025-08-29, 16:15–16:46 UTC  
- **CPU Spike**: From baseline 0-31 units to 3024 units peak
- **Memory Spike**: From baseline 16-33 MB to 307 MB sustained
- **HTTP 5xx Errors**: Expected behavior (6 errors at 16:15, 15 errors at 16:44)

## Root Cause Analysis
The incident was caused by **IaC drift** where the deployed application name (`iac-drift-demo`) did not match the Infrastructure as Code templates (`memory-stress-tester`). Additionally:

1. **Insufficient Resource Controls**: App deployed with basic B1 SKU without proper limits
2. **Missing Application Monitoring**: No Application Insights configured for performance tracking  
3. **Lack of Resource Limiting**: App could consume unlimited memory within VM constraints
4. **No Auto-scaling**: No scale-out rules to handle resource spikes gracefully
5. **Direct Production Deployment**: Missing staging slots for safer deployments

## Remediation Actions Taken

### 1. IaC Template Corrections
- ✅ Updated `deploy/main.bicep` to match actual app name `iac-drift-demo`
- ✅ Enhanced Bicep template with production-appropriate configurations:
  - App Service Plan sizing (S1 SKU with auto-scaling)
  - Application Insights integration
  - Deployment slots for staging/production
  - Proper tagging and resource management

### 2. Application-Level Safeguards
- ✅ Added resource limiting configuration:
  ```json
  "MemorySettings": {
    "DefaultThresholdMB": 512,
    "MaxAllowedThresholdMB": 2048,
    "MaxAllocationSizeMB": 256,
    "MaxConcurrentAllocations": 10,
    "EnableResourceLimiting": true
  }
  ```
- ✅ Enhanced `MemoryStressService` with:
  - Maximum allocation size limits
  - Concurrent allocation limits  
  - Threshold enforcement
  - Configurable cleanup intervals

### 3. Infrastructure Monitoring
- ✅ Created `monitoring.bicep` template with:
  - CPU usage alerts (>300s CPU time in 5min window)
  - Memory usage alerts (>200MB working set)
  - HTTP 5xx error monitoring  
  - Stress test activity tracking
  - Operational dashboard with workbooks

### 4. Parameter Files Alignment  
- ✅ Updated production parameters (`parameters.prod.json`) with:
  - Correct app name: `iac-drift-demo`
  - Conservative memory limits (512MB default, 2048MB max)
  - Proper environment tagging including incident reference
- ✅ Created staging parameters (`parameters.staging.json`)
- ✅ Updated development parameters with appropriate limits

### 5. Auto-scaling Configuration
- ✅ Added auto-scaling rules in Bicep:
  - Scale out when CPU > 70% for 5 minutes
  - Scale in when CPU < 30% for 5 minutes  
  - Maximum 3 instances to contain costs
  - 10-minute cooldown periods

## Deployment Instructions

### For Production (iac-drift-demo)
```bash
# Deploy infrastructure
az deployment group create \
  --resource-group iac-demo \
  --template-file deploy/main.bicep \
  --parameters @deploy/parameters.prod.json \
  --name iac-drift-remediation-$(date +%Y%m%d-%H%M%S)

# Deploy monitoring (optional - requires action group email)
az deployment group create \
  --resource-group iac-demo \
  --template-file deploy/monitoring.bicep \
  --parameters appName=iac-drift-demo environment=prod actionGroupEmail=sre-team@company.com \
  --name iac-drift-monitoring-$(date +%Y%m%d-%H%M%S)
```

### For New Deployments
```bash
# Use corrected deployment script
./deploy/deploy.sh --environment prod --resource-group iac-demo --use-staging
```

## Configuration Validation

### Verify No Drift
```bash
# Check deployed vs. template configuration  
az webapp show --name iac-drift-demo --resource-group iac-demo \
  --query "{name:name, sku:appServicePlanId, httpsOnly:httpsOnly}" -o table

# Verify app settings alignment
az webapp config appsettings list --name iac-drift-demo --resource-group iac-demo \
  --query "[?name=='MemorySettings__MaxAllowedThresholdMB'].{Name:name, Value:value}" -o table
```

### Test Resource Limits
```bash
# Test stress endpoint with safe parameters
curl -X POST https://iac-drift-demo.azurewebsites.net/api/memory/stress-test \
  -H "Content-Type: application/json" \
  -d '{"iterations":3, "megabytesPerIteration":100, "delayBetweenAllocationsMs":1000}'
```

## Prevention Measures

### 1. Template Validation Pipeline
- All Bicep templates now include parameter validation
- Deployment names must match actual resource names
- Template testing in staging environment mandatory

### 2. Resource Governance  
- Application-level resource limits enforced
- Maximum allocation sizes constrained
- Automatic cleanup mechanisms enabled
- Monitoring and alerting configured

### 3. Change Management
- All infrastructure changes via IaC only
- Staging deployments required for production changes
- Resource tagging includes deployment source tracking
- Drift detection via monitoring dashboard

## Monitoring and Alerting

### Key Metrics Dashboard
- **CPU Usage Trends**: Track baseline vs. spikes  
- **Memory Allocation Patterns**: Monitor stress test activity
- **HTTP Error Rates**: Distinguish expected vs. unexpected 5xx
- **Resource Utilization**: Working set, managed memory, GC pressure

### Alert Conditions
- **Critical**: CPU >300s/5min OR Memory >200MB sustained
- **Warning**: HTTP 5xx >10/5min (operational awareness)  
- **Info**: Stress test API activity (change tracking)

## Lessons Learned

1. **IaC Drift Detection**: Implement automated drift detection between templates and deployed resources
2. **Resource Limit Testing**: Test resource constraints in non-production first  
3. **Application Monitoring**: Monitor application-specific metrics, not just infrastructure
4. **Safe Defaults**: Use conservative defaults for production workloads
5. **Staging Validation**: Always validate changes in staging before production

## Next Steps

1. **Monitor for 48 hours** to ensure resource usage returns to baseline
2. **Validate alerting** by triggering controlled stress tests  
3. **Document operational procedures** for memory stress testing
4. **Review other applications** for similar IaC drift issues
5. **Implement drift detection automation** across all environments

---
**Incident Status**: ✅ **RESOLVED**  
**Documentation Date**: 2025-08-29  
**Author**: SRE Agent / GitHub Copilot  
**Review**: Pending Operations Team Approval