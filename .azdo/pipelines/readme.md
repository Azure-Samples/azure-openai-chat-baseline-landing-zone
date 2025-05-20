# Azure DevOps Deployment Notes

## Azure DevOps Pipeline Definitions

Base Pipeline Definitions:

- **[1-infra-build-deploy-pipeline.yml](1-infra-build-deploy-pipeline.yml):** Creates all of the Azure resources by deploying the [main.bicep](../../infra-as-code/bicep/main.bicep) template.
- **[2a-deploy-infra-pipeline.yml](2a-deploy-infra-pipeline.yml):** Creates all of the Azure resources by deploying the [main.bicep](../../infra-as-code/bicep/main.bicep) template.
- **[2b-build-deploy-all-pipeline.yml](2b-build-deploy-all-pipeline.yml):** Pipeline to build all apps in the app code folder, store the resulting images in the Azure Container Registry, then deploy to the Azure Container Apps environments.
  > Note: This pipeline pushes into the ACR created by the first pipeline. The service principal used to run this pipeline must have `acrpush` rights to the ACR, which will need to be added manually after the ACR is created in the Access Control page of the Container Registry.
- **[2c-build-deploy-one-pipeline.yml](2c-build-deploy-one-pipeline.yml):** Pipeline to build the one set code in the app code folder, store the resulting image in the Azure Container Registry, then deploying it to the Azure Container Apps environment.
  > Note: This pipeline pushes into the ACR created by the first pipeline. The service principal used to run this pipeline must have `acrpush` rights to the ACR, which will need to be added manually after the ACR is created in the Access Control page of the Container Registry.
- **[3-build-pr-pipeline.yml](3-build-pr-pipeline.yml):** Runs each time a Pull Request is submitted and includes results in the PR
- **[4-scan-pipeline.yml](4-scan-pipeline.yml):** Runs a periodic scan of the app for security vulnerabilities

Testing and Development Pipelines

- **[azd-pipeline.yml](azd-pipeline.yml):** This pipeline deploys the app using the "azd up" command and parameters, just like a developer would do.
- **[testing-az-import-container-pipeline.yml](testing-az-import-container-pipeline.yml):** Imports a container image into Azure Container Registry from an external source, then deploys it to Azure Container Apps.
  - Note: This import is needed until a build agent can be deployed in the same VNET as the container registry.
  - After that, it can be changed to build locally and deploy to the Container Registry and to Azure locally.
- **[testing-az-cleanup-pipeline.yml](testing-az-cleanup-pipeline.yml):** Development Cleanup task to remove items from the resource group that were created in error
- **[testing-az-call-api-pipeline.yml](testing-az-call-api-pipeline.yml):** Development test to call an API like the application would do

---

## Deploy Environments

These Azure DevOps YML files were designed to run as multi-stage environment deploys (i.e. DEV/QA/PROD). Each Azure DevOps environments can have permissions and approvals defined. For example, DEV can be published upon change, and QA/PROD environments can require an approval before any changes are made. These will be created automatically when the pipelines are run, but if you want to add approvals, you can do so in the Azure DevOps portal.

---

## Create the variable group "AI.Doc.Review.Keys"

This project needs a variable group with at least one variable in it that uniquely identifies your resources.

To create this variable groups, customize and run this command in the Azure Cloud Shell, or you can go into the Azure DevOps portal and create it manually.

> Alternatively, you could define these variables in the Azure DevOps Portal on each pipeline, but a variable group is a more repeatable and maintainable way to do it.

```bash
   az login

   az pipelines variable-group create
     --organization=https://dev.azure.com/<yourAzDOOrg>/
     --project='<yourAzDOProject>'
     --name AI.Doc.Review.Keys
     --variables
         appName='<uniqueString>-aichat'
         resourceGroupPrefix='rg-aichat'
         AdminIpAddress='<yourPublicIpAddress>'       (optional - if you want to get access to the KV and ACR)
         AdminPrincipalId='<yourAdminPrincipalId>'    (optional - if you want to get access to the KV and ACR)
```

## Resource Group Name

The Resource Group created will be `<resourceGroupPrefix>-<env>` and will be created in the `<location>` Azure region.  The `location` variable is defined in the [vars/var-common.yml](./vars/var-common.yml) file.  The `resourceGroupPrefix` variable could be defined in either the variable group or in the [var-common.yml](./vars/var-common.yml)  file.  

If you want to use an existing Resource Group Name or change the format of the `generatedResourceGroupName` variable in the [create-infra-template.yml](./pipes/templates/create-infra-template.yml) file and also in the three aca-*template.yml files in the templates folder.

Change the following line in those files to whatever you need it to be:

```bash
$resourceGroupName="$(resourceGroupPrefix)-$environmentNameLower".ToLower()
```

## Create Service Connections and update the Service Connection Variable File

The pipelines use unique Service Connection names for each environment (dev/qa/prod), and can be configured to be any name of your choosing. By default, they are set up to be a simple format of `<env> Service Connection`. Edit the [vars/var-service-connections.yml](./vars/var-service-connections.yml) file to match what you have set up as your service connections.

See [Azure DevOps Service Connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure) for more info on how to set up service connections.

```yml
- name: serviceConnectionName
  value: 'DEV Service Connection'
- name: serviceConnectionDEV
  value: 'DEV Service Connection'
- name: serviceConnectionQA
  value: 'QA Service Connection'
- name: serviceConnectionProd
  value: 'PROD Service Connection'
```

## Update the Common Variables File with your settings

Customize your deploy by editing the [vars/var-common.yml](./vars/var-common.yml) file. This file contains the following variables which you can change:

```bash
- name: location
  value: 'eastus2'
- name: openAI_deploy_location 
  value:  'eastus2'
```

## Set up the Deploy Pipelines

The Azure DevOps pipeline files exist in your repository and are defined in the `.azdo/pipelines` folder. However, in order to actually run them, you need to configure each of them using the Azure DevOps portal.

Set up each of the desired pipelines using [these steps](../../docs/CreateNewPipeline.md).

---

You should be all set to go now!

---

[Home Page](../../README.md)
