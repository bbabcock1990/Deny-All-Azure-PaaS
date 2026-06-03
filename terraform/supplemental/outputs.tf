output "initiative_id" {
  description = "Resource ID of the deployed supplemental initiative."
  value       = azurerm_policy_set_definition.this.id
}

output "assignment_id" {
  description = "Resource ID of the policy assignment."
  value       = azurerm_management_group_policy_assignment.this.id
}

output "custom_policy_definition_ids" {
  description = "Map of original JSON definition name -> deployed policy definition resource ID."
  value       = { for k, p in azurerm_policy_definition.custom : k => p.id }
}

output "bundled_policy_count" {
  description = "Number of custom policy definitions deployed and bundled into the supplemental initiative."
  value       = length(local.custom_defs)
}

output "denial_message" {
  description = "The non-compliance / deny message returned to callers."
  value       = var.non_compliance_message
}
