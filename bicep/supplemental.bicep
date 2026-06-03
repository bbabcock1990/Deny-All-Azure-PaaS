// =============================================================================
// Deny-All-Azure-PaaS — Supplemental Bicep implementation
// -----------------------------------------------------------------------------
// Deploys 17 custom policy definitions (covering gaps in the ALZ
// Deny-PublicPaaSEndpoints initiative) + a supplemental initiative bundling
// them + an assignment carrying the standard non-compliance message.
//
// Source-of-truth JSON lives in ../policies/custom-definitions/ and
// ../policies/policy_set_definition_supplemental.json.
//
// Resource NAMES (definition prefix, initiative, assignment) are fully
// customisable via parameters.
// =============================================================================

targetScope = 'managementGroup'

// ---------------------------------------------------------------------------
// Naming (override these to match your org's standards)
// ---------------------------------------------------------------------------
@description('Prefix prepended to each custom policy definition name. Leave empty to use the names as defined in the JSON files (e.g. "Deny-SignalR-Public-Network-Access").')
param customPolicyDefinitionNamePrefix string = ''

@description('Name of the supplemental policy set definition (initiative).')
param initiativeName string = 'Deny-PublicPaaSEndpoints-Supplemental'

@description('Name of the policy assignment. Azure caps assignment names at 24 characters.')
@maxLength(24)
param assignmentName string = 'deny-pna-supplemental'

@description('Display name shown for the assignment in the portal.')
param assignmentDisplayName string = 'Enforce private endpoints across PaaS services (Supplemental)'

// ---------------------------------------------------------------------------
// Behaviour
// ---------------------------------------------------------------------------
@description('Custom message returned to the caller when a deployment is denied.')
param nonComplianceMessage string = 'Private Endpoints Must Be Enabled - No Public Access'

@description('Effect propagated to every bundled custom policy.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effect string = 'Deny'

// ---------------------------------------------------------------------------
// 1. Load the supplemental initiative and every custom definition.
//   loadJsonContent() requires a literal path, so the 17 files are listed
//   explicitly. Adding a new gap = add one loadJsonContent line and one entry
//   in policy_set_definition_supplemental.json.
// ---------------------------------------------------------------------------
var initiativeFile = loadJsonContent('../policies/policy_set_definition_supplemental.json')

var customDefs = [
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
// 2. Deploy the 17 custom policy definitions
//   The deployed name is {prefix}{originalName}; the originalName is preserved
//   so the lookup in step 3 keeps working even after a rename.
// ---------------------------------------------------------------------------
resource customPolicies 'Microsoft.Authorization/policyDefinitions@2023-04-01' = [for (d, i) in customDefs: {
  name: '${customPolicyDefinitionNamePrefix}${d.name}'
  properties: d.properties
}]

// ---------------------------------------------------------------------------
// 3. Build a name→id lookup keyed by the ORIGINAL JSON name (= the
//   policyDefinitionReferenceId used in the initiative). This indirection
//   means renaming via customPolicyDefinitionNamePrefix automatically flows
//   through — the initiative still references the right deployed resource.
// ---------------------------------------------------------------------------
var customPolicyLookupEntries = [for (d, i) in customDefs: {
  name: d.name
  id: customPolicies[i].id
}]

var customPolicyIdLookup = toObject(customPolicyLookupEntries, e => e.name, e => e.id)

// ---------------------------------------------------------------------------
// 4. Resolve every initiative reference to the deployed custom-definition ID.
//   We ignore the placeholder URL in the JSON entirely and look up by
//   policyDefinitionReferenceId (which equals the original definition name).
// ---------------------------------------------------------------------------
var resolvedPolicyDefs = [for p in initiativeFile.properties.policyDefinitions: {
  policyDefinitionReferenceId: p.policyDefinitionReferenceId
  policyDefinitionId: customPolicyIdLookup[p.policyDefinitionReferenceId]
  parameters: p.parameters
  groupNames: p.?groupNames ?? []
}]

// ---------------------------------------------------------------------------
// 5. Deploy the supplemental initiative as a custom policy set
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
    customPolicies
  ]
}

// ---------------------------------------------------------------------------
// 6. Per-reference non-compliance messages (one per bundled policy, required
//   for initiative assignments to surface the deny message to callers)
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
    description: 'Blocks deployment of Azure PaaS services (gap services not covered by the ALZ Deny-PublicPaaSEndpoints initiative) that allow public network access.'
    policyDefinitionId: initiative.id
    enforcementMode: 'Default'
    parameters: {
      effect: { value: effect }
    }
    nonComplianceMessages: nonComplianceMessageList
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output initiativeId           string   = initiative.id
output assignmentId           string   = assignment.id
output customPolicyDefinitionIds array  = [for (d, i) in customDefs: customPolicies[i].id]
output bundledPolicyCount     int      = length(customDefs)
output denialMessage          string   = nonComplianceMessage
