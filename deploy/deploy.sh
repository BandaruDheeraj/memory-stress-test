#!/bin/bash

# Memory Stress Tester - Azure Deployment Script (Bash)
# This script deploys the Memory Stress Tester application to Azure App Service using Bicep

set -e  # Exit on any error

# Default values
ENVIRONMENT=""
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
LOCATION="eastus"
DEPLOY_ONLY=false
BUILD_ONLY=false
USE_STAGING=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -e <environment> -g <resource-group> -s <subscription-id> [options]"
    echo ""
    echo "Required parameters:"
    echo "  -e, --environment     Environment (dev|staging|prod)"
    echo "  -g, --resource-group  Resource group name"
    echo "  -s, --subscription    Azure subscription ID"
    echo ""
    echo "Optional parameters:"
    echo "  -l, --location        Azure location (default: eastus)"
    echo "  -d, --deploy-only     Only deploy infrastructure, skip build"
    echo "  -b, --build-only      Only build application, skip deployment"
    echo "  --use-staging         Use staging slot deployment strategy"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev -g rg-memory-tester-dev -s 12345678-1234-1234-1234-123456789012"
    echo "  $0 -e prod -g rg-memory-tester-prod -s 12345678-1234-1234-1234-123456789012 --use-staging"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -d|--deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        -b|--build-only)
            BUILD_ONLY=true
            shift
            ;;
        --use-staging)
            USE_STAGING=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ENVIRONMENT" || -z "$RESOURCE_GROUP" || -z "$SUBSCRIPTION_ID" ]]; then
    echo "Error: Missing required parameters"
    show_usage
    exit 1
fi

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Error: Environment must be dev, staging, or prod"
    exit 1
fi

print_color $GREEN "🚀 Starting Memory Stress Tester Deployment"
print_color $YELLOW "Environment: $ENVIRONMENT"
print_color $YELLOW "Resource Group: $RESOURCE_GROUP"
print_color $YELLOW "Subscription: $SUBSCRIPTION_ID"
print_color $YELLOW "Location: $LOCATION"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_color $RED "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if .NET CLI is installed
if ! command -v dotnet &> /dev/null && [[ "$BUILD_ONLY" == false ]]; then
    print_color $RED "❌ .NET CLI is not installed. Please install .NET 8.0 SDK first."
    exit 1
fi

# Set Azure subscription
print_color $BLUE "📋 Setting Azure subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# Check if resource group exists, create if not
print_color $BLUE "🏗️ Checking resource group..."
if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
    print_color $YELLOW "Creating resource group: $RESOURCE_GROUP"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
fi

APP_SERVICE_NAME=""
APP_SERVICE_URL=""
STAGING_SLOT_URL=""

if [[ "$BUILD_ONLY" == false ]]; then
    # Deploy Bicep template
    print_color $BLUE "☁️ Deploying Azure infrastructure..."
    DEPLOYMENT_NAME="memory-stress-tester-$(date +%Y%m%d-%H%M%S)"
    
    DEPLOYMENT_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "deploy/main.bicep" \
        --parameters "@deploy/parameters.$ENVIRONMENT.json" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output json)

    APP_SERVICE_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.appServiceName.value')
    APP_SERVICE_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.appServiceUrl.value')
    STAGING_SLOT_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.stagingSlotUrl.value // empty')

    print_color $GREEN "✅ Infrastructure deployed successfully!"
    print_color $CYAN "App Service Name: $APP_SERVICE_NAME"
    print_color $CYAN "App Service URL: $APP_SERVICE_URL"
    if [[ -n "$STAGING_SLOT_URL" && "$STAGING_SLOT_URL" != "null" ]]; then
        print_color $CYAN "Staging Slot URL: $STAGING_SLOT_URL"
    fi
fi

if [[ "$DEPLOY_ONLY" == false ]]; then
    # Build the application
    print_color $BLUE "🔨 Building .NET application..."
    dotnet publish -c Release -o "./publish"

    # Create deployment package
    print_color $BLUE "📦 Creating deployment package..."
    rm -f "./app.zip"
    cd "./publish"
    zip -r "../app.zip" .
    cd ".."

    if [[ "$BUILD_ONLY" == false ]]; then
        # Deploy to staging slot first if using staging strategy
        if [[ "$USE_STAGING" == true && "$ENVIRONMENT" != "dev" ]]; then
            print_color $BLUE "🚀 Deploying to staging slot..."
            az webapp deployment source config-zip \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APP_SERVICE_NAME" \
                --slot staging \
                --src "./app.zip"

            print_color $BLUE "🔄 Warming up staging slot..."
            sleep 30

            # Optional: Run health check on staging
            STAGING_HEALTH_URL="https://$APP_SERVICE_NAME-staging.azurewebsites.net/api/memory/status"
            print_color $BLUE "🏥 Checking staging health at: $STAGING_HEALTH_URL"
            
            if curl -f -s "$STAGING_HEALTH_URL" > /dev/null; then
                print_color $GREEN "✅ Staging slot is healthy!"
            else
                print_color $YELLOW "⚠️ Health check failed, but continuing with deployment..."
            fi

            # Swap slots
            print_color $BLUE "🔄 Swapping staging to production..."
            az webapp deployment slot swap \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APP_SERVICE_NAME" \
                --slot staging \
                --target-slot production
        else
            # Deploy directly to production
            print_color $BLUE "🚀 Deploying to production..."
            az webapp deployment source config-zip \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APP_SERVICE_NAME" \
                --src "./app.zip"
        fi

        # Clean up deployment package
        rm -f "./app.zip"
        rm -rf "./publish"
    fi
fi

print_color $GREEN "🎉 Deployment completed successfully!"

if [[ "$DEPLOY_ONLY" == false ]]; then
    echo ""
    print_color $CYAN "🌐 Application URLs:"
    if [[ -n "$APP_SERVICE_URL" && "$APP_SERVICE_URL" != "null" ]]; then
        print_color $NC "Production: $APP_SERVICE_URL"
    fi
    if [[ -n "$STAGING_SLOT_URL" && "$STAGING_SLOT_URL" != "null" && "$ENVIRONMENT" != "dev" ]]; then
        print_color $NC "Staging: $STAGING_SLOT_URL"
    fi
    echo ""
    print_color $YELLOW "📊 To test the memory allocation:"
    print_color $NC "1. Navigate to the application URL"
    print_color $NC "2. Set memory threshold (e.g., 1024 MB)"
    print_color $NC "3. Allocate memory above threshold to trigger 500 errors"
    print_color $NC "4. Use stress test feature for automated testing"
fi

print_color $GREEN "🏁 Script execution completed!"
