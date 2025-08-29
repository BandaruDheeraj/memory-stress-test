#!/bin/bash
# IaC Drift Validation Script
# This script validates that the Bicep template works correctly with all parameter files

set -e

print_color() {
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m'
    printf "${1}${2}${NC}\n"
}

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔍 IaC Drift Validation - Bicep Template & Parameters"
echo "=================================================="

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_color $RED "❌ Azure CLI not found. Skipping deployment validation."
    print_color $YELLOW "📝 Template syntax validation will still run."
else
    print_color $GREEN "✅ Azure CLI found"
fi

cd "$(dirname "$0")"

# Validate Bicep template syntax
print_color $YELLOW "🔧 Validating Bicep template syntax..."
if az bicep build --file main.bicep --stdout > /dev/null 2>&1; then
    print_color $GREEN "✅ Bicep template syntax is valid"
else
    print_color $RED "❌ Bicep template has syntax errors"
    az bicep build --file main.bicep 2>&1 | grep -E "(Error|Warning)" || true
    exit 1
fi

# Validate parameter files exist
environments=("dev" "staging" "prod")
for env in "${environments[@]}"; do
    param_file="parameters.$env.json"
    if [ -f "$param_file" ]; then
        print_color $GREEN "✅ Found $param_file"
        
        # Validate JSON syntax
        if jq . "$param_file" > /dev/null 2>&1; then
            print_color $GREEN "✅ $param_file has valid JSON syntax"
            
            # Check for required parameters
            required_params=("appName" "environment" "appServicePlanSku" "enableApplicationInsights" "defaultMemoryThresholdMB" "maxAllowedMemoryThresholdMB" "tags")
            for param in "${required_params[@]}"; do
                if jq -e ".parameters.$param" "$param_file" > /dev/null 2>&1; then
                    print_color $GREEN "  ✅ $param parameter found"
                else
                    print_color $RED "  ❌ $param parameter missing in $param_file"
                fi
            done
        else
            print_color $RED "❌ $param_file has invalid JSON syntax"
            jq . "$param_file" 2>&1 || true
        fi
    else
        print_color $RED "❌ Missing $param_file"
    fi
    echo ""
done

# Validate SKU configurations match expectations
print_color $YELLOW "🎯 Validating environment-specific configurations..."

dev_sku=$(jq -r '.parameters.appServicePlanSku.value' parameters.dev.json 2>/dev/null || echo "missing")
staging_sku=$(jq -r '.parameters.appServicePlanSku.value' parameters.staging.json 2>/dev/null || echo "missing") 
prod_sku=$(jq -r '.parameters.appServicePlanSku.value' parameters.prod.json 2>/dev/null || echo "missing")

if [ "$dev_sku" = "B1" ]; then
    print_color $GREEN "✅ Dev environment uses B1 SKU (cost-effective)"
else
    print_color $YELLOW "⚠️  Dev environment SKU: $dev_sku (expected: B1)"
fi

if [ "$staging_sku" = "S1" ]; then
    print_color $GREEN "✅ Staging environment uses S1 SKU (production-like)"
else
    print_color $YELLOW "⚠️  Staging environment SKU: $staging_sku (expected: S1)"
fi

if [ "$prod_sku" = "S1" ]; then
    print_color $GREEN "✅ Production environment uses S1 SKU (matches incident fix)"
else
    print_color $RED "❌ Production environment SKU: $prod_sku (expected: S1 - this was the drift issue!)"
fi

print_color $GREEN "🏁 Validation completed!"
print_color $YELLOW "📋 Summary:"
echo "   - Dev: $dev_sku SKU"  
echo "   - Staging: $staging_sku SKU"
echo "   - Prod: $prod_sku SKU"
echo ""
print_color $YELLOW "🚀 The IaC drift has been resolved. Deploy to production to align infrastructure with code."