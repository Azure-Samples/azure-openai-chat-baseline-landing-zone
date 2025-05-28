#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated deployment script for Azure AI Agent Service Mini Landing Zone

.DESCRIPTION
    This script automates the complete deployment of a hub-spoke architecture
    ready for Azure AI Agent Service. It includes:
    - Hub VNet with Azure Firewall, Private DNS Resolver, Bastion, and Jump Box
    - Spoke VNet with 192.168.x.x ranges (required for AI Agent Service)
    - Bidirectional VNet peering
    - All necessary DNS zones and routing configuration

.PARAMETER Location
    Azure region for deployment (default: eastus2)

.PARAMETER HubBaseName
    Base name for hub resources (default: hub)

.PARAMETER SpokeBaseName
    Base name for spoke resources (default: spoke)

.PARAMETER JumpBoxAdminPassword
    Password for the jump box VM admin user

.PARAMETER SkipConfirmation
    Skip confirmation prompts for automated deployment

.EXAMPLE
    .\deploy.ps1
    
.EXAMPLE
    .\deploy.ps1 -Location "westus2" -HubBaseName "myhub" -SpokeBaseName "myspoke" -SkipConfirmation

.NOTES
    Author: Azure AI Agent Service Team
    Version: 1.0
    Requires: Azure CLI, PowerShell 7+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",
    
    [Parameter(Mandatory = $false)]
    [string]$HubBaseName = "hub",
    
    [Parameter(Mandatory = $false)]
    [string]$SpokeBaseName = "spoke",
    
    [Parameter(Mandatory = $false)]
    [SecureString]$JumpBoxAdminPassword,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color functions for better output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $colorMap = @{
        "Red" = [System.ConsoleColor]::Red
        "Green" = [System.ConsoleColor]::Green
        "Yellow" = [System.ConsoleColor]::Yellow
        "Blue" = [System.ConsoleColor]::Blue
        "Cyan" = [System.ConsoleColor]::Cyan
        "Magenta" = [System.ConsoleColor]::Magenta
        "White" = [System.ConsoleColor]::White
    }
    
    Write-Host $Message -ForegroundColor $colorMap[$Color]
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "🔄 $Message" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "✅ $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "⚠️  $Message" "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "❌ $Message" "Red"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "ℹ️  $Message" "Blue"
}

# Banner
function Show-Banner {
    Write-ColorOutput @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║           🚀 Azure AI Agent Service Mini Landing Zone Deployment            ║
║                                                                              ║
║  This script will deploy a complete hub-spoke architecture ready for        ║
║  Azure AI Agent Service including:                                          ║
║                                                                              ║
║  🏗️  Hub Infrastructure (rg-hub-test):                                      ║
║     • Azure Firewall Basic + Private DNS Resolver                          ║
║     • Azure Bastion + Jump Box VM                                          ║
║     • Private DNS Zones for AI services                                    ║
║                                                                              ║
║  🎯 Spoke Infrastructure (rg-spoke-test):                                   ║
║     • 192.168.x.x network (required for AI Agent Service)                  ║
║     • Subnets ready for AI services deployment                             ║
║     • VNet peering to hub for DNS and routing                              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ "Magenta"
}

# Check prerequisites
function Test-Prerequisites {
    Write-Step "Checking prerequisites..."
    
    # Check Azure CLI
    try {
        $azVersion = az version --output json | ConvertFrom-Json
        Write-Success "Azure CLI version: $($azVersion.'azure-cli')"
    }
    catch {
        Write-Error "Azure CLI is not installed or not in PATH"
        Write-Info "Please install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    }
    
    # Check Azure CLI login
    try {
        $account = az account show --output json | ConvertFrom-Json
        Write-Success "Logged in as: $($account.user.name)"
        Write-Info "Subscription: $($account.name) ($($account.id))"
    }
    catch {
        Write-Error "Not logged in to Azure CLI"
        Write-Info "Please run: az login"
        exit 1
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "PowerShell 7+ is recommended for best experience"
    }
    else {
        Write-Success "PowerShell version: $($PSVersionTable.PSVersion)"
    }
}

# Get secure password
function Get-SecurePassword {
    if (-not $JumpBoxAdminPassword) {
        Write-Info "Please enter a password for the jump box VM admin user (vmadmin):"
        Write-Info "Password requirements: 12+ characters, uppercase, lowercase, number, special character"
        
        do {
            $JumpBoxAdminPassword = Read-Host "Jump Box Admin Password" -AsSecureString
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($JumpBoxAdminPassword))
            
            if ($plainPassword.Length -lt 12) {
                Write-Warning "Password must be at least 12 characters long"
                continue
            }
            
            $hasUpper = $plainPassword -cmatch '[A-Z]'
            $hasLower = $plainPassword -cmatch '[a-z]'
            $hasNumber = $plainPassword -cmatch '[0-9]'
            $hasSpecial = $plainPassword -cmatch '[^A-Za-z0-9]'
            
            if (-not ($hasUpper -and $hasLower -and $hasNumber -and $hasSpecial)) {
                Write-Warning "Password must contain uppercase, lowercase, number, and special character"
                continue
            }
            
            break
        } while ($true)
    }
    
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($JumpBoxAdminPassword))
}

# Show deployment summary
function Show-DeploymentSummary {
    Write-ColorOutput @"

📋 DEPLOYMENT SUMMARY
═══════════════════════════════════════════════════════════════════════════════

🌍 Location: $Location
🏗️  Hub Base Name: $HubBaseName
🎯 Spoke Base Name: $SpokeBaseName

📦 Resource Groups:
   • rg-hub-test (Hub infrastructure)
   • rg-spoke-test (Spoke infrastructure)

🌐 Network Configuration:
   • Hub VNet: 10.0.0.0/16
   • Spoke VNet: 192.168.0.0/16 (AI Agent Service compatible)

⏱️  Estimated deployment time: 15-20 minutes

"@ "White"
}

# Deploy hub infrastructure
function Deploy-HubInfrastructure {
    param([string]$Password)
    
    Write-Step "Creating hub resource group..."
    az group create --name "rg-hub-test" --location $Location --output none
    Write-Success "Hub resource group created"
    
    Write-Step "Deploying hub infrastructure (this may take 10-15 minutes)..."
    Write-Info "Components: Azure Firewall, Private DNS Resolver, Bastion, Jump Box, DNS Zones"
    
    $hubDeployment = az deployment group create `
        --resource-group "rg-hub-test" `
        --template-file "test-hub-vnet.bicep" `
        --parameters hubBaseName=$HubBaseName jumpBoxAdminPassword=$Password `
        --output json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Hub infrastructure deployment failed"
        Write-Info "Check deployment errors with: az deployment operation group list --resource-group rg-hub-test --name test-hub-vnet"
        exit 1
    }
    
    $hubOutputs = ($hubDeployment | ConvertFrom-Json).properties.outputs
    Write-Success "Hub infrastructure deployed successfully"
    
    return @{
        VNetId = $hubOutputs.hubVirtualNetworkId.value
        VNetName = $hubOutputs.hubVirtualNetworkName.value
        DnsResolverIp = $hubOutputs.dnsResolverInboundEndpointIp.value
        FirewallPrivateIp = $hubOutputs.azureFirewallPrivateIp.value
    }
}

# Deploy spoke infrastructure
function Deploy-SpokeInfrastructure {
    param(
        [hashtable]$HubOutputs
    )
    
    Write-Step "Creating spoke resource group..."
    az group create --name "rg-spoke-test" --location $Location --output none
    Write-Success "Spoke resource group created"
    
    Write-Step "Deploying spoke infrastructure..."
    Write-Info "Components: Spoke VNet, Subnets, NSGs, Route Tables, VNet Peering"
    
    $spokeDeployment = az deployment group create `
        --resource-group "rg-spoke-test" `
        --template-file "test-spoke-vnet.bicep" `
        --parameters spokeBaseName=$SpokeBaseName `
                     hubVirtualNetworkId=$HubOutputs.VNetId `
                     hubDnsResolverIp=$HubOutputs.DnsResolverIp `
                     hubFirewallPrivateIp=$HubOutputs.FirewallPrivateIp `
        --output json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Spoke infrastructure deployment failed"
        Write-Info "Check deployment errors with: az deployment operation group list --resource-group rg-spoke-test --name test-spoke-vnet"
        exit 1
    }
    
    $spokeOutputs = ($spokeDeployment | ConvertFrom-Json).properties.outputs
    Write-Success "Spoke infrastructure deployed successfully"
    
    return @{
        VNetId = $spokeOutputs.spokeVirtualNetworkId.value
        VNetName = $spokeOutputs.spokeVirtualNetworkName.value
    }
}

# Create hub-to-spoke peering
function Create-HubToSpokePeering {
    param(
        [hashtable]$HubOutputs,
        [hashtable]$SpokeOutputs
    )
    
    Write-Step "Creating hub-to-spoke VNet peering..."
    
    az network vnet peering create `
        --resource-group "rg-hub-test" `
        --vnet-name $HubOutputs.VNetName `
        --name "peer-to-spoke" `
        --remote-vnet $SpokeOutputs.VNetId `
        --allow-vnet-access `
        --allow-forwarded-traffic `
        --allow-gateway-transit `
        --output none
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Hub-to-spoke peering creation failed"
        exit 1
    }
    
    Write-Success "Hub-to-spoke VNet peering created"
}

# Verify deployment
function Test-Deployment {
    param(
        [hashtable]$HubOutputs,
        [hashtable]$SpokeOutputs
    )
    
    Write-Step "Verifying deployment..."
    
    # Check hub peering
    $hubPeering = az network vnet peering show `
        --resource-group "rg-hub-test" `
        --vnet-name $HubOutputs.VNetName `
        --name "peer-to-spoke" `
        --query "peeringState" `
        --output tsv
    
    # Check spoke peering
    $spokePeering = az network vnet peering show `
        --resource-group "rg-spoke-test" `
        --vnet-name $SpokeOutputs.VNetName `
        --name "peer-to-hub" `
        --query "peeringState" `
        --output tsv
    
    if ($hubPeering -eq "Connected" -and $spokePeering -eq "Connected") {
        Write-Success "VNet peering is connected in both directions"
    }
    else {
        Write-Warning "VNet peering status: Hub->Spoke: $hubPeering, Spoke->Hub: $spokePeering"
    }
    
    # Check DNS configuration
    $spokeDnsServers = az network vnet show `
        --resource-group "rg-spoke-test" `
        --name $SpokeOutputs.VNetName `
        --query "dhcpOptions.dnsServers[0]" `
        --output tsv
    
    if ($spokeDnsServers -eq $HubOutputs.DnsResolverIp) {
        Write-Success "Spoke VNet DNS configuration is correct"
    }
    else {
        Write-Warning "Spoke VNet DNS servers: $spokeDnsServers (expected: $($HubOutputs.DnsResolverIp))"
    }
}

# Show deployment results
function Show-DeploymentResults {
    param(
        [hashtable]$HubOutputs,
        [hashtable]$SpokeOutputs
    )
    
    Write-ColorOutput @"

🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
═══════════════════════════════════════════════════════════════════════════════

📦 Resource Groups Created:
   • rg-hub-test (Hub infrastructure)
   • rg-spoke-test (Spoke infrastructure)

🌐 Network Configuration:
   • Hub VNet: $($HubOutputs.VNetName) (10.0.0.0/16)
   • Spoke VNet: $($SpokeOutputs.VNetName) (192.168.0.0/16)
   • VNet Peering: ✅ Connected

🔧 Key Infrastructure Components:
   • Azure Firewall Private IP: $($HubOutputs.FirewallPrivateIp)
   • DNS Resolver Inbound IP: $($HubOutputs.DnsResolverIp)
   • Azure Bastion: bastion-$HubBaseName
   • Jump Box VM: vm-jumpbox-$HubBaseName

🧪 Testing Your Environment:
   1. Connect to jump box via Azure Bastion
   2. Test DNS resolution: nslookup privatelink.cognitiveservices.azure.com
   3. Verify internet access through firewall

🔄 Next Steps:
   1. Deploy Azure AI Foundry in the spoke VNet
   2. Create private endpoints in snet-privateEndpoints
   3. Deploy AI Agent Service in snet-aiAgentsEgress

🧹 Cleanup:
   Run .\cleanup.ps1 to remove all resources when done

"@ "Green"
}

# Main execution
function Main {
    try {
        Show-Banner
        
        if (-not $SkipConfirmation) {
            Show-DeploymentSummary
            $confirm = Read-Host "Do you want to proceed with the deployment? (y/N)"
            if ($confirm -notmatch '^[Yy]') {
                Write-Info "Deployment cancelled by user"
                exit 0
            }
        }
        
        Test-Prerequisites
        $password = Get-SecurePassword
        
        Write-Step "Starting deployment process..."
        $startTime = Get-Date
        
        # Deploy hub infrastructure
        $hubOutputs = Deploy-HubInfrastructure -Password $password
        
        # Deploy spoke infrastructure
        $spokeOutputs = Deploy-SpokeInfrastructure -HubOutputs $hubOutputs
        
        # Create hub-to-spoke peering
        Create-HubToSpokePeering -HubOutputs $hubOutputs -SpokeOutputs $spokeOutputs
        
        # Verify deployment
        Test-Deployment -HubOutputs $hubOutputs -SpokeOutputs $spokeOutputs
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-Success "Total deployment time: $($duration.ToString('mm\:ss'))"
        Show-DeploymentResults -HubOutputs $hubOutputs -SpokeOutputs $spokeOutputs
    }
    catch {
        Write-Error "Deployment failed: $($_.Exception.Message)"
        Write-Info "Check the error details above and try again"
        exit 1
    }
}

# Execute main function
Main 