# AWS cost guardrails:
#   1. Monthly AWS Budget with actual + forecast thresholds (email + SNS)
#   2. Cost Anomaly Detection monitor + subscription (immediate alerts through SNS)
#   3. Office-hours stop/start for EC2 instances tagged Schedule=office-hours, using
#      EventBridge Scheduler -> SSM Automation (no Lambda code to maintain)

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  monitor_arn = var.create_service_anomaly_monitor ? aws_ce_anomaly_monitor.services[0].arn : var.existing_anomaly_monitor_arn
}

# ---------------------------------------------------------------- alert topic
# Budgets and Cost Anomaly Detection cannot use the AWS-managed SNS key, so a small customer-managed
# key is created with a policy that lets exactly those two services publish (about $1/month).
resource "aws_kms_key" "cost_alerts" {
  description             = "Encrypts the ${var.name_prefix} cost alert SNS topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCostServicesToPublish"
        Effect    = "Allow"
        Principal = { Service = ["budgets.amazonaws.com", "costalerts.amazonaws.com"] }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }
    ]
  })
}

resource "aws_kms_alias" "cost_alerts" {
  name          = "alias/${var.name_prefix}-cost-alerts"
  target_key_id = aws_kms_key.cost_alerts.key_id
}

resource "aws_sns_topic" "cost_alerts" {
  name              = "${var.name_prefix}-cost-alerts"
  kms_master_key_id = aws_kms_key.cost_alerts.arn
}

resource "aws_sns_topic_policy" "cost_alerts" {
  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgetsAndAnomalyDetection"
        Effect    = "Allow"
        Principal = { Service = ["budgets.amazonaws.com", "costalerts.amazonaws.com"] }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.cost_alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------- budget
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly-cost"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.budget_notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.notification_type
      subscriber_email_addresses = var.alert_emails
      subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

# ---------------------------------------------------------------- anomaly detection
resource "aws_ce_anomaly_monitor" "services" {
  count = var.create_service_anomaly_monitor ? 1 : 0

  name              = "${var.name_prefix}-aws-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "immediate" {
  name             = "${var.name_prefix}-anomaly-alerts"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [local.monitor_arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }

  # Alert only on anomalies that are both material in dollars and significant in percent.
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(var.anomaly_min_impact_usd)]
      }
    }
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(var.anomaly_min_impact_percent)]
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.monitor_arn != ""
      error_message = "Set existing_anomaly_monitor_arn when create_service_anomaly_monitor = false."
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}
