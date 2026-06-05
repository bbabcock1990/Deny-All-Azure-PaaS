# =============================================================================
# Simple test - Deny public network access on Storage Accounts (Terraform)
#
# Mirrors bicep/deny-storage-public.bicep exactly:
#   - Creates one custom policy definition that denies creation of
#     Microsoft.Storage/storageAccounts whose publicNetworkAccess is not
#     "Disabled".
#   - Creates one subscription-scoped assignment carrying the custom
#     non-compliance message.
#
# Deploy:
#   terraform init
#   terraform apply
# =============================================================================

data "azurerm_subscription" "current" {}

resource "azurerm_policy_definition" "deny_storage_public" {
  name         = var.policy_name
  policy_type  = "Custom"
  mode         = "All"
  display_name = var.policy_display_name
  description  = "Denies creation of Storage Accounts that allow public network access. Use Private Endpoints instead."

  metadata = jsonencode({
    category = "Storage"
    version  = "1.0.0"
  })

  parameters = jsonencode({
    effect = {
      type          = "String"
      defaultValue  = var.effect
      allowedValues = ["Deny", "Audit", "Disabled"]
      metadata = {
        displayName = "Effect"
        description = "Enable or disable enforcement of the policy."
      }
    }
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Storage/storageAccounts"
        },
        {
          field     = "Microsoft.Storage/storageAccounts/publicNetworkAccess"
          notEquals = "Disabled"
        }
      ]
    }
    then = {
      effect = "[parameters('effect')]"
    }
  })
}

resource "azurerm_subscription_policy_assignment" "deny_storage_public" {
  name                 = var.assignment_name
  display_name         = var.policy_display_name
  description          = "Enforces Private Endpoint usage for all new Storage Accounts in this subscription."
  policy_definition_id = azurerm_policy_definition.deny_storage_public.id
  subscription_id      = data.azurerm_subscription.current.id
  enforce              = true

  parameters = jsonencode({
    effect = {
      value = var.effect
    }
  })

  non_compliance_message {
    content = var.non_compliance_message
  }
}
