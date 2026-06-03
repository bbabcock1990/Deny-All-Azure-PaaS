# Deny-All-Azure-PaaS

> Deploy the Azure Landing Zones **`Deny-PublicPaaSEndpoints`** initiative — with a custom deny message — using either **Bicep** or **Terraform**.

When applied to a management group, this control **denies the creation of 45 different Azure PaaS resources** unless their `publicNetworkAccess` property is set to `Disabled` (i.e., the resource is reachable only through a Private Endpoint).

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
- [What's blocked (the 45 covered services)](#whats-blocked-the-45-covered-services)
- [Adding new resource types in the future](#adding-new-resource-types-in-the-future)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Attribution](#attribution)
- [License](#license)

---

## How it works

1. The repo ships the **ALZ `Deny-PublicPaaSEndpoints` initiative JSON** plus its **one** custom policy dependency (`Deny-LogicApp-Public-Network`) — both pulled verbatim from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep).
2. Either implementation (Bicep or Terraform):
   - Deploys the custom Logic App policy definition at your management group.
   - Substitutes the ALZ placeholder URL inside the initiative with the deployed definition's real resource ID.
   - Deploys the initiative (44 built-in policies + the 1 custom policy).
   - Creates **one** policy assignment that carries your custom non-compliance message — replicated per bundled policy reference, which is what Azure requires for an initiative-level assignment to actually surface the deny message to the caller.

The other 44 policies are Microsoft built-ins, already present in every Azure tenant — nothing extra to deploy.

---

## Repository layout

```
.
├── policies/                                              ← source-of-truth JSON (shared by both implementations)
│   ├── policy_set_definition_es_Deny-PublicPaaSEndpoints.json
│   └── policy_definitions/
│       └── policy_definition_es_Deny-LogicApp-Public-Network.json
├── bicep/
│   └── main.bicep
├── terraform/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── LICENSE
└── README.md
```

Both `bicep/main.bicep` and `terraform/main.tf` read JSON from `../policies/` — keep the folder structure intact when you clone.

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

## What's blocked (the 45 covered services)

All 45 references inside the initiative, sorted by reference ID. **44** are Microsoft built-ins; **1** is the ALZ-custom Logic App policy shipped in this repo.

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

### Option C — Author a brand-new custom policy

When neither ALZ nor Microsoft has shipped anything yet:

1. Create a new JSON file under `policies/policy_definitions/`, following the shape of `policy_definition_es_Deny-LogicApp-Public-Network.json` (it's a complete worked example for a service whose `publicNetworkAccess` property lives at a non-standard path).
2. In **Bicep** (`bicep/main.bicep`):
   - Add a `loadJsonContent(...)` `var` for the new file.
   - Add a `resource 'Microsoft.Authorization/policyDefinitions@2023-04-01' = { ... }` block.
   - Extend the `endsWith(...) ? newPolicy.id : ...` ternary so the initiative's reference URL is rewritten correctly.
3. In **Terraform** (`terraform/main.tf`):
   - Add a `jsondecode(file(...))` line in `locals`.
   - Add a matching `azurerm_policy_definition` resource.
   - Extend the `endswith(...) ? ... : ...` logic the same way.
4. Add a reference entry + matching parameter to the initiative JSON (as in Option B).

> Each new custom policy adds one more substitution branch. For more than a handful, switching to a map (`{ "/policyDefinitions/Foo": foo.id, "/policyDefinitions/Bar": bar.id }`) and a `lookup`-style substitution is cleaner — it's worth refactoring at that point.

---

## Upgrading

```bash
cd Deny-All-Azure-PaaS
git pull
# Bicep:
az deployment mg create --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> --location eastus \
  --template-file ./bicep/main.bicep
# Terraform:
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

---

## Attribution

The two JSON files under `policies/` are taken **verbatim** from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep), published by Microsoft under the MIT License. This repository preserves that license and adds the Bicep + Terraform wrappers around them.

## License

[MIT](./LICENSE)
