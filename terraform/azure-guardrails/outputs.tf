output "action_group_id" {
  description = "Action group that receives budget alerts; reuse it for other cost alerts."
  value       = azurerm_monitor_action_group.cost.id
}

output "budget_id" {
  description = "ID of the monthly subscription budget."
  value       = azurerm_consumption_budget_subscription.monthly.id
}

output "office_hours_vm_ids" {
  description = "VMs that received an auto-shutdown schedule."
  value       = sort([for s in azurerm_dev_test_global_vm_shutdown_schedule.office_hours : s.virtual_machine_id])
}
