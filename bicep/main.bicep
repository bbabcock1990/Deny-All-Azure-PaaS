// =============================================================================
// Deny-All-Azure-PaaS — Combined Bicep implementation
// -----------------------------------------------------------------------------
// Deploys ONE unified initiative covering all 62 PaaS services:
//   * 44 built-in Microsoft policies (referenced by URL, no deployment needed)
//   * 1  custom ALZ policy (LogicApp)            — deployed from ../policies/policy_definitions/
//   * 17 custom supplemental policies (gap coverage) — deployed from ../policies/custom-definitions/
//
// All 18 custom definitions are deployed first, then the combined initiative
// is deployed referencing them, then the assignment is created with the
// custom non-compliance / deny message.
//
// Source-of-truth JSON lives in ../policies/ — re-pulling upstream ALZ updates
// or adding more gap definitions does not require any edits to this file
// (aside from one loadJsonContent line per new gap definition).
// =============================================================================

targetScope = 'managementGroup'

// ---------------------------------------------------------------------------
// Naming (override these to match your org's standards)
// ---------------------------------------------------------------------------
@description('Name of the custom ALZ Logic App policy definition.')
param logicAppPolicyDefinitionName string = 'Deny-LogicApp-Public-Network'

@description('Prefix prepended to each supplemental custom policy definition name. Leave empty to use the names as defined in the JSON files (e.g. "Deny-SignalR-Public-Network-Access").')
param customPolicyDefinitionNamePrefix string = ''

@description('Name of the policy set definition (combined initiative).')
param initiativeName string = 'Deny-PublicPaaSEndpoints'

@description('Name of the policy assignment. Azure caps assignment names at 24 characters.')
@maxLength(24)
param assignmentName string = 'deny-all-public-paas'

@description('Display name shown for the assignment in the portal.')
param assignmentDisplayName string = 'Enforce private endpoints across all PaaS services (62)'

// ---------------------------------------------------------------------------
// Behaviour
// ---------------------------------------------------------------------------
@description('Custom message returned to the caller when a deployment is denied.')
param nonComplianceMessage string = 'Private Endpoints Must Be Enabled - No Public Access'

@description('Force every bundled policy parameter to the value of `effect`. False (default) respects ALZ initiative defaults (43 of 45 default to Deny) AND uses `effect` only for the 17 supplemental policies.')
param overrideEffectsGlobally bool = false

@description('Effect applied to the 17 supplemental policies always, and to ALL 62 policies when overrideEffectsGlobally = true.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effect string = 'Deny'

// ---------------------------------------------------------------------------
// 1. Load combined initiative + every custom definition source file.
//   loadJsonContent() requires a literal path — adding a new gap definition
//   means appending one line to supplementalCustomDefs AND adding a reference
//   in policies/policy_set_definition.json.
// ---------------------------------------------------------------------------
var initiativeFile     = loadJsonContent('../policies/policy_set_definition.json')
var logicAppPolicyFile = loadJsonContent('../policies/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json')

var supplementalCustomDefs = [
  loadJsonContent('../policies/custom-definitions/Deny-SignalR-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-WebPubSub-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-IoTHub-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-IoTDps-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-Purview-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-HealthcareApis-Services-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-HealthDataServices-Workspace-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-HealthDataServices-FHIR-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-HealthDataServices-DICOM-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-StaticWebApps-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-Relay-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-HDInsight-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-CommunicationServices-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-DigitalTwins-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-VideoIndexer-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-LogAnalytics-Public-Network-Access.json')
  loadJsonContent('../policies/custom-definitions/Deny-AppInsights-Public-Network-Access.json')
]

// ---------------------------------------------------------------------------
// 2. Deploy the one ALZ custom policy (Logic App)
// ---------------------------------------------------------------------------
resource logicAppPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: logicAppPolicyDefinitionName
  properties: logicAppPolicyFile.properties
}

// ---------------------------------------------------------------------------
// 3. Deploy the 17 supplemental custom policy definitions
//   Deployed name = {prefix}{originalName}; originalName is preserved for
//   the lookup in step 4 so renames flow through automatically.
// ---------------------------------------------------------------------------
resource supplementalPolicies 'Microsoft.Authorization/policyDefinitions@2023-04-01' = [for (d, i) in supplementalCustomDefs: {
  name: '${customPolicyDefinitionNamePrefix}${d.name}'
  properties: d.properties
}]

// ---------------------------------------------------------------------------
// 4. Build a name→deployedId lookup for supplemental custom defs.
//   Keyed by ORIGINAL JSON name (= the policyDefinitionReferenceId used in
//   the combined initiative). The indirection means renaming via
//   customPolicyDefinitionNamePrefix automatically still resolves.
// ---------------------------------------------------------------------------
var supplementalLookupEntries = [for (d, i) in supplementalCustomDefs: {
  name: d.name
  id: supplementalPolicies[i].id
}]
var supplementalIdLookup = toObject(supplementalLookupEntries, e => e.name, e => e.id)

var supplementalPolicyNames = [for d in supplementalCustomDefs: d.name]

// ---------------------------------------------------------------------------
// 5. Resolve every initiative reference URL:
//   * ALZ supplied references to built-ins                  → use as-is
//   * Reference to the ALZ Logic App custom                 → swap for deployed .id
//   * Reference to a supplemental custom                    → swap for deployed .id (lookup)
// ---------------------------------------------------------------------------
var alzLogicAppSuffix = '/policyDefinitions/Deny-LogicApp-Public-Network'

var resolvedPolicyDefs = [for p in initiativeFile.properties.policyDefinitions: {
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
  policyDefinitionId: contains(supplementalPolicyNames, p.policyDefinitionReferenceId)
    ? supplementalIdLookup[p.policyDefinitionReferenceId]
    : (endsWith(p.policyDefinitionId, alzLogicAppSuffix) ? logicAppPolicy.id : p.policyDefinitionId)
  parameters: p.parameters
  groupNames: p.?groupNames ?? []
  definitionVersion: p.?definitionVersion
}]

// ---------------------------------------------------------------------------
// 6. Deploy the combined initiative as a custom policy set
// ---------------------------------------------------------------------------
resource initiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: initiativeName
  properties: {
    displayName: initiativeFile.properties.displayName
    description: initiativeFile.properties.description
    policyType: 'Custom'
    metadata: initiativeFile.properties.metadata
    parameters: initiativeFile.properties.parameters
    policyDefinitions: resolvedPolicyDefs
    policyDefinitionGroups: initiativeFile.properties.?policyDefinitionGroups ?? []
  }
}

// ---------------------------------------------------------------------------
// 7. Assignment parameters
//   Default mode: pass only `effect` (applies to the 17 supplementals).
//                 The 45 ALZ params fall through to initiative defaults.
//   Override mode: set every initiative parameter to `effect`.
// ---------------------------------------------------------------------------
var globalEffectOverrides = toObject(
  items(initiativeFile.properties.parameters),
  p => p.key,
  p => { value: effect }
)

var defaultAssignmentParameters = {
  effect: {
    value: effect
  }
}

// ---------------------------------------------------------------------------
// 8. Per-reference non-compliance messages (initiative assignments only
//   surface the deny message when each bundled reference is named explicitly)
// ---------------------------------------------------------------------------
var nonComplianceMessageList = [for p in initiativeFile.properties.policyDefinitions: {
  message: nonComplianceMessage
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
}]

// ---------------------------------------------------------------------------
// 9. Assignment carrying the custom deny message
// ---------------------------------------------------------------------------
resource assignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: assignmentName
  properties: {
    displayName: assignmentDisplayName
    description: 'Blocks deployment of Azure PaaS services that allow public network access. Combined ALZ + supplemental initiative covering 62 services.'
    policyDefinitionId: initiative.id
    enforcementMode: 'Default'
    parameters: overrideEffectsGlobally ? globalEffectOverrides : defaultAssignmentParameters
    nonComplianceMessages: nonComplianceMessageList
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output logicAppPolicyId          string = logicAppPolicy.id
output supplementalPolicyIds     array  = [for (d, i) in supplementalCustomDefs: supplementalPolicies[i].id]
output initiativeId              string = initiative.id
output assignmentId              string = assignment.id
output bundledPolicyCount        int    = length(initiativeFile.properties.policyDefinitions)
output denialMessage             string = nonComplianceMessage
