# format.jq - shared formatting helpers for the report renderers (imported with `include "format";`).

# 1234567 -> "1,234,567"
def commas:
  tostring
  | if length <= 3 then . else (.[0:length - 3] | commas) + "," + .[length - 3:] end;

# 1234.5 -> "$1,234.50"
def money:
  (. * 100 | round) as $cents
  | (($cents / 100) | floor) as $whole
  | ($cents - ($whole * 100)) as $frac
  | "$" + ($whole | commas) + "." + (if $frac < 10 then "0" else "" end) + ($frac | tostring);

# Escape a value for a Markdown table cell.
def md: tostring | gsub("[|]"; "\\|") | gsub("[\r\n]+"; " ");

def cloud_label: {"azure": "Azure", "aws": "AWS"}[.] // .;

def risk_label: {"low": "Low", "medium": "Medium", "high": "High"}[.] // .;
