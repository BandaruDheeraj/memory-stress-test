# IaC Drift Resolution: Memory Allocation Thresholds

## Overview
This document describes the resolution of Infrastructure-as-Code (IaC) drift between Azure infrastructure provisioning and application memory configuration.

## Problem Statement
The original Bicep template provisioned an App Service Plan with insufficient memory capacity compared to the application's configured memory allocation limits:

- **Infrastructure**: B1 SKU (~1.75 GB / 1792 MB RAM)
- **Application Config**: Max threshold up to 4096 MB
- **Result**: Memory stress tests could exhaust infrastructure resources, causing unplanned downtime

## Solution Overview
The drift has been resolved by implementing dynamic SKU selection and environment-specific configuration alignment:

### 1. Dynamic SKU Selection
The Bicep template now automatically selects appropriate App Service Plan SKUs based on memory requirements:

| Memory Requirement | Selected SKU | Actual Capacity |
|-------------------|-------------|-----------------|
| ≤ 1750 MB        | B1          | ~1.75 GB       |
| ≤ 3500 MB        | B2          | ~3.5 GB        |
| > 3500 MB        | B3          | ~7 GB          |

### 2. Environment-Specific Configuration
Each environment now has properly aligned memory configurations:

- **Development**: 1024 MB max (B1 SKU)
- **Staging**: 2048 MB max (B2 SKU) 
- **Production**: 4096 MB max (B3 SKU)

### 3. Infrastructure Validation
The deployment now outputs validation metrics:
- `isDriftResolved`: Boolean indicating if infrastructure >= application limits
- `actualMemoryCapacityMB`: Real infrastructure memory capacity
- `selectedSku`: Automatically selected SKU based on requirements

## Key Changes Made

### Bicep Template (`main.bicep`)
- Added memory threshold parameters
- Implemented SKU selection logic
- Configured application settings from infrastructure
- Added drift validation outputs

### Parameter Files
- `parameters.dev.json`: Conservative memory limits for development
- `parameters.staging.json`: Mid-tier configuration for staging
- `parameters.prod.json`: Updated to use B3 SKU for production capacity

### Deployment Script (`deploy.sh`)
- Enhanced output to show drift resolution status
- Display infrastructure capacity vs application limits
- Provide guidance based on actual deployed capacity

## Usage

### Deploy with Automatic SKU Selection
```bash
# Development environment (will use B1)
./deploy.sh -e dev -g my-rg -s my-subscription

# Production environment (will use B3)  
./deploy.sh -e prod -g my-rg -s my-subscription
```

### Override SKU (Advanced)
```bash
# Force specific SKU with validation
az deployment group create \
  --resource-group my-rg \
  --template-file main.bicep \
  --parameters @parameters.prod.json \
  --parameters appServicePlanSku=P1V2
```

## Monitoring Alignment
After deployment, verify alignment:
1. Check deployment outputs for `isDriftResolved: true`
2. Test memory allocations within reported capacity limits
3. Monitor for HTTP 500 errors during stress testing

## Future Considerations
- Consider implementing auto-scaling rules based on memory usage
- Add monitoring alerts when memory usage approaches infrastructure limits
- Evaluate container-based deployments for more granular resource control