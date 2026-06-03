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
variable "custom_policy_definition_name" {
  type        = string
  description = "Name of the custom Logic App policy definition (the one ALZ-custom dependency)."
  default     = "Deny-LogicApp-Public-Network"
}

variable "initiative_name" {
  type        = string
  description = "Name of the policy set definition (initiative)."
  default     = "Deny-PublicPaaSEndpoints"
}

variable "assignment_name" {
  type        = string
  description = "Name of the policy assignment. Azure caps assignment names at 24 characters."
  default     = "alz-deny-public-paas"

  validation {
    condition     = length(var.assignment_name) <= 24
    error_message = "assignment_name must be 24 characters or fewer (Azure limit)."
  }
}

variable "assignment_display_name" {
  type        = string
  description = "Display name shown for the assignment in the portal."
  default     = "Enforce private endpoints across PaaS services (ALZ)"
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
  description = "Force every bundled policy parameter to the value of `effect`. False (default) respects ALZ initiative defaults — 43 of 45 already default to Deny."
  default     = false
}

variable "effect" {
  type        = string
  description = "Effect propagated to every bundled policy when override_effects_globally = true."
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect)
    error_message = "effect must be one of: Audit, Deny, Disabled."
  }
}
