output "logic_app_policy_id" {
  description = "Resource ID of the deployed ALZ Logic App custom policy definition."
  value       = azurerm_policy_definition.logic_app.id
}

output "supplemental_policy_ids" {
  description = "Map of supplemental custom policy definition name -> resource ID (17 entries)."
  value       = { for k, v in azurerm_policy_definition.supplemental : k => v.id }
}

output "initiative_id" {
  description = "Resource ID of the deployed combined initiative (policy set definition)."
  value       = azurerm_policy_set_definition.this.id
}

output "assignment_id" {
  description = "Resource ID of the deployed policy assignment."
  value       = azurerm_management_group_policy_assignment.this.id
}

output "bundled_policy_count" {
  description = "Number of policies bundled inside the combined initiative."
  value       = length(local.initiative_raw.properties.policyDefinitions)
}

output "denial_message" {
  description = "Message returned to the caller when a deployment is denied."
  value       = var.non_compliance_message
}
