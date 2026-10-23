#!/usr/bin/env bash
# rule_id: aws-gp2-to-gp3
# What it finds: In-use gp2 volumes. Unattached gp2 volumes are reported by aws-unattached-ebs instead,
#   so the same volume is never counted twice.
# Why it costs money: gp3 is 20% cheaper per GB than gp2 and includes 3,000 IOPS / 125 MiB/s baseline
#   regardless of size. gp2 is a previous-generation volume type with no price advantage.
# Typical saving: About 20% of the volume cost. For volumes above 1 TiB the estimate provisions extra gp3
#   IOPS and throughput to match the gp2 baseline, so the saving shown is conservative.
# Remediation: aws ec2 modify-volume --volume-id <id> --volume-type gp3 [--iops N --throughput N].
#   The change is online with no downtime; one modification per volume every 6 hours.
# Risk: Low. Elastic Volumes modifications are online; check burst-dependent workloads on small gp2 volumes.
# Usage: gp2-to-gp3-candidates.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeVolumes
set -euo pipefail

REGION="${1:?usage: $0 <region>}"

aws ec2 describe-volumes \
  --region "$REGION" \
  --filters Name=volume-type,Values=gp2 \
  --output json |
  jq '[.Volumes[]
      | select(.VolumeType == "gp2" and .State == "in-use")
      | {
          VolumeId,
          Size,
          Iops: (.Iops // 0),
          State,
          AttachedTo: ([.Attachments[]?.InstanceId] | join(",")),
          Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
        }]'
