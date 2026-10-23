# render-html.jq - findings.json -> report.html (single self-contained file, no external assets)
include "format";

def h: tostring | @html;
def risk_badge: "<span class=\"badge risk-\(. | h)\">\(risk_label | h)</span>";
def clouds($p): if ($p | length) == 0 then "none" else ($p | map(cloud_label) | join(", ")) end;

. as $doc
| .summary as $s
| ([.findings[] | select(.monthly_cost_estimate > 0)]) as $paid
| ([.findings[] | select(.monthly_cost_estimate == 0)]) as $free
| [
    "<!doctype html>",
    "<html lang=\"en\">",
    "<head>",
    "<meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>Cloud savings report</title>",
    "<style>",
    ":root{--bg:#f7f8fa;--card:#fff;--text:#1d2330;--muted:#5b6475;--line:#e3e6ec;--accent:#0b7a53;--high:#b42318;--medium:#b54708;--low:#067647}",
    "@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--card:#171b23;--text:#e6e9ef;--muted:#9aa3b2;--line:#2a303b;--accent:#3ccf91;--high:#f97066;--medium:#fdb022;--low:#47cd89}}",
    "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}",
    "main{max-width:1200px;margin:0 auto;padding:24px 16px}h1{margin:0 0 4px;font-size:26px}h2{margin:32px 0 12px;font-size:19px}",
    ".meta{color:var(--muted);font-size:13px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin-top:20px}",
    ".card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}.card .k{color:var(--muted);font-size:13px}.card .v{font-size:24px;font-weight:650}",
    ".card.hero .v{color:var(--accent)}.wrap{overflow-x:auto;background:var(--card);border:1px solid var(--line);border-radius:10px}",
    "table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}",
    "th{color:var(--muted);font-weight:600;white-space:nowrap}td.num,th.num{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}",
    "code{font:12.5px ui-monospace,SFMono-Regular,Consolas,monospace;word-break:break-all}",
    ".badge{display:inline-block;padding:1px 8px;border-radius:999px;font-size:12px;font-weight:600;border:1px solid currentColor}",
    ".risk-high{color:var(--high)}.risk-medium{color:var(--medium)}.risk-low{color:var(--low)}",
    "ul.notes{color:var(--muted);padding-left:18px}footer{margin-top:32px;color:var(--muted);font-size:12px}",
    "</style>",
    "</head>",
    "<body>",
    "<main>",
    "<h1>Cloud savings report</h1>",
    "<div class=\"meta\">Generated \($doc.generated_at | h) &middot; Clouds: \(clouds($doc.providers) | h) &middot; Rule executions: \($doc.rule_executions) &middot; \($doc.tool.name | h) \($doc.tool.version | h)</div>",
    "<div class=\"cards\">",
    "<div class=\"card hero\"><div class=\"k\">Estimated monthly saving</div><div class=\"v\">\($s.estimated_monthly_saving | money | h)</div></div>",
    "<div class=\"card hero\"><div class=\"k\">Estimated annual saving</div><div class=\"v\">\($s.estimated_annual_saving | money | h)</div></div>",
    "<div class=\"card\"><div class=\"k\">Actionable findings</div><div class=\"v\">\($s.findings_with_saving)</div></div>",
    "<div class=\"card\"><div class=\"k\">Without priced saving</div><div class=\"v\">\($s.governance_findings)</div></div>",
    "</div>",
    "<h2>Savings by rule</h2>",
    "<div class=\"wrap\"><table>",
    "<thead><tr><th>Rule</th><th>Cloud</th><th class=\"num\">Findings</th><th class=\"num\">Est. monthly saving</th><th>Risk</th></tr></thead><tbody>",
    ($s.by_rule[] | "<tr><td>\(.title | h)<br><code>\(.rule_id | h)</code></td><td>\(.provider | cloud_label | h)</td><td class=\"num\">\(.findings)</td><td class=\"num\">\(.monthly_saving | money | h)</td><td>\(.risk | split("/") | map(risk_badge) | join(" "))</td></tr>"),
    "</tbody></table></div>",
    "<h2>Findings ranked by estimated monthly saving</h2>",
    "<div class=\"wrap\"><table>",
    "<thead><tr><th class=\"num\">#</th><th>Cloud</th><th>Resource</th><th>Region</th><th>Rule</th><th class=\"num\">Est. $/month</th><th>Risk</th><th>Recommendation</th></tr></thead><tbody>",
    ($paid | to_entries[] | .key as $i | .value
      | "<tr><td class=\"num\">\($i + 1)</td><td>\(.provider | cloud_label | h)</td><td><code title=\"\(.resource_id | h)\">\(.resource_name | h)</code></td><td>\(.region | h)</td><td><code>\(.rule_id | h)</code></td><td class=\"num\">\(.monthly_cost_estimate | money | h)</td><td>\(.risk | risk_badge)</td><td>\(.recommendation | h)</td></tr>"),
    "</tbody></table></div>",
    "<h2>Findings without a priced saving</h2>",
    "<div class=\"wrap\"><table>",
    "<thead><tr><th>Cloud</th><th>Resource</th><th>Region</th><th>Rule</th><th>Recommendation</th></tr></thead><tbody>",
    ($free[] | "<tr><td>\(.provider | cloud_label | h)</td><td><code title=\"\(.resource_id | h)\">\(.resource_name | h)</code></td><td>\(.region | h)</td><td><code>\(.rule_id | h)</code></td><td>\(.recommendation | h)</td></tr>"),
    "</tbody></table></div>",
    (if ($doc.rules_failed | length) > 0 then
       "<h2>Rules that could not run</h2>",
       "<div class=\"wrap\"><table><thead><tr><th>Rule</th><th>Region</th><th>Error</th></tr></thead><tbody>",
       ($doc.rules_failed[] | "<tr><td><code>\(.rule_id | h)</code></td><td>\(if .region == "" then "-" else .region end | h)</td><td>\(.message | h)</td></tr>"),
       "</tbody></table></div>"
     else empty end),
    "<h2>How to read this report</h2>",
    "<ul class=\"notes\">",
    "<li><strong>Estimates, not invoices.</strong> \($doc.price_basis | h)</li>",
    "<li><strong>No double counting.</strong> When two rules flag the same resource, totals count it once at the larger saving (\($s.overlap_removed | money | h) of overlap removed).</li>",
    "<li><strong>Risk</strong> is the remediation risk: Low = safe after a quick owner check, Medium = snapshot or back up first, High = needs an owner decision.</li>",
    "<li><strong>Nothing was changed.</strong> The scanner only uses read-only list, describe and query APIs.</li>",
    "</ul>",
    "<footer>Hover a resource name to see its full resource ID. Machine-readable data: findings.json.</footer>",
    "</main>",
    "</body>",
    "</html>"
  ]
| join("\n")
