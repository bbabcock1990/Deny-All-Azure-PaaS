# =============================================================================
# Deny-All-Azure-PaaS — Supplemental Terraform implementation
# -----------------------------------------------------------------------------
# Mirrors bicep/supplemental.bicep:
#   1. Discovers every Deny-*.json file in ../../policies/custom-definitions/
#   2. Deploys each as a custom policy definition at the management group
#   3. Loads the supplemental initiative manifest from ../../policies/
#   4. Builds the initiative referencing the deployed custom definitions
#      (lookup keyed by original JSON name == policyDefinitionReferenceId, so
#      renaming via the prefix variable flows through automatically).
#   5. Assigns the initiative at the target management group with the standard
#      non-compliance / deny message replicated per bundled reference.
# =============================================================================

locals {
  policies_root           = "${path.module}/../../policies"
  custom_definitions_root = "${local.policies_root}/custom-definitions"

  # Discover every custom definition file. Glob pattern matches every
  # Deny-*.json in custom-definitions/. Adding a new gap = drop a new JSON
  # file alongside the others and add a reference in the initiative manifest.
  custom_def_files = fileset(local.custom_definitions_root, "Deny-*.json")

  # Map: original definition name -> parsed JSON object
  custom_defs = {
    for f in local.custom_def_files :
    jsondecode(file("${local.custom_definitions_root}/${f}")).name => jsondecode(file("${local.custom_definitions_root}/${f}"))
  }

  # Supplemental initiative manifest
  initiative_raw = jsondecode(file("${local.policies_root}/policy_set_definition_supplemental.json"))

  # Target MG resource ID (Terraform-native form)
  management_group_resource_id = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"

  # Resolve every policy reference to the deployed custom definition's ID.
  # Keyed by policyDefinitionReferenceId which equals the original JSON name.
  resolved_policy_refs = [
    for p in local.initiative_raw.properties.policyDefinitions : {
      reference_id         = p.policyDefinitionReferenceId
      policy_definition_id = azurerm_policy_definition.custom[p.policyDefinitionReferenceId].id
      parameters           = lookup(p, "parameters", {})
    }
  ]
}

# ---------------------------------------------------------------------------
# 1. Deploy each custom policy definition
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "custom" {
  for_each = local.custom_defs

  name                = "${var.custom_policy_definition_name_prefix}${each.value.name}"
  policy_type         = "Custom"
  mode                = each.value.properties.mode
  display_name        = each.value.properties.displayName
  description         = each.value.properties.description
  management_group_id = local.management_group_resource_id

  metadata    = jsonencode(each.value.properties.metadata)
  parameters  = jsonencode(each.value.properties.parameters)
  policy_rule = jsonencode(each.value.properties.policyRule)
}

# ---------------------------------------------------------------------------
# 2. Supplemental initiative (policy set definition)
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
    }
  }

  depends_on = [azurerm_policy_definition.custom]
}

# ---------------------------------------------------------------------------
# 3. Assignment with the custom deny message
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "this" {
  name                 = var.assignment_name
  policy_definition_id = azurerm_policy_set_definition.this.id
  management_group_id  = local.management_group_resource_id
  display_name         = var.assignment_display_name
  description          = "Blocks deployment of Azure PaaS services (gap services not covered by the ALZ Deny-PublicPaaSEndpoints initiative) that allow public network access."
  enforce              = true

  parameters = jsonencode({
    effect = { value = var.effect }
  })

  dynamic "non_compliance_message" {
    for_each = local.initiative_raw.properties.policyDefinitions
    content {
      content                        = var.non_compliance_message
      policy_definition_reference_id = non_compliance_message.value.policyDefinitionReferenceId
    }
  }
}
