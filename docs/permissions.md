# Permissions: read-only by design

The scanner never needs write access. It calls Azure Resource Graph queries and AWS `Describe*`/`Get*`
APIs only, and the test suite enforces this: the mocked `az` and `aws` CLIs in `tests/mocks/bin` refuse
any other call, and the run log is checked after every test scan.

GitHub Actions authenticates with **OIDC federation**. There are no client secrets, access keys or
long-lived tokens stored anywhere, and the cloud side only trusts tokens issued to the `main` branch
of this repository.

| Where | Identity | Permission | Scope |
|---|---|---|---|
| Azure | App registration / user-assigned managed identity with a federated credential | `Reader` (built-in) or the custom `Cloud Cost Guardian Reader` role | Management group (or each subscription) |
| AWS | IAM role assumed with `sts:AssumeRoleWithWebIdentity` | `cost-guardian-readonly-policy.json` (10 read actions) | Account |
| GitHub | Workflow `GITHUB_TOKEN` | `contents: read`, `id-token: write`, `issues: write` | This repository only |

`issues: write` is the only write permission anywhere, and it only lets the workflow create/update the
weekly report issue in this repository.

## Azure

Files:
- [`permissions/azure/cost-guardian-reader-role.json`](../permissions/azure/cost-guardian-reader-role.json): custom role, `*/read` style actions for the inspected resource types only, no data actions
- [`permissions/azure/github-federated-credential.json`](../permissions/azure/github-federated-credential.json): federated identity credential (subject `repo:<owner>/<repo>:ref:refs/heads/main`)

Built-in `Reader` (`acdd72a7-3385-48ef-bd42-f606fba81ae7`) is the simplest choice and also lets the
untagged-resource rule see every resource type. Use the custom role when a client wants the narrowest
possible grant; Resource Graph only returns resources the identity can read.

```bash
# 1. Identity (app registration) with a federated credential for this repo's main branch
APP_ID=$(az ad app create --display-name cloud-cost-guardian --query appId -o tsv)
az ad sp create --id "$APP_ID"
sed -e 's#<GITHUB_OWNER>/<GITHUB_REPO>#rsk071216-stack/cloud-cost-guardian#' \
  permissions/azure/github-federated-credential.json > /tmp/fic.json
az ad app federated-credential create --id "$APP_ID" --parameters @/tmp/fic.json

# 2a. Built-in Reader at management group scope (covers every subscription below it) ...
az role assignment create --assignee "$APP_ID" --role Reader \
  --scope "/providers/Microsoft.Management/managementGroups/<MANAGEMENT_GROUP_ID>"

# 2b. ... or the narrower custom role
sed -e 's#<MANAGEMENT_GROUP_ID>#my-mg#' permissions/azure/cost-guardian-reader-role.json > /tmp/role.json
az role definition create --role-definition @/tmp/role.json
az role assignment create --assignee "$APP_ID" --role "Cloud Cost Guardian Reader" \
  --scope "/providers/Microsoft.Management/managementGroups/my-mg"
```

Repository variables (Settings > Secrets and variables > Actions > **Variables**):
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (any subscription the identity can read;
used for the login context) and optionally `CCG_AZURE_MANAGEMENT_GROUPS`.

## AWS

Files:
- [`permissions/aws/cost-guardian-readonly-policy.json`](../permissions/aws/cost-guardian-readonly-policy.json): the complete permission policy
- [`permissions/aws/github-oidc-trust-policy.json`](../permissions/aws/github-oidc-trust-policy.json): trust policy template (audience + exact `sub` match)
- [`terraform/aws-scanner-access`](../terraform/aws-scanner-access): creates the OIDC provider, role and policy (the policy is read from the JSON file above, so documentation and deployment cannot drift)

| Action | Used by |
|---|---|
| `ec2:DescribeRegions` | region discovery when `CCG_AWS_REGIONS` is not set |
| `ec2:DescribeVolumes` | `aws-unattached-ebs`, `aws-gp2-to-gp3`, `aws-stopped-ec2-volumes` |
| `ec2:DescribeSnapshots` | `aws-old-ebs-snapshot` |
| `ec2:DescribeAddresses` | `aws-unused-eip` |
| `ec2:DescribeInstances` | `aws-stopped-ec2-volumes` |
| `ec2:DescribeNatGateways` | `aws-idle-nat-gateway` |
| `cloudwatch:GetMetricStatistics` | `aws-idle-nat-gateway` (14-day traffic) |
| `elasticloadbalancing:DescribeLoadBalancers` | `aws-unused-load-balancer` (ALB/NLB/GWLB and Classic) |
| `elasticloadbalancing:DescribeTargetGroups` | `aws-unused-load-balancer` |
| `elasticloadbalancing:DescribeTargetHealth` | `aws-unused-load-balancer` |

`sts:GetCallerIdentity` needs no permission. None of these actions can read data inside volumes,
snapshots or databases.

```bash
cd terraform/aws-scanner-access
terraform init
terraform apply -var 'github_repository=rsk071216-stack/cloud-cost-guardian'
terraform output role_arn   # -> repository variable AWS_ROLE_ARN
```

Repository variables: `AWS_ROLE_ARN`, optionally `CCG_AWS_REGIONS` (for example `us-east-1,eu-west-1`)
and `AWS_DEFAULT_REGION`.

## Multi-account / multi-subscription

- Azure: assign the role at a management group; Resource Graph queries every subscription below it in one call.
- AWS: deploy the same role into each member account (StackSets or a Terraform loop) and run one scan per
  account, or extend the workflow with a matrix over role ARNs. Organization-wide scanning is on the roadmap.
