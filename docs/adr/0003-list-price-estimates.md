# ADR 0003: Estimate savings from a versioned list-price sheet

- Status: Accepted
- Date: 2026-10-19

## Context

A finding without a dollar value does not get prioritised. Exact numbers would require the client's
billing export (negotiated discounts, reservations, savings plans) and live pricing API calls for every
SKU in every region, which adds permissions, latency and non-determinism.

## Decision

- `pricing/price-sheet.json` holds approximate pay-as-you-go list prices for the SKUs the rules price,
  with a `_meta.basis` statement that is printed in every report.
- Each rule documents its savings formula in `rules/catalogue.json` (`savings_formula`).
- When a price is unknown the finding is still reported, with `$0` and an explicit "not estimated" note,
  rather than inventing a number.
- Totals de-duplicate by resource ID so two rules hitting one resource never inflate the headline figure.
- Snapshot estimates use provisioned size and are labelled as upper bounds (snapshots are incremental).

## Consequences

- Reports are reproducible and testable; the same input always produces the same report.
- Figures are directionally right for prioritisation. For a client engagement, the price sheet is tuned
  to their region and discounts, or the findings are joined with their Cost Management / CUR export.
