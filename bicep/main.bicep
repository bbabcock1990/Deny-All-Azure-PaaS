// =============================================================================
// Deny-All-Azure-PaaS — Bicep implementation
// -----------------------------------------------------------------------------
// Deploys the ALZ "Deny-PublicPaaSEndpoints" initiative + its one custom
// policy dependency at a management group, and assigns it with a custom
// non-compliance / deny message.
//
// Loads source-of-truth JSON from ../policies/ (kept in sync with
// Azure/ALZ-Bicep). Resource NAMES (definition, initiative, assignment) are
// fully customisable via parameters — the underlying policy logic is not
// touched, so re-pulling the ALZ JSON is still a clean upgrade.
// =============================================================================

targetScope = 'managementGroup'

// ---------------------------------------------------------------------------
// Naming (override these to match your org's standards)
// ---------------------------------------------------------------------------
@description('Name of the custom Logic App policy definition (the one ALZ-custom dependency).')
param customPolicyDefinitionName string = 'Deny-LogicApp-Public-Network'

@description('Name of the policy set definition (initiative).')
param initiativeName string = 'Deny-PublicPaaSEndpoints'

@description('Name of the policy assignment. Azure caps assignment names at 24 characters.')
@maxLength(24)
param assignmentName string = 'alz-deny-public-paas'

@description('Display name shown for the assignment in the portal.')
param assignmentDisplayName string = 'Enforce private endpoints across PaaS services (ALZ)'

// ---------------------------------------------------------------------------
// Behaviour
// ---------------------------------------------------------------------------
@description('Custom message returned to the caller when a deployment is denied.')
param nonComplianceMessage string = 'Private Endpoints Must Be Enabled - No Public Access'

@description('Force every bundled policy parameter to the value of `effect`. False (default) respects ALZ initiative defaults — 43 of 45 already default to Deny.')
param overrideEffectsGlobally bool = false

@description('Effect propagated to every bundled policy when overrideEffectsGlobally = true.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effect string = 'Deny'

// ---------------------------------------------------------------------------
// 1. Load the ALZ source files (single source of truth — DO NOT hand-edit)
// ---------------------------------------------------------------------------
var initiativeFile     = loadJsonContent('../policies/policy_set_definition_es_Deny-PublicPaaSEndpoints.json')
var logicAppPolicyFile = loadJsonContent('../policies/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json')

// ---------------------------------------------------------------------------
// 2. Deploy the one custom policy definition the initiative depends on
// ---------------------------------------------------------------------------
resource logicAppPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: customPolicyDefinitionName
  properties: logicAppPolicyFile.properties
}

// ---------------------------------------------------------------------------
// 3. Resolve the initiative's policyDefinitions[] references.
//   The ALZ source references the custom Logic App policy via the literal
//   string "/policyDefinitions/Deny-LogicApp-Public-Network". Whenever we
//   spot that suffix, swap the entire URL for the deployed resource's actual
//   .id — which handles BOTH the MG-placeholder substitution AND any rename
//   via `customPolicyDefinitionName`.
// ---------------------------------------------------------------------------
var alzCustomPolicySuffix = '/policyDefinitions/Deny-LogicApp-Public-Network'

var resolvedPolicyDefs = [for p in initiativeFile.properties.policyDefinitions: {
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
  policyDefinitionId: endsWith(p.policyDefinitionId, alzCustomPolicySuffix) ? logicAppPolicy.id : p.policyDefinitionId
  parameters: p.parameters
  groupNames: p.groupNames
  definitionVersion: p.definitionVersion
}]

// ---------------------------------------------------------------------------
// 4. Deploy the initiative as a custom policy set
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
  dependsOn: [
    logicAppPolicy
  ]
}

// ---------------------------------------------------------------------------
// 5. Optional global effect override — { paramName: { value: effect } }
// ---------------------------------------------------------------------------
var globalEffectOverrides = toObject(
  items(initiativeFile.properties.parameters),
  p => p.key,
  p => { value: effect }
)

// ---------------------------------------------------------------------------
// 6. Per-reference non-compliance messages
//   (initiative assignments only surface the deny message when each entry
//   includes a policyDefinitionReferenceId — so we emit one per bundled policy)
// ---------------------------------------------------------------------------
var nonComplianceMessageList = [for p in initiativeFile.properties.policyDefinitions: {
  message: nonComplianceMessage
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
}]

// ---------------------------------------------------------------------------
// 7. Assignment carrying the custom deny message
// ---------------------------------------------------------------------------
resource assignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: assignmentName
  properties: {
    displayName: assignmentDisplayName
    description: 'Blocks deployment of Azure PaaS services that allow public network access. Wraps the Azure Landing Zones Deny-PublicPaaSEndpoints initiative.'
    policyDefinitionId: initiative.id
    enforcementMode: 'Default'
    parameters: overrideEffectsGlobally ? globalEffectOverrides : {}
    nonComplianceMessages: nonComplianceMessageList
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output customLogicAppPolicyId string = logicAppPolicy.id
output initiativeId            string = initiative.id
output assignmentId            string = assignment.id
output bundledPolicyCount      int    = length(initiativeFile.properties.policyDefinitions)
output denialMessage           string = nonComplianceMessage
