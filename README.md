# Deny-All-Azure-PaaS

> One combined Azure Policy initiative that **denies the creation of 62 Azure PaaS resources** unless their `publicNetworkAccess` is set to `Disabled` (so the resource is only reachable through a Private Endpoint). Ships with a custom deny message and is deployable via **Bicep** or **Terraform**.

When applied to a management group, this control blocks creation of:

- **45 services from the Azure Landing Zones `Deny-PublicPaaSEndpoints` initiative** — Storage, SQL, Cosmos, Key Vault, App Service, Function App, Logic Apps, Container Registry, AKS, Cognitive Services, Service Bus, Event Hub, Event Grid, AI Search, Synapse, ADF, ADX, AVD, and many more (44 Microsoft built-ins + 1 ALZ-shipped custom for Logic Apps).
- **17 supplemental services covered by custom policies in this repo** — SignalR, Web PubSub, IoT Hub, IoT DPS, Purview, Health Data Services (workspace + FHIR + DICOM + legacy FHIR), Static Web Apps, Relay, HDInsight, Communication Services, Digital Twins, AI Video Indexer, Log Analytics workspaces, Application Insights.

All 62 services are bundled into **one initiative**, deployed with **one wrapper** (Bicep or Terraform) and assigned **once** at your management group. Anyone whose deployment is blocked sees:

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
- [Automated validation (62 services)](#automated-validation-62-services)
- [Just want a tiny single-service demo?](#just-want-a-tiny-single-service-demo)
- [What's blocked (62 services)](#whats-blocked-62-services)
- [Adding new resource types in the future](#adding-new-resource-types-in-the-future)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Attribution](#attribution)
- [License](#license)

---

## How it works

The repo ships **one combined initiative** that bundles 62 policy references:
- **44** Microsoft built-in policies (referenced by URL — no deployment needed).
- **1** custom ALZ policy for Logic Apps (`Deny-LogicApp-Public-Network`), deployed from `policies/policy_definitions/`.
- **17** custom supplemental policies for gap services, deployed from `policies/custom-definitions/`.

For services where Microsoft only ships an audit-only built-in (e.g. Purview, Health Data Services), this repo's custom version is **stronger** — it denies on `publicNetworkAccess` directly rather than checking after the fact for an approved private endpoint connection.

The Bicep and Terraform wrappers do the same five things:

1. Load the combined initiative JSON (`policies/policy_set_definition.json`).
2. Deploy the **18 custom policy definitions** (1 ALZ + 17 supplemental).
3. Rewrite the initiative's `policyDefinitionId` URLs so each reference points at the actual deployed custom definitions (built-in URLs pass through untouched).
4. Deploy the combined initiative as one custom policy set at the target management group.
5. Create one policy assignment carrying your custom non-compliance message — **replicated per bundled policy reference**, which is what Azure requires for an initiative-level assignment to actually surface the deny message to the caller.

---

## Repository layout

```
.
├── policies/                                                ← source-of-truth JSON
│   ├── policy_set_definition.json                           ← combined initiative (62 refs, 46 params)
│   ├── policy_definitions/                                  ← ALZ-derived custom dependencies (verbatim)
│   │   └── policy_definition_es_Deny-LogicApp-Public-Network.json
│   └── custom-definitions/                                  ← supplemental custom definitions (this repo)
│       ├── README.md                                        ← authoring template + alias guidance
│       └── Deny-*.json                                      ← 17 files, one per gap service
├── bicep/
│   └── main.bicep                                           ← Bicep wrapper
├── terraform/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── validation-testing/                                      ← end-to-end policy validation harness
│   ├── README.md                                            ← how to run + interpret results
│   └── validate_policy.py                                   ← 62-service test harness
├── simple-test/                                             ← tiny "hello world" single-policy demo
│   ├── README.md                                            ← deploy + test walkthrough (Bicep & Terraform)
│   ├── verify.py                                            ← validates Enabled = DENY, Disabled = ALLOW
│   ├── bicep/
│   │   └── deny-storage-public.bicep                        ← one-policy Bicep (sub scope)
│   └── terraform/                                           ← same policy in Terraform
│       ├── providers.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── LICENSE
└── README.md
```

The Bicep file and the Terraform module both read JSON from `../policies/` — keep the folder structure intact when you clone.

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
      initiativeName=MyOrg-Deny-PaaS-Public \
      assignmentName=my-pe-policy \
      logicAppPolicyDefinitionName=MyOrg-Deny-LogicApp-Public \
      customPolicyDefinitionNamePrefix=myorg- \
      nonComplianceMessage="Your message here" \
      effect=Audit
```

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

---

## Customisation

Both implementations expose the **same** knobs. Defaults are sensible — change what you need.

### Naming

| Bicep parameter | Terraform variable | Default | What it names |
|---|---|---|---|
| `logicAppPolicyDefinitionName` | `logic_app_policy_definition_name` | `Deny-LogicApp-Public-Network` | The ALZ-derived Logic App custom policy definition |
| `customPolicyDefinitionNamePrefix` | `custom_policy_definition_name_prefix` | *(empty)* | Prefix prepended to every supplemental custom policy name (e.g. `contoso-`). The initiative's lookup keys off the original name, so renames flow through automatically. |
| `initiativeName` | `initiative_name` | `Deny-PublicPaaSEndpoints` | The combined policy set (initiative) |
| `assignmentName` | `assignment_name` | `deny-all-public-paas` | The policy assignment (**max 24 chars** — Azure limit, enforced at compile/plan time) |
| `assignmentDisplayName` | `assignment_display_name` | `Enforce private endpoints across all PaaS services (62)` | Friendly name in the portal |

### Behaviour

| Bicep parameter | Terraform variable | Default | What it does |
|---|---|---|---|
| `nonComplianceMessage` | `non_compliance_message` | `Private Endpoints Must Be Enabled - No Public Access` | Custom message shown to the caller when a deploy is denied |
| `effect` | `effect` | `Deny` | Effect applied to the **17 supplemental** policies always, and to **all 62** policies when `overrideEffectsGlobally = true`. One of: `Audit`, `Deny`, `Disabled` |
| `overrideEffectsGlobally` | `override_effects_globally` | `false` | If `true`, forces every initiative parameter to `effect`. If `false`, the 17 supplemental policies use `effect` and the 45 ALZ ones fall back to ALZ defaults (43 of 45 already default to `Deny`) |

> ⚠️ **About `overrideEffectsGlobally = true`** — 2 of the 45 ALZ-bundled policies have allowed-value lists that don't include `Deny` (they default to `Audit` or `AuditIfNotExists` because their underlying control can't deny at create-time). Forcing them to `Deny` may fail validation. The safe default is `false` — those two stay at `Audit`, and everything else is `Deny`.

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
ASSIGN=deny-all-public-paas     # or whatever you set as assignment name

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

# Count bundled references (should be 62)
az policy set-definition show \
  --name Deny-PublicPaaSEndpoints \
  --management-group $MG \
  --query "length(policyDefinitions)" -o tsv

# (Optional) try to create a non-compliant storage account — should be denied
az storage account create \
  -n stpetest$RANDOM -g <some-rg> -l eastus --sku Standard_LRS
# → RequestDisallowedByPolicy with your custom message in `additionalInfo`
```

For a fully automated end-to-end check of all 62 services, see
[Automated validation](#automated-validation-62-services) below.

---

## Automated validation (62 services)

The [`validation-testing/`](validation-testing/) folder contains a
Python harness that confirms every one of the 62 references in the
initiative actually denies a non-compliant deployment **and** that your
custom non-compliance message is returned to the caller.

The script is **read-only** — it submits one minimal ARM template per
service through `az deployment group validate`, which runs the full
Azure Policy evaluation engine **without creating any resources**. A
clean run takes ~3–4 minutes, consumes no quota, and creates nothing to
clean up.

### Quick run (Cloud Shell or local)

```bash
cd validation-testing

# point at any sub that inherits the assignment + an existing RG inside it
export VAL_SUB_ID="<subscription-id>"
export VAL_TENANT_ID="<tenant-id>"
export VAL_RG="<existing-rg-name>"

python validate_policy.py
```

A clean run prints:

```
[PASS]  Denied at deploy time, expected ref fired:    58
[PASS*] Denied at deploy time, by overlapping ref:     2
[AUDIT] Audit-only by upstream ALZ design (ok):        2
[FAIL]  Other errors / unknown:                        0
[!!!!]  Unexpected allow (regression!):                0
[MSG]   Custom non-compliance message visible in:     60/62
```

The script exits non-zero on any unexpected allow or other error, so it
can be wired into CI as a guardrail.

See [`validation-testing/README.md`](validation-testing/README.md) for
prerequisites, environment variables, how to interpret each result, how
to add a test for a new service, and a sample GitHub Actions snippet.

---

## Just want a tiny single-service demo?

If you don't need the full 62-service initiative and just want a quick
**"hello world"** demo of one deny policy you can deploy and test in
under five minutes, see [`simple-test/`](simple-test/). That folder
contains the same single-policy demo implemented in **both Bicep and
Terraform**:

- **`bicep/deny-storage-public.bicep`** — one subscription-scoped Bicep
  file that deploys a single custom policy + assignment blocking
  Storage Accounts with public network access enabled.
- **`terraform/`** — the same policy + assignment as a small Terraform
  module (`providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`).
- **`verify.py`** — works against either deployment; runs
  `az deployment group validate` twice (enabled → expect DENY,
  disabled → expect ALLOW) and exits 0 on success.
- **`README.md`** — copy-paste deploy / test / clean-up walkthrough for
  both stacks.

Use this folder to learn the pattern, demo the concept on a single
subscription, or rule out integration issues before deploying the full
initiative at management-group scope.

---

## What's blocked (62 services)

All 62 references bundled inside the combined initiative. Sources: **44** Microsoft built-ins, **1** ALZ-custom (Logic App), **17** supplemental customs from this repo.

| # | Reference ID | Service / Resource type | Source |
|---|---|---|---|
| 1  | `ACRDenyPaasPublicIP` | Azure Container Registry | Built-in |
| 2  | `AFSDenyPaasPublicIP` | Azure File Sync | Built-in |
| 3  | `AKSDenyPaasPublicIP` | Azure Kubernetes Service | Built-in |
| 4  | `ApiManDenyPublicIP` | API Management | Built-in |
| 5  | `AppConfigDenyPublicIP` | App Configuration | Built-in |
| 6  | `AsDenyPublicIP` | App Service | Built-in |
| 7  | `AseDenyPublicIP` | App Service Environment | Built-in |
| 8  | `AsrVaultDenyPublicIP` | Azure Site Recovery vault | Built-in |
| 9  | `AutomationDenyPublicIP` | Automation Account | Built-in |
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
| 46 | `Deny-SignalR-Public-Network-Access` | Azure SignalR Service | **Custom (this repo)** |
| 47 | `Deny-WebPubSub-Public-Network-Access` | Azure Web PubSub | **Custom (this repo)** |
| 48 | `Deny-IoTHub-Public-Network-Access` | Azure IoT Hub | **Custom (this repo)** |
| 49 | `Deny-IoTDps-Public-Network-Access` | IoT Hub Device Provisioning Service | **Custom (this repo)** |
| 50 | `Deny-Purview-Public-Network-Access` | Microsoft Purview | **Custom (this repo)** |
| 51 | `Deny-HealthcareApis-Services-Public-Network-Access` | Legacy Azure API for FHIR | **Custom (this repo)** |
| 52 | `Deny-HealthDataServices-Workspace-Public-Network-Access` | Health Data Services workspace | **Custom (this repo)** |
| 53 | `Deny-HealthDataServices-FHIR-Public-Network-Access` | Health Data Services FHIR | **Custom (this repo)** |
| 54 | `Deny-HealthDataServices-DICOM-Public-Network-Access` | Health Data Services DICOM | **Custom (this repo)** |
| 55 | `Deny-StaticWebApps-Public-Network-Access` | Azure Static Web Apps | **Custom (this repo)** |
| 56 | `Deny-Relay-Public-Network-Access` | Azure Relay | **Custom (this repo)** |
| 57 | `Deny-HDInsight-Public-Network-Access` | Azure HDInsight (checks `networkProperties.privateLink`) | **Custom (this repo)** |
| 58 | `Deny-CommunicationServices-Public-Network-Access` | Azure Communication Services | **Custom (this repo)** |
| 59 | `Deny-DigitalTwins-Public-Network-Access` | Azure Digital Twins (Preview) | **Custom (this repo)** |
| 60 | `Deny-VideoIndexer-Public-Network-Access` | Azure AI Video Indexer | **Custom (this repo)** |
| 61 | `Deny-LogAnalytics-Public-Network-Access` | Log Analytics workspaces (both `...ForIngestion` and `...ForQuery`) | **Custom (this repo)** |
| 62 | `Deny-AppInsights-Public-Network-Access` | Application Insights (both `...ForIngestion` and `...ForQuery`) | **Custom (this repo)** |

### Why custom instead of Microsoft built-ins?

For each of the 17 supplemental services, one of the following is true:
1. **No built-in `Deny` policy exists** at all (e.g., Communication Services, Digital Twins, Video Indexer).
2. **Microsoft's built-in is audit-only** — it checks for an approved private endpoint connection rather than the `publicNetworkAccess` field. Our custom version denies on the field directly, which is stronger (Purview, Health Data Services).
3. **A built-in exists but defaults to `Audit`** and we want a `Deny` default with our standard non-compliance message.

See `policies/custom-definitions/README.md` for the authoring template and details on each file.

---

## Adding new resource types in the future

There are three ways to extend the coverage, listed from simplest to most invasive.

### Option A — Pull in upstream ALZ updates

Microsoft updates the [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep) repo as new PaaS services support `publicNetworkAccess`. To pick up their additions:

1. Fetch the latest ALZ initiative JSON:
   ```bash
   curl -L -o /tmp/alz.json \
     https://raw.githubusercontent.com/Azure/ALZ-Bicep/main/infra-as-code/bicep/modules/policy/definitions/lib/policy_set_definitions/policy_set_definition_es_Deny-PublicPaaSEndpoints.json
   ```
2. Merge any **new** `policyDefinitions[]` entries and matching `parameters{}` from `/tmp/alz.json` into this repo's `policies/policy_set_definition.json`. Leave the 17 supplemental entries (`Deny-…-Public-Network-Access` at the end of the array) alone.
3. If a new entry references **another** ALZ-custom (non-built-in) policy, also fetch its JSON into `policies/policy_definitions/` and add a matching `resource` in `bicep/main.bicep`. The Terraform side picks it up automatically once you extend the `endswith()` substitution (or add a new branch alongside the Logic App one).
4. Redeploy.

### Option B — Add a Microsoft built-in policy reference

If Microsoft ships a built-in `Deny` policy for a new service before this repo picks it up:

1. Find the policy's GUID:
   ```bash
   az policy definition list \
     --query "[?contains(displayName,'should disable public network access')].{name:name,display:displayName}" -o table
   ```
2. Add an entry to `properties.policyDefinitions` in `policies/policy_set_definition.json`:
   ```json
   {
     "policyDefinitionReferenceId": "MyNewServiceDeny",
     "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/<GUID-HERE>",
     "parameters": { "effect": { "value": "[[parameters('myNewServiceEffect')]" } },
     "groupNames": [],
     "definitionVersion": "1.*.*"
   }
   ```
3. Add a matching parameter to `properties.parameters` in the same file:
   ```json
   "myNewServiceEffect": {
     "type": "String",
     "allowedValues": ["Audit","Deny","Disabled"],
     "defaultValue": "Deny",
     "metadata": { "displayName": "My new service effect", "description": "..." }
   }
   ```
4. Redeploy. Both Bicep and Terraform pick the new entry up — no wrapper edits required.

### Option C — Author a brand-new custom policy (recommended for gap services)

When neither ALZ nor Microsoft has shipped a built-in Deny policy yet, **add it to the supplemental custom definitions**:

1. **Create the policy JSON.** Drop a new `Deny-<Service>-Public-Network-Access.json` into `policies/custom-definitions/`. Use the template in `policies/custom-definitions/README.md` — most services just need their ARM type, the alias for `publicNetworkAccess`, and a friendly display name.

2. **Reference it in the combined initiative.** Open `policies/policy_set_definition.json` and add an entry to `properties.policyDefinitions`:
   ```json
   {
     "policyDefinitionReferenceId": "Deny-MyNewService-Public-Network-Access",
     "policyDefinitionId": "${managementGroupResourceId}/providers/Microsoft.Authorization/policyDefinitions/Deny-MyNewService-Public-Network-Access",
     "parameters": { "effect": { "value": "[parameters('effect')]" } },
     "groupNames": []
   }
   ```
   The `policyDefinitionReferenceId` **must equal** the `name` field inside your new JSON file — that's the lookup key both wrappers use to rewrite the URL.

3. **Bicep only:** add one line to `bicep/main.bicep` — `loadJsonContent('../policies/custom-definitions/Deny-MyNewService-Public-Network-Access.json')` — inside the `supplementalCustomDefs` array. Bicep needs literal paths, so the list is explicit.

   **Terraform requires no edits.** The `fileset()` glob picks up every `Deny-*.json` in `custom-definitions/` automatically.

4. Redeploy:
   ```bash
   # Bicep
   az deployment mg create --name deploy-deny-all-paas \
     --management-group-id <your-mg-id> --location eastus \
     --template-file ./bicep/main.bicep

   # Terraform
   cd terraform && terraform apply
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

# Bicep
az deployment mg create --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> --location eastus \
  --template-file ./bicep/main.bicep

# Terraform
cd terraform && terraform apply
```

Both implementations are idempotent — re-running won't recreate unchanged resources.

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
| One of the 17 supplemental policies fails with `The alias '…' is not defined` | The ARM alias for that resource's `publicNetworkAccess` may have changed or doesn't exist. Verify with `az provider show --namespace Microsoft.<Provider> --expand "resourceTypes/aliases"` and edit the corresponding `policies/custom-definitions/Deny-*.json`. |

---

## Attribution

The combined initiative in `policies/policy_set_definition.json` is built from two sources:
- 45 references (44 built-ins + the Logic App custom in `policies/policy_definitions/`) come from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep), published by Microsoft under the MIT License.
- 17 references (the custom definitions in `policies/custom-definitions/`) are authored in this repository.

This repository preserves the MIT License and adds the Bicep + Terraform wrappers around the combined initiative.

## License

[MIT](./LICENSE)
