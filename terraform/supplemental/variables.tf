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
variable "custom_policy_definition_name_prefix" {
  type        = string
  description = "Prefix prepended to each custom policy definition name. Leave empty to use the names defined in the JSON files (e.g. 'Deny-SignalR-Public-Network-Access')."
  default     = ""
}

variable "initiative_name" {
  type        = string
  description = "Name of the supplemental policy set definition (initiative)."
  default     = "Deny-PublicPaaSEndpoints-Supplemental"
}

variable "assignment_name" {
  type        = string
  description = "Name of the policy assignment. Azure caps assignment names at 24 characters."
  default     = "deny-pna-supplemental"

  validation {
    condition     = length(var.assignment_name) <= 24
    error_message = "assignment_name must be 24 characters or fewer (Azure limit)."
  }
}

variable "assignment_display_name" {
  type        = string
  description = "Display name shown for the assignment in the portal."
  default     = "Enforce private endpoints across PaaS services (Supplemental)"
}

# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------
variable "non_compliance_message" {
  type        = string
  description = "Custom message returned to the caller when a deployment is denied."
  default     = "Private Endpoints Must Be Enabled - No Public Access"
}

variable "effect" {
  type        = string
  description = "Effect propagated to every bundled custom policy."
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect)
    error_message = "effect must be one of: Audit, Deny, Disabled."
  }
}
