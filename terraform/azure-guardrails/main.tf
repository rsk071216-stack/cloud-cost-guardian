# Azure cost guardrails:
#   1. Subscription budget with actual + forecast thresholds, routed to an action group
#   2. Cost Management anomaly alert (ML-based daily anomaly detection)
#   3. Office-hours auto-shutdown for every VM tagged schedule=office-hours
#
# Everything here is free or near-free to run; it exists to stop surprise bills, not to cut existing ones.

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "finops" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_monitor_action_group" "cost" {
  name                = "ag-${var.name_prefix}-cost-alerts"
  resource_group_name = azurerm_resource_group.finops.name
  short_name          = substr("${var.name_prefix}cost", 0, 12)
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = { for idx, email in var.alert_emails : idx => email }
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "budget-${var.name_prefix}-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = var.budget_notifications
    content {
      enabled        = true
      threshold      = notification.value.threshold
      threshold_type = notification.value.threshold_type
      operator       = "GreaterThanOrEqualTo"
      contact_emails = var.alert_emails
      contact_groups = [azurerm_monitor_action_group.cost.id]
    }
  }

  lifecycle {
    # Azure normalises the start date; changing it after creation would force a replacement.
    ignore_changes = [time_period]
  }
}

resource "azurerm_cost_anomaly_alert" "subscription" {
  count = var.enable_anomaly_alert ? 1 : 0

  name            = "${var.name_prefix}-daily-anomaly-alert"
  display_name    = "Daily cost anomaly alert (${data.azurerm_subscription.current.display_name})"
  subscription_id = data.azurerm_subscription.current.id
  email_subject   = "Cost anomaly detected in ${data.azurerm_subscription.current.display_name}"
  email_addresses = var.alert_emails
  message         = "Azure Cost Management detected unusual spend. Review the cost analysis smart view and the latest cloud-cost-guardian report."
}

# ---------------------------------------------------------------- office-hours auto-shutdown
# Every VM carrying the office-hours tag (at plan time) gets a daily shutdown schedule.
# Re-apply (e.g. nightly in CI) to pick up newly tagged VMs. Start-up is intentionally manual
# (or Start/Stop VMs v2): shutting down is safe, starting things automatically spends money.
data "azurerm_resources" "office_hours_vms" {
  type          = "Microsoft.Compute/virtualMachines"
  required_tags = { (var.office_hours_tag.key) = var.office_hours_tag.value }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "office_hours" {
  for_each = { for vm in data.azurerm_resources.office_hours_vms.resources : lower(vm.id) => vm }

  virtual_machine_id    = each.value.id
  location              = each.value.location
  enabled               = true
  daily_recurrence_time = var.shutdown_time
  timezone              = var.shutdown_timezone
  tags                  = var.tags

  notification_settings {
    enabled         = true
    email           = join(";", var.alert_emails)
    time_in_minutes = 30
  }
}
