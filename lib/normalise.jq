# normalise.jq - turn the raw rows of ONE rule into findings that follow schema/finding.schema.json.
#
# Input : JSON array of raw rows (Resource Graph `data` rows or the output of a queries/aws/*.sh script)
# Args  : --arg rule_id <id>  --arg region <aws region or "">  --arg account <aws account id or "">
#         --slurpfile catalogue rules/catalogue.json  --slurpfile prices pricing/price-sheet.json
# Output: JSON array of findings
#
# Every cost below is an ESTIMATED MONTHLY SAVING in USD based on list prices from the price sheet.

def r2: (. * 100 | round) / 100;
def num: if . == null then 0 else tonumber end;
def max0: if . < 0 then 0 else . end;

def P: $prices[0];
def rule: first($catalogue[0].rules[] | select(.id == $rule_id));

# ---------- price helpers ----------
def az_disk_month($sku; $gb):
  (P.azure.managed_disk_per_gb_month[$sku] // P.azure.managed_disk_per_gb_month.default) * ($gb | num);

def az_snapshot_month($sku; $gb):
  (P.azure.snapshot_per_gb_month[$sku] // P.azure.snapshot_per_gb_month.default) * ($gb | num);

def az_vm_month($size): P.azure.vm_month[$size];

# EBS monthly cost for {VolumeType, Size, Iops, Throughput}
def ebs_month:
  (.VolumeType // "gp2") as $t
  | (.Size | num) as $gb
  | (.Iops | num) as $iops
  | (.Throughput | num) as $thr
  | (P.aws.ebs_gb_month[$t] // P.aws.ebs_gb_month.gp2) * $gb
    + (if $t == "gp3" then
         (($iops - P.aws.gp3_free_iops) | max0) * P.aws.ebs_iops_month.gp3
         + (($thr - P.aws.gp3_free_throughput_mibps) | max0) * P.aws.gp3_throughput_mibps_month
       elif $t == "io1" or $t == "io2" then
         $iops * P.aws.ebs_iops_month[$t]
       else 0 end);

# gp2 -> gp3 saving, provisioning gp3 to match gp2 baseline performance
def gp2_to_gp3_saving:
  (.Size | num) as $gb
  | ([([$gb * 3, 100] | max), 16000] | min) as $gp2_iops
  | (if $gb <= 170 then 125 else 250 end) as $gp2_thr  # gp2 small-volume throughput (128) ~ gp3 baseline (125)
  | ($gb * P.aws.ebs_gb_month.gp2) as $gp2
  | ($gb * P.aws.ebs_gb_month.gp3
     + (($gp2_iops - P.aws.gp3_free_iops) | max0) * P.aws.ebs_iops_month.gp3
     + (($gp2_thr - P.aws.gp3_free_throughput_mibps) | max0) * P.aws.gp3_throughput_mibps_month) as $gp3
  | {saving: (($gp2 - $gp3) | max0), iops: $gp2_iops, throughput: $gp2_thr};

def az_successor($size):
  if ($size | test("^Standard_E"; "i")) then "Esv5/Easv6"
  elif ($size | test("^Standard_F"; "i")) then "Fasv6/Fsv2"
  elif ($size | test("^(Standard_A|Basic_A)"; "i")) then "Bsv2 (burstable) or Dsv5"
  elif ($size | test("^Standard_G"; "i")) then "Esv5/Ebsv5"
  else "Dsv5/Dasv6" end;

# ---------- common row shapes ----------
def azure_base: {id: .id, name: .name, region: (.location // ""), account: (.subscriptionId // "")};
def aws_base($id; $name): {id: $id, name: (if ($name // "") == "" then $id else $name end), region: $region, account: $account};

# ---------- per-rule mapping: raw row -> {id,name,region,account,cost,rec,risk?,evidence} ----------
def map_row:
  if $rule_id == "az-unattached-disk" then
    azure_base + {
      cost: az_disk_month(.skuName; .sizeGb),
      rec: "Snapshot if the data may be needed, then delete this unattached \(.sizeGb) GB \(.skuName) disk.",
      evidence: {sku: .skuName, size_gb: .sizeGb, time_created: .timeCreated, last_ownership_update: (.lastOwnershipUpdate // "")}
    }
  elif $rule_id == "az-unassociated-public-ip" then
    azure_base + {
      cost: P.azure.public_ip_month,
      rec: "Release the unassociated \(.skuName) \(.allocation) public IP \(.ipAddress // "") after checking DNS and allow-lists.",
      evidence: {sku: .skuName, allocation: .allocation, ip_address: (.ipAddress // "")}
    }
  elif $rule_id == "az-stopped-vm-billed" then
    ([.disks[]? | select(.sizeGb != null)]) as $disks
    | ([$disks[] | az_disk_month(.sku; .sizeGb)] | add // 0) as $disk_cost
    | (.powerState | ascii_downcase) as $ps
    | (if $ps == "powerstate/stopped" then (az_vm_month(.vmSize) // 0) else 0 end) as $compute
    | azure_base + {
        cost: ($disk_cost + $compute),
        rec: (if $ps == "powerstate/stopped"
              then "VM is stopped but NOT deallocated, so compute is still billed. Deallocate it (az vm deallocate) or delete it."
              else "VM is deallocated but its \($disks | length) disk(s) still bill. Snapshot and delete if retired, or downgrade disks to Standard HDD while parked." end),
        risk: (if $ps == "powerstate/stopped" then "low" else "medium" end),
        evidence: {vm_size: .vmSize, power_state: .powerState, disk_count: ($disks | length),
                   disk_gb: ([$disks[].sizeGb] | add // 0), compute_cost_included: ($compute > 0)}
      }
  elif $rule_id == "az-old-snapshot" then
    azure_base + {
      cost: az_snapshot_month(.skuName; .sizeGb),
      rec: "Snapshot is \(.ageDays) days old. Confirm retention needs, move long-term copies to Azure Backup, then delete.",
      evidence: {sku: .skuName, size_gb: .sizeGb, age_days: .ageDays, incremental: (.incremental // false),
                 source_resource_id: (.sourceResourceId // "")}
    }
  elif $rule_id == "az-empty-app-service-plan" then
    ((.workers | num) | if . < 1 then 1 else . end) as $w
    | azure_base + {
        cost: ((P.azure.app_service_plan_month[.skuName] // P.azure.app_service_plan_month.default) * $w),
        rec: "Delete the empty \(.skuName) App Service plan (\($w) worker(s)) or consolidate apps onto a shared plan.",
        evidence: {sku: .skuName, tier: .skuTier, workers: $w}
      }
  elif $rule_id == "az-idle-load-balancer" then
    (.ruleCount | num) as $rules
    | azure_base + {
        cost: (P.azure.load_balancer_standard_first5_rules_month
               + (([$rules - 5, 0] | max) * P.azure.load_balancer_standard_extra_rule_month)),
        rec: "Standard load balancer has \($rules) rule(s) but empty backend pools. Delete it or remove its rules.",
        evidence: {sku: .skuName, rule_count: $rules, backend_pool_count: .backendPoolCount}
      }
  elif $rule_id == "az-legacy-vm-sku" then
    az_vm_month(.vmSize) as $price
    | azure_base + {
        cost: (if $price == null then 0 else $price * P.azure.legacy_vm_saving_ratio end),
        rec: ("Resize \(.vmSize) to a current-generation \(az_successor(.vmSize)) size during a maintenance window"
              + (if $price == null then " (size not in price sheet; saving not estimated)." else "." end)),
        evidence: {vm_size: .vmSize, list_price_month: $price, assumed_saving_ratio: P.azure.legacy_vm_saving_ratio}
      }
  elif $rule_id == "az-untagged-resource" then
    ([if .missingOwner then "owner" else empty end,
      if .missingCostCenter then "cost-center" else empty end,
      if .missingEnvironment then "environment" else empty end]) as $missing
    | azure_base + {
        cost: 0,
        rec: "Add missing tag(s): \($missing | join(", ")). Enforce with Azure Policy tag inheritance.",
        evidence: {type: .type, missing_tags: $missing}
      }
  elif $rule_id == "az-orphaned-nic" then
    azure_base + {
      cost: 0,
      rec: ("Delete the orphaned NIC" + (if .hasPublicIp then " and review its billed public IP." else "." end)),
      evidence: {private_ip: (.privateIp // ""), has_public_ip: (.hasPublicIp // false)}
    }
  elif $rule_id == "aws-unattached-ebs" then
    aws_base(.VolumeId; .Name) + {
      cost: ebs_month,
      rec: "Snapshot if needed, then delete this unattached \(.Size) GiB \(.VolumeType) volume.",
      evidence: {volume_type: .VolumeType, size_gb: .Size, iops: .Iops, throughput: .Throughput,
                 create_time: .CreateTime, availability_zone: .AvailabilityZone}
    }
  elif $rule_id == "aws-unused-eip" then
    aws_base(.AllocationId; .Name) + {
      cost: P.aws.public_ipv4_month,
      rec: "Release unassociated Elastic IP \(.PublicIp) after checking DNS and allow-lists.",
      evidence: {public_ip: .PublicIp, domain: .Domain, network_border_group: .NetworkBorderGroup}
    }
  elif $rule_id == "aws-old-ebs-snapshot" then
    (if .StorageTier == "archive" then P.aws.snapshot_gb_month.archive else P.aws.snapshot_gb_month.standard end) as $rate
    | aws_base(.SnapshotId; .Name) + {
        cost: ((.VolumeSize | num) * $rate),
        rec: (if .BackupManaged then "Managed by AWS Backup: shorten the backup plan retention instead of deleting manually."
              elif .AmiBacked then "Backs an AMI (\(.AgeDays) days old): deregister the AMI if unused, then delete the snapshot."
              else "Snapshot is \(.AgeDays) days old: apply a DLM/AWS Backup retention policy, archive or delete it." end),
        risk: (if .BackupManaged or .AmiBacked then "high" else rule.risk end),
        evidence: {volume_id: .VolumeId, size_gb: .VolumeSize, age_days: .AgeDays, storage_tier: .StorageTier,
                   ami_backed: .AmiBacked, backup_managed: .BackupManaged}
      }
  elif $rule_id == "aws-idle-nat-gateway" then
    aws_base(.NatGatewayId; .Name) + {
      cost: P.aws.nat_gateway_month,
      rec: "NAT gateway moved \((.BytesOut / 1048576) | floor) MiB in \(.LookbackDays) days. Remove it and its routes, or share one gateway per VPC.",
      evidence: {vpc_id: .VpcId, subnet_id: .SubnetId, connectivity_type: .ConnectivityType,
                 bytes_out: .BytesOut, lookback_days: .LookbackDays}
    }
  elif $rule_id == "aws-gp2-to-gp3" then
    gp2_to_gp3_saving as $s
    | aws_base(.VolumeId; .Name) + {
        cost: $s.saving,
        rec: ("Modify to gp3 online: aws ec2 modify-volume --volume-id \(.VolumeId) --volume-type gp3"
              + (if $s.iops > 3000 or $s.throughput > 125 then " --iops \([$s.iops, 3000] | max) --throughput \([$s.throughput, 125] | max)" else "" end)),
        evidence: {size_gb: .Size, gp2_baseline_iops: $s.iops, attached_to: .AttachedTo}
      }
  elif $rule_id == "aws-stopped-ec2-volumes" then
    ([.Volumes[] | ebs_month] | add // 0) as $c
    | aws_base(.InstanceId; .Name) + {
        cost: $c,
        rec: ("Instance stopped" + (if .StoppedDays == null then " (stop time unknown)" else " for \(.StoppedDays) days" end)
              + " with \(.Volumes | length) volume(s) billing. Create an AMI and terminate, or schedule with office-hours start/stop."),
        evidence: {instance_type: .InstanceType, stopped_since: .StoppedSince, stopped_days: .StoppedDays,
                   volume_ids: [.Volumes[].VolumeId], volume_gb: ([.Volumes[].Size] | add // 0)}
      }
  elif $rule_id == "aws-unused-load-balancer" then
    aws_base(.Id; .Name) + {
      cost: (P.aws.load_balancer_month[.Type] // P.aws.load_balancer_month.application),
      rec: "\({"application": "Application", "network": "Network", "gateway": "Gateway", "classic": "Classic"}[.Type] // .Type) load balancer has \(.TargetGroups) target group(s) and \(.RegisteredTargets) registered target(s). Check DNS, then delete it.",
      evidence: {type: .Type, scheme: .Scheme, dns_name: .DNSName, target_groups: .TargetGroups, created: .CreatedTime}
    }
  else
    error("normalise.jq: no mapping for rule_id \($rule_id)")
  end;

# ---------- main ----------
([rule][0]) as $r
| if $r == null then error("normalise.jq: rule_id \($rule_id) is not in the catalogue") else . end
| [ .[]
    | map_row
    | {
        provider: $r.provider,
        rule_id: $r.id,
        title: $r.title,
        category: $r.category,
        severity: $r.severity,
        resource_id: .id,
        resource_name: .name,
        region: .region,
        account: .account,
        monthly_cost_estimate: (.cost | r2),
        currency: "USD",
        recommendation: .rec,
        risk: (.risk // $r.risk),
        evidence: .evidence
      }
  ]
