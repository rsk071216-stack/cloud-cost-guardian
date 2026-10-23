#!/usr/bin/env bash
# rule_id: aws-unused-load-balancer
# What it finds: Application/Network/Gateway load balancers with no target groups or zero registered
#   targets across all their target groups, and Classic load balancers with no registered instances.
# Why it costs money: Load balancers bill an hourly charge (about $16-$18/month) plus capacity units
#   whether or not anything is behind them. They are often left over from decommissioned services.
# Typical saving: $9-$18 per load balancer per month, more where LCU/NLCU charges apply.
# Remediation: Check DNS records (Route 53 aliases, external DNS) that point at the load balancer, then
#   delete it. ALBs that only serve redirects or fixed responses are legitimate; review listener actions.
# Risk: Low. A load balancer without targets cannot route traffic to a backend.
# Usage: unused-load-balancers.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: elasticloadbalancing:DescribeLoadBalancers, elasticloadbalancing:DescribeTargetGroups,
#   elasticloadbalancing:DescribeTargetHealth
set -euo pipefail

REGION="${1:?usage: $0 <region>}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

aws elbv2 describe-load-balancers --region "$REGION" --output json >"$tmp/lbs.json"
aws elbv2 describe-target-groups --region "$REGION" --output json >"$tmp/tgs.json"

# Count registered targets per target group that is attached to at least one load balancer.
printf '{}' >"$tmp/counts.json"
while IFS= read -r tg_arn; do
  [[ -n "$tg_arn" ]] || continue
  n="$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$tg_arn" --output json |
    jq '.TargetHealthDescriptions | length')"
  jq --arg a "$tg_arn" --argjson n "$n" '. + {($a): $n}' "$tmp/counts.json" >"$tmp/next.json"
  mv "$tmp/next.json" "$tmp/counts.json"
done < <(jq -r '.TargetGroups[] | select((.LoadBalancerArns // []) | length > 0) | .TargetGroupArn' "$tmp/tgs.json")

jq --slurpfile tgs "$tmp/tgs.json" --slurpfile counts "$tmp/counts.json" '
  [.LoadBalancers[]
   | .LoadBalancerArn as $lb
   | [$tgs[0].TargetGroups[] | select(any((.LoadBalancerArns // [])[]; . == $lb))] as $mine
   | ([$mine[] | $counts[0][.TargetGroupArn] // 0] | add // 0) as $targets
   | select($targets == 0)
   | {
       Id: .LoadBalancerArn,
       Name: .LoadBalancerName,
       Type: .Type,
       Scheme,
       CreatedTime,
       DNSName,
       TargetGroups: ($mine | length),
       RegisteredTargets: $targets
     }]' "$tmp/lbs.json" >"$tmp/v2.json"

aws elb describe-load-balancers --region "$REGION" --output json |
  jq '[.LoadBalancerDescriptions[]
       | select((.Instances // []) | length == 0)
       | {
           Id: .LoadBalancerName,
           Name: .LoadBalancerName,
           Type: "classic",
           Scheme,
           CreatedTime,
           DNSName,
           TargetGroups: 0,
           RegisteredTargets: 0
         }]' >"$tmp/classic.json"

jq -s 'add' "$tmp/v2.json" "$tmp/classic.json"
