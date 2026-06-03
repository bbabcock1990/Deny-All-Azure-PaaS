# Deny-All-Azure-PaaS

A Bicep wrapper that deploys the **Azure Landing Zones (ALZ) `Deny-PublicPaaSEndpoints` initiative** at a management group, plus its one custom policy dependency, and assigns it with a custom deny message:

> **Private Endpoints Must Be Enabled - No Public Access**

The initiative bundles **45 policies** that block creation of Azure PaaS resources whenever `publicNetworkAccess` is not `Disabled` — i.e., the resource must be reachable only via a Private Endpoint.

## What's deployed

| Resource | Source |
|---|---|
| `policySetDefinitions/Deny-PublicPaaSEndpoints` | ALZ initiative (44 built-in policies + 1 custom) |
| `policyDefinitions/Deny-LogicApp-Public-Network` | Custom ALZ policy (only one not in the built-in catalog) |
| `policyAssignments/alz-deny-public-paas` | New — carries the custom non-compliance / deny message |

## Layout

```
.
├── main.bicep                                                  ← deploy this
├── policy_set_definition_es_Deny-PublicPaaSEndpoints.json     ← initiative JSON (verbatim from ALZ-Bicep)
└── policy_definitions/
    └── policy_definition_es_Deny-LogicApp-Public-Network.json ← custom policy (verbatim from ALZ-Bicep)
```

`main.bicep` loads both JSON files with `loadJsonContent`, substitutes the ALZ-Bicep placeholder `${varTargetManagementGroupResourceId}` with the actual management group resource ID, deploys the definition + initiative, and creates a single assignment.

## Deploy

From Azure Cloud Shell or any environment with the Azure CLI:

```bash
az account show -o table   # confirm tenant context

az deployment mg create \
  --name deploy-deny-all-paas \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./main.bicep
```

### Optional parameter overrides

| Parameter | Default | Notes |
|---|---|---|
| `nonComplianceMessage` | `Private Endpoints Must Be Enabled - No Public Access` | Surfaced to the caller when a deploy is denied |
| `assignmentName` | `alz-deny-public-paas` | Max 24 characters (Azure limit) |
| `assignmentDisplayName` | `Enforce private endpoints across PaaS services (ALZ)` | |
| `overrideEffectsGlobally` | `false` | If `true`, forces every bundled policy parameter to `effect` |
| `effect` | `Deny` | Only used when `overrideEffectsGlobally = true` |

**Audit-first dry run:**

```bash
az deployment mg create \
  --name deploy-deny-all-paas-audit \
  --management-group-id <your-mg-id> \
  --location eastus \
  --template-file ./main.bicep \
  --parameters overrideEffectsGlobally=true effect=Audit
```

> ⚠️ Two of the 45 bundled policies default to `Audit` / `AuditIfNotExists` because they can't deny at create-time. Setting `overrideEffectsGlobally=true effect=Deny` may fail validation if those two policies don't list `Deny` in `allowedValues`. The safe default is to leave the override off and trust the ALZ per-policy defaults (43 of 45 default to `Deny`).

## Upgrading

When ALZ publishes a new version of the initiative or the custom Logic App policy:

1. Re-download the two JSON files from [`Azure/ALZ-Bicep`](https://github.com/Azure/ALZ-Bicep) (overwrite in place):
   - `infra-as-code/bicep/modules/policy/definitions/lib/policy_set_definitions/policy_set_definition_es_Deny-PublicPaaSEndpoints.json`
   - `infra-as-code/bicep/modules/policy/definitions/lib/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json`
2. Redeploy `main.bicep`.

If a future ALZ revision adds another *custom* (non-built-in) policy dependency, drop its JSON next to `Deny-LogicApp-Public-Network.json` and add a matching `resource ... 'Microsoft.Authorization/policyDefinitions@2023-04-01'` block in `main.bicep`.

## Attribution

The two JSON files in this repository are taken **verbatim** from the [Azure/ALZ-Bicep](https://github.com/Azure/ALZ-Bicep) project, which is published by Microsoft under the **MIT License**. This repository preserves that license and adds only the `main.bicep` wrapper.

## License

[MIT](./LICENSE)
