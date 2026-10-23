#!/usr/bin/env bash
# rule_id: aws-old-ebs-snapshot
# What it finds: Self-owned EBS snapshots older than CCG_SNAPSHOT_MIN_AGE_DAYS (default 90 days).
#   Snapshots that back an AMI or are managed by AWS Backup are flagged so they are handled correctly.
# Why it costs money: Snapshots bill $0.05 per GB-month (standard tier) until deleted. One-off snapshots
#   taken "just in case" before changes are rarely cleaned up.
# Typical saving: Up to $0.05 per GB-month. Snapshots are incremental, so size-based estimates are an upper bound.
# Remediation: Put retention under Data Lifecycle Manager or AWS Backup; move must-keep snapshots to the
#   archive tier (75% cheaper); delete the rest. Deregister unused AMIs before deleting their snapshots.
# Risk: Medium. A snapshot can be the only remaining copy of a deleted volume.
# Usage: old-ebs-snapshots.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeSnapshots
set -euo pipefail

REGION="${1:?usage: $0 <region>}"
NOW="${CCG_NOW_EPOCH:-$(date -u +%s)}"
MIN_AGE_DAYS="${CCG_SNAPSHOT_MIN_AGE_DAYS:-90}"

aws ec2 describe-snapshots \
  --region "$REGION" \
  --owner-ids self \
  --output json |
  jq --argjson now "$NOW" --argjson min "$MIN_AGE_DAYS" '
    def epoch: sub("[.][0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601;
    [.Snapshots[]
     | ((($now - (.StartTime | epoch)) / 86400) | floor) as $age
     | select($age >= $min)
     | {
         SnapshotId,
         VolumeId: (.VolumeId // ""),
         VolumeSize,
         StartTime,
         AgeDays: $age,
         StorageTier: (.StorageTier // "standard"),
         Description: (.Description // ""),
         AmiBacked: ((.Description // "") | test("CreateImage")),
         BackupManaged: ([(.Tags // [])[] | select(.Key == "aws:backup:source-resource")] | length > 0),
         Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
       }]'
