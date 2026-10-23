# ADR 0001: Azure Resource Graph and the AWS CLI instead of an SDK application

- Status: Accepted
- Date: 2026-10-19

## Context

A cost review usually starts on a client machine or a locked-down CI runner. Installing a Python or
Node toolchain, a container runtime or a SaaS agent is often the slowest part of an engagement, and every
extra dependency needs a security review before the client lets it near production accounts.

## Decision

- **Azure:** every rule is a single Azure Resource Graph (KQL) query. One call covers every subscription
  under a management group, results come back in seconds, and the same `.kql` file can be pasted into
  Resource Graph Explorer or an Azure Workbook by the client's own team.
- **AWS:** every rule is a small bash script using `aws ... describe-*` and `jq`. AWS Config advanced
  queries were considered but require Config to be enabled and recording the right resource types,
  which many small accounts do not have.
- Only `bash`, `jq`, `az` and `aws` are required. All four are pre-installed on GitHub-hosted runners
  and in Azure Cloud Shell / AWS CloudShell.

## Consequences

- Queries are readable by non-developers and reusable outside this tool.
- Bash needs discipline: `set -euo pipefail`, ShellCheck in CI and a test suite with mocked CLIs.
- Complex logic (pricing, de-duplication, rendering) lives in `jq` programs under `lib/`, which are
  deterministic and covered by golden-file tests.
