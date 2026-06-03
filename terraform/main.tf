# =============================================================================
# Deny-All-Azure-PaaS — Terraform implementation
# -----------------------------------------------------------------------------
# Mirrors bicep/main.bicep:
#   1. Loads the ALZ source JSON from ../policies/
#   2. Deploys the one custom Logic App policy definition
#   3. Resolves the ${varTargetManagementGroupResourceId} placeholder by
#      substituting the deployed definition's actual ID wherever the suffix
#      "/policyDefinitions/Deny-LogicApp-Public-Network" appears.
#   4. Deploys the initiative referencing 44 built-ins + the custom policy
#   5. Assigns the initiative at the target management group with a custom
#      deny / non-compliance message replicated per bundled policy reference.
# =============================================================================

locals {
  # ---- Source-of-truth ALZ files (DO NOT hand-edit) ----
  initiative_raw   = jsondecode(file("${path.module}/../policies/policy_set_definition_es_Deny-PublicPaaSEndpoints.json"))
  logic_app_policy = jsondecode(file("${path.module}/../policies/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json"))

  # Target MG resource ID (Terraform-native form)
  management_group_resource_id = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"

  # ALZ-source suffix that identifies the custom Logic App policy reference
  alz_custom_policy_suffix = "/policyDefinitions/Deny-LogicApp-Public-Network"

  # Resolve every policy reference: when the URL ends with the ALZ custom
  # policy suffix, swap it for the actual deployed resource ID; otherwise
  # leave the built-in reference alone.
  resolved_policy_refs = [
    for p in local.initiative_raw.properties.policyDefinitions : {
      reference_id         = p.policyDefinitionReferenceId
      policy_definition_id = endswith(p.policyDefinitionId, local.alz_custom_policy_suffix) ? azurerm_policy_definition.logic_app.id : p.policyDefinitionId
      parameters           = lookup(p, "parameters", {})
      version              = lookup(p, "definitionVersion", null)
    }
  ]

  # Optional global override — { paramName = { value = effect } }
  global_effect_overrides = {
    for k in keys(local.initiative_raw.properties.parameters) :
    k => { value = var.effect }
  }
}

# ---------------------------------------------------------------------------
# 1. Custom Logic App policy definition
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "logic_app" {
  name                = var.custom_policy_definition_name
  policy_type         = "Custom"
  mode                = local.logic_app_policy.properties.mode
  display_name        = local.logic_app_policy.properties.displayName
  description         = local.logic_app_policy.properties.description
  management_group_id = local.management_group_resource_id

  metadata    = jsonencode(local.logic_app_policy.properties.metadata)
  parameters  = jsonencode(local.logic_app_policy.properties.parameters)
  policy_rule = jsonencode(local.logic_app_policy.properties.policyRule)
}

# ---------------------------------------------------------------------------
# 2. Initiative (policy set definition)
# ---------------------------------------------------------------------------
resource "azurerm_policy_set_definition" "this" {
  name                = var.initiative_name
  policy_type         = "Custom"
  display_name        = local.initiative_raw.properties.displayName
  description         = local.initiative_raw.properties.description
  management_group_id = local.management_group_resource_id

  metadata   = jsonencode(local.initiative_raw.properties.metadata)
  parameters = jsonencode(local.initiative_raw.properties.parameters)

  dynamic "policy_definition_reference" {
    for_each = local.resolved_policy_refs
    content {
      reference_id         = policy_definition_reference.value.reference_id
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      parameter_values     = jsonencode(policy_definition_reference.value.parameters)
      version              = policy_definition_reference.value.version
    }
  }

  depends_on = [azurerm_policy_definition.logic_app]
}

# ---------------------------------------------------------------------------
# 3. Assignment with the custom deny message
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "this" {
  name                 = var.assignment_name
  policy_definition_id = azurerm_policy_set_definition.this.id
  management_group_id  = local.management_group_resource_id
  display_name         = var.assignment_display_name
  description          = "Blocks deployment of Azure PaaS services that allow public network access. Wraps the Azure Landing Zones Deny-PublicPaaSEndpoints initiative."
  enforce              = true

  parameters = var.override_effects_globally ? jsonencode(local.global_effect_overrides) : null

  dynamic "non_compliance_message" {
    for_each = local.initiative_raw.properties.policyDefinitions
    content {
      content                        = var.non_compliance_message
      policy_definition_reference_id = non_compliance_message.value.policyDefinitionReferenceId
    }
  }
}
