# Custom Policy Definitions

This folder holds **non-built-in** Azure Policy definitions authored for this repo. They cover Azure PaaS services that are missing from (or only partially covered by) the ALZ `Deny-PublicPaaSEndpoints` initiative.

> The one custom definition that ships *with* the ALZ initiative (`Deny-LogicApp-Public-Network`) lives separately in `../policy_definitions/` so it stays in sync with upstream.

---

## Why custom?

For each service in this folder, one of the following is true:

1. **No built-in `Deny` policy exists.** Microsoft only publishes an audit-only built-in (e.g., Purview, Health Data Services — both check for *approved private endpoint connections* rather than the `publicNetworkAccess` field).
2. **A built-in exists but defaults to `Audit`** and we want a `Deny` default with our standard non-compliance message.
3. **The service isn't yet in the ALZ initiative**, and we don't want to wait for an upstream release.

Custom definitions in this folder follow a single template (see below) so they can be bundled into a supplemental initiative and assigned with the same standard deny message: **"Private Endpoints Must Be Enabled - No Public Access"**.

---

## What's in here today

17 custom policy definitions, all bundled into the supplemental initiative (`../policy_set_definition_supplemental.json`):

| File | Resource type | Field checked |
|---|---|---|
| `Deny-SignalR-Public-Network-Access.json` | `Microsoft.SignalRService/SignalR` | `publicNetworkAccess` |
| `Deny-WebPubSub-Public-Network-Access.json` | `Microsoft.SignalRService/webPubSub` | `publicNetworkAccess` |
| `Deny-IoTHub-Public-Network-Access.json` | `Microsoft.Devices/IotHubs` | `publicNetworkAccess` |
| `Deny-IoTDps-Public-Network-Access.json` | `Microsoft.Devices/provisioningServices` | `publicNetworkAccess` |
| `Deny-Purview-Public-Network-Access.json` | `Microsoft.Purview/accounts` | `publicNetworkAccess` |
| `Deny-HealthcareApis-Services-Public-Network-Access.json` | `Microsoft.HealthcareApis/services` (legacy FHIR/DICOM) | `publicNetworkAccess` |
| `Deny-HealthDataServices-Workspace-Public-Network-Access.json` | `Microsoft.HealthcareApis/workspaces` | `publicNetworkAccess` |
| `Deny-HealthDataServices-FHIR-Public-Network-Access.json` | `Microsoft.HealthcareApis/workspaces/fhirservices` | `publicNetworkAccess` |
| `Deny-HealthDataServices-DICOM-Public-Network-Access.json` | `Microsoft.HealthcareApis/workspaces/dicomservices` | `publicNetworkAccess` |
| `Deny-StaticWebApps-Public-Network-Access.json` | `Microsoft.Web/staticSites` | `publicNetworkAccess` |
| `Deny-Relay-Public-Network-Access.json` | `Microsoft.Relay/namespaces` | `publicNetworkAccess` |
| `Deny-HDInsight-Public-Network-Access.json` | `Microsoft.HDInsight/clusters` | `networkProperties.privateLink` must be `Enabled` |
| `Deny-CommunicationServices-Public-Network-Access.json` | `Microsoft.Communication/communicationServices` | `publicNetworkAccess` |
| `Deny-DigitalTwins-Public-Network-Access.json` | `Microsoft.DigitalTwins/digitalTwinsInstances` | `publicNetworkAccess` (Preview Private Link) |
| `Deny-VideoIndexer-Public-Network-Access.json` | `Microsoft.VideoIndexer/accounts` | `publicNetworkAccess` |
| `Deny-LogAnalytics-Public-Network-Access.json` | `Microsoft.OperationalInsights/workspaces` | both `publicNetworkAccessForIngestion` and `...ForQuery` |
| `Deny-AppInsights-Public-Network-Access.json` | `Microsoft.Insights/components` | both `publicNetworkAccessForIngestion` and `...ForQuery` |

### Definitions with non-standard rules

Most files follow the standard "deny when `publicNetworkAccess != Disabled`" template. These ones diverge:

- **HDInsight** — has no `publicNetworkAccess` property. We deny when `networkProperties.privateLink != Enabled` (the only way to make an HDInsight cluster private is at creation time).
- **Log Analytics** & **App Insights** — have two separate fields (`publicNetworkAccessForIngestion` + `publicNetworkAccessForQuery`). We deny when *either* is not `Disabled`.

---

## Authoring template

To add a new custom definition, copy this skeleton, change the four `<placeholders>`, and save as `Deny-<Service>-Public-Network-Access.json`:

```json
{
  "name": "Deny-<Service>-Public-Network-Access",
  "type": "Microsoft.Authorization/policyDefinitions",
  "apiVersion": "2021-06-01",
  "scope": null,
  "properties": {
    "policyType": "Custom",
    "mode": "All",
    "displayName": "<Service display name> should disable public network access",
    "description": "Disabling public network access improves security by ensuring that <service> is only reachable from a private endpoint.",
    "metadata": {
      "version": "1.0.0",
      "category": "<Category>",
      "source": "https://github.com/bbabcock1990/Deny-All-Azure-PaaS"
    },
    "parameters": {
      "effect": {
        "type": "String",
        "allowedValues": ["Audit", "Deny", "Disabled"],
        "defaultValue": "Deny",
        "metadata": {
          "displayName": "Effect",
          "description": "Enable or disable the execution of the policy"
        }
      }
    },
    "policyRule": {
      "if": {
        "allOf": [
          { "field": "type", "equals": "<ARM type, e.g. Microsoft.X/y>" },
          {
            "anyOf": [
              { "field": "<ARM type>/publicNetworkAccess", "exists": "false" },
              { "field": "<ARM type>/publicNetworkAccess", "notEquals": "Disabled" }
            ]
          }
        ]
      },
      "then": { "effect": "[parameters('effect')]" }
    }
  }
}
```

### Notes on the template

- **`exists: false` guard**: Some resource types omit `publicNetworkAccess` from the payload on creation if not set. We treat *missing* as **not Disabled** so the policy denies it. This matches the ALZ pattern.
- **`scope: null`**: Required by ARM/Bicep `loadJsonContent()` deployment of policy definition objects.
- **`mode: "All"`**: Use this unless you specifically need `Indexed`. `All` covers resource groups and extension resources too.
- **Default effect `Deny`**: Diverges from Microsoft built-ins (which default to `Audit`). Aligns with this repo's intent.

### Verifying the alias

Before authoring, confirm the property alias exists for that resource type:

```bash
az provider show --namespace Microsoft.<Provider> --expand "resourceTypes/aliases" \
  --query "resourceTypes[?resourceType=='<type>'].aliases[?name=='<alias>']"
```

If the alias doesn't exist, you may need to wait for ARM to publish it or use a different field path.

---

## Adding a new gap to the supplemental initiative

After dropping a new `.json` here, wire it up by:

1. Adding a `policyDefinitionReference` entry in `../policy_set_definition_supplemental.json` *(file to be created)*.
2. Adding a matching `nonComplianceMessage` entry so the standard deny message surfaces.
3. Re-running `az deployment mg create` (Bicep) or `terraform apply` (Terraform).

See the top-level `README.md` "Adding new resource types" section for the full procedure.
