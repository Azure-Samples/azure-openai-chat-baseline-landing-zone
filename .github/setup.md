# Set up GitHub

The GitHub workflows in this project require several secrets set at the repository level or at the environment level.

---

## Workflow Definitions

- **[1_deploy_infra.yml](./workflows/1_deploy_infra.yml):** Deploys the main.bicep template with all new resources and does nothing else. You can use this to do a `what-if` deployment to see what resources will be created/updated/deleted by the [main.bicep](../infra-as-code/bicep/main.bicep) file.
- **[2-build-deploy-apps.yml](./workflows/2-build-deploy-apps.yml):** Builds the app and deploys it to Azure - this could/should be set up to happen automatically after each check-in to main branch app folder
- **[3-deploy-infra-and-apps](./workflows/1-infra-build-deploy-all.yml):** Deploys the main.bicep template then builds and deploys all the apps
- **[4_scan_build_pr.yml](./workflows/4_scan_build_pr.yml):** Runs each time a Pull Request is submitted and includes the results in the PR
- **[5_scheduled_scan.yml](./workflows/5_scheduled_scan.yml):** Runs a scheduled periodic scan of the app for security vulnerabilities
- **[6-deploy-ai-hub-project.yml](./workflows/6-deploy-ai-hub-project.yml):** Deploys an AI Foundry Hub

---

## Quick Start Summary

Follow these steps to get started quickly:

1. Set up a federated App Registration configuration for this repo with your environment name.

    See [https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust)

1. Create these environment secrets either manually or by customizing these commands. They should be in each environment if you are using multiple environments, or could be at the repository level if you are only deploying one version.

    *(Note that there is no CLIENT_SECRET because the previous step recommended using a Federated Identity. If you want to use a secret, you would need to add that and update the workflow login steps.)*

    ```bash
    gh secret set --env <envName> AZURE_SUBSCRIPTION_ID -b xxx-xx-xx-xx-xxxx
    gh secret set --env <envName> AZURE_TENANT_ID -b xxx-xx-xx-xx-xxxx
    gh secret set --env <envName> CICD_CLIENT_ID -b xxx-xx-xx-xx-xxxx
    ```

1. The following variables should be set or updated at the repository level, as they should be the same for most uses. If desired, you could set them at the environment level to customize them for each environment. These values are used by the Bicep templates to configure the resource names that are deployed.

     Make sure the App_Name variable is unique to your deploy. It will be used as the basis for the application name and for all the other Azure resources, some of which must be globally unique.    Update `APP_NAME` with a value that is unique to your deployment, which can contain dashes or underscores (i.e. 'xxx-doc-review'). The `APP_NAME` will be used as the basis for all of the resource names, with the environment name (i.e. dev/qa/prod) appended to each resource name.

    The Resource Group Name created will be `<RESOURCEGROUP_PREFIX>-<ENVIRONMENT>` and will be created in the `<RESOURCEGROUP_LOCATION>` Azure region. If you want to use an existing Resource Group Name or change the format of the `generatedResourceGroupName` variable in the [template-create-infra.yml](./workflows/template-create-infra.yml) file.

    The `<OPENAI_DEPLOY_LOCATION>` can be specified if you want to deploy the OpenAI resources in a different region than the rest of the resources due to region constraints.

    ```bash
    gh variable set --env <envName> APP_NAME -b YOUR-APP-NAME-aichat
    gh variable set --env <envName> RESOURCEGROUP_PREFIX -b rg-aichat
    gh variable set --env <envName> RESOURCEGROUP_LOCATION -b eastus2
    gh variable set --env <envName> OPENAI_DEPLOY_LOCATION -b eastus2
    ```

1. Run the **[1-infra-build-deploy-all](./workflows/1-infra-build-deploy-all.yml):** action in this repo to deploy the UI.

That's it - you should have a fully working deployed environment!

---

### Admin Rights

ADMIN_IP_ADDRESS and ADMIN_PRINCIPAL_ID are optional settings at the environment level - set these only if you want your admin to have access to the Key Vault and Container Registry. You can customize and run the following commands, or you can set these secrets up manually.

```bash
gh secret set --env dev ADMIN_IP_ADDRESS 192.168.1.1
gh secret set --env dev ADMIN_PRINCIPAL_ID <yourGuid>
```

---

## References

- [Deploying ARM Templates with GitHub Actions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-github-actions)
- [GitHub Secrets CLI](https://cli.github.com/manual/gh_secret_set)

---

[Home Page](../README.md)
