#!/usr/bin/env bash
# rule_id: aws-unattached-ebs
# What it finds: EBS volumes in the "available" state, i.e. not attached to any instance.
# Why it costs money: EBS bills provisioned GB (plus provisioned IOPS/throughput) every hour the volume
#   exists, attached or not. Volumes survive instance termination when DeleteOnTermination is false.
# Typical saving: 100% of the volume cost: $0.08/GB-month (gp3) up to $0.125/GB-month plus IOPS (io1/io2).
# Remediation: Snapshot the volume (archive tier for long-term), confirm with the owner, then delete it.
# Risk: Medium. Deletion is irreversible; keep a snapshot when ownership is unclear.
# Usage: unattached-ebs-volumes.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeVolumes
set -euo pipefail

REGION="${1:?usage: $0 <region>}"

aws ec2 describe-volumes \
  --region "$REGION" \
  --filters Name=status,Values=available \
  --output json |
  jq '[.Volumes[]
      | select(.State == "available")
      | {
          VolumeId,
          VolumeType,
          Size,
          Iops: (.Iops // 0),
          Throughput: (.Throughput // 0),
          CreateTime,
          AvailabilityZone,
          Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
        }]'
