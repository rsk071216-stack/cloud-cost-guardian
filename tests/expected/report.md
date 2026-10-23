# Cloud savings report

**Generated:** 2026-10-19T06:00:00Z | **Clouds:** Azure, AWS | **Rule executions:** 16 | **Tool:** cloud-cost-guardian 1.0.0

> **Estimated saving: $1,590.03 per month ($19,080.36 per year)** from 33 actionable findings.
> Read-only scan: nothing was changed. Figures are list-price estimates, see [How to read this report](#how-to-read-this-report).

## Summary

| Metric | Value |
|---|---|
| Estimated monthly saving | **$1,590.03** |
| Estimated annual saving | **$19,080.36** |
| AWS monthly saving | $612.92 (19 findings) |
| Azure monthly saving | $977.11 (20 findings) |
| Findings with a direct saving | 33 |
| Findings without a priced saving | 6 |
| Severity (high / medium / low) | 11 / 23 / 5 |
| Rules that failed to run | 0 |

## Savings by rule

| Rule | Cloud | Findings | Est. monthly saving | Remediation risk |
|---|---|---:|---:|---|
| Stopped or deallocated VM still incurring cost (`az-stopped-vm-billed`) | Azure | 2 | $364.80 | Low / Medium |
| Unattached EBS volume (`aws-unattached-ebs`) | AWS | 3 | $343.00 | Medium |
| App Service plan with no apps (`az-empty-app-service-plan`) | Azure | 2 | $297.11 | Low |
| Unattached managed disk (`az-unattached-disk`) | Azure | 3 | $163.20 | Medium |
| EBS snapshot older than 90 days (`aws-old-ebs-snapshot`) | AWS | 4 | $105.00 | High / Medium |
| Snapshot older than 90 days (`az-old-snapshot`) | Azure | 2 | $66.56 | Medium |
| Legacy-generation VM size (`az-legacy-vm-sku`) | Azure | 3 | $59.89 | Medium |
| Load balancer with no registered targets (`aws-unused-load-balancer`) | AWS | 3 | $51.11 | Low |
| gp2 volume that should be gp3 (`aws-gp2-to-gp3`) | AWS | 4 | $37.16 | Low |
| Stopped EC2 instance still paying for EBS (`aws-stopped-ec2-volumes`) | AWS | 2 | $36.50 | Medium |
| Idle NAT gateway (`aws-idle-nat-gateway`) | AWS | 1 | $32.85 | Medium |
| Standard load balancer with no backends (`az-idle-load-balancer`) | Azure | 1 | $18.25 | Low |
| Unassociated Elastic IP (`aws-unused-eip`) | AWS | 2 | $7.30 | Low |
| Unassociated public IP address (`az-unassociated-public-ip`) | Azure | 2 | $7.30 | Low |
| Orphaned network interface (`az-orphaned-nic`) | Azure | 2 | $0.00 | Low |
| Billable resource missing cost-allocation tags (`az-untagged-resource`) | Azure | 3 | $0.00 | Low |

## Findings ranked by estimated monthly saving

| # | Cloud | Resource | Region | Rule | Est. $/month | Risk | Recommendation |
|---:|---|---|---|---|---:|---|---|
| 1 | AWS | `db-migration-temp` | us-east-1 | `aws-unattached-ebs` | $285.00 | Medium | Snapshot if needed, then delete this unattached 200 GiB io1 volume. |
| 2 | Azure | `asp-marketing-prod` | westeurope | `az-empty-app-service-plan` | $227.76 | Low | Delete the empty P1v3 App Service plan (2 worker(s)) or consolidate apps onto a shared plan. |
| 3 | Azure | `vm-sap-sandbox` | westeurope | `az-stopped-vm-billed` | $207.36 | Medium | VM is deallocated but its 2 disk(s) still bill. Snapshot and delete if retired, or downgrade disks to Standard HDD while parked. |
| 4 | Azure | `vm-build-agent-02` | westeurope | `az-stopped-vm-billed` | $157.44 | Low | VM is stopped but NOT deallocated, so compute is still billed. Deallocate it (az vm deallocate) or delete it. |
| 5 | Azure | `vm-erp-legacy-01_DataDisk_0` | westeurope | `az-unattached-disk` | $138.24 | Medium | Snapshot if the data may be needed, then delete this unattached 1024 GB Premium_LRS disk. |
| 6 | Azure | `asp-legacy-api` | northeurope | `az-empty-app-service-plan` | $69.35 | Low | Delete the empty S1 App Service plan (1 worker(s)) or consolidate apps onto a shared plan. |
| 7 | Azure | `snap-sqlvm-before-patch-2025` | westeurope | `az-old-snapshot` | $51.20 | Medium | Snapshot is 410 days old. Confirm retention needs, move long-term copies to Azure Backup, then delete. |
| 8 | AWS | `snap-0e00000000000a004` | us-east-1 | `aws-old-ebs-snapshot` | $50.00 | High | Managed by AWS Backup: shorten the backup plan retention instead of deleting manually. |
| 9 | AWS | `legacy-reporting-data` | us-east-1 | `aws-unattached-ebs` | $50.00 | Medium | Snapshot if needed, then delete this unattached 500 GiB gp2 volume. |
| 10 | Azure | `vm-erp-app-01` | westeurope | `az-legacy-vm-sku` | $49.93 | Medium | Resize Standard_D4_v2 to a current-generation Dsv5/Dasv6 size during a maintenance window. |
| 11 | AWS | `dev-nat-az-b` | us-east-1 | `aws-idle-nat-gateway` | $32.85 | Medium | NAT gateway moved 50 MiB in 14 days. Remove it and its routes, or share one gateway per VPC. |
| 12 | AWS | `snap-0e00000000000a001` | us-east-1 | `aws-old-ebs-snapshot` | $25.00 | Medium | Snapshot is 646 days old: apply a DLM/AWS Backup retention policy, archive or delete it. |
| 13 | AWS | `erp-archive-2024` | us-east-1 | `aws-old-ebs-snapshot` | $25.00 | Medium | Snapshot is 687 days old: apply a DLM/AWS Backup retention policy, archive or delete it. |
| 14 | AWS | `batch-worker-old` | us-east-1 | `aws-stopped-ec2-volumes` | $22.50 | Medium | Instance stopped (stop time unknown) with 1 volume(s) billing. Create an AMI and terminate, or schedule with office-hours start/stop. |
| 15 | AWS | `api-prod-01-data` | us-east-1 | `aws-gp2-to-gp3` | $20.00 | Low | Modify to gp3 online: aws ec2 modify-volume --volume-id vol-0a1b2c3d4e5f60005 --volume-type gp3 --iops 6000 --throughput 250 |
| 16 | Azure | `pvc-3f9c1e2a-7b44-4c1e-9d0a-2f6a1c9e8b10` | westeurope | `az-unattached-disk` | $19.20 | Medium | Snapshot if the data may be needed, then delete this unattached 256 GB StandardSSD_LRS disk. |
| 17 | AWS | `clb-legacy-shop` | us-east-1 | `aws-unused-load-balancer` | $18.25 | Low | Classic load balancer has 0 target group(s) and 0 registered target(s). Check DNS, then delete it. |
| 18 | Azure | `lbi-old-ftp` | westeurope | `az-idle-load-balancer` | $18.25 | Low | Standard load balancer has 2 rule(s) but empty backend pools. Delete it or remove its rules. |
| 19 | AWS | `alb-orders-old` | us-east-1 | `aws-unused-load-balancer` | $16.43 | Low | Application load balancer has 0 target group(s) and 0 registered target(s). Check DNS, then delete it. |
| 20 | AWS | `nlb-legacy-ingest` | us-east-1 | `aws-unused-load-balancer` | $16.43 | Low | Network load balancer has 1 target group(s) and 0 registered target(s). Check DNS, then delete it. |
| 21 | Azure | `snap-web01-os` | westeurope | `az-old-snapshot` | $15.36 | Medium | Snapshot is 200 days old. Confirm retention needs, move long-term copies to Azure Backup, then delete. |
| 22 | AWS | `api-prod-01-root` | us-east-1 | `aws-gp2-to-gp3` | $15.00 | Low | Modify to gp3 online: aws ec2 modify-volume --volume-id vol-0a1b2c3d4e5f60004 --volume-type gp3 --iops 3000 --throughput 250 |
| 23 | AWS | `qa-selenium-runner` | us-east-1 | `aws-stopped-ec2-volumes` | $14.00 | Medium | Instance stopped for 138 days with 2 volume(s) billing. Create an AMI and terminate, or schedule with office-hours start/stop. |
| 24 | Azure | `vm-jumpbox` | westeurope | `az-legacy-vm-sku` | $9.96 | Medium | Resize Standard_A2_v2 to a current-generation Bsv2 (burstable) or Dsv5 size during a maintenance window. |
| 25 | AWS | `vol-0a1b2c3d4e5f60003` | us-east-1 | `aws-unattached-ebs` | $8.00 | Medium | Snapshot if needed, then delete this unattached 100 GiB gp3 volume. |
| 26 | Azure | `restore-test-osdisk` | northeurope | `az-unattached-disk` | $5.76 | Medium | Snapshot if the data may be needed, then delete this unattached 128 GB Standard_LRS disk. |
| 27 | AWS | `snap-0e00000000000a002` | us-east-1 | `aws-old-ebs-snapshot` | $5.00 | High | Backs an AMI (352 days old): deregister the AMI if unused, then delete the snapshot. |
| 28 | AWS | `vpn-old` | us-east-1 | `aws-unused-eip` | $3.65 | Low | Release unassociated Elastic IP 44.205.7.130 after checking DNS and allow-lists. |
| 29 | AWS | `eipalloc-0b00000000000a003` | us-east-1 | `aws-unused-eip` | $3.65 | Low | Release unassociated Elastic IP 52.4.118.9 after checking DNS and allow-lists. |
| 30 | Azure | `pip-old-vpn-gw` | westeurope | `az-unassociated-public-ip` | $3.65 | Low | Release the unassociated Standard Static public IP 20.31.104.17 after checking DNS and allow-lists. |
| 31 | Azure | `pip-test-lb` | northeurope | `az-unassociated-public-ip` | $3.65 | Low | Release the unassociated Standard Static public IP 52.169.12.201 after checking DNS and allow-lists. |
| 32 | AWS | `vol-0a1b2c3d4e5f60006` | us-east-1 | `aws-gp2-to-gp3` | $2.00 | Low | Modify to gp3 online: aws ec2 modify-volume --volume-id vol-0a1b2c3d4e5f60006 --volume-type gp3 |
| 33 | AWS | `vol-0a1b2c3d4e5f60009` | us-east-1 | `aws-gp2-to-gp3` | $0.16 | Low | Modify to gp3 online: aws ec2 modify-volume --volume-id vol-0a1b2c3d4e5f60009 --volume-type gp3 |

## Findings without a priced saving

Governance and hygiene items (they block cost allocation or hide billed resources), plus anything whose price is not in the price sheet.

| Cloud | Resource | Region | Rule | Recommendation |
|---|---|---|---|---|
| Azure | `vm-reporting` | westeurope | `az-legacy-vm-sku` | Resize Standard_DS13_v2 to a current-generation Dsv5/Dasv6 size during a maintenance window (size not in price sheet; saving not estimated). |
| Azure | `vm-old-crm-nic01` | westeurope | `az-orphaned-nic` | Delete the orphaned NIC and review its billed public IP. |
| Azure | `nic-test-temp` | northeurope | `az-orphaned-nic` | Delete the orphaned NIC. |
| Azure | `vm-erp-app-01` | westeurope | `az-untagged-resource` | Add missing tag(s): owner, cost-center. Enforce with Azure Policy tag inheritance. |
| Azure | `asp-marketing-prod` | westeurope | `az-untagged-resource` | Add missing tag(s): cost-center. Enforce with Azure Policy tag inheritance. |
| Azure | `stsandboxexports01` | northeurope | `az-untagged-resource` | Add missing tag(s): owner, cost-center, environment. Enforce with Azure Policy tag inheritance. |

## How to read this report

- **Estimates, not invoices.** Approximate public pay-as-you-go list prices (Azure East US, Linux; AWS us-east-1), 730 hours per month. Estimates for prioritisation only: negotiated rates, reservations, savings plans and regional differences change the real number.
- **No double counting.** When two rules flag the same resource, totals count it once at the larger saving ($0.00 of overlap removed).
- **Risk** is the remediation risk: *Low* = safe to action after a quick owner check, *Medium* = take a snapshot or backup first, *High* = needs an owner decision.
- **Nothing was changed.** The scanner uses read-only list/describe/query APIs. Every action above is a recommendation for a human to approve.
- Full resource IDs and evidence for every finding are in `findings.json` next to this report.
