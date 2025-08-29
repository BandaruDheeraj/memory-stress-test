# Memory Stress Tester - Azure Deployment Script
# This script deploys the Memory Stress Tester application to Azure App Service using Bicep

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory = $false)]
    [switch]$DeployOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$BuildOnly,
    
    [Parameter(Mandatory = $false)]
    [switch]$UseStaging
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Memory Stress Tester Deployment" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow

try {
    # Set Azure subscription
    Write-Host "📋 Setting Azure subscription..." -ForegroundColor Blue
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription" }

    # Check if resource group exists, create if not
    Write-Host "🏗️ Checking resource group..." -ForegroundColor Blue
    $rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
    if (-not $rgExists) {
        Write-Host "Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
        az group create --name $ResourceGroupName --location $Location
        if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group" }
    }

    if (-not $BuildOnly) {
        # Deploy Bicep template
        Write-Host "☁️ Deploying Azure infrastructure..." -ForegroundColor Blue
        $deploymentName = "memory-stress-tester-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        $deploymentResult = az deployment group create `
            --resource-group $ResourceGroupName `
            --template-file "deploy/main.bicep" `
            --parameters "@deploy/parameters.$Environment.json" `
            --name $deploymentName `
            --query "properties.outputs" `
            --output json | ConvertFrom-Json

        if ($LASTEXITCODE -ne 0) { throw "Failed to deploy infrastructure" }

        $appServiceName = $deploymentResult.appServiceName.value
        $appServiceUrl = $deploymentResult.webAppUrl.value
        $appServicePlanName = $deploymentResult.appServicePlanName.value
        $appServicePlanSku = $deploymentResult.appServicePlanSku.value
        $appInsightsName = $deploymentResult.applicationInsightsName.value

        Write-Host "✅ Infrastructure deployed successfully!" -ForegroundColor Green
        Write-Host "App Service Name: $appServiceName" -ForegroundColor Cyan
        Write-Host "App Service URL: $appServiceUrl" -ForegroundColor Cyan
        if ($appServicePlanName) {
            Write-Host "App Service Plan: $appServicePlanName ($appServicePlanSku)" -ForegroundColor Cyan
        }
        if ($appInsightsName) {
            Write-Host "Application Insights: $appInsightsName" -ForegroundColor Cyan
        }
    }

    if (-not $DeployOnly) {
        # Build the application
        Write-Host "🔨 Building .NET application..." -ForegroundColor Blue
        dotnet publish -c Release -o "./publish"
        if ($LASTEXITCODE -ne 0) { throw "Failed to build application" }

        # Create deployment package
        Write-Host "📦 Creating deployment package..." -ForegroundColor Blue
        if (Test-Path "./app.zip") { Remove-Item "./app.zip" -Force }
        Compress-Archive -Path "./publish/*" -DestinationPath "./app.zip" -Force

        if (-not $BuildOnly) {
            # Get app service name from deployment output or construct it
            if (-not $appServiceName) {
                $uniqueSuffix = (Get-Random -Minimum 100000 -Maximum 999999)
                $appServiceName = "memory-stress-tester-app-$Environment-$uniqueSuffix"
                Write-Warning "Using constructed app service name: $appServiceName"
            }

            # Deploy to staging slot first if using staging strategy
            if ($UseStaging -and $Environment -ne 'dev') {
                Write-Host "🚀 Deploying to staging slot..." -ForegroundColor Blue
                az webapp deployment source config-zip `
                    --resource-group $ResourceGroupName `
                    --name $appServiceName `
                    --slot staging `
                    --src "./app.zip"
                
                if ($LASTEXITCODE -ne 0) { throw "Failed to deploy to staging slot" }

                Write-Host "🔄 Warming up staging slot..." -ForegroundColor Blue
                Start-Sleep -Seconds 30

                # Optional: Run health check on staging
                $stagingHealthUrl = "https://$appServiceName-staging.azurewebsites.net/api/memory/status"
                Write-Host "🏥 Checking staging health at: $stagingHealthUrl" -ForegroundColor Blue
                
                try {
                    $response = Invoke-RestMethod -Uri $stagingHealthUrl -Method Get -TimeoutSec 30
                    Write-Host "✅ Staging slot is healthy!" -ForegroundColor Green
                } catch {
                    Write-Warning "Health check failed, but continuing with deployment..."
                }

                # Swap slots
                Write-Host "🔄 Swapping staging to production..." -ForegroundColor Blue
                az webapp deployment slot swap `
                    --resource-group $ResourceGroupName `
                    --name $appServiceName `
                    --slot staging `
                    --target-slot production

                if ($LASTEXITCODE -ne 0) { throw "Failed to swap slots" }
            } else {
                # Deploy directly to production
                Write-Host "🚀 Deploying to production..." -ForegroundColor Blue
                az webapp deployment source config-zip `
                    --resource-group $ResourceGroupName `
                    --name $appServiceName `
                    --src "./app.zip"
                
                if ($LASTEXITCODE -ne 0) { throw "Failed to deploy to production" }
            }

            # Clean up deployment package
            Remove-Item "./app.zip" -Force
            Remove-Item -Recurse -Force "./publish"
        }
    }

    Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
    
    if (-not $DeployOnly) {
        Write-Host ""
        Write-Host "🌐 Application URLs:" -ForegroundColor Cyan
        if ($appServiceUrl) {
            Write-Host "Production: $appServiceUrl" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "📋 Infrastructure Details:" -ForegroundColor Cyan
        if ($appServicePlanName) {
            Write-Host "App Service Plan: $appServicePlanName ($appServicePlanSku)" -ForegroundColor White
        }
        if ($appInsightsName) {
            Write-Host "Application Insights: $appInsightsName (Enabled)" -ForegroundColor White
        } else {
            Write-Host "Application Insights: Disabled" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "📊 To test the memory allocation:" -ForegroundColor Yellow
        Write-Host "1. Navigate to the application URL" -ForegroundColor White
        Write-Host "2. Set memory threshold (e.g., 1024 MB)" -ForegroundColor White
        Write-Host "3. Allocate memory above threshold to trigger 500 errors" -ForegroundColor White
        Write-Host "4. Use stress test feature for automated testing" -ForegroundColor White
    }

} catch {
    Write-Host "❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "🏁 Script execution completed!" -ForegroundColor Green
