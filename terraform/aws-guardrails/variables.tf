variable "region" {
  description = "Region for the SNS topic, scheduler and IAM roles. Budgets and Cost Explorer are global."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "finops"
}

variable "alert_emails" {
  description = "Who receives budget and anomaly alerts (SNS email subscriptions must be confirmed once)."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && length(var.alert_emails) <= 10
    error_message = "Provide between 1 and 10 email addresses (AWS Budgets limit per notification)."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget for the account in USD."
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}

variable "budget_notifications" {
  description = "Budget thresholds in percent. ACTUAL = spend so far, FORECASTED = projected month-end spend."
  type = list(object({
    threshold         = number
    notification_type = string
  }))
  default = [
    { threshold = 50, notification_type = "ACTUAL" },
    { threshold = 80, notification_type = "ACTUAL" },
    { threshold = 100, notification_type = "ACTUAL" },
    { threshold = 100, notification_type = "FORECASTED" },
  ]

  validation {
    condition     = alltrue([for n in var.budget_notifications : contains(["ACTUAL", "FORECASTED"], n.notification_type)])
    error_message = "notification_type must be ACTUAL or FORECASTED."
  }
}

variable "create_service_anomaly_monitor" {
  description = "Create an AWS-services anomaly monitor. Only one per account is allowed: set false and pass existing_anomaly_monitor_arn if the account already has one (new accounts often get a default monitor)."
  type        = bool
  default     = true
}

variable "existing_anomaly_monitor_arn" {
  description = "ARN of an existing Cost Anomaly Detection monitor, used when create_service_anomaly_monitor = false."
  type        = string
  default     = ""
}

variable "anomaly_min_impact_usd" {
  description = "Alert only when an anomaly's total impact is at least this many USD..."
  type        = number
  default     = 50
}

variable "anomaly_min_impact_percent" {
  description = "...and at least this percentage above expected spend."
  type        = number
  default     = 15
}

variable "office_hours_tag" {
  description = "EC2 instances with this tag key/value are stopped in the evening and started in the morning on weekdays."
  type = object({
    key   = string
    value = string
  })
  default = {
    key   = "Schedule"
    value = "office-hours"
  }
}

variable "office_hours_timezone" {
  description = "IANA time zone for the office-hours schedules."
  type        = string
  default     = "Europe/Berlin"
}

variable "stop_cron" {
  description = "EventBridge Scheduler cron expression (without the cron() wrapper) for stopping tagged instances."
  type        = string
  default     = "0 19 ? * MON-FRI *"
}

variable "start_cron" {
  description = "EventBridge Scheduler cron expression for starting tagged instances."
  type        = string
  default     = "0 8 ? * MON-FRI *"
}

variable "enable_morning_start" {
  description = "Also start tagged instances in the morning. Disable to only stop (safest, cheapest)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Default tags for every resource."
  type        = map(string)
  default = {
    owner         = "platform-team"
    "cost-center" = "finops"
    environment   = "shared"
    "managed-by"  = "terraform"
  }
}
