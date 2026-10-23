# ADR 0005: Golden-file tests with mocked cloud CLIs

- Status: Accepted
- Date: 2026-10-19

## Context

Cost tooling is usually untested because it "needs a real account". Without tests, a jq typo silently
drops a whole class of findings, or a pricing change halves the headline number without anyone noticing.

## Decision

- `tests/mocks/bin/az` and `tests/mocks/bin/aws` replace the real CLIs in `PATH` and serve recorded API
  responses from `tests/fixtures`. They refuse any operation that is not `describe-*`, `get-*`, `list-*`,
  `graph query` or `account show`.
- `tests/run.sh` runs the real scanner end-to-end (query scripts, normaliser, assembler, renderers) with a
  fixed clock and compares `findings.json`, `report.md`, `report.html` and `issue.md` with golden files.
- The committed `docs/sample-report.md` must equal the golden report, so the README never shows output the
  code cannot produce.
- Edge cases are covered by fixtures: Resource Graph paging, AccessDenied on one rule, a cloud that is not
  logged in, snapshots under the age threshold, deleted NAT gateways, load balancers with healthy targets.

## Consequences

- CI proves the pipeline without any cloud credentials.
- The KQL queries themselves are not executed in CI (Resource Graph has no local emulator); the fixtures
  encode the documented output columns of each query, and the queries are verified against real tenants
  during engagements.
- Golden files are regenerated with `tests/run.sh --update`; the diff must be reviewed in the pull request.
