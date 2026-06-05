// =============================================================================
// Simple test — Deny public network access on Storage Accounts
//
// Deploys one custom Azure Policy + one assignment at the subscription scope
// that blocks creation of Microsoft.Storage/storageAccounts whose
// `publicNetworkAccess` is anything other than `Disabled`.
//
// Anyone whose deployment is blocked sees the custom non-compliance message
// (configurable via the `nonComplianceMessage` parameter).
//
// Deploy:
//   az deployment sub create \
//     --location eastus \
//     --template-file deny-storage-public.bicep
//
// See README.md in this folder for the full walkthrough + test commands.
// =============================================================================

targetScope = 'subscription'

@description('Name of the custom policy definition.')
param policyName string = 'deny-storage-public-network-access'

@description('Name of the policy assignment.')
param assignmentName string = 'deny-storage-public'

@description('Display name shown in the Azure Policy portal.')
param policyDisplayName string = 'Storage accounts must disable public network access'

@description('Non-compliance message shown to anyone whose deployment is blocked.')
param nonComplianceMessage string = 'Private Endpoints Must Be Enabled - No Public Access'

@description('Effect for the policy. Use Audit for a soft rollout before enabling Deny.')
@allowed([
  'Deny'
  'Audit'
  'Disabled'
])
param effect string = 'Deny'

resource definition 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: policyName
  properties: {
    displayName: policyDisplayName
    description: 'Denies creation of Storage Accounts that allow public network access. Use Private Endpoints instead.'
    policyType: 'Custom'
    mode: 'All'
    metadata: {
      category: 'Storage'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: effect
        allowedValues: [
          'Deny'
          'Audit'
          'Disabled'
        ]
        metadata: {
          displayName: 'Effect'
          description: 'Enable or disable enforcement of the policy.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Storage/storageAccounts'
          }
          {
            field: 'Microsoft.Storage/storageAccounts/publicNetworkAccess'
            notEquals: 'Disabled'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

resource assignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: assignmentName
  properties: {
    displayName: policyDisplayName
    description: 'Enforces Private Endpoint usage for all new Storage Accounts in this subscription.'
    enforcementMode: 'Default'
    policyDefinitionId: definition.id
    parameters: {
      effect: {
        value: effect
      }
    }
    nonComplianceMessages: [
      {
        message: nonComplianceMessage
      }
    ]
  }
}

output policyDefinitionId string = definition.id
output assignmentId string = assignment.id
output effect string = effect
output nonComplianceMessage string = nonComplianceMessage
