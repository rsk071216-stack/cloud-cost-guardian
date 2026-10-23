#!/usr/bin/env bash
# rule_id: aws-stopped-ec2-volumes
# What it finds: EC2 instances stopped for at least CCG_STOPPED_MIN_DAYS (default 7) days, with the
#   EBS volumes still attached to them.
# Why it costs money: A stopped instance has no compute charge, but every attached EBS volume (and any
#   associated public IPv4 address) keeps billing. "Temporarily stopped" instances are often forgotten.
# Typical saving: 100% of the attached volume cost if the instance is retired.
# Remediation: Create an AMI or snapshots, terminate the instance, or put it on an office-hours schedule
#   (see terraform/aws-guardrails) if it is a dev machine that is still needed.
# Risk: Medium. Termination deletes volumes with DeleteOnTermination=true; take an AMI first.
# Usage: stopped-ec2-with-volumes.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeInstances, ec2:DescribeVolumes
set -euo pipefail

REGION="${1:?usage: $0 <region>}"
NOW="${CCG_NOW_EPOCH:-$(date -u +%s)}"
MIN_DAYS="${CCG_STOPPED_MIN_DAYS:-7}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# StateTransitionReason looks like: "User initiated (2026-08-01 18:04:12 GMT)"
aws ec2 describe-instances \
  --region "$REGION" \
  --filters Name=instance-state-name,Values=stopped \
  --output json |
  jq --argjson now "$NOW" --argjson min "$MIN_DAYS" '
    [.Reservations[].Instances[]
     | select(.State.Name == "stopped")
     | ([(.StateTransitionReason // "") | capture("[(](?<ts>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) GMT[)]") | .ts] | first) as $ts
     | (if $ts == null then null
        else ((($now - (($ts | sub(" "; "T")) + "Z" | fromdateiso8601)) / 86400) | floor) end) as $days
     | select($days == null or $days >= $min)
     | {
         InstanceId,
         InstanceType,
         StoppedSince: (if $ts == null then "" else $ts + " UTC" end),
         StoppedDays: $days,
         Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
       }]' >"$tmp/instances.json"

if [[ "$(jq 'length' "$tmp/instances.json")" -eq 0 ]]; then
  printf '[]\n'
  exit 0
fi

ids="$(jq -r '[.[].InstanceId] | join(",")' "$tmp/instances.json")"
aws ec2 describe-volumes \
  --region "$REGION" \
  --filters "Name=attachment.instance-id,Values=$ids" \
  --output json >"$tmp/volumes.json"

jq --slurpfile v "$tmp/volumes.json" '
  [.[]
   | .InstanceId as $iid
   | . + {
       Volumes: [$v[0].Volumes[]
                 | select(any(.Attachments[]?; .InstanceId == $iid))
                 | {VolumeId, VolumeType, Size, Iops: (.Iops // 0), Throughput: (.Throughput // 0)}]
     }
   | select(.Volumes | length > 0)]' "$tmp/instances.json"
