output "policy_definition_id" {
  description = "Resource ID of the custom policy definition."
  value       = azurerm_policy_definition.deny_storage_public.id
}

output "assignment_id" {
  description = "Resource ID of the subscription-scoped policy assignment."
  value       = azurerm_subscription_policy_assignment.deny_storage_public.id
}

output "effect" {
  description = "Effect the assignment was deployed with."
  value       = var.effect
}

output "non_compliance_message" {
  description = "Custom message returned to anyone whose deployment is blocked."
  value       = var.non_compliance_message
}
