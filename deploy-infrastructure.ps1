#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploy Azure AI Foundry + Agent Service Infrastructure
.DESCRIPTION
    This script deploys the complete hub-spoke infrastructure for Azure AI Foundry with AI Agent Service capability.
    It deploys in the correct order: Hub, Spoke, then AI workloads.
.PARAMETER SubscriptionId
    Azure subscription ID
.PARAMETER HubResourceGroupName
    Name of the hub resource group
.PARAMETER SpokeResourceGroupName
    Name of the spoke resource group
.PARAMETER BaseName
    Base name for resources (e.g., aiagt03)
.PARAMETER Location
    Azure region (default: eastus2)
.PARAMETER YourPrincipalId
    Your Azure AD principal ID for RBAC assignments
.PARAMETER SkipHub
    Skip hub deployment (if already exists)
.PARAMETER SkipSpoke
    Skip spoke deployment (if already exists)
.PARAMETER SkipWorkloads
    Skip workload deployment
.EXAMPLE
    .\deploy-infrastructure.ps1 -SubscriptionId "9492515f-7f1c-4cb1-be70-1a9aeef0c4da" -HubResourceGroupName "rg-hub-test" -SpokeResourceGroupName "rg-spoke-new" -BaseName "aiagt04" -YourPrincipalId "b68b11de-d473-4278-a9b1-efab61ed0759"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$HubResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SpokeResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$BaseName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory=$true)]
    [string]$YourPrincipalId,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipHub,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipSpoke,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipWorkloads
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Colors for output
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Cyan = "Cyan"

function Write-Status {
    param([string]$Message, [string]$Color = "White")
    Write-Host "🔄 $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor $Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Cyan
}

# Function to check if deployment was successful
function Test-DeploymentSuccess {
    param([string]$DeploymentName, [string]$ResourceGroupName)
    
    $deployment = az deployment group show --resource-group $ResourceGroupName --name $DeploymentName --query "properties.provisioningState" --output tsv 2>$null
    return $deployment -eq "Succeeded"
}

# Function to wait for deployment
function Wait-ForDeployment {
    param([string]$DeploymentName, [string]$ResourceGroupName, [int]$TimeoutMinutes = 30)
    
    $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
    
    while ((Get-Date) -lt $timeout) {
        $state = az deployment group show --resource-group $ResourceGroupName --name $DeploymentName --query "properties.provisioningState" --output tsv 2>$null
        
        if ($state -eq "Succeeded") {
            Write-Success "Deployment '$DeploymentName' completed successfully"
            return $true
        } elseif ($state -eq "Failed") {
            Write-Error "Deployment '$DeploymentName' failed"
            # Get error details
            az deployment group show --resource-group $ResourceGroupName --name $DeploymentName --query "properties.error" --output json
            return $false
        }
        
        Write-Status "Deployment '$DeploymentName' is $state... waiting 30 seconds"
        Start-Sleep 30
    }
    
    Write-Error "Deployment '$DeploymentName' timed out after $TimeoutMinutes minutes"
    return $false
}

# Main deployment function
try {
    Write-Info "Starting Azure AI Foundry + Agent Service Infrastructure Deployment"
    Write-Info "Subscription: $SubscriptionId"
    Write-Info "Hub RG: $HubResourceGroupName"
    Write-Info "Spoke RG: $SpokeResourceGroupName"
    Write-Info "Base Name: $BaseName"
    Write-Info "Location: $Location"
    
    # Set subscription
    Write-Status "Setting Azure subscription..."
    az account set --subscription $SubscriptionId
    Write-Success "Subscription set successfully"
    
    # Navigate to bicep directory
    if (Test-Path "infra-as-code/bicep") {
        Set-Location "infra-as-code/bicep"
    } elseif (Test-Path "bicep") {
        Set-Location "bicep"
    } else {
        Write-Error "Cannot find bicep directory. Run this script from the repository root."
        exit 1
    }
    
    # STEP 1: Deploy Hub Infrastructure
    if (-not $SkipHub) {
        Write-Status "🏗️  STEP 1: Deploying Hub Infrastructure..." -Color $Cyan
        
        # Check if hub resource group exists
        $hubRgExists = az group exists --name $HubResourceGroupName --output tsv
        if ($hubRgExists -eq "false") {
            Write-Status "Creating hub resource group: $HubResourceGroupName"
            az group create --name $HubResourceGroupName --location $Location
            Write-Success "Hub resource group created"
        } else {
            Write-Info "Hub resource group already exists"
        }
        
        # Deploy hub (you'll need to specify the correct hub bicep file)
        Write-Warning "Hub deployment skipped - please deploy hub infrastructure separately"
        Write-Info "Hub should include: Log Analytics, DNS zones, Firewall, Hub VNet"
    } else {
        Write-Info "Skipping hub deployment"
    }
    
    # STEP 2: Deploy Spoke Infrastructure
    if (-not $SkipSpoke) {
        Write-Status "🏗️  STEP 2: Deploying Spoke Infrastructure..." -Color $Cyan
        
        # Check if spoke resource group exists
        $spokeRgExists = az group exists --name $SpokeResourceGroupName --output tsv
        if ($spokeRgExists -eq "false") {
            Write-Status "Creating spoke resource group: $SpokeResourceGroupName"
            az group create --name $SpokeResourceGroupName --location $Location
            Write-Success "Spoke resource group created"
        } else {
            Write-Info "Spoke resource group already exists"
        }
        
        # Deploy spoke network (if test-spoke-vnet.bicep exists)
        if (Test-Path "test-spoke-vnet.bicep") {
            Write-Status "Deploying spoke network..."
            
            # You'll need to provide the hub VNet resource ID
            $hubVNetId = "/subscriptions/$SubscriptionId/resourceGroups/$HubResourceGroupName/providers/Microsoft.Network/virtualNetworks/vnet-hub"
            
            az deployment group create `
                --resource-group $SpokeResourceGroupName `
                --template-file test-spoke-vnet.bicep `
                --parameters hubVNetResourceId=$hubVNetId `
                            firewallPrivateIpAddress="10.0.1.4" `
                            dnsResolverInboundPrivateIpAddress="10.0.3.4" `
                --name "spoke-network" `
                --verbose
                
            if (Test-DeploymentSuccess -DeploymentName "spoke-network" -ResourceGroupName $SpokeResourceGroupName) {
                Write-Success "Spoke network deployed successfully"
            } else {
                Write-Error "Spoke network deployment failed"
                exit 1
            }
        } else {
            Write-Warning "Spoke network template not found. Please ensure test-spoke-vnet.bicep exists."
        }
    } else {
        Write-Info "Skipping spoke deployment"
    }
    
    # STEP 3: Deploy AI Workloads
    if (-not $SkipWorkloads) {
        Write-Status "🏗️  STEP 3: Deploying AI Workloads..." -Color $Cyan
        
        # Deploy main AI infrastructure
        if (Test-Path "main.bicep" -and Test-Path "parameters-main.json") {
            Write-Status "Deploying main AI infrastructure..."
            
            # Update parameters file with current values
            $parametersContent = @{
                "`$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
                "contentVersion" = "1.0.0.0"
                "parameters" = @{
                    "baseName" = @{ "value" = $BaseName }
                    "hubResourceGroupName" = @{ "value" = $HubResourceGroupName }
                    "logAnalyticsWorkspaceName" = @{ "value" = "log-hub" }
                    "yourPrincipalId" = @{ "value" = $YourPrincipalId }
                    "existingAiAgentsEgressSubnetName" = @{ "value" = "snet-aiAgentsEgress" }
                }
            }
            
            $parametersContent | ConvertTo-Json -Depth 10 | Set-Content -Path "parameters-main-generated.json"
            
            az deployment group create `
                --resource-group $SpokeResourceGroupName `
                --template-file main.bicep `
                --parameters "@parameters-main-generated.json" `
                --name "ai-infrastructure" `
                --verbose
                
            if (-not (Wait-ForDeployment -DeploymentName "ai-infrastructure" -ResourceGroupName $SpokeResourceGroupName -TimeoutMinutes 45)) {
                Write-Error "AI infrastructure deployment failed"
                exit 1
            }
        } else {
            Write-Warning "Main bicep template or parameters not found"
        }
        
        # Deploy AI Foundry Project
        if (Test-Path "ai-foundry-project.bicep") {
            Write-Status "Deploying AI Foundry Project..."
            
            # Get resource names from the main deployment
            $aiFoundryName = "ai$BaseName"
            $searchName = "srch$BaseName"
            $cosmosName = "cosmos$BaseName"
            $storageName = $(az storage account list --resource-group $SpokeResourceGroupName --query "[?contains(name, '$BaseName')].name" --output tsv)
            $appInsightsName = "appi-$BaseName"
            
            $projectParameters = @{
                "`$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
                "contentVersion" = "1.0.0.0"
                "parameters" = @{
                    "existingAiFoundryName" = @{ "value" = $aiFoundryName }
                    "existingAISearchAccountName" = @{ "value" = $searchName }
                    "existingCosmosDbAccountName" = @{ "value" = $cosmosName }
                    "existingStorageAccountName" = @{ "value" = $storageName }
                    "existingBingAccountName" = @{ "value" = "bing-grounding" }
                    "existingWebApplicationInsightsResourceName" = @{ "value" = $appInsightsName }
                }
            }
            
            $projectParameters | ConvertTo-Json -Depth 10 | Set-Content -Path "parameters-project-generated.json"
            
            az deployment group create `
                --resource-group $SpokeResourceGroupName `
                --template-file ai-foundry-project.bicep `
                --parameters "@parameters-project-generated.json" `
                --name "ai-foundry-project" `
                --verbose
                
            if (-not (Wait-ForDeployment -DeploymentName "ai-foundry-project" -ResourceGroupName $SpokeResourceGroupName -TimeoutMinutes 30)) {
                Write-Warning "AI Foundry Project deployment had issues (capability host may have failed - this is expected in preview)"
            }
        }
    } else {
        Write-Info "Skipping workload deployment"
    }
    
    # STEP 4: Configure DNS Links (Critical for AI Agent Service)
    Write-Status "🏗️  STEP 4: Configuring Private DNS Zone Links..." -Color $Cyan
    
    $dnsZones = @(
        "privatelink.search.windows.net",
        "privatelink.documents.azure.com",
        "privatelink.blob.core.windows.net",
        "privatelink.services.ai.azure.com",
        "privatelink.openai.azure.com"
    )
    
    foreach ($zone in $dnsZones) {
        Write-Status "Linking DNS zone: $zone to spoke VNet"
        az network private-dns link vnet create `
            --resource-group $HubResourceGroupName `
            --zone-name $zone `
            --name "link-spoke-vnet" `
            --virtual-network "/subscriptions/$SubscriptionId/resourceGroups/$SpokeResourceGroupName/providers/Microsoft.Network/virtualNetworks/vnet-spoke" `
            --registration-enabled false `
            --output none 2>$null
            
        if ($LASTEXITCODE -eq 0) {
            Write-Success "DNS zone $zone linked successfully"
        } else {
            Write-Warning "DNS zone $zone link may already exist or failed"
        }
    }
    
    # Final status
    Write-Success "🎉 Infrastructure deployment completed!"
    Write-Info "Next Steps:"
    Write-Info "1. Verify all resources in Azure portal"
    Write-Info "2. Test AI Foundry project at https://ai.azure.com/"
    Write-Info "3. Create AI agents manually if capability host deployment failed"
    Write-Info "4. Check private endpoint connectivity and DNS resolution"
    
    # Clean up generated files
    if (Test-Path "parameters-main-generated.json") { Remove-Item "parameters-main-generated.json" }
    if (Test-Path "parameters-project-generated.json") { Remove-Item "parameters-project-generated.json" }
    
} catch {
    Write-Error "Deployment failed with error: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
} 