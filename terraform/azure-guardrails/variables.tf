variable "subscription_id" {
  description = "Subscription the budget, anomaly alert and shutdown schedules are created in."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "location" {
  description = "Region for the FinOps resource group and action group metadata."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group that holds the FinOps action group."
  type        = string
  default     = "rg-finops-guardrails"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "finops"
}

variable "alert_emails" {
  description = "Who receives budget, forecast and anomaly alerts."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Provide at least one valid email address."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly subscription budget in the billing currency."
  type        = number

  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than zero."
  }
}

variable "budget_start_date" {
  description = "First day of the budget period in RFC3339 format, must be the first of a month (e.g. 2026-11-01T00:00:00Z)."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first day of a month, e.g. 2026-11-01T00:00:00Z."
  }
}

variable "budget_notifications" {
  description = "Budget thresholds (percent of budget). Actual = spend so far, Forecasted = projected month-end spend. Azure allows at most 5."
  type = list(object({
    threshold      = number
    threshold_type = string
  }))
  default = [
    { threshold = 50, threshold_type = "Actual" },
    { threshold = 80, threshold_type = "Actual" },
    { threshold = 100, threshold_type = "Actual" },
    { threshold = 100, threshold_type = "Forecasted" },
  ]

  validation {
    condition     = length(var.budget_notifications) <= 5 && alltrue([for n in var.budget_notifications : contains(["Actual", "Forecasted"], n.threshold_type)])
    error_message = "Use at most 5 notifications with threshold_type Actual or Forecasted."
  }
}

variable "enable_anomaly_alert" {
  description = "Create a Cost Management anomaly alert (daily ML-based anomaly detection, email only)."
  type        = bool
  default     = true
}

variable "office_hours_tag" {
  description = "VMs carrying this tag key/value get a daily auto-shutdown schedule."
  type = object({
    key   = string
    value = string
  })
  default = {
    key   = "schedule"
    value = "office-hours"
  }
}

variable "shutdown_time" {
  description = "Daily shutdown time in HHmm (24h) for tagged VMs."
  type        = string
  default     = "1900"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.shutdown_time))
    error_message = "shutdown_time must be HHmm, e.g. 1900."
  }
}

variable "shutdown_timezone" {
  description = "Windows time zone ID for the shutdown schedule (e.g. 'W. Europe Standard Time', 'Pakistan Standard Time', 'UTC')."
  type        = string
  default     = "W. Europe Standard Time"
}

variable "tags" {
  description = "Tags applied to every resource created here."
  type        = map(string)
  default = {
    owner         = "platform-team"
    "cost-center" = "finops"
    environment   = "shared"
    "managed-by"  = "terraform"
  }
}
