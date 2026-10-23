# ADR 0004: OIDC federation only, no stored cloud credentials

- Status: Accepted
- Date: 2026-10-19

## Context

A scheduled job that reads several client accounts is an attractive target. Long-lived service
principal secrets and IAM access keys leak through logs, forks and laptop backups, and need rotation.

## Decision

- The weekly workflow uses `azure/login` and `aws-actions/configure-aws-credentials` with GitHub's OIDC
  token (`id-token: write`). Credentials live for at most one hour.
- Cloud trust is pinned to `repo:<owner>/<repo>:ref:refs/heads/main` and the expected audience, so pull
  requests, forks and other branches cannot assume the scanner identity.
- Configuration is passed as repository **variables** (client ID, tenant ID, role ARN are identifiers,
  not secrets). The only secret in the repository settings is the optional `INFRACOST_API_KEY`.
- Every third-party action is pinned to a full commit SHA with the version in a comment; Dependabot
  proposes updates weekly.

## Consequences

- Onboarding a client is a role assignment plus a federated credential, both reviewable as code.
- Running from a fork or a feature branch will not reach any cloud account; this is intended.
