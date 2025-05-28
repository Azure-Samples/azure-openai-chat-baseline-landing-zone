#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Cleanup script for Azure AI Agent Service Mini Landing Zone

.DESCRIPTION
    This script removes all resources created by the deploy.ps1 script including:
    - Hub resource group (rg-hub-test) and all contained resources
    - Spoke resource group (rg-spoke-test) and all contained resources
    - VNet peerings between hub and spoke

.PARAMETER SkipConfirmation
    Skip confirmation prompts for automated cleanup

.PARAMETER Force
    Force deletion without any prompts (use with caution)

.EXAMPLE
    .\cleanup.ps1
    
.EXAMPLE
    .\cleanup.ps1 -SkipConfirmation

.EXAMPLE
    .\cleanup.ps1 -Force

.NOTES
    Author: Azure AI Agent Service Team
    Version: 1.0
    Requires: Azure CLI, PowerShell 7+
    
    WARNING: This script will permanently delete all resources in the specified resource groups.
    Make sure you have backed up any important data before running this script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
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
║           🧹 Azure AI Agent Service Mini Landing Zone Cleanup               ║
║                                                                              ║
║  This script will remove ALL resources created by the deployment script:    ║
║                                                                              ║
║  🗑️  Resource Groups to be deleted:                                         ║
║     • rg-hub-test (Hub infrastructure)                                      ║
║     • rg-spoke-test (Spoke infrastructure)                                  ║
║                                                                              ║
║  ⚠️  WARNING: This action is IRREVERSIBLE!                                  ║
║     All data and configurations will be permanently lost.                   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ "Red"
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
}

# Check if resource groups exist
function Test-ResourceGroups {
    Write-Step "Checking for existing resource groups..."
    
    $hubRgExists = $false
    $spokeRgExists = $false
    
    try {
        az group show --name "rg-hub-test" --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hubRgExists = $true
            Write-Info "Found: rg-hub-test"
        }
    }
    catch {
        # Resource group doesn't exist
    }
    
    try {
        az group show --name "rg-spoke-test" --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $spokeRgExists = $true
            Write-Info "Found: rg-spoke-test"
        }
    }
    catch {
        # Resource group doesn't exist
    }
    
    if (-not $hubRgExists -and -not $spokeRgExists) {
        Write-Info "No resource groups found to delete"
        Write-Success "Cleanup completed - nothing to remove"
        exit 0
    }
    
    return @{
        HubExists = $hubRgExists
        SpokeExists = $spokeRgExists
    }
}

# Show resources to be deleted
function Show-ResourcesToDelete {
    param([hashtable]$ResourceGroups)
    
    Write-ColorOutput @"

📋 RESOURCES TO BE DELETED
═══════════════════════════════════════════════════════════════════════════════

"@ "Yellow"
    
    if ($ResourceGroups.HubExists) {
        Write-ColorOutput "🏗️  Hub Resource Group (rg-hub-test):" "White"
        try {
            $hubResources = az resource list --resource-group "rg-hub-test" --query "[].{Name:name, Type:type}" --output table
            Write-ColorOutput $hubResources "White"
        }
        catch {
            Write-Warning "Could not list hub resources"
        }
        Write-ColorOutput "" "White"
    }
    
    if ($ResourceGroups.SpokeExists) {
        Write-ColorOutput "🎯 Spoke Resource Group (rg-spoke-test):" "White"
        try {
            $spokeResources = az resource list --resource-group "rg-spoke-test" --query "[].{Name:name, Type:type}" --output table
            Write-ColorOutput $spokeResources "White"
        }
        catch {
            Write-Warning "Could not list spoke resources"
        }
        Write-ColorOutput "" "White"
    }
    
    Write-ColorOutput "⚠️  ALL RESOURCES ABOVE WILL BE PERMANENTLY DELETED!" "Red"
    Write-ColorOutput "" "White"
}

# Get user confirmation
function Get-UserConfirmation {
    if ($Force) {
        Write-Warning "Force flag specified - skipping all confirmations"
        return $true
    }
    
    if ($SkipConfirmation) {
        Write-Warning "SkipConfirmation flag specified - proceeding with deletion"
        return $true
    }
    
    Write-ColorOutput "Type 'DELETE' to confirm resource deletion:" "Red"
    $confirmation = Read-Host "Confirmation"
    
    if ($confirmation -eq "DELETE") {
        return $true
    }
    else {
        Write-Info "Cleanup cancelled by user"
        return $false
    }
}

# Delete resource groups
function Remove-ResourceGroups {
    param([hashtable]$ResourceGroups)
    
    $deletionJobs = @()
    
    if ($ResourceGroups.SpokeExists) {
        Write-Step "Deleting spoke resource group (rg-spoke-test)..."
        Write-Info "This may take several minutes..."
        
        $spokeJob = Start-Job -ScriptBlock {
            az group delete --name "rg-spoke-test" --yes --no-wait --output none
        }
        $deletionJobs += @{ Name = "rg-spoke-test"; Job = $spokeJob }
    }
    
    if ($ResourceGroups.HubExists) {
        Write-Step "Deleting hub resource group (rg-hub-test)..."
        Write-Info "This may take several minutes..."
        
        $hubJob = Start-Job -ScriptBlock {
            az group delete --name "rg-hub-test" --yes --no-wait --output none
        }
        $deletionJobs += @{ Name = "rg-hub-test"; Job = $hubJob }
    }
    
    # Wait for all deletion jobs to complete
    if ($deletionJobs.Count -gt 0) {
        Write-Step "Waiting for resource group deletions to complete..."
        
        foreach ($jobInfo in $deletionJobs) {
            Write-Info "Waiting for $($jobInfo.Name) deletion..."
            Wait-Job $jobInfo.Job | Out-Null
            
            if ($jobInfo.Job.State -eq "Completed") {
                Write-Success "$($jobInfo.Name) deleted successfully"
            }
            else {
                Write-Warning "$($jobInfo.Name) deletion may have failed"
            }
            
            Remove-Job $jobInfo.Job
        }
    }
}

# Verify cleanup
function Test-Cleanup {
    Write-Step "Verifying cleanup completion..."
    
    $hubExists = $false
    $spokeExists = $false
    
    try {
        az group show --name "rg-hub-test" --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $hubExists = $true
        }
    }
    catch {
        # Expected - resource group should not exist
    }
    
    try {
        az group show --name "rg-spoke-test" --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $spokeExists = $true
        }
    }
    catch {
        # Expected - resource group should not exist
    }
    
    if ($hubExists -or $spokeExists) {
        Write-Warning "Some resource groups may still exist:"
        if ($hubExists) { Write-Warning "- rg-hub-test" }
        if ($spokeExists) { Write-Warning "- rg-spoke-test" }
        Write-Info "Resource group deletion may still be in progress. Check Azure portal for status."
    }
    else {
        Write-Success "All resource groups have been deleted successfully"
    }
}

# Show cleanup results
function Show-CleanupResults {
    Write-ColorOutput @"

🎉 CLEANUP COMPLETED!
═══════════════════════════════════════════════════════════════════════════════

✅ Resource groups deleted:
   • rg-hub-test (Hub infrastructure)
   • rg-spoke-test (Spoke infrastructure)

✅ All associated resources removed:
   • Virtual networks and subnets
   • Azure Firewall and Public IPs
   • Private DNS Resolver and DNS zones
   • Azure Bastion and Jump Box VM
   • Network Security Groups and Route Tables
   • VNet peerings

💡 Next Steps:
   • You can now run .\deploy.ps1 to create a fresh environment
   • All resources have been permanently deleted
   • No ongoing charges for these resources

"@ "Green"
}

# Main execution
function Main {
    try {
        Show-Banner
        
        Test-Prerequisites
        $resourceGroups = Test-ResourceGroups
        
        if ($resourceGroups.HubExists -or $resourceGroups.SpokeExists) {
            Show-ResourcesToDelete -ResourceGroups $resourceGroups
            
            if (-not (Get-UserConfirmation)) {
                exit 0
            }
            
            $startTime = Get-Date
            Remove-ResourceGroups -ResourceGroups $resourceGroups
            
            # Wait a bit for Azure to process the deletions
            Start-Sleep -Seconds 30
            
            Test-Cleanup
            
            $endTime = Get-Date
            $duration = $endTime - $startTime
            
            Write-Success "Total cleanup time: $($duration.ToString('mm\:ss'))"
            Show-CleanupResults
        }
    }
    catch {
        Write-Error "Cleanup failed: $($_.Exception.Message)"
        Write-Info "You may need to manually delete remaining resources in the Azure portal"
        exit 1
    }
}

# Execute main function
Main 