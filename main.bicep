// =============================================================================
// Wrapper: deploy the ALZ "Deny-PublicPaaSEndpoints" initiative + its one
// custom policy dependency, and assign it with a custom deny message.
// -----------------------------------------------------------------------------
// Files consumed (must sit next to this .bicep):
//   ./policy_set_definition_es_Deny-PublicPaaSEndpoints.json
//   ./policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json
//
// Both files are pulled verbatim from
//   https://github.com/Azure/ALZ-Bicep  (infra-as-code/bicep/modules/policy)
//
// Re-running this template after updating those two JSON files is the upgrade
// path — no rule rewriting required.
// =============================================================================

targetScope = 'managementGroup'

@description('Custom message returned to the caller when a deployment is denied.')
param nonComplianceMessage string = 'Private Endpoints Must Be Enabled - No Public Access'

@description('Name of the policy assignment.')
param assignmentName string = 'enforce-private-endpoints-paas'

@description('Display name shown for the assignment.')
param assignmentDisplayName string = 'Enforce private endpoints across PaaS services (ALZ)'

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
// 1. Load the ALZ source files (source of truth)
// ---------------------------------------------------------------------------
var initiativeFile      = loadJsonContent('./policy_set_definition_es_Deny-PublicPaaSEndpoints.json')
var logicAppPolicyFile  = loadJsonContent('./policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json')

// ---------------------------------------------------------------------------
// 2. Deploy the one custom policy definition the initiative depends on
// ---------------------------------------------------------------------------
resource logicAppPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: logicAppPolicyFile.name
  properties: logicAppPolicyFile.properties
}

// ---------------------------------------------------------------------------
// 3. Resolve the ${varTargetManagementGroupResourceId} placeholder embedded
//    in the initiative's policyDefinitions[] entries.
// ---------------------------------------------------------------------------
var mgResourceIdPlaceholder = '\${varTargetManagementGroupResourceId}'
var targetMgResourceId      = managementGroup().id

var resolvedPolicyDefs = [for p in initiativeFile.properties.policyDefinitions: {
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
  policyDefinitionId: replace(p.policyDefinitionId, mgResourceIdPlaceholder, targetMgResourceId)
  parameters: p.parameters
  groupNames: p.groupNames
  definitionVersion: p.definitionVersion
}]

// ---------------------------------------------------------------------------
// 4. Deploy the initiative as a custom policy set
// ---------------------------------------------------------------------------
resource initiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: initiativeFile.name
  properties: {
    displayName: initiativeFile.properties.displayName
    description: initiativeFile.properties.description
    policyType: 'Custom'
    metadata: initiativeFile.properties.metadata
    parameters: initiativeFile.properties.parameters
    policyDefinitions: resolvedPolicyDefs
    policyDefinitionGroups: initiativeFile.properties.policyDefinitionGroups
  }
  dependsOn: [
    logicAppPolicy
  ]
}

// ---------------------------------------------------------------------------
// 5. Build optional global effect overrides — { paramName: { value: effect } }
// ---------------------------------------------------------------------------
var globalEffectOverrides = toObject(
  items(initiativeFile.properties.parameters),
  p => p.key,
  p => { value: effect }
)

// ---------------------------------------------------------------------------
// 6. Build per-reference non-compliance messages
//    (initiative assignments only surface the deny message when each entry
//     includes a policyDefinitionReferenceId).
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
