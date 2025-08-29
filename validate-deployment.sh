#!/bin/bash

# IaC Drift Detection and Validation Script
# Purpose: Validate deployed resources match IaC templates
# Author: SRE Team / GitHub Copilot
# Created: 2025-08-29 (Post-incident remediation)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
APP_NAME=""
ENVIRONMENT=""
BICEP_FILE="deploy/main.bicep"
PARAMETERS_FILE=""
VALIDATE_ONLY=false
FIX_DRIFT=false

print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_header() {
    echo ""
    print_color $BLUE "================================================="
    print_color $BLUE "$1"
    print_color $BLUE "================================================="
}

show_help() {
    echo "IaC Drift Detection Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group RG    Azure resource group name"
    echo "  -a, --app-name NAME        Application name"
    echo "  -e, --environment ENV      Environment (dev/staging/prod)"
    echo "  -v, --validate-only        Only validate, don't report drift"
    echo "  -f, --fix-drift           Attempt to fix detected drift"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -g iac-demo -a iac-drift-demo -e prod"
    echo "  $0 -g iac-demo -a iac-drift-demo -e prod --fix-drift"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -a|--app-name)
            APP_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        -f|--fix-drift)
            FIX_DRIFT=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" || -z "$APP_NAME" || -z "$ENVIRONMENT" ]]; then
    print_color $RED "❌ Missing required parameters"
    show_help
    exit 1
fi

# Set parameters file based on environment
PARAMETERS_FILE="deploy/parameters.${ENVIRONMENT}.json"

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    print_color $RED "❌ Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

print_header "IaC Drift Detection - $APP_NAME ($ENVIRONMENT)"

print_color $YELLOW "Configuration:"
print_color $NC "  Resource Group: $RESOURCE_GROUP"
print_color $NC "  App Name: $APP_NAME"
print_color $NC "  Environment: $ENVIRONMENT"
print_color $NC "  Parameters File: $PARAMETERS_FILE"
print_color $NC "  Bicep Template: $BICEP_FILE"

# Check if Azure CLI is logged in
if ! az account show &> /dev/null; then
    print_color $RED "❌ Not logged in to Azure CLI"
    exit 1
fi

# Check if resource group exists
print_color $BLUE "🔍 Checking resource group existence..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_color $RED "❌ Resource group $RESOURCE_GROUP does not exist"
    exit 1
fi

# Get current deployed resources
print_color $BLUE "📋 Getting current deployed resources..."
DEPLOYED_APP=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" 2>/dev/null || echo "null")

if [[ "$DEPLOYED_APP" == "null" ]]; then
    print_color $RED "❌ App Service $APP_NAME not found in resource group $RESOURCE_GROUP"
    exit 1
fi

# Extract current configuration
CURRENT_SKU=$(echo "$DEPLOYED_APP" | jq -r '.appServicePlanId' | xargs -I {} az appservice plan show --ids {} --query 'sku.name' -o tsv)
CURRENT_HTTPS_ONLY=$(echo "$DEPLOYED_APP" | jq -r '.httpsOnly')
CURRENT_DOTNET_VERSION=$(echo "$DEPLOYED_APP" | jq -r '.siteConfig.netFrameworkVersion // "null"')

# Get expected configuration from parameters
print_color $BLUE "📖 Reading expected configuration from IaC templates..."
EXPECTED_SKU=$(jq -r '.parameters.appServicePlanSku.value // "S1"' "$PARAMETERS_FILE")
EXPECTED_APP_NAME=$(jq -r '.parameters.appName.value' "$PARAMETERS_FILE")
EXPECTED_ENV=$(jq -r '.parameters.environment.value' "$PARAMETERS_FILE")

print_color $BLUE "📊 Configuration comparison:"

# Check app name drift
DRIFT_DETECTED=false
if [[ "$APP_NAME" != "$EXPECTED_APP_NAME" ]]; then
    print_color $RED "  ❌ App Name Drift: Deployed='$APP_NAME' vs Expected='$EXPECTED_APP_NAME'"
    DRIFT_DETECTED=true
else
    print_color $GREEN "  ✅ App Name: $APP_NAME"
fi

# Check SKU drift  
if [[ "$CURRENT_SKU" != "$EXPECTED_SKU" ]]; then
    print_color $RED "  ❌ SKU Drift: Deployed='$CURRENT_SKU' vs Expected='$EXPECTED_SKU'"
    DRIFT_DETECTED=true
else
    print_color $GREEN "  ✅ SKU: $CURRENT_SKU"
fi

# Check HTTPS configuration
if [[ "$CURRENT_HTTPS_ONLY" != "true" ]]; then
    print_color $RED "  ❌ HTTPS Drift: Deployed='$CURRENT_HTTPS_ONLY' vs Expected='true'"
    DRIFT_DETECTED=true
else
    print_color $GREEN "  ✅ HTTPS Only: $CURRENT_HTTPS_ONLY"
fi

# Check .NET version
if [[ "$CURRENT_DOTNET_VERSION" != "v8.0" && "$CURRENT_DOTNET_VERSION" != "null" ]]; then
    print_color $YELLOW "  ⚠️  .NET Version: Deployed='$CURRENT_DOTNET_VERSION' vs Expected='v8.0'"
fi

# Check app settings alignment
print_color $BLUE "🔧 Checking application settings alignment..."
APP_SETTINGS=$(az webapp config appsettings list --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'MemorySettings')]" -o json)

EXPECTED_DEFAULT_THRESHOLD=$(jq -r '.parameters.defaultMemoryThresholdMB.value // "512"' "$PARAMETERS_FILE")
EXPECTED_MAX_THRESHOLD=$(jq -r '.parameters.maxAllowedMemoryThresholdMB.value // "2048"' "$PARAMETERS_FILE")

CURRENT_DEFAULT_THRESHOLD=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="MemorySettings__DefaultThresholdMB") | .value // "null"')
CURRENT_MAX_THRESHOLD=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="MemorySettings__MaxAllowedThresholdMB") | .value // "null"')

if [[ "$CURRENT_DEFAULT_THRESHOLD" != "$EXPECTED_DEFAULT_THRESHOLD" ]]; then
    print_color $RED "  ❌ Default Threshold Drift: Deployed='$CURRENT_DEFAULT_THRESHOLD' vs Expected='$EXPECTED_DEFAULT_THRESHOLD'"
    DRIFT_DETECTED=true
else
    print_color $GREEN "  ✅ Default Threshold: $CURRENT_DEFAULT_THRESHOLD MB"
fi

if [[ "$CURRENT_MAX_THRESHOLD" != "$EXPECTED_MAX_THRESHOLD" ]]; then
    print_color $RED "  ❌ Max Threshold Drift: Deployed='$CURRENT_MAX_THRESHOLD' vs Expected='$EXPECTED_MAX_THRESHOLD'"
    DRIFT_DETECTED=true
else
    print_color $GREEN "  ✅ Max Threshold: $CURRENT_MAX_THRESHOLD MB"
fi

# Check for Application Insights
print_color $BLUE "📈 Checking Application Insights configuration..."
APP_INSIGHTS_CONN_STRING=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="APPLICATIONINSIGHTS_CONNECTION_STRING") | .value // "null"')

if [[ "$APP_INSIGHTS_CONN_STRING" == "null" || "$APP_INSIGHTS_CONN_STRING" == "" ]]; then
    print_color $YELLOW "  ⚠️  Application Insights: Not configured (monitoring limited)"
else
    print_color $GREEN "  ✅ Application Insights: Configured"
fi

# Summary
print_header "Drift Detection Summary"

if [[ "$DRIFT_DETECTED" == true ]]; then
    print_color $RED "❌ IaC DRIFT DETECTED!"
    print_color $YELLOW "Recommendation: Review and apply corrected IaC templates"
    
    if [[ "$FIX_DRIFT" == true ]]; then
        print_color $BLUE "🔧 Attempting to fix drift..."
        
        DEPLOYMENT_NAME="drift-fix-$(date +%Y%m%d-%H%M%S)"
        print_color $BLUE "Deploying corrected template: $DEPLOYMENT_NAME"
        
        az deployment group create \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$BICEP_FILE" \
            --parameters "@$PARAMETERS_FILE" \
            --name "$DEPLOYMENT_NAME" \
            --only-show-errors
        
        if [[ $? -eq 0 ]]; then
            print_color $GREEN "✅ Drift correction deployment completed successfully"
            print_color $BLUE "Re-running drift detection to verify..."
            sleep 10
            exec "$0" -g "$RESOURCE_GROUP" -a "$APP_NAME" -e "$ENVIRONMENT" --validate-only
        else
            print_color $RED "❌ Drift correction deployment failed"
            exit 1
        fi
    else
        print_color $YELLOW "To fix drift, run: $0 -g $RESOURCE_GROUP -a $APP_NAME -e $ENVIRONMENT --fix-drift"
    fi
    
    exit 1
else
    print_color $GREEN "✅ NO DRIFT DETECTED"
    print_color $GREEN "Infrastructure matches IaC templates"
fi

# Performance recommendations based on incident
print_header "Performance & Security Recommendations"

# Check current resource usage
print_color $BLUE "📊 Current resource metrics (last 1 hour)..."

# Note: This would require more complex metrics querying in a real environment
print_color $YELLOW "Manual verification recommended:"
print_color $NC "1. Check CPU/Memory usage in Azure Portal"
print_color $NC "2. Verify auto-scaling rules are active"  
print_color $NC "3. Test stress endpoints with safe parameters"
print_color $NC "4. Validate monitoring alerts are configured"

print_color $GREEN "🎉 IaC drift detection completed successfully!"

if [[ "$VALIDATE_ONLY" == false ]]; then
    # Generate drift report
    REPORT_FILE="drift-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "appName": "$APP_NAME",
  "resourceGroup": "$RESOURCE_GROUP", 
  "environment": "$ENVIRONMENT",
  "driftDetected": $DRIFT_DETECTED,
  "currentConfiguration": {
    "sku": "$CURRENT_SKU",
    "httpsOnly": $CURRENT_HTTPS_ONLY,
    "dotnetVersion": "$CURRENT_DOTNET_VERSION",
    "defaultThresholdMB": "$CURRENT_DEFAULT_THRESHOLD",
    "maxThresholdMB": "$CURRENT_MAX_THRESHOLD",
    "applicationInsights": "$APP_INSIGHTS_CONN_STRING"
  },
  "expectedConfiguration": {
    "appName": "$EXPECTED_APP_NAME",
    "sku": "$EXPECTED_SKU", 
    "environment": "$EXPECTED_ENV",
    "defaultThresholdMB": "$EXPECTED_DEFAULT_THRESHOLD",
    "maxThresholdMB": "$EXPECTED_MAX_THRESHOLD"
  }
}
EOF

    print_color $BLUE "📄 Drift report saved: $REPORT_FILE"
fi