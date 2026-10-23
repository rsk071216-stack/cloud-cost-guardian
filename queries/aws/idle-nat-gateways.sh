#!/usr/bin/env bash
# rule_id: aws-idle-nat-gateway
# What it finds: Available NAT gateways that sent less than CCG_NAT_IDLE_BYTES (default 1 GiB) to
#   destinations over the last CCG_NAT_LOOKBACK_DAYS (default 14) days, using the CloudWatch
#   AWS/NATGateway BytesOutToDestination metric.
# Why it costs money: Every NAT gateway bills about $0.045 per hour (~$33/month) before any data
#   processing charges. Dev/test VPCs often keep one gateway per AZ that nobody uses.
# Typical saving: About $32.85 per gateway per month.
# Remediation: Remove the gateway and its routes, use one gateway per VPC for non-production, or replace
#   S3/DynamoDB traffic with free gateway VPC endpoints.
# Risk: Medium. Removing a NAT gateway breaks outbound internet access for private subnets that still use it.
# Usage: idle-nat-gateways.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeNatGateways, cloudwatch:GetMetricStatistics
set -euo pipefail

REGION="${1:?usage: $0 <region>}"
NOW="${CCG_NOW_EPOCH:-$(date -u +%s)}"
LOOKBACK_DAYS="${CCG_NAT_LOOKBACK_DAYS:-14}"
IDLE_BYTES="${CCG_NAT_IDLE_BYTES:-1073741824}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

start="$(jq -nr --argjson n "$NOW" --argjson d "$LOOKBACK_DAYS" '($n - ($d * 86400)) | todate')"
end="$(jq -nr --argjson n "$NOW" '$n | todate')"

aws ec2 describe-nat-gateways \
  --region "$REGION" \
  --filter Name=state,Values=available \
  --output json |
  jq -c '.NatGateways[]
         | select(.State == "available")
         | {
             NatGatewayId,
             VpcId,
             SubnetId,
             ConnectivityType: (.ConnectivityType // "public"),
             CreateTime,
             Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
           }' >"$tmp/gateways.jsonl"

printf '[]' >"$tmp/result.json"
while IFS= read -r gw; do
  id="$(jq -r '.NatGatewayId' <<<"$gw")"
  aws cloudwatch get-metric-statistics \
    --region "$REGION" \
    --namespace AWS/NATGateway \
    --metric-name BytesOutToDestination \
    --dimensions "Name=NatGatewayId,Value=$id" \
    --start-time "$start" \
    --end-time "$end" \
    --period 86400 \
    --statistics Sum \
    --output json >"$tmp/metric.json"
  printf '%s\n' "$gw" >"$tmp/gw.json"
  jq --slurpfile gw "$tmp/gw.json" --slurpfile m "$tmp/metric.json" \
    --argjson idle "$IDLE_BYTES" --argjson days "$LOOKBACK_DAYS" '
      ([$m[0].Datapoints[]?.Sum] | add // 0) as $bytes
      | if $bytes < $idle then . + [$gw[0] + {BytesOut: $bytes, LookbackDays: $days}] else . end
    ' "$tmp/result.json" >"$tmp/next.json"
  mv "$tmp/next.json" "$tmp/result.json"
done <"$tmp/gateways.jsonl"

jq '.' "$tmp/result.json"
