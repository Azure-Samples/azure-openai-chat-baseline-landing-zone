# Azure AI Foundry + Agent Service Deployment Guide

## 🎯 Overview

This guide documents the deployment of Azure AI Foundry with AI Agent Service capability using a hub-spoke network architecture. This represents a migration from Azure OpenAI + ML Studio to the new Azure AI Foundry platform.

## 🏗️ Architecture

### Hub-Spoke Network Topology

```
┌─────────────────────────┐     ┌─────────────────────────┐
│        HUB              │────▶│        SPOKE             │
│  rg-hub-test            │     │  rg-spoke-new           │
│                         │     │                         │
│  • Log Analytics        │     │  • AI Foundry           │
│  • Private DNS Zones    │     │  • AI Search            │
│  • Azure Firewall       │     │  • Cosmos DB            │
│  • DNS Resolver         │     │  • Storage Account      │
│  • vnet-hub (10.0.0.0/16)│    │  • vnet-spoke           │
│                         │     │    (192.168.0.0/16)     │
└─────────────────────────┘     └─────────────────────────┘
```

### Subnet Configuration (Spoke VNet)

| Subnet Name | CIDR | Purpose |
|-------------|------|---------|
| `snet-appGateway` | `192.168.0.0/24` | Application Gateway |
| `snet-appServices` | `192.168.1.0/24` | App Services |
| `snet-privateEndpoints` | `192.168.2.0/24` | Private Endpoints |
| `snet-buildAgents` | `192.168.4.0/24` | Build Agents |
| `snet-aiAgentsEgress` | `192.168.3.0/24` | **AI Agents Egress** |

## 📁 File Structure

```
├── infra-as-code/bicep/
│   ├── main.bicep                           # Main AI infrastructure
│   ├── ai-foundry.bicep                     # AI Foundry account + model
│   ├── ai-foundry-project.bicep            # AI Foundry project + connections
│   ├── test-spoke-vnet.bicep               # Spoke VNet with hub peering
│   ├── cosmos-db.bicep                     # Cosmos DB for thread storage
│   ├── ai-search.bicep                     # AI Search for vector store
│   ├── ai-agent-blob-storage.bicep         # Storage for AI agents
│   └── parameters/
│       ├── parameters-main-example.json
│       ├── parameters-ai-foundry-project-example.json
│       └── parameters-spoke-vnet-example.json
├── deploy-infrastructure.ps1               # Automated deployment script
└── DEPLOYMENT_GUIDE.md                     # This guide
```

## 🚀 Quick Start

### Prerequisites

1. **Azure CLI** installed and authenticated
2. **PowerShell 7+** (for the deployment script)
3. **Azure subscription** with appropriate permissions
4. **Hub infrastructure** already deployed with:
   - Log Analytics workspace (`log-hub`)
   - Private DNS zones
   - Hub VNet (`vnet-hub`)
   - Azure Firewall (IP: `10.0.1.4`)
   - DNS Resolver (IP: `10.0.3.4`)

### Get Your Principal ID

```bash
az ad signed-in-user show --query id --output tsv
```

### Automated Deployment

```powershell
# Run from repository root
.\deploy-infrastructure.ps1 `
    -SubscriptionId "YOUR_SUBSCRIPTION_ID" `
    -HubResourceGroupName "rg-hub-test" `
    -SpokeResourceGroupName "rg-spoke-new" `
    -BaseName "aiagt04" `
    -YourPrincipalId "YOUR_PRINCIPAL_ID" `
    -SkipHub  # Skip if hub already exists
```

### Manual Deployment Steps

#### Step 1: Deploy Spoke Network

```bash
az deployment group create \
    --resource-group rg-spoke-new \
    --template-file test-spoke-vnet.bicep \
    --parameters @parameters-spoke-vnet-example.json
```

#### Step 2: Deploy AI Infrastructure

```bash
az deployment group create \
    --resource-group rg-spoke-new \
    --template-file main.bicep \
    --parameters @parameters-main-example.json
```

#### Step 3: Deploy AI Foundry Project

```bash
az deployment group create \
    --resource-group rg-spoke-new \
    --template-file ai-foundry-project.bicep \
    --parameters @parameters-ai-foundry-project-example.json
```

#### Step 4: Link Private DNS Zones

```bash
# Link each DNS zone to spoke VNet
az network private-dns link vnet create \
    --resource-group rg-hub-test \
    --zone-name privatelink.services.ai.azure.com \
    --name link-spoke-vnet \
    --virtual-network /subscriptions/SUB_ID/resourceGroups/rg-spoke-new/providers/Microsoft.Network/virtualNetworks/vnet-spoke \
    --registration-enabled false
```

## 🔧 Configuration Details

### Resource Naming Convention

- **Base Name**: `aiagt04` (customizable)
- **AI Foundry**: `ai{baseName}` → `aifaiagt04`
- **AI Search**: `srch{baseName}` → `srchaiagt04`
- **Cosmos DB**: `cosmos{baseName}` → `cosmosaiagt04`
- **Storage**: `st{baseName}{random}` → `staiagt04abcd1234`
- **App Insights**: `appi-{baseName}` → `appi-aiagt04`

### Key Parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| `baseName` | `aiagt04` | Unique identifier for resources |
| `hubResourceGroupName` | `rg-hub-test` | Hub resource group name |
| `yourPrincipalId` | `b68b11de-...` | Your Azure AD principal ID |
| `logAnalyticsWorkspaceName` | `log-hub` | Log Analytics workspace in hub |

## 🐛 Troubleshooting

### Common Issues & Solutions

#### 1. Missing Spoke Virtual Network

**Error**: `The resource 'vnet-spoke' doesn't exist`

**Solution**: Deploy the spoke network first:
```bash
az deployment group create \
    --resource-group rg-spoke-new \
    --template-file test-spoke-vnet.bicep \
    --parameters hubVNetResourceId="/subscriptions/SUB/resourceGroups/rg-hub-test/providers/Microsoft.Network/virtualNetworks/vnet-hub"
```

#### 2. Log Analytics Workspace Scope Issues

**Error**: `The resource '/subscriptions/.../resourcegroups/rg-spoke-new/providers/microsoft.operationalinsights/workspaces/log-hub' doesn't exist`

**Root Cause**: Bicep modules looking for Log Analytics in wrong resource group

**Solution**: Ensure `scope: resourceGroup(hubResourceGroupName)` is used in dependent modules

#### 3. AI Foundry Deployment Failures

**Error**: `InternalServerError` or API version issues

**Solutions**:
- Use correct API version: `Microsoft.CognitiveServices/accounts@2025-04-01-preview`
- Ensure `hubResourceGroupName` parameter is passed
- Delete and purge failed AI Foundry accounts before retry

#### 4. Capability Host Failures

**Error**: `The resource write operation failed to complete successfully, because it reached terminal provisioning state 'Failed'`

**Known Issue**: Azure AI Agent Service capability hosts appear to have preview limitations

**Workarounds**:
1. **Deploy without capability host** (commented out in template)
2. **Create agents manually** in Azure AI Foundry portal
3. **Contact Microsoft Support** for preview service issues

#### 5. DNS Resolution Issues

**Error**: Capability host can't resolve private endpoints

**Solution**: Link private DNS zones to spoke VNet:
```bash
# Required DNS zones
- privatelink.search.windows.net
- privatelink.documents.azure.com  
- privatelink.blob.core.windows.net
- privatelink.services.ai.azure.com
- privatelink.openai.azure.com
```

### Verification Commands

```bash
# Check DNS A records
az network private-dns record-set a list \
    --resource-group rg-hub-test \
    --zone-name privatelink.services.ai.azure.com

# Check private endpoint status
az network private-endpoint list \
    --resource-group rg-spoke-new \
    --query "[].{Name:name, State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}"

# Check AI Foundry status
az cognitiveservices account show \
    --name aifaiagt04 \
    --resource-group rg-spoke-new \
    --query "properties.provisioningState"
```

## 📊 Deployment Timeline

| Phase | Duration | Components |
|-------|----------|------------|
| **Spoke Network** | 5-10 min | VNet, subnets, peering, NSGs |
| **AI Infrastructure** | 15-25 min | AI Foundry, Search, Cosmos, Storage |
| **AI Project** | 10-15 min | Connections, role assignments |
| **DNS Configuration** | 2-5 min | Private DNS zone links |
| **Total** | **30-55 min** | Complete infrastructure |

## 🎯 Success Criteria

### ✅ Infrastructure Validation

1. **Hub-Spoke Networking**
   - [ ] VNet peering in "Connected" state
   - [ ] Route tables directing traffic through firewall
   - [ ] NSGs allowing required traffic

2. **Private Endpoints**
   - [ ] All services have private endpoints in `snet-privateEndpoints`
   - [ ] Private endpoint connections approved
   - [ ] DNS A records point to private IPs (192.168.2.x)

3. **AI Services**
   - [ ] AI Foundry account deployed and accessible
   - [ ] AI Foundry project created (`projchat`)
   - [ ] GPT-4o model deployed
   - [ ] All connections configured (Search, Cosmos, Storage, AppInsights)

4. **Security**
   - [ ] Public access disabled on all services
   - [ ] Managed identity authentication
   - [ ] RBAC roles assigned correctly

### 🧪 Functional Testing

1. **Access AI Foundry Portal**
   ```
   https://ai.azure.com/
   Navigate to: projchat project
   ```

2. **Create Test Agent**
   - Create agent manually in portal
   - Test with simple conversation
   - Verify connections work

3. **Network Connectivity**
   ```bash
   # From spoke VNet VM or Azure Bastion
   nslookup aifaiagt04.services.ai.azure.com
   # Should resolve to 192.168.2.x IP
   ```

## 🔄 Migration Notes

### From Azure OpenAI + ML Studio

**Previous Architecture**:
- Standalone Azure OpenAI accounts
- ML Studio workspaces
- Manual model deployments

**New Architecture**:
- Unified Azure AI Foundry platform
- Integrated AI Agent Service
- Declarative model deployment
- Enhanced security with private networking

### Key Differences

| Aspect | Old (OpenAI + ML Studio) | New (AI Foundry + Agents) |
|--------|-------------------------|---------------------------|
| **Platform** | Separate services | Unified AI Foundry |
| **Agents** | Custom code | Built-in AI Agent Service |
| **Networking** | Basic private endpoints | Full hub-spoke topology |
| **Models** | Manual deployment | Declarative bicep |
| **Security** | Service-level | Project-level isolation |

## 📝 Known Limitations

### Azure AI Agent Service (Preview)

1. **Capability Host Issues**
   - Deployment failures in certain regions
   - API instability in preview
   - Limited documentation

2. **Network Requirements**
   - Complex DNS zone linking required
   - Specific subnet configuration needed
   - Firewall rules must allow AI service traffic

3. **Bicep Support**
   - Some API versions not stable
   - Resource type validation issues
   - Limited IntelliSense support

## 🆘 Support Resources

### Microsoft Documentation
- [Azure AI Foundry](https://docs.microsoft.com/azure/ai-foundry/)
- [AI Agent Service](https://docs.microsoft.com/azure/ai-agent-service/)
- [Hub-Spoke Network](https://docs.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)

### Troubleshooting Contacts
- **Azure Support**: Create support ticket for preview service issues
- **AI Foundry Forums**: Community support and discussions
- **GitHub Issues**: For bicep template issues

## 🎉 Next Steps

After successful deployment:

1. **Configure AI Agents**
   - Create custom agents in AI Foundry portal
   - Configure RAG with AI Search indexes
   - Set up conversation flows

2. **Security Hardening**
   - Configure Azure Firewall rules
   - Set up monitoring and alerting
   - Implement backup strategies

3. **Scale & Optimize**
   - Monitor resource utilization
   - Adjust compute capacity
   - Optimize cost allocation

## 📋 Appendix

### Complete Parameter Examples

See the generated parameter files:
- `parameters-main-example.json`
- `parameters-ai-foundry-project-example.json`  
- `parameters-spoke-vnet-example.json`

### Deployment Log Analysis

Common deployment patterns and error resolution strategies are documented in the deployment script comments and error handling.

---

**Last Updated**: 2025-01-30
**Version**: 1.0.0
**Author**: AI Migration Team 