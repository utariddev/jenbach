#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_FILE="$SCRIPT_DIR/price_sources.json"
UPSTREAM_FIXTURE="${1:-}"
TARGET_PRICES="${2:-$REPO_DIR/prices.json}"

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required." >&2; exit 1; }

if [ ! -r "$SOURCES_FILE" ] || ! jq -e '(.upstream_url | type == "string") and (.models | type == "object")' "$SOURCES_FILE" >/dev/null 2>&1; then
  echo "Error: Invalid or missing $SOURCES_FILE" >&2
  exit 1
fi

TMP_UPSTREAM=$(mktemp)
TMP_NEW=$(mktemp)
trap 'rm -f "$TMP_UPSTREAM" "$TMP_NEW" "${TARGET_PRICES}.tmp.$$"' EXIT

if [ -n "$UPSTREAM_FIXTURE" ]; then
  if [ ! -r "$UPSTREAM_FIXTURE" ]; then
    echo "Error: Cannot read upstream fixture: $UPSTREAM_FIXTURE" >&2
    exit 1
  fi
  cp "$UPSTREAM_FIXTURE" "$TMP_UPSTREAM"
else
  command -v curl >/dev/null 2>&1 || { echo "Error: curl is required." >&2; exit 1; }
  UPSTREAM_URL=$(jq -r '.upstream_url' "$SOURCES_FILE")
  if ! curl -fsSL --max-time 20 "$UPSTREAM_URL" -o "$TMP_UPSTREAM"; then
    echo "Error: Failed to fetch upstream pricing from $UPSTREAM_URL" >&2
    exit 1
  fi
fi

if ! jq -e 'type == "object"' "$TMP_UPSTREAM" >/dev/null 2>&1; then
  echo "Error: Upstream pricing payload is not a JSON object." >&2
  exit 1
fi

if [ -r "$TARGET_PRICES" ] && jq -e '.models | type == "object"' "$TARGET_PRICES" >/dev/null 2>&1; then
  OLD_JSON=$(cat "$TARGET_PRICES")
else
  OLD_JSON='{"updated_at":"0000-00-00","models":{}}'
fi

TODAY=$(date -u +%Y-%m-%d)

# Build candidate models JSON and emit warnings to stderr for unmatched keys
GENERATED=$(jq -n \
  --slurpfile src "$SOURCES_FILE" \
  --slurpfile up "$TMP_UPSTREAM" \
  --argjson old "$OLD_JSON" \
  --arg today "$TODAY" '
  def r6: (. * 1000000 | round) / 1000000;
  ($src[0]) as $s |
  ($up[0]) as $u |
  ($old.models // {}) as $om |

  reduce ($s.models | to_entries[]) as $entry (
    {models: {}, warnings: []};
    ($entry.key) as $k |
    ($entry.value) as $cfg |
    (if ($om[$k] | type) == "object" then $om[$k] else null end) as $prev |
    ([
      $cfg.candidates[]? |
      . as $cid |
      $u[$cid] |
      select(
        type == "object" and
        (.input_cost_per_token | type == "number") and
        (.output_cost_per_token | type == "number")
      )
    ] | .[0] // null) as $hit |
    if $hit != null then
      ($hit.input_cost_per_token * 1000000 | r6) as $in |
      ($hit.output_cost_per_token * 1000000 | r6) as $out |
      (if (($hit.cache_read_input_token_cost | type) == "number" and $hit.cache_read_input_token_cost >= 0) then
        (($hit.cache_read_input_token_cost * 1000000) | r6)
       elif ($prev != null and ($prev["in"] // -1) == $in and ($prev.cached | type) == "number" and $prev.cached >= 0 and $prev.cached <= $in) then
        $prev.cached
       else
        (($in * 0.25) | r6)
       end) as $cached |
      (if ($prev != null and $prev["in"] == $in and $prev.cached == $cached and $prev.out == $out and (($prev.note // "") != "")) then
        $prev.note
       else
        ($cfg.note // "")
       end) as $note |
      .models[$k] = {"in": $in, "cached": $cached, "out": $out, "note": $note}
    else
      .warnings += ["Warning: No matching upstream candidate for '\''\($k)'\''; preserving existing entry."] |
      if $prev != null then
        .models[$k] = $prev
      else
        .
      end
    end
  ) |
  ($s.default_from // "argon") as $df |
  (.models[$df] // (if ($om.default | type) == "object" then $om.default else null end) // null) as $def_src |
  (if $def_src != null then
    .models["default"] = {
      "in": $def_src["in"],
      "cached": $def_src.cached,
      "out": $def_src.out,
      "note": "Fallback rate"
    }
   else
    .
   end) |
  {
    warnings: .warnings,
    payload: {
      updated_at: $today,
      models: .models
    }
  }
')

# Print any warnings to stderr
printf '%s' "$GENERATED" | jq -r '.warnings[]' >&2

printf '%s\n' "$GENERATED" | jq '.payload' > "$TMP_NEW"

# Compare normalized .models against existing target prices.json
OLD_MODELS_NORM=$(printf '%s' "$OLD_JSON" | jq -S -c '.models // {}')
NEW_MODELS_NORM=$(jq -S -c '.models // {}' "$TMP_NEW")

if [ "$OLD_MODELS_NORM" = "$NEW_MODELS_NORM" ]; then
  exit 0
fi

# Price Validation Guard
if ! jq -e '
  (.models | type == "object") and
  (.models.default | type == "object") and
  ([.models[] | (
    (.["in"] | type == "number") and .["in"] > 0 and .["in"] < 500 and
    (.cached | type == "number") and .cached >= 0 and .cached <= .["in"] and
    (.out | type == "number") and .out > 0 and .out < 1000
  )] | all)
' "$TMP_NEW" >/dev/null 2>&1; then
  echo "Error: Price Validation Guard rejected generated prices.json." >&2
  exit 1
fi

# Atomic write
mkdir -p "$(dirname "$TARGET_PRICES")"
cp "$TMP_NEW" "${TARGET_PRICES}.tmp.$$" && mv -f "${TARGET_PRICES}.tmp.$$" "$TARGET_PRICES"

# Generate Markdown diff table
DIFF_MD=$(jq -rn --argjson old "$OLD_JSON" --slurpfile new "$TMP_NEW" '
  ($old.models // {}) as $om |
  ($new[0].models // {}) as $nm |
  (($om | keys) + ($nm | keys) | unique) as $all_keys |
  def fmt_rate(r): if r == null then "-" else (r | tostring) end;
  "### Model Pricing Diff (\($new[0].updated_at))\n\n" +
  "| Model | Change | Input / 1M | Cached / 1M | Output / 1M |\n" +
  "| :--- | :--- | ---: | ---: | ---: |\n" +
  ([
    $all_keys[] | . as $k |
    (if ($om[$k] | type) == "object" then $om[$k] else null end) as $o |
    (if ($nm[$k] | type) == "object" then $nm[$k] else null end) as $n |
    if $o == null and $n != null then
      "| `\($k)` | Added | \(fmt_rate($n["in"])) | \(fmt_rate($n.cached)) | \(fmt_rate($n.out)) |"
    elif $o != null and $n == null then
      "| `\($k)` | Removed | \(fmt_rate($o["in"])) | \(fmt_rate($o.cached)) | \(fmt_rate($o.out)) |"
    elif ($o["in"] != $n["in"] or $o.cached != $n.cached or $o.out != $n.out) then
      "| `\($k)` | Updated | \(fmt_rate($o["in"])) -> \(fmt_rate($n["in"])) | \(fmt_rate($o.cached)) -> \(fmt_rate($n.cached)) | \(fmt_rate($o.out)) -> \(fmt_rate($n.out)) |"
    else empty end
  ] | join("\n"))
')

printf '%s\n' "$DIFF_MD"
if [ -n "${SYNC_SUMMARY_FILE:-}" ]; then
  printf '%s\n' "$DIFF_MD" > "$SYNC_SUMMARY_FILE"
fi
