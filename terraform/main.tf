# =============================================================================
# Deny-All-Azure-PaaS — Combined Terraform implementation
# -----------------------------------------------------------------------------
# Mirrors bicep/main.bicep:
#   1. Loads the combined initiative manifest from ../policies/
#   2. Deploys the ALZ custom Logic App policy definition
#   3. Discovers + deploys every Deny-*.json in ../policies/custom-definitions/
#      (17 supplemental custom policies — fileset() means adding a new gap
#       definition needs zero Terraform edits)
#   4. Resolves every initiative reference URL:
#        * built-ins                       -> as-is
#        * ALZ Logic App custom            -> deployed .id
#        * supplemental custom (by name)   -> deployed .id (lookup)
#   5. Deploys the combined initiative
#   6. Assigns it at the target MG with the custom deny message replicated
#      per bundled reference
# =============================================================================

locals {
  policies_root            = "${path.module}/../policies"
  custom_definitions_root  = "${local.policies_root}/custom-definitions"

  # ----- Source-of-truth files -----
  initiative_raw   = jsondecode(file("${local.policies_root}/policy_set_definition.json"))
  logic_app_policy = jsondecode(file("${local.policies_root}/policy_definitions/policy_definition_es_Deny-LogicApp-Public-Network.json"))

  # ----- Discover supplemental custom definitions -----
  # Glob picks up every Deny-*.json in custom-definitions/. Adding a new gap
  # definition = drop a JSON file alongside the others and add a reference in
  # policies/policy_set_definition.json. No Terraform edits needed.
  custom_def_files = fileset(local.custom_definitions_root, "Deny-*.json")
  custom_defs = {
    for f in local.custom_def_files :
    jsondecode(file("${local.custom_definitions_root}/${f}")).name => jsondecode(file("${local.custom_definitions_root}/${f}"))
  }

  # ----- Target MG resource ID (Terraform-native form) -----
  management_group_resource_id = "/providers/Microsoft.Management/managementGroups/${var.management_group_id}"

  # ----- Resolution rules for initiative references -----
  alz_logic_app_suffix    = "/policyDefinitions/Deny-LogicApp-Public-Network"
  supplemental_policy_set = keys(local.custom_defs)

  resolved_policy_refs = [
    for p in local.initiative_raw.properties.policyDefinitions : {
      reference_id = p.policyDefinitionReferenceId
      policy_definition_id = (
        contains(local.supplemental_policy_set, p.policyDefinitionReferenceId)
          ? azurerm_policy_definition.supplemental[p.policyDefinitionReferenceId].id
          : (endswith(p.policyDefinitionId, local.alz_logic_app_suffix)
              ? azurerm_policy_definition.logic_app.id
              : p.policyDefinitionId)
      )
      parameters = lookup(p, "parameters", {})
      version    = lookup(p, "definitionVersion", null)
    }
  ]

  # Optional global override — every initiative param set to var.effect
  global_effect_overrides = {
    for k in keys(local.initiative_raw.properties.parameters) :
    k => { value = var.effect }
  }

  # Default assignment parameters — only the supplemental `effect` is set;
  # the 45 ALZ params fall through to their initiative defaults.
  default_assignment_parameters = {
    effect = { value = var.effect }
  }
}

# ---------------------------------------------------------------------------
# 1. ALZ custom Logic App policy definition
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "logic_app" {
  name                = var.logic_app_policy_definition_name
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
# 2. Supplemental custom policy definitions (17 from custom-definitions/)
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "supplemental" {
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
# 3. Combined initiative (policy set definition)
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

  depends_on = [
    azurerm_policy_definition.logic_app,
    azurerm_policy_definition.supplemental,
  ]
}

# ---------------------------------------------------------------------------
# 4. Assignment with the custom deny message
# ---------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "this" {
  name                 = var.assignment_name
  policy_definition_id = azurerm_policy_set_definition.this.id
  management_group_id  = local.management_group_resource_id
  display_name         = var.assignment_display_name
  description          = "Blocks deployment of Azure PaaS services that allow public network access. Combined ALZ + supplemental initiative covering 62 services."
  enforce              = true

  parameters = jsonencode(
    var.override_effects_globally ? local.global_effect_overrides : local.default_assignment_parameters
  )

  dynamic "non_compliance_message" {
    for_each = local.initiative_raw.properties.policyDefinitions
    content {
      content                        = var.non_compliance_message
      policy_definition_reference_id = non_compliance_message.value.policyDefinitionReferenceId
    }
  }
}
