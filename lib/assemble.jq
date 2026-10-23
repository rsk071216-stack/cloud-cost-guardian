# assemble.jq - combine all normalised findings into the report document.
# Args: $findings[0] (array), $errors[0] (array), $prices[0] (price sheet),
#       $generated_at, $version, $providers (csv), $aws_regions (csv), $aws_account, $executions

def r2: (. * 100 | round) / 100;
def csv: split(",") | map(select(. != ""));

($findings[0] | sort_by(-.monthly_cost_estimate, .provider, .rule_id, .resource_id)) as $f
| ($f | map(select(.monthly_cost_estimate > 0))) as $savings
# The same resource can be hit by two rules (e.g. a legacy-SKU VM that is also stopped).
# Count each resource once, using its largest single saving, so totals are never inflated.
| ($savings | group_by(.resource_id) | map(max_by(.monthly_cost_estimate))) as $dedup
| ($dedup | map(.monthly_cost_estimate) | add // 0 | r2) as $monthly
| {
    schema_version: "1.0",
    tool: {name: "cloud-cost-guardian", version: $version},
    generated_at: $generated_at,
    providers: ($providers | csv),
    scope: {
      azure_subscriptions: ([$f[] | select(.provider == "azure") | .account] | unique),
      aws_account: $aws_account,
      aws_regions: ($aws_regions | csv)
    },
    price_basis: $prices[0]._meta.basis,
    rule_executions: ($executions | tonumber),
    rules_failed: ($errors[0] | sort_by(.rule_id, .region)),
    summary: {
      estimated_monthly_saving: $monthly,
      estimated_annual_saving: ($monthly * 12 | r2),
      overlap_removed: ((($savings | map(.monthly_cost_estimate) | add // 0) - $monthly) | r2),
      findings_total: ($f | length),
      findings_with_saving: ($savings | length),
      governance_findings: (($f | length) - ($savings | length)),
      by_severity: (reduce $f[] as $x ({high: 0, medium: 0, low: 0}; .[$x.severity] += 1)),
      by_provider: (
        [$f[].provider] | unique
        | map(. as $p | {
            key: $p,
            value: {
              findings: ([$f[] | select(.provider == $p)] | length),
              monthly_saving: ([$dedup[] | select(.provider == $p) | .monthly_cost_estimate] | add // 0 | r2)
            }
          })
        | from_entries
      ),
      by_rule: (
        $f | group_by(.rule_id)
        | map({
            rule_id: .[0].rule_id,
            provider: .[0].provider,
            title: .[0].title,
            category: .[0].category,
            risk: (map(.risk) | unique | join("/")),
            findings: length,
            monthly_saving: (map(.monthly_cost_estimate) | add | r2)
          })
        | sort_by(-.monthly_saving, .rule_id)
      )
    },
    findings: $f
  }
