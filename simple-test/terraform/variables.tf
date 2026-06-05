variable "policy_name" {
  description = "Name of the custom policy definition."
  type        = string
  default     = "deny-storage-public-network-access"
}

variable "assignment_name" {
  description = "Name of the policy assignment."
  type        = string
  default     = "deny-storage-public"
}

variable "policy_display_name" {
  description = "Display name shown in the Azure Policy portal."
  type        = string
  default     = "Storage accounts must disable public network access"
}

variable "non_compliance_message" {
  description = "Custom non-compliance message returned to anyone whose deployment is blocked."
  type        = string
  default     = "Private Endpoints Must Be Enabled - No Public Access"
}

variable "effect" {
  description = "Policy effect. Use Audit for a soft rollout before enabling Deny."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Deny", "Audit", "Disabled"], var.effect)
    error_message = "effect must be one of: Deny, Audit, Disabled."
  }
}
