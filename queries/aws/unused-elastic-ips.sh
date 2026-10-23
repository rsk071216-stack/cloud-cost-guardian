#!/usr/bin/env bash
# rule_id: aws-unused-eip
# What it finds: Elastic IP addresses that are not associated with an instance or network interface.
# Why it costs money: Since February 2024 AWS charges $0.005 per hour for every public IPv4 address.
#   An allocated but unassociated Elastic IP is pure waste.
# Typical saving: About $3.65 per address per month.
# Remediation: Confirm the address is not referenced by DNS records or partner allow-lists, then release it.
# Risk: Low. A released address usually cannot be recovered, which matters if third parties allow-list it.
# Usage: unused-elastic-ips.sh <region>   -> prints a JSON array of rows to stdout
# Required IAM: ec2:DescribeAddresses
set -euo pipefail

REGION="${1:?usage: $0 <region>}"

aws ec2 describe-addresses \
  --region "$REGION" \
  --output json |
  jq '[.Addresses[]
      | select(.AssociationId == null and .InstanceId == null and .NetworkInterfaceId == null)
      | {
          AllocationId: (.AllocationId // .PublicIp),
          PublicIp,
          Domain: (.Domain // "vpc"),
          NetworkBorderGroup: (.NetworkBorderGroup // ""),
          Name: ([(.Tags // [])[] | select(.Key == "Name") | .Value] | first // "")
        }]'
