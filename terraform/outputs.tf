output "custom_logic_app_policy_id" {
  description = "Resource ID of the deployed Logic App custom policy definition."
  value       = azurerm_policy_definition.logic_app.id
}

output "initiative_id" {
  description = "Resource ID of the deployed initiative (policy set definition)."
  value       = azurerm_policy_set_definition.this.id
}

output "assignment_id" {
  description = "Resource ID of the deployed policy assignment."
  value       = azurerm_management_group_policy_assignment.this.id
}

output "bundled_policy_count" {
  description = "Number of policies bundled inside the initiative."
  value       = length(local.initiative_raw.properties.policyDefinitions)
}

output "denial_message" {
  description = "Message returned to the caller when a deployment is denied."
  value       = var.non_compliance_message
}
