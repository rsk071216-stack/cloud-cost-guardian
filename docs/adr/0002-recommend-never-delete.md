# ADR 0002: Recommend, never remediate automatically

- Status: Accepted
- Date: 2026-10-19

## Context

Many cleanup tools can delete idle resources automatically. In practice the riskiest findings are the
ones that look the most obviously wasteful: an unattached disk can be the only copy of a database after
a failed migration, and an "idle" NAT gateway may serve a monthly batch job.

## Decision

- The scanner is strictly read-only. The cloud identities it uses cannot write (see `docs/permissions.md`),
  and the test suite fails if any non read-only CLI call is attempted.
- Every finding carries a `risk` field (risk of acting on it) and a human-readable `recommendation`.
- Remediation is a separate, reviewed step: a change ticket, a pull request or a runbook executed by the
  owner. The weekly GitHub issue is the hand-off point.
- Preventive guardrails (budgets, anomaly alerts, office-hours shutdown) are deployed through Terraform
  where they can be reviewed in a pull request and costed with Infracost.

## Consequences

- Clients can grant access with confidence; the security conversation takes minutes, not weeks.
- Savings are realised more slowly than with auto-deletion. This is intentional; trust is the product.
