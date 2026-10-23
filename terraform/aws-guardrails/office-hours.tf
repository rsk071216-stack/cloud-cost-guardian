# Office-hours scheduling for EC2 instances tagged <office_hours_tag.key>=<office_hours_tag.value>.
#
# EventBridge Scheduler calls SSM StartAutomationExecution (universal target) with tag-based targets,
# so instances are resolved at run time: tag a dev instance and it is included from the next run.
# The automation role can only stop/start instances that carry the office-hours tag.

locals {
  automation_documents = {
    stop  = "AWS-StopEC2Instance"
    start = "AWS-StartEC2Instance"
  }
  schedules = {
    stop = {
      cron     = var.stop_cron
      document = local.automation_documents.stop
      enabled  = true
    }
    start = {
      cron     = var.start_cron
      document = local.automation_documents.start
      enabled  = var.enable_morning_start
    }
  }
}

# Role assumed by SSM Automation to stop/start the tagged instances.
resource "aws_iam_role" "office_hours_automation" {
  name = "${var.name_prefix}-office-hours-automation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "office_hours_automation" {
  name = "stop-start-tagged-instances"
  role = aws_iam_role.office_hours_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StopStartOnlyTaggedInstances"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances", "ec2:StartInstances"]
        Resource = "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/${var.office_hours_tag.key}" = var.office_hours_tag.value }
        }
      },
      {
        Sid      = "DescribeForAutomationWaitSteps"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      }
    ]
  })
}

# Role assumed by EventBridge Scheduler to start the automation.
resource "aws_iam_role" "office_hours_scheduler" {
  name = "${var.name_prefix}-office-hours-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "office_hours_scheduler" {
  name = "start-office-hours-automation"
  role = aws_iam_role.office_hours_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartStopStartAutomations"
        Effect = "Allow"
        Action = "ssm:StartAutomationExecution"
        Resource = [
          for doc in values(local.automation_documents) :
          "arn:${local.partition}:ssm:${var.region}::automation-definition/${doc}:*"
        ]
      },
      {
        Sid      = "PassAutomationRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.office_hours_automation.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" }
        }
      },
      {
        Sid      = "ResolveTagTargets"
        Effect   = "Allow"
        Action   = ["tag:GetResources", "ec2:DescribeInstances"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_scheduler_schedule_group" "office_hours" {
  name = "${var.name_prefix}-office-hours"
}

resource "aws_scheduler_schedule" "office_hours" {
  for_each = local.schedules

  name                         = "${var.name_prefix}-office-hours-${each.key}"
  group_name                   = aws_scheduler_schedule_group.office_hours.name
  description                  = "${title(each.key)} EC2 instances tagged ${var.office_hours_tag.key}=${var.office_hours_tag.value}"
  schedule_expression          = "cron(${each.value.cron})"
  schedule_expression_timezone = var.office_hours_timezone
  state                        = each.value.enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${local.partition}:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.office_hours_scheduler.arn

    input = jsonencode({
      DocumentName        = each.value.document
      TargetParameterName = "InstanceId"
      Targets = [{
        Key    = "tag:${var.office_hours_tag.key}"
        Values = [var.office_hours_tag.value]
      }]
      Parameters = {
        AutomationAssumeRole = [aws_iam_role.office_hours_automation.arn]
      }
      MaxConcurrency = "25%"
      MaxErrors      = "100%"
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
