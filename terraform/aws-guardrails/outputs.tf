output "cost_alerts_topic_arn" {
  description = "SNS topic that receives budget and anomaly alerts (subscribe Slack/Teams/ChatOps here)."
  value       = aws_sns_topic.cost_alerts.arn
}

output "budget_name" {
  description = "Name of the monthly AWS Budget."
  value       = aws_budgets_budget.monthly.name
}

output "anomaly_monitor_arn" {
  description = "Cost Anomaly Detection monitor used by the alert subscription."
  value       = local.monitor_arn
}

output "office_hours_schedules" {
  description = "EventBridge Scheduler schedules for office-hours stop/start."
  value       = { for k, s in aws_scheduler_schedule.office_hours : k => s.arn }
}
