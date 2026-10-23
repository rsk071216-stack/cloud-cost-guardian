# render-markdown.jq - findings.json -> report.md
include "format";

. as $doc
| .summary as $s
| ([.findings[] | select(.monthly_cost_estimate > 0)]) as $paid
| ([.findings[] | select(.monthly_cost_estimate == 0)]) as $free
| [
    "# Cloud savings report",
    "",
    "**Generated:** \($doc.generated_at) | **Clouds:** \(if ($doc.providers | length) == 0 then "none" else ($doc.providers | map(cloud_label) | join(", ")) end) | **Rule executions:** \($doc.rule_executions) | **Tool:** \($doc.tool.name) \($doc.tool.version)",
    "",
    "> **Estimated saving: \($s.estimated_monthly_saving | money) per month (\($s.estimated_annual_saving | money) per year)** from \($s.findings_with_saving) actionable findings.",
    "> Read-only scan: nothing was changed. Figures are list-price estimates, see [How to read this report](#how-to-read-this-report).",
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "|---|---|",
    "| Estimated monthly saving | **\($s.estimated_monthly_saving | money)** |",
    "| Estimated annual saving | **\($s.estimated_annual_saving | money)** |",
    ($s.by_provider | to_entries[] | "| \(.key | cloud_label) monthly saving | \(.value.monthly_saving | money) (\(.value.findings) findings) |"),
    "| Findings with a direct saving | \($s.findings_with_saving) |",
    "| Findings without a priced saving | \($s.governance_findings) |",
    "| Severity (high / medium / low) | \($s.by_severity.high) / \($s.by_severity.medium) / \($s.by_severity.low) |",
    "| Rules that failed to run | \($doc.rules_failed | length) |",
    "",
    "## Savings by rule",
    "",
    "| Rule | Cloud | Findings | Est. monthly saving | Remediation risk |",
    "|---|---|---:|---:|---|",
    ($s.by_rule[] | "| \(.title | md) (`\(.rule_id)`) | \(.provider | cloud_label) | \(.findings) | \(.monthly_saving | money) | \(.risk | split("/") | map(risk_label) | join(" / ")) |"),
    "",
    "## Findings ranked by estimated monthly saving",
    "",
    (if ($paid | length) == 0 then "No findings with a direct saving."
     else
       "| # | Cloud | Resource | Region | Rule | Est. $/month | Risk | Recommendation |",
       "|---:|---|---|---|---|---:|---|---|",
       ($paid | to_entries[] | .key as $i | .value
         | "| \($i + 1) | \(.provider | cloud_label) | `\(.resource_name | md)` | \(.region | md) | `\(.rule_id)` | \(.monthly_cost_estimate | money) | \(.risk | risk_label) | \(.recommendation | md) |")
     end),
    "",
    "## Findings without a priced saving",
    "",
    "Governance and hygiene items (they block cost allocation or hide billed resources), plus anything whose price is not in the price sheet.",
    "",
    (if ($free | length) == 0 then "None."
     else
       "| Cloud | Resource | Region | Rule | Recommendation |",
       "|---|---|---|---|---|",
       ($free[] | "| \(.provider | cloud_label) | `\(.resource_name | md)` | \(.region | md) | `\(.rule_id)` | \(.recommendation | md) |")
     end),
    (if ($doc.rules_failed | length) > 0 then
       "",
       "## Rules that could not run",
       "",
       "| Rule | Region | Error |",
       "|---|---|---|",
       ($doc.rules_failed[] | "| `\(.rule_id)` | \(if .region == "" then "-" else .region end) | \(.message | md) |")
     else empty end),
    "",
    "## How to read this report",
    "",
    "- **Estimates, not invoices.** \($doc.price_basis)",
    "- **No double counting.** When two rules flag the same resource, totals count it once at the larger saving (\($s.overlap_removed | money) of overlap removed).",
    "- **Risk** is the remediation risk: *Low* = safe to action after a quick owner check, *Medium* = take a snapshot or backup first, *High* = needs an owner decision.",
    "- **Nothing was changed.** The scanner uses read-only list/describe/query APIs. Every action above is a recommendation for a human to approve.",
    "- Full resource IDs and evidence for every finding are in `findings.json` next to this report."
  ]
| join("\n")
