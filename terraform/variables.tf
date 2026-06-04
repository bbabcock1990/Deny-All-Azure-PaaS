# ---------------------------------------------------------------------------
# Target scope
# ---------------------------------------------------------------------------
variable "management_group_id" {
  type        = string
  description = "Name (not display name) of the management group where the policy artefacts and assignment will be created."
}

# ---------------------------------------------------------------------------
# Naming (override these to match your org's standards)
# ---------------------------------------------------------------------------
variable "logic_app_policy_definition_name" {
  type        = string
  description = "Name of the custom ALZ Logic App policy definition."
  default     = "Deny-LogicApp-Public-Network"
}

variable "custom_policy_definition_name_prefix" {
  type        = string
  description = "Prefix prepended to each supplemental custom policy definition name. Leave empty to use names as authored in custom-definitions/."
  default     = ""
}

variable "initiative_name" {
  type        = string
  description = "Name of the policy set definition (combined initiative)."
  default     = "Deny-PublicPaaSEndpoints"
}

variable "assignment_name" {
  type        = string
  description = "Name of the policy assignment. Azure caps assignment names at 24 characters."
  default     = "deny-all-public-paas"

  validation {
    condition     = length(var.assignment_name) <= 24
    error_message = "assignment_name must be 24 characters or fewer (Azure limit)."
  }
}

variable "assignment_display_name" {
  type        = string
  description = "Display name shown for the assignment in the portal."
  default     = "Enforce private endpoints across all PaaS services (62)"
}

# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------
variable "non_compliance_message" {
  type        = string
  description = "Custom message returned to the caller when a deployment is denied."
  default     = "Private Endpoints Must Be Enabled - No Public Access"
}

variable "override_effects_globally" {
  type        = bool
  description = "Force every bundled policy parameter to the value of `effect`. False (default) respects ALZ initiative defaults (43 of 45 are Deny) AND uses `effect` only for the 17 supplemental policies."
  default     = false
}

variable "effect" {
  type        = string
  description = "Effect applied to the 17 supplemental policies always, and to ALL 62 policies when override_effects_globally = true."
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect)
    error_message = "effect must be one of: Audit, Deny, Disabled."
  }
}
