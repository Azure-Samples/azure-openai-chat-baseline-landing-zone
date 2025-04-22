# Azure OpenAI chat baseline reference implementation in an application landing zone

This reference implementation extends the foundation set in the [Azure OpenAI end-to-end chat baseline](https://github.com/Azure-Samples/openai-end-to-end-baseline/) reference implementation. Specifically, this repository takes that reference implementation and deploys it within an application landing zone.

If you haven't yet, you should start by reviewing the [Azure OpenAI chat baseline architecture in an Azure landing zone](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/azure-openai-baseline-landing-zone) article on Microsoft Learn. It sets important context for this implementation that is not covered in this deployment guide.

## Azure landing zone: application landing zone deployment

This application landing zone deployment guide assuming you are using a typical Azure landing zone approach with platform and workload separation. This deployment assumes many pre-existing platform resources and deploys nothing outside of the scope of the application landing zone. That means to fully deploy this repo, it must be done so as part of your organization's actual subscription vending process. If you do not have the ability to deploy into an actual application landing zone, then consider this simply reference material.

> [!IMPORTANT]
> Because organizations may implement landing zones different, it is *expected* that you will need to further adjust the deployment beyond the configuration provided.

### Differences from the Azure OpenAI end-to-end chat baseline reference implementation

The key differences when integrating the Azure OpenAI chat baseline into a application landing zone as opposed to a fully standalone deployment are as follows:

- **Virtual network**: The virtual network will be deployed and configured by the platform team. This involves them providing a UDR and DNS configuration on the virtual network. The subnets are still under the control of the workload team.

- **DNS forwarding**: Rather than using local DNS settings, the application's virtual network likely will be configured to use central DNS servers, such as Azure Firewall DNS Proxy or Azure Private DNS Resolver, for DNS forwarding. This centralizes DNS management and ensures consistency across the landscape.

- **Bastion host**: Instead of deploying an Azure Bastion host within the application's landing zone, a centralized bastion service already provisioned within the platform landing zone subscriptions is used. This means all remote administrative traffic is routed through a common, secure access point, adhering to the principle of least privilege and centralized auditing.

- **Private DNS Zones**: Private endpoints within the application need to be integrated with centralized private DNS zones that are managed at the platform landing zone level. Such DNS zones might be shared across multiple applications or environments, simplifying the DNS management and providing an organized approach to name resolution.

- **Network virtual appliance (NVA)**: Outbound connectivity is handled through a centralized NVA, routing traffic via user-defined routes (UDRs) to enforce consistent network security policies and traffic inspections. This approach channels all outbound traffic through a central point where security measures such as firewalls and intrusion detection systems can be applied.

- **Compliance with centralized governance**: An application landing zone comes with predefined governance policies regarding resource provisioning, network configurations, and security settings. Integrating with the Azure landing zone structure demands compliance with these policies, ensuring that all deployments meet the organization's regulatory, compliance, and governance standards.

### Integration with existing platform services

Most of the configuration for this scenario is in the **parameters.alz.json** file, which specifies the integration points for existing Azure services such as the spoke virtual network, the UDR to route internet traffic. It also includes an external DNS server address and the IP address of an existing Network Virtual Appliance (NVA) for routing configuration.

## Architecture

Just like the baseline reference implementation, this implementation covers the same following three scenarios:

1. Authoring a flow - Authoring a flow using prompt flow in the Azure AI Foundry portal
1. Deploying a flow to managed compute behind an Azure Machine Learning endpoint - The deployment of the executable flow created in Azure AI Foundry to managed online endpoint. The client UI that is hosted in Azure App Service accesses the deployed flow.
1. Deploying a flow to Azure App Service (Self-hosted option) - The deployment of an executable flow as a container to Azure App Service. The client UI that accesses the flow is also hosted in Azure App Service.

### Authoring a flow

![Diagram of the authoring architecture using Azure AI Foundry. It demonstrates key architecture components and flow when using the Azure AI Foundry portal as an authoring environment.](docs/media/azure-openai-baseline-landing-zone-networking.png)

The authoring architecture diagram illustrates how flow authors [connect to Azure AI Foundry through a private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link) in a virtual network. In this case, the author connects to the virtual network through routing established by the platform team that supports workstation-based connectivity.

The diagram further illustrates how AI Foundry is configured for [managed virtual network isolation](https://learn.microsoft.com/azure/ai-studio/how-to/configure-managed-network). With this configuration, a managed virtual network is created, along with managed private endpoints enabling connectivity to private resources such as the project's Azure Storage and Azure Container Registry. You can also create user-defined connections like private endpoints to connect to resources like Azure OpenAI service and Azure AI Search.

### Deploying a flow to Azure Machine Learning managed online endpoint

![Diagram of the deploying a flow to managed online endpoint. The diagram illustrates the Azure services' relationships for an AI Foundry environment with a managed online endpoint. This diagram also demonstrates the private endpoints used to ensure private connectivity for the managed private endpoint in Azure AI Foundry.](docs/media/azure-openai-baseline-landing-zone.png)

The Azure AI Foundry deployment architecture diagram illustrates how a front-end web application, deployed into a [network-secured App Service](https://github.com/Azure-Samples/app-service-baseline-implementation), [connects to a managed online endpoint through a private endpoint](https://learn.microsoft.com/azure/ai-studio/how-to/configure-private-link) in a virtual network. Like the authoring flow, the diagram illustrates how the AI Foundry project is configured for [managed virtual network isolation](https://learn.microsoft.com/azure/ai-studio/how-to/configure-managed-network). The deployed flow connects to required resources such as Azure OpenAI and Azure AI Search through managed private endpoints.

### Deploying a flow to Azure App Service (alternative)

![Diagram of the deploying a flow to Azure App Service. This drawing emphasizes how AI Foundry compute and endpoints are bypassed, and Azure App Service and its virtual network become responsible for connecting to the private endpoints for dependencies.](docs/media/azure-openai-chat-baseline-appservices.png)

The Azure App Service deployment architecture diagram illustrates how the same prompt flow is containerized and deployed to Azure App Service alongside the same front-end web application from the prior architecture. This solution is a completely self-hosted, externalized alternative to an Azure AI Foundry managed online endpoint.

The flow is still authored in a network-isolated Azure AI Foundry project. To deploy an App Service in this architecture, the flows need to be containerized and pushed to the Azure Container Registry that is accessible through private endpoints by the App Service.

## Deployment guide

Follow these instructions to deploy this example to your application landing zone subscription, try out what you've deployed, and learn how to clean up those resources.

> [!WARNING]
> The deployment steps assume you have an application landing zone already provisioned through your subscription vending process. This deployment will not work unless you have permission to manage subnets on an existing virtual network and means to ensure private endpoint DNS configuration (such as platform provided DINE Azure Policy). It also requires your platform team to have required NVA allowances on the hub's egress firewall.

### Prerequisites

- You have an application landing zone subscription ready for this deployment that contains the following platform-provided resources:

  - One virtual network (spoke)
    - Must be at least a `/22`
    - DNS configuration set for hub-based resolution
    - Peering fully established between the hub and the spoke as well as the spoke and the hub
    - In the same region as your workload resources

  - One unassociated route table to force Internet-bound traffic through a platform-provided NVA *(if not using Azure VWAN)*
    - In the same region as your spoke virtual network

  - A mechanism to get private endpoint DNS registered with the DNS services set in the virtual network configuration

- The application landing zone subscription must have the following quota available in the location you'll select to deploy this implementation.

  - Azure OpenAI: Standard, GPT-35-Turbo, 25K TPM
  - Storage Accounts: 2 instances
  - App Service Plans: P1v3 (AZ), 3 instances
  - Azure DDoS protection plan: 1
  - Standard, static Public IP Addresses: 2
  - Standard DASv4 Family Cluster Dedicated vCPUs for machine learning: 8

- The application landing zone subscription must have the following resource providers [registered](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types#register-resource-provider).

  - `Microsoft.AlertsManagement`
  - `Microsoft.CognitiveServices`
  - `Microsoft.Compute`
  - `Microsoft.ContainerRegistry`
  - `Microsoft.KeyVault`
  - `Microsoft.Insights`
  - `Microsoft.MachineLearningServices`
  - `Microsoft.ManagedIdentity`
  - `Microsoft.Network`
  - `Microsoft.OperationalInsights`
  - `Microsoft.Storage`
  - `Microsoft.Web`

- Your deployment user must have the following permissions at the application landing zone subscription scope.

  - Ability to assign [Azure roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) on newly created resource groups and resources. (E.g. `User Access Administrator` or `Owner`)
  - Ability to purge deleted AI services resources. (E.g. `Contributor` or `Cognitive Services Contributor`)

- The [Azure CLI installed](https://learn.microsoft.com/cli/azure/install-azure-cli)

  If you're executing this from WSL, be sure the Azure CLI is installed in WSL and is not using the version installed in Windows. `which az` should show `/usr/bin/az`.

- The [OpenSSL CLI](https://docs.openssl.org/3.3/man7/ossl-guide-introduction/#getting-and-installing-openssl) installed.

### 1. :rocket: Deploy the infrastructure

The following steps are required to deploy the infrastructure from the command line.

1. In your shell, clone this repo and navigate to the root directory of this repository.

   ```bash
   git clone https://github.com/Azure-Samples/azure-openai-chat-baseline-landing-zone
   cd azure-openai-chat-baseline-landing-zone
   ```

1. Log in and set the application landing zone subscription.

   ```bash
   az login
   az account set --subscription xxxxx
   ```

1. Obtain the App Gateway certificate

   Azure Application Gateway support for secure TLS using Azure Key Vault and managed identities for Azure resources. This configuration enables end-to-end encryption of the network traffic using standard TLS protocols. For production systems, you should use a publicly signed certificate backed by a public root certificate authority (CA). Here, we will use a self-signed certificate for demonstration purposes.

   - Set a variable for the domain used in the rest of this deployment.

     ```bash
     DOMAIN_NAME_APPSERV="contoso.com"
     ```

   - Generate a client-facing, self-signed TLS certificate.

     :warning: Do not use the certificate created by this script for actual deployments. The use of self-signed certificates are provided for ease of illustration purposes only. For your App Service solution, use your organization's requirements for procurement and lifetime management of TLS certificates, *even for development purposes*.

     Create the certificate that will be presented to web clients by Azure Application Gateway for your domain.

     ```bash
     openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out appgw.crt -keyout appgw.key -subj "/CN=${DOMAIN_NAME_APPSERV}/O=Contoso" -addext "subjectAltName = DNS:${DOMAIN_NAME_APPSERV}" -addext "keyUsage = digitalSignature" -addext "extendedKeyUsage = serverAuth"
     openssl pkcs12 -export -out appgw.pfx -in appgw.crt -inkey appgw.key -passout pass:
     ```

   - Base64 encode the client-facing certificate.

     :bulb: No matter if you used a certificate from your organization or generated one from above, you'll need the certificate (as `.pfx`) to be Base64 encoded for proper storage in Key Vault later.

     ```bash
     APP_GATEWAY_LISTENER_CERTIFICATE=$(cat appgw.pfx | base64 | tr -d '\n')
     echo APP_GATEWAY_LISTENER_CERTIFICATE: $APP_GATEWAY_LISTENER_CERTIFICATE
     ```

1. Update the **infra-as-code/parameters.alz.json** file with all references to your platform team's provided resources.

   You must set the following json values:

   - `existingResourceIdForSpokeVirtualNetwork`: Set this to the resource ID of the spoke virtual network the platform team deployed into your application landing zone subscription.
   - `existingResourceIdForUdrForInternetTraffic`: Set this to the resource ID of the UDR the platform team deployed into your application landing zone subscription. Leave blank if your platform team is using VWAN-provided route tables instead.
   - `bastionSubnetAddresses`: Set this to the `AzureBastionSubnet` range for the Azure Bastion hosts provided by your platform team for VM connectivity (used in jump boxes or build agents).
   - The five `...AddressPrefix` values for the subnets in this architecture. The values must be within the platform-allocated address space for spoke and must be large enough for their respective services. Tip: Update the example ranges, not the subnet mask.

1. Set the resource deployment location to the location of where the virtual network was provisioned for you.

   The location one that [supports availability zones](https://learn.microsoft.com/azure/reliability/availability-zones-service-support) and has available quota. This deployment has been tested in the following locations: `australiaeast`, `eastus`, `eastus2`, `francecentral`, `japaneast`, `southcentralus`, `swedencentral`, `switzerlandnorth`, or `uksouth`. You might be successful in other locations as well.

   ```bash
   LOCATION=eastus
   ```

1. Set the base name value that will be used as part of the Azure resource names for the resources deployed in this solution.

   ```bash
   BASE_NAME=<base resource name, between 6 and 8 lowercase characters, all DNS names will include this text, so it must be unique.>
   ```

1. Create a resource group and deploy the workload infrastructure.

   *There is an optional tracking ID on this deployment. To opt out of its use, add the following parameter to the deployment code below: `-p telemetryOptOut true`.*

   :clock8: *This might take about 20 minutes.*

   ```bash
   RESOURCE_GROUP="rg-chat-alz-baseline-${LOCATION}"
   az group create -l $LOCATION -n $RESOURCE_GROUP

   PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

   az deployment sub create -f ./infra-as-code/bicep/main.bicep \
     -n chat-baseline-000 \
     -l $LOCATION \
     -p @./infra-as-code/bicep/parameters.alz.json \
     -p workloadResourceGroupName=${RESOURCE_GROUP} \
     -p appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE} \
     -p baseName=${BASE_NAME} \
     -p yourPrincipalId=${PRINCIPAL_ID}
   ```

1. Apply workaround for Azure AI Foundry not deploying its managed network.

   Azure AI Foundry tends to delay deploying its managed network, which causes problems when trying to access the Azure AI Foundry portal experience in the next step. Your final IaC implementation must account for this.

   :clock8: *This might take about 15 minutes.*

   ```bash
   az extension add --name ml
   az ml workspace provision-network -n aihub-${BASE_NAME} -g $RESOURCE_GROUP
   ```

### 2. Deploy a prompt flow from the Azure AI Foundry portal

To test this scenario, you'll be deploying a pre-built prompt flow. The prompt flow is called "Chat with Wikipedia" which adds a Wikipedia search as grounding data. Deploying a prompt flow requires data plane and control plane access.

In this architecture, a network perimeter is established, and you must interact with Azure AI Foundry and its resources from the network. You'll need to perform this from your workstation that has a private network line of sight to your deployed Azure AI Foundry and dependent resources. This connection is typically established by the platform team. If instead you use a jump box for access, then use the Azure Bastion provided by your platform team. These instructions assume you're on a workstation or connected to a jump box that can access the Azure AI Foundry portal.

1. Deploy jump box, **if necessary**. *Skip this if your platform team has provided workstation based access or another method.*

   If you need to deploy a jump box into your application landing zone, this deployment guide has a simple one that you can use. You will be prompted for an admin password for the jump box; it must satisfy the [complexity requirements for Windows VM in Azure](https://learn.microsoft.com/azure/virtual-machines/windows/faq#what-are-the-password-requirements-when-creating-a-vm-). You'll need to identify your landing zone virtual network as well in **infra-as-code/bicep/jumpbox/parameters.json**. This is the same value you used in **infra-as-code/bicep/parameters.alz.json**.

   *There is an optional tracking ID on this deployment. To opt out of the deployment tracking, add the following parameter to the deployment code below: `-p telemetryOptOut true`.*

   ```bash
   az deployment group create -f ./infra-as-code/bicep/jumpbox/jumpbox.bicep \
      -g $RESOURCE_GROUP \
      -p @./infra-as-code/bicep/jumpbox/parameters.json \
      -p baseName=$BASE_NAME
   ```

   The username for the Windows jump box deployed in this solution is `vmadmin`.

   Your hub's egress firewall will need various application rule allowances to support this use case. Below are some key destinations that need to be opened from your jump box's subnet:

   - `ai.azure.com:443`
   - `login.microsoftonline.com:443`
   - `login.live.com:443`
   - and many more...

1. If your organization does not provide you with network access from your workstation, then connect to the virtual network via [Azure Bastion and the jump box](https://learn.microsoft.com/azure/bastion/bastion-connect-vm-rdp-windows#rdp)

   | :computer: | This and all of the following steps are performed from your network-connected workstation or a jump box you have control over. The instructions are written as if you are using a network-connected workstation. |
   | :--------: | :------------------------- |

1. Open the Azure portal to your subscription and navigate to the Azure AI project named **aiproj-chat** in your resource group.

   You'll need to sign in if this is the first time you are connecting through a jump box.

1. Open the Azure AI Foundry portal by clicking the **Launch studio** button.

   This will take you directly into the 'Chat with Wikipedia project'. In the future, you can find all your AI Foundry hubs and projects by going to <https://ai.azure.com>.

1. Click on **Prompt flow** in the left navigation.

1. On the **Flows** tab, click **+ Create**.

1. Under **Explore gallery**, find "Chat with Wikipedia" and click **Clone**.

1. Set the Folder name to `chat_wiki` and click **Clone**.

   This copies a starter prompt flow template into your Azure Files storage account. This action is performed by the managed identity of the project. After the files are copied, then you're directed to a prompt flow editor. That editor experience uses your own identity for access to Azure Files.

   :bug: Occasionally, you might receive the following error:

   > CloudDependencyPermission: This request is not authorized to perform this operation using this permission. Please grant workspace/registry read access to the source storage account.

   If this happens, simply choose a new folder name and click the **Clone** button again. You'll need to remember the new folder name to adjust the instructions later.

1. Connect the `extract_query_from_question` prompt flow step to your Azure OpenAI model deployment.

   - For **Connection**, select 'aoai' from the dropdown menu. This is your deployed Azure OpenAI instance.
   - For **deployment_name**, select 'gpt35' from the dropdown menu. This is the model you've deployed in that Azure OpenAI instance.
   - For **response_format**, select '{"type":"text"}' from the dropdown menu

1. Also connect the `augmented_chat` prompt flow step to your Azure OpenAI model deployment.

   - For **Connection**, select the same 'aoai' from the dropdown menu.
   - For **deployment_name**, select the same 'gpt35' from the dropdown menu.
   - For **response_format**, also select '{"type":"text"}' from the dropdown menu.

1. Click **Save** on the whole flow.

### 3. Test the prompt flow from the Azure AI Foundry portal

Here you'll test your flow by invoking it directly from the Azure AI Foundry portal. The flow still requires you to bring compute to execute it from. The compute you'll use when in the portal is the default *Serverless* offering, which is only used for portal-based prompt flow experiences. The interactions against Azure OpenAI are performed by your identity; the bicep template has already granted your user data plane access. The serverless compute is run from the managed virtual network and is beholden to the egress network rules defined.

1. Click **Start compute session**.

1. :clock8: Wait for that button to change to *Compute session running*. This might take about ten minutes.

   *Do not advance until the serverless compute session is running.*

1. Click the enabled **Chat** button on the UI.

1. Enter a question that would require grounding data through recent Wikipedia content, such as a notable current event.

1. A grounded response to your question should appear on the UI.

### 4. Deploy the prompt flow to an Azure Machine Learning managed online endpoint

Here you'll take your tested flow and deploy it to a managed online endpoint using Azure AI Foundry.

1. Click the **Deploy** button in the UI.

1. Choose **Existing** endpoint and select the one called *ept-chat-BASE_NAME*.

1. Set the following Basic settings and click **Next**.

   - **Deployment name**: ept-chat-deployment
   - **Virtual machine**: Choose a small virtual machine size from which you have quota. 'Standard_D2as_v4' is plenty for this sample.
   - **Instance count**: 3. *This is the recommended minimum count.*
   - **Inferencing data collection**: Enabled

1. Set the following Advanced settings and click **Next**.

   - **Deployment tags**: You can leave blank.
   - **Environment**: Use environment of current flow definition.
   - **Application Insights diagnostics**: Enabled

1. Ensure the Output & connections settings are still set to the same connection name and deployment name as configured in the prompt flow and click **Next**.

1. Click the **Create** button.

   There is a notice on the final screen that says:

   > Following connection(s) are using Microsoft Entra ID based authentication. You need to manually grant the endpoint identity access to the related resource of these connection(s).
   > - aoai

   This has already been taken care of by your IaC deployment. The managed online endpoint identity already has this permission to Azure OpenAI, so there is no action for you to take.

1. :clock9: Wait for the deployment to finish creating.

   The deployment can take over 15 minutes to create. To check on the process, navigate to the deployments screen using the **Models + endpoints** link in the left navigation. If you are asked about unsaved changes, just click **Confirm**.

   Eventually 'ept-chat-deployment' will be on this list and the deployment will be listed with a State of 'Succeeded' and have 100% traffic allocation. Use the **Refresh** button as needed.

   *Do not advance until this deployment is complete.*

### 5. Test the Azure Machine Learning online endpoint from the network

As a quick checkpoint of progress, you should test to make sure your Azure Machine Learning managed online endpoint is able to be called from the network. These steps test the network and authorization configuration of that endpoint.

1. Execute an HTTP request to the online endpoint.

   Feel free to adjust for your own question.

   ```powershell
   cat '{"question":"Who were the top three medal winning countries in the 2024 Paris Olympics?"}' > request.json
   az ml online-endpoint invoke -w aiproj-chat -n ept-chat-${BASE_NAME} -g $RESOURCE_GROUP -r request.json
   ```

1. A grounded response to your question should appear in the output. This test emulates any compute platform that is on the virtual network that would be calling the `/score` API on the managed online endpoint.

### 6. Publish the chat front-end web app

Workloads build chat functionality into an application. Those interfaces usually call APIs which in turn call into prompt flow. This implementation comes with such an interface. You'll deploy it to Azure App Service using its [run from package](https://learn.microsoft.com/azure/app-service/deploy-run-package) capabilities.

In a production environment, you use a CI/CD pipeline to:

- Build your web application
- Create the project zip package
- Upload the zip file to your storage account from compute that is in or connected to the workload's virtual network.

For this deployment guide, you'll continue using your network connected workstation (or jump box) to simulate part of that process.

1. Download the web UI.

   ```bash
   wget https://github.com/Azure-Samples/azure-openai-chat-baseline-landing-zone/raw/refs/heads/main/website/chatui.zip
   ```

1. Upload the web application to Azure Storage, where the web app will load the code from.

   ```bash
   az storage blob upload -f chatui.zip --account-name "st${BASE_NAME}" --auth-mode login -c deploy -n chatui.zip
   ```

1. Restart the web app to launch the site.

   ```bash
   az webapp restart --name "app-${BASE_NAME}" --resource-group "${RESOURCE_GROUP}"
   ```

### 7. Test the deployed application that calls into the Azure Machine Learning managed online endpoint

This section will help you to validate that the workload is exposed correctly and responding to HTTP requests. This will validate that traffic is flowing through Application Gateway, into your Web App, and from your Web App, into the Azure Machine Learning managed online endpoint, which contains the hosted prompt flow. The hosted prompt flow will interface with Wikipedia for grounding data and Azure OpenAI for generative responses.

1. Get the public IP address of the Application Gateway.

   ```bash
   # Query the Azure Application Gateway Public IP
   APPGW_PUBLIC_IP=$(az network public-ip show -g $RESOURCE_GROUP -n "pip-$BASE_NAME" --query [ipAddress] --output tsv)
   echo APPGW_PUBLIC_IP: $APPGW_PUBLIC_IP
   ```

1. Create an `A` record for DNS.

   > :bulb: You can simulate this via a local hosts file modification.  Alternatively, you can add a real DNS entry for your specific deployment's application domain name if permission to do so.

   Map the Azure Application Gateway public IP address to the application domain name. To do that, please edit your hosts file (`C:\Windows\System32\drivers\etc\hosts` or `/etc/hosts`) and add the following record to the end: `${APPGW_PUBLIC_IP} www.${DOMAIN_NAME_APPSERV}` (e.g. `50.140.130.120  www.contoso.com`)

1. Browse to the site (e.g. <https://www.contoso.com>).

   > :bulb: It may take up to a few minutes for the App Service to start properly. Remember to include the protocol prefix `https://` in the URL you type in your browser's address bar. A TLS warning will be present due to using a self-signed certificate. You can ignore it or import the self-signed cert (`appgw.pfx`) to your user's trusted root store.

> :bulb: Read through the next steps, but follow the guidance in the [Workaround](#workaround) section.

1. Try it out!

   Once you're there, ask your solution a question. Your question should involve something that would only be known if the RAG process included context from Wikipedia such as recent data or events.

### 8. Rehost the prompt flow in Azure App Service

This is a second option for deploying the prompt flow code. With this option, you deploy the flow to Azure App Service instead of the managed online endpoint.

You will need access to the prompt flow files for this experience, since we'll be building a container out of them. These instructions will use your network-connected workstation as your prompt flow development environmen and simulates a build agent in your workload. To perform these build and deploy tasks, you'll need to install some developer tools.

1. Install [Miniconda](https://docs.anaconda.com/miniconda/) (or an equivilant).

1. Create a python environment with prompt flow tooling.

   ```bash
   conda create -y --name pf python=3.12
   conda activate pf

   pip install promptflow[azure] promptflow-tools bs4
   ```

1. Open the Prompt flow UI again in your Azure AI Foundry project.

1. Expand the **Files** tab in the upper-right pane of the UI.

1. Click on the download icon to download the flow as a zip file to your current directory.

1. Unzip the prompt flow zip file you downloaded.

   *Ensure this file name is set to the directory name you used when first cloning this prompt flow.*

   ```bash
   unzip chat_wiki.zip
   cd chat_wiki
   ```

1. Add packages to requirements.txt, which ensures they are installed in your container.

   ```bash
   cat << EOF > requirements.txt
   promptflow[azure]
   promptflow-tools
   python-dotenv
   bs4
   EOF
   ```

1. Create a file for the Azure OpenAI connection named **aoai.yaml** and register it.

   ```bash
   cat << EOF > aoai.yaml
   $schema: https://azuremlschemas.azureedge.net/promptflow/latest/AzureOpenAIConnection.schema.json
   name: aoai
   type: azure_open_ai
   api_base: "${env:OPENAICONNECTION_API_BASE}"
   api_type: "azure"
   api_version: "2024-02-01"
   auth_mode: "meid_token"
   EOF

   pf connection create -f aoai.yaml
   ```

   > :bulb: The App Service is configured with App Settings that surface as environment variables for ```OPENAICONNECTION_API_BASE```.

1. Bundle the prompt flow to support creating a container image.

   The following command will create a directory named 'dist' with a Dockerfile and all the required flow code files.

   ```bash
   pf flow build --source ./ --output dist --format docker
   ```

1. Build the container image and push it to your Azure Container Registry.

   ```bash
   cd dist

   NAME_OF_ACR="cr${BASE_NAME}"
   IMAGE_NAME='wikichatflow'
   FULL_IMAGE_NAME="aoai/${IMAGE_NAME}:1.0"

   az acr build --agent-pool imgbuild -t $FULL_IMAGE_NAME -r $NAME_OF_ACR .
   ```

1. Set the container image on the Web App that will be hosting the prompt flow.

   ```powershell
   PF_APP_SERVICE_NAME="app-$BASE_NAME-pf"
   ACR_IMAGE_NAME="${NAME_OF_ACR}.azurecr.io/${FULL_IMAGE_NAME}"

   az webapp config container set -n $PF_APP_SERVICE_NAME -g $RESOURCE_GROUP -i $ACR_IMAGE_NAME -r "https://${NAME_OF_ACR}.azurecr.io"
   az webapp deployment container config -e true -n $PF_APP_SERVICE_NAME -g $RESOURCE_GROUP

1. Modify the configuration setting in the App Service that has the chat UI and point it to your deployed prompt flow endpoint hosted in App Service instead of the managed online endpoint.

   ```bash
   $UI_APP_SERVICE_NAME="app-$BASE_NAME"
   $ENDPOINT_URL="https://$PF_APP_SERVICE_NAME.azurewebsites.net/score"

   az webapp config appsettings set --name $UI_APP_SERVICE_NAME --resource-group $RESOURCE_GROUP --settings chatApiEndpoint=$ENDPOINT_URL
   az webapp restart --name $UI_APP_SERVICE_NAME --resource-group $RESOURCE_GROUP
   ```

## :checkered_flag: Try it out. Test the final deployment

| :computer: | Unless otherwise noted, the remaining steps are performed from your original workstation, not from the jump box. |
| :--------: | :------------------------- |

Browse to the site (e.g. <https://www.contoso.com>) once again. Once there, ask your solution a question. Like before, your question should involve something that would only be known if the RAG process included context from Wikipedia such as recent data or events.

In this final configuration, your chat UI is interacting with the prompt flow code hosted in another Web App in your Azure App Service instance. Your Azure Machine Learning online endpoint is not used, and Wikipedia and Azure OpenAI are being called right from your prompt flow Web App.

## :broom: Clean up resources

Most Azure resources deployed in the prior steps will incur ongoing charges unless removed. This deployment is typically over $100 a day, mostly due to Azure DDoS Protection and Azure AI Foundry's managed network's firewall. Promptly delete resources when you are done using them.

Additionally, a few of the resources deployed enter soft delete status which will restrict the ability to redeploy another resource with the same name and might not release quota. It's best to purge any soft deleted resources once you are done exploring. Use the following commands to delete the deployed resources and resource group and to purge each of the resources with soft delete.

| :warning: | This will completely delete any data you may have included in this example. That data and this deployment will be unrecoverable. |
| :--------: | :------------------------- |

```bash
# These deletes and purges take about 30 minutes to run.
az group delete --name $RESOURCE_GROUP -y

az keyvault purge  -n kv-${BASE_NAME}
az cognitiveservices account purge -g $RESOURCE_GROUP -l $LOCATION -n oai-${BASE_NAME}
```

## Contributions

Please see our [Contributor guide](./CONTRIBUTING.md).

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact <opencode@microsoft.com> with any additional questions or comments.

With :heart: from Azure Patterns & Practices, [Azure Architecture Center](https://azure.com/architecture).
