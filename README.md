# Deny-All-Azure-PaaS

> Deploy the Azure Landing Zones **`Deny-PublicPaaSEndpoints`** initiative — plus an **optional supplemental initiative covering 17 additional services** — with a custom deny message, using either **Bicep** or **Terraform**.

When applied to a management group, this control **denies the creation of up to 62 different Azure PaaS resources** unless their `publicNetworkAccess` property is set to `Disabled` (i.e., the resource is reachable only through a Private Endpoint):

- **ALZ initiative (45 services)** — `bicep/main.bicep` / `terraform/main.tf` — Storage, SQL, Cosmos, Key Vault, App Service, Function App, Logic Apps, Container Registry, AKS, Cognitive Services, Service Bus, Event Hub, Event Grid, AI Search, Synapse, ADF, ADX, AVD, and more.
- **Supplemental initiative (17 services)** — `bicep/supplemental.bicep` / `terraform/supplemental/` — SignalR, Web PubSub, IoT Hub, IoT DPS, Purview, Health Data Services (workspace + FHIR + DICOM + legacy FHIR), Static Web Apps, Relay, HDInsight, Communication Services, Digital Twins, AI Video Indexer, Log Analytics workspaces, Application Insights.

Anyone whose deployment is blocked sees the message:

> **Private Endpoints Must Be Enabled - No Public Access**

(Both the message and every resource name are fully overridable — see [Customisation](#customisation).)

---

## Table of contents

- [How it works](#how-it-works)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Quickstart — Bicep](#quickstart--bicep)
- [Quickstart — Terraform](#quickstart--terraform)
- [Customisation](#customisation)
- [Verifying the deployment](#verifying-the-deployment)
- [What's blocked — ALZ initiative (45 services)](#whats-blocked--alz-initiative-45-services)
- [What's blocked — Supplemental initiative (17 services)](#whats-blocked--supplemental-initiative-17-services)
- [Adding new resource types in the future](#adding-new-resource-types-in-the-future)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Attribution](#attribution)
- [License](#license)

---

## How it works

The repo ships **two independent initiatives**, each with its own Bicep and Terraform deployment. You can deploy one, the other, or both.

**1. ALZ initiative** (`bicep/main.bicep` / `terraform/main.tf`)
- Ships the **ALZ `Deny-PublicPaaSEndpoints` initiative JSON** plus its **one** custom policy dependency (`Deny-LogicApp-Public-Network`) — both pulled verbatim from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep).
- Deploys the custom Logic App policy + the initiative (44 built-ins + 1 custom) at your management group.
- 45 PaaS services covered, mostly via Microsoft built-in policies (no extra definitions to maintain).

**2. Supplemental initiative** (`bicep/supplemental.bicep` / `terraform/supplemental/`)
- Bundles **17 custom policy definitions** authored in this repo, covering PaaS services that are missing from (or only partially covered by) ALZ.
- The definitions live in `policies/custom-definitions/`. Each is a small JSON file following a single template — easy to read, easy to extend.
- For services where Microsoft only ships an audit-only built-in (e.g. Purview, Health Data Services), the custom version is **stronger** — it denies on `publicNetworkAccess` directly rather than checking after the fact for an approved private endpoint connection.

Both deployments produce **one** policy assignment carrying your custom non-compliance message — replicated per bundled policy reference, which is what Azure requires for an initiative-level assignment to actually surface the deny message to the caller.

---

## Repository layout

```
.
├── policies/                                              ← source-of-truth JSON (shared by both implementations)
│   ├── policy_set_definition_es_Deny-PublicPaaSEndpoints.json   ← ALZ initiative (verbatim from upstream)
│   ├── policy_set_definition_supplemental.json                  ← supplemental initiative (this repo)
│   ├── policy_definitions/                                ← ALZ-derived custom dependencies (verbatim)
│   │   └── policy_definition_es_Deny-LogicApp-Public-Network.json
│   └── custom-definitions/                                ← gap-coverage custom definitions (this repo)
│       ├── README.md                                      ← authoring template + alias guidance
│       └── Deny-*.json                                    ← 17 files, one per gap service
├── bicep/
│   ├── main.bicep                                         ← ALZ initiative wrapper
│   └── supplemental.bicep                                 ← supplemental initiative wrapper
├── terraform/
│   ├── providers.tf                                       ← ALZ initiative module
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── supplemental/                                      ← supplemental initiative module (separate root)
│       ├── providers.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── LICENSE
└── README.md
```

Both Bicep files and both Terraform modules read JSON from `../policies/` (or `../../policies/` for the supplemental Terraform module) — keep the folder structure intact when you clone.

---

## Prerequisites

| | Required |
|---|---|
| Azure subscription | Yes |
| Management group to assign at | Yes — get the **name** (not display name): `az account management-group list -o table` |
| Permissions on that MG | **Resource Policy Contributor** (or higher, e.g. Owner) |
| Tools — Bicep path | Azure CLI ≥ 2.50 *or* Azure Cloud Shell (Bicep bundled in `az`) |
| Tools — Terraform path | Terraform ≥ 1.5.0, AzureRM provider ≥ 3.80.0, and either `az login` or a service principal |

---

## Quickstart — Bicep

From **Azure Cloud Shell** (or any machine with the Azure CLI):

```bash
# 1. Clone
git clone https://github.com/bbabcock1990/Deny-All-Azure-PaaS.git
cd Deny-All-Azure-PaaS

# 2. Make sure you're in the right tenant
az account show -o table

# 3. (Optional but recommended) preview the changes
az deployment mg what-if \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./bicep/main.bicep

# 4. Deploy
az deployment mg create \
  --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./bicep/main.bicep
```

Override anything at deploy time with `--parameters key=value`:

```bash
az deployment mg create \
  --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./bicep/main.bicep \
  --parameters \
      assignmentName=my-pe-policy \
      initiativeName=MyOrg-Deny-PaaS-Public \
      customPolicyDefinitionName=MyOrg-Deny-LogicApp-Public \
      nonComplianceMessage="Your message here"
```

### Deploy the supplemental initiative (optional — 17 more services)

```bash
# What-if
az deployment mg what-if \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./bicep/supplemental.bicep

# Deploy
az deployment mg create \
  --name deploy-deny-paas-supplemental \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./bicep/supplemental.bicep
```

Same naming overrides apply (`assignmentName`, `initiativeName`, `customPolicyDefinitionNamePrefix`, `nonComplianceMessage`, `effect`).

---

## Quickstart — Terraform

```bash
# 1. Clone
git clone https://github.com/bbabcock1990/Deny-All-Azure-PaaS.git
cd Deny-All-Azure-PaaS/terraform

# 2. Authenticate (Cloud Shell is already logged in; locally, run `az login`)
az account show -o table

# 3. Create your tfvars from the example
cp terraform.tfvars.example terraform.tfvars
#   ...edit terraform.tfvars and set at minimum:
#   management_group_id = "<your-mg-id>"

# 4. Init + plan + apply
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` accepts the same naming/behaviour overrides as the Bicep parameters (see [Customisation](#customisation)).

### Deploy the supplemental initiative (optional — 17 more services)

The supplemental Terraform module is a **separate root** under `terraform/supplemental/` so its state is isolated from the ALZ deployment.

```bash
cd Deny-All-Azure-PaaS/terraform/supplemental

cp terraform.tfvars.example terraform.tfvars
#   ...edit terraform.tfvars and set management_group_id = "<your-mg-id>"

terraform init
terraform plan
terraform apply
```

The supplemental module accepts the same shape of overrides as the ALZ one (assignment name, initiative name, custom-definition name prefix, deny message, effect).

---

## Customisation

Both implementations expose the **same** knobs. Defaults are sensible — change what you need.

### Naming

| Bicep parameter | Terraform variable | Default | What it names |
|---|---|---|---|
| `customPolicyDefinitionName` | `custom_policy_definition_name` | `Deny-LogicApp-Public-Network` | The one custom policy definition |
| `initiativeName` | `initiative_name` | `Deny-PublicPaaSEndpoints` | The policy set (initiative) |
| `assignmentName` | `assignment_name` | `alz-deny-public-paas` | The policy assignment (**max 24 chars** — Azure limit, enforced at compile/plan time) |
| `assignmentDisplayName` | `assignment_display_name` | `Enforce private endpoints across PaaS services (ALZ)` | Friendly name in the portal |

### Behaviour

| Bicep parameter | Terraform variable | Default | What it does |
|---|---|---|---|
| `nonComplianceMessage` | `non_compliance_message` | `Private Endpoints Must Be Enabled - No Public Access` | Custom message shown to the caller when a deploy is denied |
| `overrideEffectsGlobally` | `override_effects_globally` | `false` | If `true`, forces every bundled policy parameter to `effect`. If `false`, respects ALZ defaults (43 of 45 already default to `Deny`) |
| `effect` | `effect` | `Deny` | Only consulted when `overrideEffectsGlobally = true`. One of: `Audit`, `Deny`, `Disabled` |

> ⚠️ **About `overrideEffectsGlobally = true`** — 2 of the 45 bundled policies have allowed-value lists that don't include `Deny` (they default to `Audit` or `AuditIfNotExists` because their underlying control can't deny at create-time). Forcing them to `Deny` may fail validation. The safe default is `false` — the ALZ per-policy defaults are already mostly `Deny`.

### Audit-first dry run (recommended)

Before flipping to deny:

```bash
# Bicep
az deployment mg create ... --parameters overrideEffectsGlobally=true effect=Audit

# Terraform
echo 'override_effects_globally = true' >> terraform.tfvars
echo 'effect                    = "Audit"' >> terraform.tfvars
terraform apply
```

---

## Verifying the deployment

```bash
MG=<your-mg-id>
ASSIGN=alz-deny-public-paas     # or whatever you set as assignment name

# Show the assignment
az policy assignment show \
  --name $ASSIGN \
  --scope /providers/Microsoft.Management/managementGroups/$MG \
  -o table

# Confirm the custom message is attached
az policy assignment show \
  --name $ASSIGN \
  --scope /providers/Microsoft.Management/managementGroups/$MG \
  --query "nonComplianceMessages[0].message" -o tsv
# → Private Endpoints Must Be Enabled - No Public Access

# (Optional) try to create a non-compliant storage account — should be denied
az storage account create \
  -n stpetest$RANDOM -g <some-rg> -l eastus --sku Standard_LRS
# → RequestDisallowedByPolicy with your custom message in `additionalInfo`
```

---

## What's blocked — ALZ initiative (45 services)

All 45 references inside the ALZ initiative, sorted by reference ID. **44** are Microsoft built-ins; **1** is the ALZ-custom Logic App policy shipped in this repo.

| # | Reference ID inside the initiative | Service / Resource type | Source |
|---|---|---|---|
| 1 | `ACRDenyPaasPublicIP` | Azure Container Registry | Built-in |
| 2 | `AFSDenyPaasPublicIP` | Azure File Sync | Built-in |
| 3 | `AKSDenyPaasPublicIP` | Azure Kubernetes Service | Built-in |
| 4 | `ApiManDenyPublicIP` | API Management | Built-in |
| 5 | `AppConfigDenyPublicIP` | App Configuration | Built-in |
| 6 | `AsDenyPublicIP` | App Service | Built-in |
| 7 | `AseDenyPublicIP` | App Service Environment | Built-in |
| 8 | `AsrVaultDenyPublicIP` | Azure Site Recovery vault | Built-in |
| 9 | `AutomationDenyPublicIP` | Automation Account | Built-in |
| 10 | `BatchDenyPublicIP` | Batch Account | Built-in |
| 11 | `BotServiceDenyPublicIP` | Bot Service | Built-in |
| 12 | `ContainerAppsEnvironmentDenyPublicIP` | Container Apps Environment | Built-in |
| 13 | `CosmosDenyPaasPublicIP` | Azure Cosmos DB | Built-in |
| 14 | `Deny-Adf-Public-Network-Access` | Azure Data Factory | Built-in |
| 15 | `Deny-ADX-Public-Network-Access` | Azure Data Explorer | Built-in |
| 16 | `Deny-AppSlots-Public` | App Service Slots | Built-in |
| 17 | `Deny-Cognitive-Services-Network-Access` | Cognitive Services (network ACLs) | Built-in |
| 18 | `Deny-Cognitive-Services-Public-Network-Access` | Cognitive Services (public access) | Built-in |
| 19 | `Deny-CognitiveSearch-PublicEndpoint` | Azure AI Search | Built-in |
| 20 | `Deny-ContainerApps-Public-Network-Access` | Container Apps | Built-in |
| 21 | `Deny-EH-Public-Network-Access` | Event Hubs | Built-in |
| 22 | `Deny-EventGrid-Public-Network-Access` | Event Grid (Domains) | Built-in |
| 23 | `Deny-EventGrid-Topic-Public-Network-Access` | Event Grid (Topics) | Built-in |
| 24 | `Deny-Grafana-PublicNetworkAccess` | Azure Managed Grafana | Built-in |
| 25 | `Deny-Hostpool-PublicNetworkAccess` | Azure Virtual Desktop — Host Pool | Built-in |
| 26 | `Deny-KV-Hms-PublicNetwork` | Key Vault Managed HSM | Built-in |
| 27 | `Deny-LogicApp-Public-Network-Access` | **Logic Apps (Standard / `workflowapp`)** | **Custom (ALZ — shipped in this repo)** |
| 28 | `Deny-ManagedDisk-Public-Network-Access` | Managed Disks | Built-in |
| 29 | `Deny-MySql-Public-Network-Access` | Azure DB for MySQL (Single) | Built-in |
| 30 | `Deny-PostgreSql-Public-Network-Access` | Azure DB for PostgreSQL (Single) | Built-in |
| 31 | `Deny-Sb-PublicEndpoint` | Service Bus | Built-in |
| 32 | `Deny-Sql-Managed-Public-Endpoint` | SQL Managed Instance | Built-in |
| 33 | `Deny-Storage-Public-Access` | Storage Account (public access) | Built-in |
| 34 | `Deny-Synapse-Public-Network-Access` | Synapse Workspace | Built-in |
| 35 | `Deny-Workspace-PublicNetworkAccess` | Azure Virtual Desktop — Workspace | Built-in |
| 36 | `FunctionAppSlotsDenyPublicIP` | Function App Slots | Built-in |
| 37 | `FunctionDenyPublicIP` | Function App | Built-in |
| 38 | `KeyVaultDenyPaasPublicIP` | Key Vault | Built-in |
| 39 | `MariaDbDenyPublicIP` | Azure DB for MariaDB | Built-in |
| 40 | `MlDenyPublicIP` | Azure Machine Learning Workspace | Built-in |
| 41 | `MySQLFlexDenyPublicIP` | Azure DB for MySQL — Flexible Server | Built-in |
| 42 | `PostgreSQLFlexDenyPublicIP` | Azure DB for PostgreSQL — Flexible Server | Built-in |
| 43 | `RedisCacheDenyPublicIP` | Azure Cache for Redis | Built-in |
| 44 | `SqlServerDenyPaasPublicIP` | Azure SQL Server | Built-in |
| 45 | `StorageDenyPaasPublicIP` | Storage Account (network ACLs) | Built-in |

---

## What's blocked — Supplemental initiative (17 services)

The supplemental initiative (`bicep/supplemental.bicep` / `terraform/supplemental/`) bundles **17 custom policy definitions** authored in this repo, all living in `policies/custom-definitions/`. Default effect: `Deny`.

| # | Reference ID | Service / Resource type | Field checked |
|---|---|---|---|
| 1 | `Deny-SignalR-Public-Network-Access` | Azure SignalR Service (`Microsoft.SignalRService/SignalR`) | `publicNetworkAccess` |
| 2 | `Deny-WebPubSub-Public-Network-Access` | Azure Web PubSub (`Microsoft.SignalRService/webPubSub`) | `publicNetworkAccess` |
| 3 | `Deny-IoTHub-Public-Network-Access` | Azure IoT Hub (`Microsoft.Devices/IotHubs`) | `publicNetworkAccess` |
| 4 | `Deny-IoTDps-Public-Network-Access` | IoT Hub Device Provisioning Service (`Microsoft.Devices/provisioningServices`) | `publicNetworkAccess` |
| 5 | `Deny-Purview-Public-Network-Access` | Microsoft Purview (`Microsoft.Purview/accounts`) | `publicNetworkAccess` |
| 6 | `Deny-HealthcareApis-Services-Public-Network-Access` | Legacy Azure API for FHIR (`Microsoft.HealthcareApis/services`) | `publicNetworkAccess` |
| 7 | `Deny-HealthDataServices-Workspace-Public-Network-Access` | Health Data Services workspace (`Microsoft.HealthcareApis/workspaces`) | `publicNetworkAccess` |
| 8 | `Deny-HealthDataServices-FHIR-Public-Network-Access` | Health Data Services FHIR (`.../workspaces/fhirservices`) | `publicNetworkAccess` |
| 9 | `Deny-HealthDataServices-DICOM-Public-Network-Access` | Health Data Services DICOM (`.../workspaces/dicomservices`) | `publicNetworkAccess` |
| 10 | `Deny-StaticWebApps-Public-Network-Access` | Azure Static Web Apps (`Microsoft.Web/staticSites`) | `publicNetworkAccess` |
| 11 | `Deny-Relay-Public-Network-Access` | Azure Relay (`Microsoft.Relay/namespaces`) | `publicNetworkAccess` |
| 12 | `Deny-HDInsight-Public-Network-Access` | Azure HDInsight (`Microsoft.HDInsight/clusters`) | `networkProperties.privateLink` must be `Enabled` |
| 13 | `Deny-CommunicationServices-Public-Network-Access` | Azure Communication Services (`Microsoft.Communication/communicationServices`) | `publicNetworkAccess` |
| 14 | `Deny-DigitalTwins-Public-Network-Access` | Azure Digital Twins (`Microsoft.DigitalTwins/digitalTwinsInstances`) | `publicNetworkAccess` (Preview) |
| 15 | `Deny-VideoIndexer-Public-Network-Access` | Azure AI Video Indexer (`Microsoft.VideoIndexer/accounts`) | `publicNetworkAccess` |
| 16 | `Deny-LogAnalytics-Public-Network-Access` | Log Analytics workspaces (`Microsoft.OperationalInsights/workspaces`) | both `publicNetworkAccessForIngestion` and `...ForQuery` |
| 17 | `Deny-AppInsights-Public-Network-Access` | Application Insights (`Microsoft.Insights/components`) | both `publicNetworkAccessForIngestion` and `...ForQuery` |

### Why custom instead of Microsoft built-ins?

For each service in this list, one of the following is true:
1. **No built-in `Deny` policy exists** at all (e.g., Communication Services, Digital Twins, Video Indexer).
2. **Microsoft's built-in is audit-only** — it checks for an approved private endpoint connection rather than the `publicNetworkAccess` field. Our custom version denies on the field directly, which is stronger (Purview, Health Data Services).
3. **A built-in exists but defaults to `Audit`** and we want a `Deny` default with our standard non-compliance message.

See `policies/custom-definitions/README.md` for the authoring template and details on each file.

---

## Adding new resource types in the future

There are three ways to extend the coverage, listed from simplest to most invasive.

### Option A — Wait for ALZ to add it (recommended)

Microsoft updates the [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep) repo as new PaaS services support `publicNetworkAccess`. To pick up their updates:

```bash
cd Deny-All-Azure-PaaS

# Pull the two latest JSON files into ./policies/
curl -L -o policies/policy_set_definition_es_Deny-PublicPaaSEndpoints.json \
  https://raw.githubusercontent.com/Azure/ALZ-Bicep/main/infra-as-code/bicep/modules/policy/definitions/lib/policy_set_definitions/policy_set_definition_es_Deny-PublicPaaSEndpoints.json

curl -L -o policies/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json \
  https://raw.githubusercontent.com/Azure/ALZ-Bicep/main/infra-as-code/bicep/modules/policy/definitions/lib/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json

# Redeploy via Bicep or Terraform
```

> If a future ALZ release adds **another** custom (non-built-in) policy dependency, you'll need to:
> - Place its `.json` next to the Logic App one in `policies/policy_definitions/`.
> - Add a matching block in `bicep/main.bicep` (`resource 'Microsoft.Authorization/policyDefinitions@2023-04-01' = { ... }`) and update the `endsWith` substitution to recognise its suffix.
> - Add a matching `azurerm_policy_definition` resource in `terraform/main.tf` and update the `endswith()` substitution likewise.

### Option B — Add a new built-in policy reference yourself

If Microsoft ships a *built-in* policy for a new service before ALZ picks it up:

1. Find the policy's GUID — `az policy definition list --query "[?contains(displayName,'should disable public network access')].{name:name,display:displayName}" -o table`
2. Open `policies/policy_set_definition_es_Deny-PublicPaaSEndpoints.json` and add an entry to `properties.policyDefinitions`:
   ```json
   {
     "policyDefinitionReferenceId": "MyNewServiceDeny",
     "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/<GUID-HERE>",
     "parameters": {
       "effect": { "value": "[[parameters('myNewServiceEffect')]" }
     },
     "groupNames": [],
     "definitionVersion": "1.*.*"
   }
   ```
3. Add the matching parameter to `properties.parameters` in the same file:
   ```json
   "myNewServiceEffect": {
     "type": "String",
     "allowedValues": ["Audit","Deny","Disabled"],
     "defaultValue": "Deny",
     "metadata": { "displayName": "My new service effect", "description": "..." }
   }
   ```
4. Redeploy. The wrapper picks up the new entry automatically — no Bicep/Terraform edits required.

### Option C — Author a brand-new custom policy (recommended for gap services)

When neither ALZ nor Microsoft has shipped a built-in Deny policy yet, **add it to the supplemental initiative** — much simpler than touching the ALZ wrapper.

1. **Create the policy JSON.** Drop a new `Deny-<Service>-Public-Network-Access.json` into `policies/custom-definitions/`. Use the template in `policies/custom-definitions/README.md` — most services just need their ARM type, the alias for `publicNetworkAccess`, and a friendly display name.

2. **Reference it in the supplemental initiative.** Open `policies/policy_set_definition_supplemental.json` and add an entry to `properties.policyDefinitions`:
   ```json
   {
     "policyDefinitionReferenceId": "Deny-MyNewService-Public-Network-Access",
     "policyDefinitionId": "${managementGroupResourceId}/providers/Microsoft.Authorization/policyDefinitions/Deny-MyNewService-Public-Network-Access",
     "parameters": { "effect": { "value": "[parameters('effect')]" } },
     "groupNames": []
   }
   ```
   The `policyDefinitionReferenceId` **must equal** the `name` field inside your new JSON file — that's the lookup key both wrappers use.

3. **(Bicep only)** Add one line to `bicep/supplemental.bicep` — `loadJsonContent('../policies/custom-definitions/Deny-MyNewService-Public-Network-Access.json')` — inside the `customDefs` array. Bicep needs literal paths, so the list is explicit.

   **Terraform requires no edits.** The `fileset()` glob picks up every `Deny-*.json` in `custom-definitions/` automatically.

4. Redeploy:
   ```bash
   # Bicep
   az deployment mg create --name deploy-deny-paas-supplemental \
     --management-group-id <your-mg-id> --location eastus \
     --template-file ./bicep/supplemental.bicep

   # Terraform
   cd terraform/supplemental && terraform apply
   ```

> When in doubt about the alias for `publicNetworkAccess` on a given resource type, verify with:
> ```bash
> az provider show --namespace Microsoft.<Provider> --expand "resourceTypes/aliases" \
>   --query "resourceTypes[?resourceType=='<type>'].aliases[?name=='Microsoft.<Provider>/<type>/publicNetworkAccess']"
> ```

---

## Upgrading

```bash
cd Deny-All-Azure-PaaS
git pull

# Bicep — ALZ initiative
az deployment mg create --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> --location eastus \
  --template-file ./bicep/main.bicep

# Bicep — Supplemental initiative
az deployment mg create --name deploy-deny-paas-supplemental \
  --management-group-id <your-mg-id> --location eastus \
  --template-file ./bicep/supplemental.bicep

# Terraform — ALZ initiative
cd terraform && terraform apply

# Terraform — Supplemental initiative
cd ../terraform/supplemental && terraform apply
```

All four deployments are idempotent — re-running won't recreate unchanged resources.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `The policy assignment name '...' is invalid. The policy assignment name length must not exceed '24' characters.` | Shorten `assignmentName` / `assignment_name` (max 24 chars). The wrapper enforces this at compile/plan time. |
| `AuthorizationFailed` on the management group | You need **Resource Policy Contributor** (or higher) at the MG scope. |
| `Cannot find the Management Group '...'` | You passed a display name — pass the MG **name** (use `az account management-group list -o table` to find it). |
| `InvalidPolicyAssignmentParameters` after setting `overrideEffectsGlobally=true effect=Deny` | One of the bundled policies doesn't allow `Deny` in its `allowedValues`. Revert to `overrideEffectsGlobally=false` or use `effect=Audit`. |
| Deny works but the message isn't shown to the caller | Confirm the assignment was created with `nonComplianceMessages` populated — `az policy assignment show … --query nonComplianceMessages`. The wrapper emits **one entry per bundled policy** because Azure requires that for an initiative-level deny message. |
| Terraform: `endswith` is not a defined function | Upgrade Terraform to ≥ 1.5.0. |
| Terraform: `policy_definition_reference` block doesn't accept `version` | Upgrade the AzureRM provider to ≥ 3.80.0. |

---

## Attribution

The two JSON files under `policies/` are taken **verbatim** from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep), published by Microsoft under the MIT License. This repository preserves that license and adds the Bicep + Terraform wrappers around them.

## License

[MIT](./LICENSE)
