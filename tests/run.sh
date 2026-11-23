#!/usr/bin/env bash
set -euo pipefail
export JENBACH_HEIGHT=0

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc" >&2
    echo "  expected: [$expected]" >&2
    echo "  actual:   [$actual]" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (missing '$needle')" >&2
    echo "  actual: [$haystack]" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (unexpected '$needle')" >&2
    echo "  actual: [$haystack]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# 1. Syntax checks
bash -n "$REPO_DIR/statusline.sh" "$REPO_DIR/report.sh" "$REPO_DIR/install.sh" "$REPO_DIR/uninstall.sh" "$REPO_DIR/lib/auto_update.sh" "$REPO_DIR/scripts/sync_prices.sh" "$REPO_DIR/tests/run.sh"
if command -v python3 >/dev/null 2>&1; then
  PYC_TMP=$(mktemp -d)
  PYTHONPYCACHEPREFIX="$PYC_TMP" python3 -m py_compile "$REPO_DIR/lib/subagent_sync.py"
  rm -rf "$PYC_TMP"
fi
jq empty "$REPO_DIR/prices.json" "$REPO_DIR/scripts/price_sources.json"
PASS=$((PASS + 1))

# 2. Unit tests for lib/common.jq
LIB_DIR="$REPO_DIR/lib"
assert_eq "repeat_str(0)" "" "$(jq -L "$LIB_DIR" -rn 'include "common"; repeat_str(" "; 0)')"
assert_eq "repeat_str(-2)" "" "$(jq -L "$LIB_DIR" -rn 'include "common"; repeat_str(" "; -2)')"
assert_eq "fmt_usd3(0)" '$0.000' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_usd3(0)')"
assert_eq "fmt_usd3(0.05)" '$0.050' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_usd3(0.05)')"
assert_eq "fmt_usd3(0.9999)" '$1.000' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_usd3(0.9999)')"
assert_eq "fmt_sub_cell(0)" '-' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_sub_cell(0)')"
assert_eq "fmt_sub_cell(0.0002)" '<$0.001' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_sub_cell(0.0002)')"
assert_eq "fmt_sub_cell(0.15)" '$0.150' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_sub_cell(0.15)')"
assert_eq "fmt_tok(999950)" '1M' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_tok(999950; true)')"
assert_eq "fmt_tok(500)" '500' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_tok(500; true)')"
assert_eq "fmt_tok(1500)" '1.5k' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_tok(1500; true)')"
assert_eq "fmt_tok(1500, false)" '1500' "$(jq -L "$LIB_DIR" -rn 'include "common"; fmt_tok(1500; false)')"
assert_eq "progress_bar(-10)" '------' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(-10; 6; true)')"
assert_eq "progress_bar(0, plain)" '------' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(0; 6; true)')"
assert_eq "progress_bar(0, modern)" '░░░░░░' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(0; 6; false)')"
assert_eq "progress_bar(null, plain)" '------' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(null; 6; true)')"
assert_eq "progress_bar(1, plain)" '#-----' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(1; 6; true)')"
assert_eq "progress_bar(1, modern)" '▓░░░░░' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(1; 6; false)')"
assert_eq "progress_bar(92, plain)" '#####-' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(92; 6; true)')"
assert_eq "progress_bar(92, modern)" '▓▓▓▓▓░' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(92; 6; false)')"
assert_eq "progress_bar(99.9, plain)" '#####-' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(99.9; 6; true)')"
assert_eq "progress_bar(99.99999999999999, plain)" '#####-' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(99.99999999999999; 6; true)')"
assert_eq "progress_bar(100, plain)" '######' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(100; 6; true)')"
assert_eq "progress_bar(100, modern)" '▓▓▓▓▓▓' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(100; 6; false)')"
assert_eq "progress_bar(150)" '######' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(150; 6; true)')"
assert_eq "progress_bar(width=0)" '' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(50; 0; true)')"
assert_eq "progress_bar(width=1, 0)" '-' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(0; 1; true)')"
assert_eq "progress_bar(width=1, 50)" '#' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(50; 1; true)')"
assert_eq "progress_bar(width=1, 50, modern)" '▓' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(50; 1; false)')"
assert_eq "progress_bar(width=1, 100)" '#' "$(jq -L "$LIB_DIR" -rn 'include "common"; progress_bar(100; 1; true)')"
assert_eq "pad_cell(l)" 'hi   ' "$(jq -L "$LIB_DIR" -rn 'include "common"; pad_cell("hi"; 5; "l")')"
assert_eq "pad_cell(r)" '   hi' "$(jq -L "$LIB_DIR" -rn 'include "common"; pad_cell("hi"; 5; "r")')"
assert_eq "paint(off)" 'hi' "$(jq -L "$LIB_DIR" -rn 'include "common"; paint("hi"; "red"; false)')"
assert_eq "paint(empty)" '' "$(jq -L "$LIB_DIR" -rn 'include "common"; paint(""; "red"; true)')"
assert_eq "hit_color(85)" 'bold_green' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(85)')"
assert_eq "hit_color(80)" 'bold_green' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(80)')"
assert_eq "hit_color(79)" 'green' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(79)')"
assert_eq "hit_color(60)" 'green' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(60)')"
assert_eq "hit_color(50)" 'green' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(50)')"
assert_eq "hit_color(49)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(49)')"
assert_eq "hit_color(30)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(30)')"
assert_eq "hit_color(null)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color(null)')"
assert_eq "hit_color(string)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; hit_color("bad")')"
assert_eq "think_color(High)" 'bold' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color("High")')"
assert_eq "think_color(high)" 'bold' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color("high")')"
assert_eq "think_color(Medium)" '' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color("Medium")')"
assert_eq "think_color(Low)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color("Low")')"
assert_eq "think_color(Minimal)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color("Minimal")')"
assert_eq "think_color(null)" 'dim' "$(jq -L "$LIB_DIR" -rn 'include "common"; think_color(null)')"
assert_eq "short_model modern" '123456789012345…' "$(jq -L "$LIB_DIR" -rn 'include "common"; short_model("Gemini 12345678901234567890"; false)')"
assert_eq "short_model plain" '1234567890123...' "$(jq -L "$LIB_DIR" -rn 'include "common"; short_model("Gemini 12345678901234567890"; true)')"
assert_eq "model_quota_bucket argon" "gemini-argon-wtu-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Gemini 3.8 Argon")')"
assert_eq "model_quota_bucket carbon" "gemini-argon-wtu-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Carbon Pro")')"
assert_eq "model_quota_bucket flash" "gemini-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Gemini 3.8 Flash")')"
assert_eq "model_quota_bucket hydrogen" "gemini-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Hydrogen")')"
assert_eq "model_quota_bucket neon" "gemini-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Neon")')"
assert_eq "model_quota_bucket 3p" "3p-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket("Claude Sonnet 4.5")')"
assert_eq "model_quota_bucket null" "3p-weekly" "$(jq -L "$LIB_DIR" -rn 'include "common"; model_quota_bucket(null)')"

assert_eq "subagent_spinner(0, false)" "⠋" "$(jq -L "$LIB_DIR" -rn 'include "common"; subagent_spinner(0; false)')"
assert_eq "subagent_spinner(7, false)" "⠧" "$(jq -L "$LIB_DIR" -rn 'include "common"; subagent_spinner(7; false)')"
assert_eq "subagent_spinner(8, false)" "⠋" "$(jq -L "$LIB_DIR" -rn 'include "common"; subagent_spinner(8; false)')"
assert_eq "subagent_spinner(-1, true)" "/" "$(jq -L "$LIB_DIR" -rn 'include "common"; subagent_spinner(-1; true)')"
assert_eq "subagent_spinner(null, true)" "|" "$(jq -L "$LIB_DIR" -rn 'include "common"; subagent_spinner(null; true)')"

# 3. Isolated HOME integration tests
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT
export HOME="$TMP_HOME"

"$REPO_DIR/install.sh" >/dev/null
JB_DIR="$HOME/.gemini/antigravity-cli/jenbach"
assert_eq "lib/common.jq installed" "true" "$([ -f "$JB_DIR/lib/common.jq" ] && echo true || echo false)"
assert_eq "lib/auto_update.sh installed" "true" "$([ -f "$JB_DIR/lib/auto_update.sh" ] && echo true || echo false)"
assert_eq "lib/subagent_sync.py installed" "true" "$([ -x "$JB_DIR/lib/subagent_sync.py" ] && echo true || echo false)"
assert_eq "VERSION installed" "true" "$([ -f "$JB_DIR/VERSION" ] && echo true || echo false)"
assert_eq "config theme migrated" "modern" "$(jq -r '.theme' "$JB_DIR/report_config.json")"
assert_eq "config color migrated" "auto" "$(jq -r '.color' "$JB_DIR/report_config.json")"
assert_eq "config auto_update_prices migrated" "true" "$(jq -r '.auto_update_prices' "$JB_DIR/report_config.json")"
assert_eq "config default_view migrated" "cycle" "$(jq -r '.default_view' "$JB_DIR/report_config.json")"
assert_eq "config subagent_cost_mode migrated" "split" "$(jq -r '.subagent_cost_mode' "$JB_DIR/report_config.json")"
assert_eq "config statusline_subagent_detail migrated" "true" "$(jq -r '.statusline_subagent_detail' "$JB_DIR/report_config.json")"

# Pre-seed .prices_next_check so baseline tests stay offline before dedicated auto-update suite
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$JB_DIR/.prices_next_check"

# Statusline responsive width tests
PAYLOAD_BASE='{"session_id":"s1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":12400,"total_output_tokens":1800,"used_percentage":14,"current_usage":{"input_tokens":2400,"cache_read_input_tokens":10000}},"cost":{"total_usd":0.05,"subagent_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.845}}}'

OUT_WIDE=$(printf '%s' "$PAYLOAD_BASE" | jq -c '. + {terminal_width: 120}' | "$JB_DIR/statusline.sh")
assert_contains "wide has bar" "▓" "$OUT_WIDE"
assert_contains "wide has sub" "(Sub: \$0.010)" "$OUT_WIDE"

OUT_MED=$(printf '%s' "$PAYLOAD_BASE" | jq -c '. + {terminal_width: 90}' | "$JB_DIR/statusline.sh")
assert_not_contains "medium has no bar" "▓" "$OUT_MED"
assert_contains "medium has down arrow" "↓" "$OUT_MED"

OUT_NAR=$(printf '%s' "$PAYLOAD_BASE" | jq -c '. + {terminal_width: 60}' | "$JB_DIR/statusline.sh")
assert_contains "narrow has dot" "·" "$OUT_NAR"

# NO_COLOR test
OUT_NOCOLOR=$(NO_COLOR=1 bash -c 'printf "%s" "$1" | "$2"' _ "$PAYLOAD_BASE" "$JB_DIR/statusline.sh")
assert_eq "NO_COLOR strips ESC" "0" "$(printf '%s' "$OUT_NOCOLOR" | grep -c $'\x1b' || true)"

# Plain theme test (pure 7-bit ASCII, zero ESC)
"$JB_DIR/report.sh" set theme plain >/dev/null
OUT_PLAIN=$(printf '%s' "$PAYLOAD_BASE" | jq -c '. + {terminal_width: 120}' | "$JB_DIR/statusline.sh")
assert_eq "plain statusline zero ESC" "0" "$(printf '%s' "$OUT_PLAIN" | grep -c $'\x1b' || true)"
assert_eq "plain statusline pure ASCII" "0" "$(LC_ALL=C grep -c '[^ -~]' <(printf '%s\n' "$OUT_PLAIN") || true)"

# Report tests: set theme/color & invalid values
"$JB_DIR/report.sh" set theme compact >/dev/null
"$JB_DIR/report.sh" set color on >/dev/null
if "$JB_DIR/report.sh" set theme bogus 2>/dev/null; then
  echo "FAIL: invalid theme should exit 1" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi
if "$JB_DIR/report.sh" set color bogus 2>/dev/null; then
  echo "FAIL: invalid color should exit 1" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# Report KPI box alignment across themes
"$JB_DIR/report.sh" set theme modern >/dev/null
"$JB_DIR/report.sh" set color on >/dev/null
REP_MODERN=$("$JB_DIR/report.sh")
assert_contains "report modern has KPI box" "╭─ Jenbach Usage" "$REP_MODERN"
assert_contains "report modern has Subagent split" "Sub: \$0.010)" "$(printf '%s\n' "$REP_MODERN" | sed $'s/\x1b\\[[0-9;]*m//g')"
# Verify all box lines (╭, │, ╰) have identical visible width
BOX_WIDTHS=$(printf '%s\n' "$REP_MODERN" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^[╭│╰]' | awk '{print length($0)}' | sort -u | wc -l)
assert_eq "modern KPI box consistent width" "1" "$BOX_WIDTHS"

"$JB_DIR/report.sh" set theme plain >/dev/null
REP_PLAIN=$("$JB_DIR/report.sh")
assert_eq "plain report zero ESC" "0" "$(printf '%s' "$REP_PLAIN" | grep -c $'\x1b' || true)"
assert_eq "plain report pure ASCII" "0" "$(LC_ALL=C grep -c '[^ -~]' <(printf '%s\n' "$REP_PLAIN") || true)"

# Prices test
PRICES_OUT=$("$JB_DIR/report.sh" prices)
assert_contains "prices has Model Key" "Model Key" "$PRICES_OUT"

# Additional statusline & report edge-case tests
OUT_EMPTY=$(printf '' | "$JB_DIR/statusline.sh")
assert_eq "empty stdin fallback" "Statusline ready..." "$OUT_EMPTY"

OUT_STR_MODEL=$(printf '%s' '{"session_id":"s_str","model":"gemini-3.8-flash","context_window":{"total_input_tokens":100,"total_output_tokens":50,"used_percentage":5}}' | "$JB_DIR/statusline.sh")
assert_contains "string model handled" "gemini-3.8-flash" "$OUT_STR_MODEL"
assert_contains "null quota N/A" "N/A" "$OUT_STR_MODEL"

# Turn idempotency
printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" >/dev/null
COST_1=$(jq -r '.cost_usd' "$JB_DIR/usage_logs/s1.json")
printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" >/dev/null
COST_2=$(jq -r '.cost_usd' "$JB_DIR/usage_logs/s1.json")
assert_eq "turn idempotency" "$COST_1" "$COST_2"

# Report CLI validation & reset
for bad_cmd in "unknown-cmd" "set limit abc" "set limit 0" "set chain bogus"; do
  if $JB_DIR/report.sh $bad_cmd >/dev/null 2>&1; then
    echo "FAIL: '$bad_cmd' should exit 1" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done

"$JB_DIR/report.sh" set short off >/dev/null
"$JB_DIR/report.sh" set status-short off >/dev/null
"$JB_DIR/report.sh" set limit 10 >/dev/null
"$JB_DIR/report.sh" set chain off >/dev/null
"$JB_DIR/report.sh" reset >/dev/null
EMPTY_REP=$("$JB_DIR/report.sh")
assert_contains "empty logs message" "No recorded sessions found" "$EMPTY_REP"

# 4. Offline sync_prices.sh tests
SYNC_TMP="$TMP_HOME/sync_test"
mkdir -p "$SYNC_TMP"
cp "$REPO_DIR/prices.json" "$SYNC_TMP/prices.json"

cat << 'JSON' > "$SYNC_TMP/upstream.json"
{
  "gemini/gemini-3.8-flash": {
    "input_cost_per_token": 0.0000003,
    "output_cost_per_token": 0.0000025,
    "cache_read_input_token_cost": 0.000000075
  },
  "gemini/gemini-4-hydrogen": {
    "input_cost_per_token": 0.0000015,
    "output_cost_per_token": 0.0000075
  },
  "gemini/gemini-4-argon": {
    "input_cost_per_token": 0.000002,
    "output_cost_per_token": 0.00001
  },
  "gemini/gemini-4-carbon": {
    "input_cost_per_token": 0.00000125,
    "output_cost_per_token": 0.00001
  },
  "gemini/gemini-4-neon": {
    "input_cost_per_token": 0.000003,
    "output_cost_per_token": 0.000015,
    "cache_read_input_token_cost": 0.00000015
  },
  "claude-sonnet-5-5": {
    "input_cost_per_token": 0.000002,
    "output_cost_per_token": 0.00001,
    "cache_read_input_token_cost": 0.0000001
  },
  "claude-opus-5-5": {
    "input_cost_per_token": 0.000004,
    "output_cost_per_token": 0.00002,
    "cache_read_input_token_cost": 0.0000002
  }
}
JSON

SYNC_DIFF=$(bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream.json" "$SYNC_TMP/prices.json" 2>/dev/null)
assert_contains "sync_prices outputs diff table" "| Model | Change |" "$SYNC_DIFF"
assert_eq "sync_prices flash in" "0.3" "$(jq -r '.models.flash.in' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices flash cached" "0.075" "$(jq -r '.models.flash.cached' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices flash out" "2.5" "$(jq -r '.models.flash.out' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices hydrogen cached preserved on unchanged in" "0.375" "$(jq -r '.models.hydrogen.cached' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices argon note preserved on unchanged rates" "Promo until 2026-11-30" "$(jq -r '.models.argon.note' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices carbon in" "1.25" "$(jq -r '.models.carbon.in' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices carbon cached recomputed on changed in" "0.3125" "$(jq -r '.models.carbon.cached' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices neon added" "3" "$(jq -r '.models.neon.in' "$SYNC_TMP/prices.json")"
assert_eq "sync_prices gpt-oss fallback preserved" "0.50" "$(jq -r '.models["gpt-oss"].in' "$SYNC_TMP/prices.json")"

# Idempotent second run should not bump updated_at or emit diff
jq '.updated_at = "2020-01-01"' "$SYNC_TMP/prices.json" > "$SYNC_TMP/prices.json.tmp" && mv "$SYNC_TMP/prices.json.tmp" "$SYNC_TMP/prices.json"
SYNC_IDEMP=$(bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream.json" "$SYNC_TMP/prices.json" 2>/dev/null)
assert_eq "sync_prices idempotent empty diff" "" "$SYNC_IDEMP"
assert_eq "sync_prices idempotent keeps updated_at" "2020-01-01" "$(jq -r '.updated_at' "$SYNC_TMP/prices.json")"

# Out-of-range rate rejection (in: 9999)
cat << 'JSON' > "$SYNC_TMP/upstream_bad.json"
{
  "gemini/gemini-3.8-flash": {
    "input_cost_per_token": 0.009999,
    "output_cost_per_token": 0.0000025
  }
}
JSON
if bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_bad.json" "$SYNC_TMP/prices.json" >/dev/null 2>&1; then
  echo "FAIL: sync_prices should reject out-of-range rate" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# Unreadable fixture and non-object upstream payload should exit 1
if bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/nonexistent.json" "$SYNC_TMP/prices.json" >/dev/null 2>&1; then
  echo "FAIL: sync_prices should reject missing fixture" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi
printf '[]\n' > "$SYNC_TMP/not_obj.json"
if bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/not_obj.json" "$SYNC_TMP/prices.json" >/dev/null 2>&1; then
  echo "FAIL: sync_prices should reject non-object JSON" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# Fresh generation without existing prices.json + SYNC_SUMMARY_FILE + cached fallback (in*0.25)
rm -f "$SYNC_TMP/fresh_prices.json" "$SYNC_TMP/summary.md"
SYNC_SUMMARY_FILE="$SYNC_TMP/summary.md" bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream.json" "$SYNC_TMP/fresh_prices.json" >/dev/null 2>&1
assert_eq "sync_prices fresh generation creates file" "true" "$([ -s "$SYNC_TMP/fresh_prices.json" ] && echo true || echo false)"
assert_eq "sync_prices fresh carbon cached fallback 0.25x" "0.3125" "$(jq -r '.models.carbon.cached' "$SYNC_TMP/fresh_prices.json")"
assert_contains "sync_prices writes SYNC_SUMMARY_FILE" "| Model | Change |" "$(cat "$SYNC_TMP/summary.md")"

# Stale cached rate > new dropped in rate should fall back to 0.25x instead of failing guard
cat << 'JSON' > "$SYNC_TMP/upstream_drop.json"
{
  "gemini/gemini-4-argon": {
    "input_cost_per_token": 0.0000002,
    "output_cost_per_token": 0.000001
  }
}
JSON
bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_drop.json" "$SYNC_TMP/fresh_prices.json" >/dev/null 2>&1
assert_eq "sync_prices dropped in falls back cached to 0.25x" "0.05" "$(jq -r '.models.argon.cached' "$SYNC_TMP/fresh_prices.json")"

# Stale cached rate <= new dropped in rate (when in changed) and negative cache_read_input_token_cost
cp "$REPO_DIR/prices.json" "$SYNC_TMP/stale_prices.json"
cat << 'JSON' > "$SYNC_TMP/upstream_stale_cached.json"
{
  "together_ai/openai/gpt-oss-120b": {
    "input_cost_per_token": 0.00000015,
    "output_cost_per_token": 0.0000006
  },
  "claude-opus-5-5": {
    "input_cost_per_token": 0.000005,
    "output_cost_per_token": 0.000025,
    "cache_read_input_token_cost": -0.000001
  },
  "gemini/gemini-3.8-flash": {
    "input_cost_per_token": 0.00000075,
    "output_cost_per_token": 0.00000375,
    "cache_read_input_token_cost": -0.000001
  },
  "claude-sonnet-5-5": {
    "input_cost_per_token": 0.000003,
    "output_cost_per_token": 0.000015
  },
  "gemini/gemini-4-neon": {
    "input_cost_per_token": 0.000003,
    "output_cost_per_token": 0.000015,
    "cache_read_input_token_cost": 0
  }
}
JSON
bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_stale_cached.json" "$SYNC_TMP/stale_prices.json" >/dev/null 2>&1
assert_eq "sync_prices stale cached <= new_in recomputes 0.25x on in change" "0.0375" "$(jq -r '.models["gpt-oss"].cached' "$SYNC_TMP/stale_prices.json")"
assert_eq "sync_prices negative cache_read_input_token_cost falls back cleanly" "0.1875" "$(jq -r '.models.flash.cached' "$SYNC_TMP/stale_prices.json")"
assert_eq "sync_prices negative cache_read_input_token_cost preserves non-0.25x prev.cached" "0.50" "$(jq -r '.models.opus.cached' "$SYNC_TMP/stale_prices.json")"
assert_eq "sync_prices unchanged in preserves non-0.25x prev.cached" "0.30" "$(jq -r '.models.sonnet.cached' "$SYNC_TMP/stale_prices.json")"
assert_eq "sync_prices zero cache_read_input_token_cost accepted" "0" "$(jq -r '.models.neon.cached' "$SYNC_TMP/stale_prices.json")"

# Guard rejects cache_read_input_token_cost > input_cost_per_token
cat << 'JSON' > "$SYNC_TMP/upstream_bad_cached.json"
{
  "gemini/gemini-3.8-flash": {
    "input_cost_per_token": 0.000001,
    "output_cost_per_token": 0.000002,
    "cache_read_input_token_cost": 0.000002
  }
}
JSON
if bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_bad_cached.json" "$SYNC_TMP/stale_prices.json" >/dev/null 2>&1; then
  echo "FAIL: sync_prices should reject cached > in" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# Non-object previous model entry in target prices.json should not crash jq
jq '.models.flash = "corrupt"' "$REPO_DIR/prices.json" > "$SYNC_TMP/corrupt_prices.json"
bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_stale_cached.json" "$SYNC_TMP/corrupt_prices.json" >/dev/null 2>&1
assert_eq "sync_prices recovers from non-object prev entry" "0.1875" "$(jq -r '.models.flash.cached' "$SYNC_TMP/corrupt_prices.json")"

# Missing default_from (argon) falls back to valid $om.default, and rejects non-object $om.default
jq 'del(.models.argon)' "$REPO_DIR/prices.json" > "$SYNC_TMP/no_argon_prices.json"
bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_stale_cached.json" "$SYNC_TMP/no_argon_prices.json" >/dev/null 2>&1
assert_eq "sync_prices preserves object om.default when default_from missing" "2.00" "$(jq -r '.models.default.in' "$SYNC_TMP/no_argon_prices.json")"
jq '.models.default = "corrupt"' "$SYNC_TMP/no_argon_prices.json" > "$SYNC_TMP/corrupt_default_prices.json"
if bash "$REPO_DIR/scripts/sync_prices.sh" "$SYNC_TMP/upstream_stale_cached.json" "$SYNC_TMP/corrupt_default_prices.json" >/dev/null 2>&1; then
  echo "FAIL: sync_prices should reject missing default when om.default is non-object" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# 5. Offline auto_update.sh tests with mock curl shim
"$REPO_DIR/install.sh" >/dev/null
MOCK_BIN="$TMP_HOME/mock_bin"
MOCK_STATE="$TMP_HOME/mock_state"
mkdir -p "$MOCK_BIN" "$MOCK_STATE"

cat << 'SH' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${JENBACH_MOCK_STATE:?}"
echo "$@" >> "$STATE_DIR/calls.log"
MODE=$(cat "$STATE_DIR/mode" 2>/dev/null || echo "200")
DELAY=$(cat "$STATE_DIR/delay" 2>/dev/null || echo "0")
if [ "$DELAY" != "0" ]; then
  sleep "$DELAY"
fi

HDR_FILE=""
OUT_FILE=""
WRITE_FMT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -D) HDR_FILE="$2"; shift 2 ;;
    -o) OUT_FILE="$2"; shift 2 ;;
    -w) WRITE_FMT="$2"; shift 2 ;;
    -H|-m|--max-time) shift 2 ;;
    *) shift ;;
  esac
done

if [ "$MODE" = "304" ]; then
  [ -n "$HDR_FILE" ] && printf 'HTTP/1.1 304 Not Modified\r\n\r\n' > "$HDR_FILE"
  [ -n "$OUT_FILE" ] && : > "$OUT_FILE"
  [ "$WRITE_FMT" = "%{http_code}" ] && printf '304'
  exit 0
elif [ "$MODE" = "bad_json" ]; then
  [ -n "$HDR_FILE" ] && printf 'HTTP/1.1 200 OK\r\nETag: "bad1"\r\n\r\n' > "$HDR_FILE"
  [ -n "$OUT_FILE" ] && printf '{"updated_at":"2026-11-21","models":{"default":{"in":9999,"cached":0,"out":10}}}\n' > "$OUT_FILE"
  [ "$WRITE_FMT" = "%{http_code}" ] && printf '200'
  exit 0
elif [ "$MODE" = "500" ]; then
  [ -n "$HDR_FILE" ] && printf 'HTTP/1.1 500 Internal Server Error\r\n\r\n' > "$HDR_FILE"
  [ -n "$OUT_FILE" ] && printf 'error\n' > "$OUT_FILE"
  [ "$WRITE_FMT" = "%{http_code}" ] && printf '500'
  exit 0
else
  [ -n "$HDR_FILE" ] && printf 'HTTP/1.1 200 OK\r\nETag: "v2-etag"\r\n\r\n' > "$HDR_FILE"
  [ -n "$OUT_FILE" ] && cat "$STATE_DIR/body.json" > "$OUT_FILE"
  [ "$WRITE_FMT" = "%{http_code}" ] && printf '200'
  exit 0
fi
SH
# Use bash wrapper since chmod +x may not be needed if invoked directly, wait: PATH lookup needs +x!
# Let's check if chmod +x works inside the test script itself (tests/run.sh runs in bash)
chmod +x "$MOCK_BIN/curl"

export JENBACH_MOCK_STATE="$MOCK_STATE"
export PATH="$MOCK_BIN:$PATH"

cat << 'JSON' > "$MOCK_STATE/body.json"
{
  "updated_at": "2099-01-01",
  "models": {
    "flash": { "in": 0.42, "cached": 0.1, "out": 2.1, "note": "Mock Flash" },
    "default": { "in": 2.0, "cached": 0.5, "out": 10.0, "note": "Fallback rate" }
  }
}
JSON

wait_for_bg() {
  local tries=0
  while [ -d "$JB_DIR/.prices_update.lock" ] && [ "$tries" -lt 40 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
}

# 5a. HTTP 200 + ETag -> updates prices.json, writes .prices.etag and .prices_next_check
rm -f "$JB_DIR/.prices_next_check" "$JB_DIR/.prices.etag" "$MOCK_STATE/calls.log"
echo "200" > "$MOCK_STATE/mode"
"$JB_DIR/report.sh" prices >/dev/null
wait_for_bg
assert_eq "auto_update 200 updated prices.json" "2099-01-01" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"
assert_eq "auto_update 200 wrote .prices.etag" '"v2-etag"' "$(cat "$JB_DIR/.prices.etag")"
assert_eq "auto_update 200 wrote .prices_next_check" "true" "$([ -s "$JB_DIR/.prices_next_check" ] && echo true || echo false)"

# 5b. TTL fast path -> subsequent statusline.sh and report.sh do not invoke mock curl
CALLS_BEFORE=$(wc -l < "$MOCK_STATE/calls.log")
printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" >/dev/null
"$JB_DIR/report.sh" --help >/dev/null
"$JB_DIR/report.sh" config >/dev/null
CALLS_AFTER=$(wc -l < "$MOCK_STATE/calls.log")
assert_eq "TTL fast path 0 curl calls" "$CALLS_BEFORE" "$CALLS_AFTER"

# 5c. HTTP 304 -> sends If-None-Match and leaves prices.json untouched
rm -f "$JB_DIR/.prices_next_check"
echo "304" > "$MOCK_STATE/mode"
"$JB_DIR/report.sh" prices >/dev/null
wait_for_bg
assert_contains "HTTP 304 sent If-None-Match" "If-None-Match: \"v2-etag\"" "$(tail -n 1 "$MOCK_STATE/calls.log")"
assert_eq "HTTP 304 preserved prices.json" "2099-01-01" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"

# 5d. HTTP 200 with out-of-range JSON -> rejected cleanly
rm -f "$JB_DIR/.prices_next_check"
echo "bad_json" > "$MOCK_STATE/mode"
"$JB_DIR/report.sh" prices >/dev/null
wait_for_bg
assert_eq "bad_json rejected, prices.json preserved" "2099-01-01" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"

# 5e. set auto-update off -> mock curl never invoked
"$JB_DIR/report.sh" set auto-update off >/dev/null
rm -f "$JB_DIR/.prices_next_check"
CALLS_BEFORE=$(wc -l < "$MOCK_STATE/calls.log")
echo "200" > "$MOCK_STATE/mode"
printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" >/dev/null
"$JB_DIR/report.sh" prices >/dev/null
CALLS_AFTER=$(wc -l < "$MOCK_STATE/calls.log")
assert_eq "auto-update off skips curl" "$CALLS_BEFORE" "$CALLS_AFTER"

# 5f. set check-interval validation & .prices_next_check clearing
for bad_iv in 0 721 abc; do
  if "$JB_DIR/report.sh" set check-interval "$bad_iv" >/dev/null 2>&1; then
    echo "FAIL: set check-interval $bad_iv should exit 1" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done
"$JB_DIR/report.sh" set check-interval 12 >/dev/null
assert_eq "set check-interval 12 persisted" "12" "$(jq -r '.price_check_interval_hours' "$JB_DIR/report_config.json")"
assert_eq "set check-interval clears .prices_next_check" "false" "$([ -f "$JB_DIR/.prices_next_check" ] && echo true || echo false)"
"$JB_DIR/report.sh" set auto-update on >/dev/null

# 5g. Stale lock recovery (ts = now - 300)
rm -f "$JB_DIR/.prices_next_check"
mkdir -p "$JB_DIR/.prices_update.lock"
printf '%s\n' "$(( $(date +%s) - 300 ))" > "$JB_DIR/.prices_update.lock/ts"
cat << 'JSON' > "$MOCK_STATE/body.json"
{
  "updated_at": "2099-02-02",
  "models": {
    "flash": { "in": 0.45, "cached": 0.1, "out": 2.2, "note": "Recovered" },
    "default": { "in": 2.0, "cached": 0.5, "out": 10.0, "note": "Fallback rate" }
  }
}
JSON
echo "200" > "$MOCK_STATE/mode"
"$JB_DIR/report.sh" prices >/dev/null
wait_for_bg
assert_eq "stale lock recovered and updated" "2099-02-02" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"

# 5h. Pipe EOF test (statusline.sh | cat must not block on 2s sleeping mock curl)
rm -f "$JB_DIR/.prices_next_check"
echo "200" > "$MOCK_STATE/mode"
echo "2" > "$MOCK_STATE/delay"
cat << 'JSON' > "$MOCK_STATE/body.json"
{
  "updated_at": "2099-03-03",
  "models": {
    "flash": { "in": 0.48, "cached": 0.1, "out": 2.3, "note": "Pipe EOF" },
    "default": { "in": 2.0, "cached": 0.5, "out": 10.0, "note": "Fallback rate" }
  }
}
JSON
SECONDS=0
OUT_PIPE=$(printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" | cat)
PIPE_ELAPSED=$SECONDS
assert_contains "pipe EOF statusline returned output" "Flash" "$OUT_PIPE"
assert_eq "pipe EOF completed in <= 1s" "true" "$([ "$PIPE_ELAPSED" -le 1 ] && echo true || echo false)"
wait_for_bg
assert_eq "pipe EOF background curl completed" "2099-03-03" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"
echo "0" > "$MOCK_STATE/delay"

# 5i. HTTP 500 leaves prices.json and .prices.etag untouched
rm -f "$JB_DIR/.prices_next_check"
echo "500" > "$MOCK_STATE/mode"
"$JB_DIR/report.sh" prices >/dev/null
wait_for_bg
assert_eq "HTTP 500 preserves prices.json" "2099-03-03" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"
assert_eq "HTTP 500 preserves .prices.etag" '"v2-etag"' "$(cat "$JB_DIR/.prices.etag")"

# 5j. Missing prices.json with existing .prices.etag skips If-None-Match and restores prices.json
rm -f "$JB_DIR/.prices_next_check" "$JB_DIR/prices.json"
echo "200" > "$MOCK_STATE/mode"
printf '%s' "$PAYLOAD_BASE" | "$JB_DIR/statusline.sh" >/dev/null
wait_for_bg
assert_not_contains "missing prices.json omits If-None-Match" "If-None-Match" "$(tail -n 1 "$MOCK_STATE/calls.log")"
assert_eq "missing prices.json restored" "2099-03-03" "$(jq -r '.updated_at' "$JB_DIR/prices.json")"

# 5k. Active lock (and fresh lock without ts yet) prevents duplicate curl
rm -f "$JB_DIR/.prices_next_check"
mkdir -p "$JB_DIR/.prices_update.lock"
CALLS_BEFORE=$(wc -l < "$MOCK_STATE/calls.log")
"$JB_DIR/report.sh" prices >/dev/null
CALLS_AFTER=$(wc -l < "$MOCK_STATE/calls.log")
assert_eq "fresh lock without ts skips curl (no TOCTOU)" "$CALLS_BEFORE" "$CALLS_AFTER"
rm -rf "$JB_DIR/.prices_update.lock"

# 5l. report.sh update-prices success & invalid JSON rejection
UPD_OUT=$("$JB_DIR/report.sh" update-prices "https://example.test/prices.json")
assert_contains "update-prices prints version" "2099-03-03" "$UPD_OUT"
assert_eq "update-prices clears .prices.etag" "false" "$([ -f "$JB_DIR/.prices.etag" ] && echo true || echo false)"
echo "bad_json" > "$MOCK_STATE/mode"
if "$JB_DIR/report.sh" update-prices "https://example.test/prices.json" >/dev/null 2>&1; then
  echo "FAIL: update-prices should reject invalid JSON" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# 5m. set auto-update invalid value exits 1
if "$JB_DIR/report.sh" set auto-update bogus >/dev/null 2>&1; then
  echo "FAIL: set auto-update bogus should exit 1" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# 6. Info, version, quota cycle detection, and date/cycle filter tests
VER_EXPECTED=$(tr -d '[:space:]' < "$REPO_DIR/VERSION")
assert_eq "--version output" "jenbach $VER_EXPECTED" "$("$JB_DIR/report.sh" --version)"
assert_eq "-v output" "jenbach $VER_EXPECTED" "$("$JB_DIR/report.sh" -v)"

"$JB_DIR/report.sh" set theme modern >/dev/null
"$JB_DIR/report.sh" set color on >/dev/null
INFO_MOD=$("$JB_DIR/report.sh" info)
assert_contains "info has version" "$VER_EXPECTED" "$INFO_MOD"
assert_contains "info has GitHub URL" "https://github.com/utariddev/jenbach" "$INFO_MOD"
assert_contains "info has Jenbach colophon" "Named after the peaceful town of Jenbach." "$INFO_MOD"
assert_not_contains "info has no markdown asterisks" "*Named" "$INFO_MOD"

"$JB_DIR/report.sh" set theme compact >/dev/null
INFO_CMP=$("$JB_DIR/report.sh" info)
assert_contains "compact info has version" "$VER_EXPECTED" "$INFO_CMP"

"$JB_DIR/report.sh" set theme plain >/dev/null
INFO_PLN=$("$JB_DIR/report.sh" info)
assert_eq "plain info zero ESC" "0" "$(printf '%s' "$INFO_PLN" | grep -c $'\x1b' || true)"
assert_eq "plain info pure ASCII" "0" "$(LC_ALL=C grep -c '[^ -~]' <(printf '%s\n' "$INFO_PLN") || true)"
"$JB_DIR/report.sh" set theme modern >/dev/null

# 6a. Quota cycle tracking in statusline.sh
rm -f "$JB_DIR/quota_cycles.json" "$JB_DIR/usage_logs"/*.json
EMPTY_CYCLES=$("$JB_DIR/report.sh" cycles)
assert_contains "empty cycles message" "No weekly quota cycles tracked yet" "$EMPTY_CYCLES"

Q_INIT='{"session_id":"q1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.80,"reset_time":"2026-11-28T00:00:00Z"},"3p-weekly":{"remaining_fraction":0.90,"reset_time":"2026-11-28T00:00:00Z"},"gemini-5h":{"remaining_fraction":0.50,"reset_time":"2026-11-21T20:00:00Z"},"disabled-weekly":{"remaining_fraction":1.0,"disabled":true}}}'
printf '%s' "$Q_INIT" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "quota_cycles.json created" "true" "$([ -f "$JB_DIR/quota_cycles.json" ] && echo true || echo false)"
assert_eq "initial cycle_started_at is empty" "" "$(jq -r '.buckets["gemini-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")"
assert_eq "5h bucket ignored" "false" "$(jq -r '.buckets | has("gemini-5h")' "$JB_DIR/quota_cycles.json")"
assert_eq "disabled bucket ignored" "false" "$(jq -r '.buckets | has("disabled-weekly")' "$JB_DIR/quota_cycles.json")"

# Model switch without reset_time change and small drop does not trigger reset
Q_SWITCH='{"session_id":"q1","model":{"display_name":"Claude Sonnet 4.5"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.78,"reset_time":"2026-11-28T00:00:00Z"},"3p-weekly":{"remaining_fraction":0.90,"reset_time":"2026-11-28T00:00:00Z"}}}'
printf '%s' "$Q_SWITCH" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "no false reset on model switch" "0" "$(jq -r '.buckets["gemini-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"

# Cycles command before any resets exist
CYCLES_UNTRACKED=$("$JB_DIR/report.sh" cycles)
assert_contains "cycles shows All recorded before reset" "All recorded" "$CYCLES_UNTRACKED"
assert_contains "cycles shows readable Gemini bucket" "Gemini (Weekly)" "$CYCLES_UNTRACKED"
assert_contains "cycles shows readable 3P bucket" "Claude / 3P (Weekly)" "$CYCLES_UNTRACKED"
assert_contains "cycles shows no resets yet" "No quota resets detected yet." "$CYCLES_UNTRACKED"

# Scheduled reset: reset_time shifts forward
Q_RESET_TIME='{"session_id":"q1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-12-05T00:00:00Z"},"3p-weekly":{"remaining_fraction":0.90,"reset_time":"2026-11-28T00:00:00Z"}}}'
printf '%s' "$Q_RESET_TIME" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "reset_time_changed detected" "reset_time_changed" "$(jq -r '.buckets["gemini-weekly"].resets[0].reason' "$JB_DIR/quota_cycles.json")"
assert_eq "cycle_started_at populated on reset" "true" "$([ -n "$(jq -r '.buckets["gemini-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")" ] && echo true || echo false)"
assert_eq "3p-weekly isolated from gemini reset" "" "$(jq -r '.buckets["3p-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")"

# Surprise reset: remaining_fraction jumps >= +0.05 without reset_time change
Q_JUMP='{"session_id":"q1","model":{"display_name":"Claude Sonnet 4.5"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-12-05T00:00:00Z"},"3p-weekly":{"remaining_fraction":0.98,"reset_time":"2026-11-28T00:00:00Z"}}}'
printf '%s' "$Q_JUMP" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "remaining_jump detected on 3p" "remaining_jump" "$(jq -r '.buckets["3p-weekly"].resets[0].reason' "$JB_DIR/quota_cycles.json")"

CYCLES_OUT=$("$JB_DIR/report.sh" cycles)
assert_contains "cycles shows WEEKLY QUOTA CYCLES" "WEEKLY QUOTA CYCLES" "$CYCLES_OUT"
assert_contains "cycles shows RECENT DETECTED RESETS" "RECENT DETECTED RESETS" "$CYCLES_OUT"
assert_contains "cycles shows Scheduled reset" "Scheduled reset" "$CYCLES_OUT"
assert_contains "cycles shows Quota jump" "Quota jump" "$CYCLES_OUT"
assert_contains "cycles formats UTC timestamp" "2026-12-05 00:00" "$CYCLES_OUT"
assert_contains "cycles shows Gemini (Weekly)" "Gemini (Weekly)" "$CYCLES_OUT"
assert_contains "cycles shows Claude / 3P (Weekly)" "Claude / 3P (Weekly)" "$CYCLES_OUT"

# Quota edge cases: malformed quota_cycles.json, invalid remaining_fraction, and 50-entry cap
printf 'not json\n' > "$JB_DIR/quota_cycles.json"
Q_BAD_FRAC='{"session_id":"q1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.75,"reset_time":"2026-11-28T00:00:00Z"},"bad-neg-weekly":{"remaining_fraction":-0.1},"bad-over-weekly":{"remaining_fraction":1.5},"bad-str-weekly":{"remaining_fraction":"nope"}}}'
printf '%s' "$Q_BAD_FRAC" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "malformed quota_cycles.json recovered" "0.75" "$(jq -r '.buckets["gemini-weekly"].last_remaining' "$JB_DIR/quota_cycles.json")"
assert_eq "negative remaining_fraction ignored" "false" "$(jq -r '.buckets | has("bad-neg-weekly")' "$JB_DIR/quota_cycles.json")"
assert_eq ">1 remaining_fraction ignored" "false" "$(jq -r '.buckets | has("bad-over-weekly")' "$JB_DIR/quota_cycles.json")"
assert_eq "non-number remaining_fraction ignored" "false" "$(jq -r '.buckets | has("bad-str-weekly")' "$JB_DIR/quota_cycles.json")"

jq -n '{buckets:{"gemini-weekly":{last_remaining:0.5,last_reset_time:"2026-11-28T00:00:00Z",cycle_started_at:"2026-11-01 00:00",resets:[range(0;50)|{detected_at:"2026-11-01 00:00",reason:"reset_time_changed",prev_remaining:0.5,new_remaining:1.0,reset_time:"2026-11-28T00:00:00Z"}]}}}' > "$JB_DIR/quota_cycles.json"
printf '%s' "$Q_RESET_TIME" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "resets array capped at 50" "50" "$(jq -r '.buckets["gemini-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"
assert_eq "newest reset kept at tail" "2026-12-05T00:00:00Z" "$(jq -r '.buckets["gemini-weekly"].resets[-1].reset_time' "$JB_DIR/quota_cycles.json")"

# 6b. Mixed-bucket cycle isolation & date filter tests
rm -f "$JB_DIR/usage_logs"/*.json
cat << 'JSON' > "$JB_DIR/quota_cycles.json"
{
  "buckets": {
    "gemini-weekly": {
      "last_remaining": 0.9,
      "last_reset_time": "2026-12-05T00:00:00Z",
      "cycle_started_at": "2026-11-20 10:00",
      "resets": []
    },
    "3p-weekly": {
      "last_remaining": 0.7,
      "last_reset_time": "2026-11-28T00:00:00Z",
      "cycle_started_at": "",
      "resets": []
    }
  }
}
JSON

TODAY_D=$(date +"%Y-%m-%d")
cat << JSON > "$JB_DIR/usage_logs/s_gem_old.json"
{"timestamp":"2026-11-19 09:00","session_id":"s_gem_old","model":"Gemini 3.8 Flash","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":1.0}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_gem_new.json"
{"timestamp":"2026-11-20 12:00","session_id":"s_gem_new","model":"Gemini 3.8 Flash","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":2.0}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_3p_old.json"
{"timestamp":"2026-11-19 09:00","session_id":"s_3p_old","model":"Claude Sonnet 4.5","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":4.0}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_arg_old.json"
{"timestamp":"2026-11-19 09:00","session_id":"s_arg_old","model":"Gemini 3.8 Argon","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":8.0}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_today.json"
{"timestamp":"$TODAY_D 08:00","session_id":"s_today","model":"Neon","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":0.5}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_old_week.json"
{"timestamp":"2020-01-01 09:00","session_id":"s_old_week","model":"Gemini 3.8 Flash","input_tokens":1000,"uncached_tokens":1000,"cache_tokens":0,"output_tokens":100,"cost_usd":0.25}
JSON

# Default view is cycle: should include s_gem_new ($2.0), s_3p_old ($4.0), s_today ($0.5) if today >= 2026-11-20; exclude s_gem_old ($1.0) and s_arg_old ($8.0)
REP_CYCLE=$("$JB_DIR/report.sh" cycle)
assert_contains "cycle includes s_gem_new" "s_gem_ne" "$REP_CYCLE"
assert_not_contains "cycle excludes s_gem_old" "s_gem_ol" "$REP_CYCLE"
assert_contains "cycle preserves un-reset 3p-weekly s_3p_old" "s_3p_old" "$REP_CYCLE"
assert_not_contains "cycle falls back absent argon to gemini-weekly" "s_arg_ol" "$REP_CYCLE"

REP_CYCLE_3P=$("$JB_DIR/report.sh" cycle 3p)
assert_contains "cycle 3p includes Claude" "Claude Sonnet 4.5" "$REP_CYCLE_3P"
assert_not_contains "cycle 3p excludes Gemini" "Gemini 3.8 Flash" "$REP_CYCLE_3P"

REP_CYCLE_GEM=$("$JB_DIR/report.sh" cycle gemini)
assert_contains "cycle gemini includes Gemini" "Gemini 3.8 Flash" "$REP_CYCLE_GEM"
assert_not_contains "cycle gemini excludes Claude" "Claude Sonnet 4.5" "$REP_CYCLE_GEM"

REP_CYCLE_ARG=$("$JB_DIR/report.sh" cycle argon)
assert_contains "cycle argon empty message" "No sessions match filter" "$REP_CYCLE_ARG"

REP_ALL=$("$JB_DIR/report.sh" all)
assert_contains "all includes s_gem_old" "s_gem_ol" "$REP_ALL"
assert_contains "all includes s_arg_old" "s_arg_ol" "$REP_ALL"

REP_TODAY=$("$JB_DIR/report.sh" today)
assert_contains "today includes s_today" "s_today" "$REP_TODAY"
assert_not_contains "today excludes 2026-11-19" "s_gem_ol" "$REP_TODAY"

REP_WEEK=$("$JB_DIR/report.sh" week)
assert_contains "week includes s_today" "s_today" "$REP_WEEK"
assert_not_contains "week excludes old 2020-01-01" "s_old_we" "$REP_WEEK"

REP_MONTH=$("$JB_DIR/report.sh" --month 2026-11)
assert_contains "month 2026-11 includes s_gem_old" "s_gem_ol" "$REP_MONTH"

REP_RANGE=$("$JB_DIR/report.sh" --from 2026-11-20 --to 2026-11-20)
assert_contains "range includes s_gem_new" "s_gem_ne" "$REP_RANGE"
assert_not_contains "range excludes s_gem_old" "s_gem_ol" "$REP_RANGE"

REP_FROM_ONLY=$("$JB_DIR/report.sh" --from 2026-11-20)
assert_contains "open-ended --from includes s_gem_new" "s_gem_ne" "$REP_FROM_ONLY"
assert_not_contains "open-ended --from excludes s_gem_old" "s_gem_ol" "$REP_FROM_ONLY"

REP_TO_ONLY=$("$JB_DIR/report.sh" --to 2026-11-19)
assert_contains "open-ended --to includes s_gem_old" "s_gem_ol" "$REP_TO_ONLY"
assert_not_contains "open-ended --to excludes s_gem_new" "s_gem_ne" "$REP_TO_ONLY"

# default-view setting toggle
"$JB_DIR/report.sh" set default-view all >/dev/null
REP_DEF_ALL=$("$JB_DIR/report.sh")
assert_contains "default-view all includes s_gem_old" "s_gem_ol" "$REP_DEF_ALL"
"$JB_DIR/report.sh" set default-view cycle >/dev/null

# Invalid / conflicting filter flags exit 1
for bad_flt in "today week" "--month" "--from" "--to" "--month 2026-13" "--from 2026-02-30" "--from 2026-11-20 --to 2026-11-19" "--from 2026-11-01 --from 2026-11-02" "--to 2026-11-01 --to 2026-11-02" "--month 2026-11 --from 2026-11-01" "cycle --month 2026-11" "cycle bogus" "set default-view bogus"; do
  if $JB_DIR/report.sh $bad_flt >/dev/null 2>&1; then
    echo "FAIL: '$bad_flt' should exit 1" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done

# 6c. Regression tests: sliding 100% reset_time, stale out-of-order reset_time, and bogus reset self-healing
rm -f "$JB_DIR/quota_cycles.json"
Q_SLIDE_1='{"session_id":"qs1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:31:31Z"},"gemini-argon-wtu-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:31:31Z"}}}'
Q_SLIDE_2='{"session_id":"qs1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:31:32Z"},"gemini-argon-wtu-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:37:59Z"}}}'
Q_SLIDE_3='{"session_id":"qs1","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:38:00.123456Z"},"gemini-argon-wtu-weekly":{"remaining_fraction":1.0,"reset_time":"2026-12-06T00:00:00Z"}}}'
printf '%s' "$Q_SLIDE_1" | "$JB_DIR/statusline.sh" >/dev/null
printf '%s' "$Q_SLIDE_2" | "$JB_DIR/statusline.sh" >/dev/null
printf '%s' "$Q_SLIDE_3" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "sliding 100% gemini produces 0 resets" "0" "$(jq -r '.buckets["gemini-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"
assert_eq "sliding 100% gemini keeps cycle_started_at empty" "" "$(jq -r '.buckets["gemini-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")"
assert_eq "sliding 100% argon (>6h) produces 0 resets" "0" "$(jq -r '.buckets["gemini-argon-wtu-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"
assert_eq "sliding 100% argon (>6h) updates last_reset_time" "2026-12-06T00:00:00Z" "$(jq -r '.buckets["gemini-argon-wtu-weekly"].last_reset_time' "$JB_DIR/quota_cycles.json")"

# Missing reset_time in payload preserves existing last_reset_time; empty prev_rt gets populated
Q_NO_RT='{"session_id":"qs1b","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.95},"custom-weekly":{"remaining_fraction":0.85}}}'
printf '%s' "$Q_NO_RT" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "missing reset_time preserves last_reset_time" "2026-11-28T16:31:31Z" "$(jq -r '.buckets["gemini-weekly"].last_reset_time' "$JB_DIR/quota_cycles.json")"

Q_FILL_RT='{"session_id":"qs1b","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"custom-weekly":{"remaining_fraction":0.85,"reset_time":"2026-11-28T17:00:00Z"}}}'
printf '%s' "$Q_FILL_RT" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "empty prev_rt gets populated" "2026-11-28T17:00:00Z" "$(jq -r '.buckets["custom-weekly"].last_reset_time' "$JB_DIR/quota_cycles.json")"

# Minor reset_time drift >= 60s (< 6h) while < 99.5% updates last_reset_time without logging reset
Q_DRIFT='{"session_id":"qs1b","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"custom-weekly":{"remaining_fraction":0.85,"reset_time":"2026-11-28T17:05:00Z"}}}'
printf '%s' "$Q_DRIFT" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "minor drift >= 60s updates last_reset_time" "2026-11-28T17:05:00Z" "$(jq -r '.buckets["custom-weekly"].last_reset_time' "$JB_DIR/quota_cycles.json")"
assert_eq "minor drift >= 60s does not log reset" "0" "$(jq -r '.buckets["custom-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"

# Stale out-of-order reset_time must not rewind last_reset_time
Q_USED_1='{"session_id":"qs2","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.80,"reset_time":"2026-11-28T16:37:59Z"}}}'
Q_USED_STALE='{"session_id":"qs2","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.80,"reset_time":"2026-11-28T16:31:32Z"}}}'
printf '%s' "$Q_USED_1" | "$JB_DIR/statusline.sh" >/dev/null
printf '%s' "$Q_USED_STALE" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "stale reset_time does not rewind last_reset_time" "2026-11-28T16:37:59Z" "$(jq -r '.buckets["gemini-weekly"].last_reset_time' "$JB_DIR/quota_cycles.json")"
assert_eq "stale reset_time does not trigger reset" "0" "$(jq -r '.buckets["gemini-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"

# Unused bucket recovery: 0.992 -> 1.0 (< 6h advance) updates last_remaining to 1.0
Q_REC_1='{"session_id":"qs3","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":0.992,"reset_time":"2026-11-28T16:40:00Z"}}}'
Q_REC_2='{"session_id":"qs3","model":{"display_name":"Gemini 3.8 Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":100,"used_percentage":5},"cost":{"total_usd":0.01},"quota":{"gemini-weekly":{"remaining_fraction":1.0,"reset_time":"2026-11-28T16:50:00Z"}}}'
printf '%s' "$Q_REC_1" | "$JB_DIR/statusline.sh" >/dev/null
printf '%s' "$Q_REC_2" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "0.992 -> 1.0 recovery updates last_remaining" "1.0" "$(jq -r '.buckets["gemini-weekly"].last_remaining' "$JB_DIR/quota_cycles.json")"

# Pre-seeded bogus 100% -> 100% resets self-heal upon running jenbach cycles
cat << 'JSON' > "$JB_DIR/quota_cycles.json"
{
  "buckets": {
    "gemini-weekly": {
      "last_remaining": 1.0,
      "last_reset_time": "2026-11-28T16:37:59Z",
      "cycle_started_at": "2026-11-21 16:37",
      "resets": [
        {"detected_at":"2026-11-21 16:31","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-11-28T16:31:32Z"},
        {"detected_at":"2026-11-21 16:32","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-11-28T16:32:00Z"},
        {"detected_at":"2026-11-21 16:33","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-11-28T16:33:00Z"},
        {"detected_at":"2026-11-21 16:34","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-11-28T16:34:00Z"},
        {"detected_at":"2026-11-21 16:37","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-11-28T16:37:59Z"}
      ]
    },
    "gemini-argon-wtu-weekly": {
      "last_remaining": 1.0,
      "last_reset_time": "2026-12-05T00:00:00Z",
      "cycle_started_at": "2026-11-21 16:37",
      "resets": [
        {"detected_at":"2026-11-21 12:00","reason":"reset_time_changed","prev_remaining":0.85,"new_remaining":1.0,"reset_time":"2026-12-05T00:00:00Z"},
        {"detected_at":"2026-11-21 16:37","reason":"reset_time_changed","prev_remaining":1.0,"new_remaining":1.0,"reset_time":"2026-12-05T00:01:00Z"}
      ]
    }
  }
}
JSON
HEALED_CYCLES=$("$JB_DIR/report.sh" cycles)
assert_contains "healed cycles shows Gemini (Weekly)" "Gemini (Weekly)" "$HEALED_CYCLES"
assert_contains "healed cycles shows Gemini Argon (Weekly)" "Gemini Argon (Weekly)" "$HEALED_CYCLES"
assert_contains "healed cycles shows All recorded for gemini" "All recorded" "$HEALED_CYCLES"
assert_contains "healed cycles shows Scheduled reset for argon" "Scheduled reset" "$HEALED_CYCLES"
assert_contains "healed cycles formats argon reset UTC" "2026-12-05 00:00" "$HEALED_CYCLES"
assert_eq "healed quota_cycles.json strips all 5 bogus gemini resets" "0" "$(jq -r '.buckets["gemini-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"
assert_eq "healed quota_cycles.json clears gemini cycle_started_at" "" "$(jq -r '.buckets["gemini-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")"
assert_eq "healed quota_cycles.json keeps 1 genuine argon reset" "1" "$(jq -r '.buckets["gemini-argon-wtu-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"
assert_eq "healed quota_cycles.json restores argon cycle_started_at" "2026-11-21 12:00" "$(jq -r '.buckets["gemini-argon-wtu-weekly"].cycle_started_at' "$JB_DIR/quota_cycles.json")"
assert_eq "healed quota_cycles.json preserves raw bucket keys" "true" "$(jq -r '.buckets | has("gemini-weekly") and has("gemini-argon-wtu-weekly")' "$JB_DIR/quota_cycles.json")"

# Fallback & malformed bucket handling in common.jq / report.sh cycles
cat << 'JSON' > "$JB_DIR/quota_cycles.json"
{
  "buckets": {
    "bogus-non-obj": "bad",
    "custom-weekly": {
      "last_remaining": 0.5,
      "last_reset_time": "bad-date",
      "cycle_started_at": "",
      "resets": [null, {"detected_at":"2026-11-21 12:00","reason":"reset_time_changed","prev_remaining":"not-a-num","new_remaining":1.0,"reset_time":""}]
    }
  }
}
JSON
MALFORMED_CYCLES=$("$JB_DIR/report.sh" cycles)
assert_contains "cycles renders unknown bucket fallback" "custom-weekly" "$MALFORMED_CYCLES"
assert_contains "cycles renders non-ISO reset_time fallback" "bad-date" "$MALFORMED_CYCLES"
assert_contains "cycles renders empty reset_time as N/A" "N/A" "$MALFORMED_CYCLES"
assert_eq "cycles strips non-object bucket entry" "false" "$(jq -r '.buckets | has("bogus-non-obj")' "$JB_DIR/quota_cycles.json")"
assert_eq "cycles strips null reset element" "1" "$(jq -r '.buckets["custom-weekly"].resets | length' "$JB_DIR/quota_cycles.json")"

# Info fallback paths (missing VERSION, invalid/missing prices.json)
mv "$JB_DIR/VERSION" "$JB_DIR/VERSION.bak"
mv "$JB_DIR/prices.json" "$JB_DIR/prices.json.bak"
printf '{\n' > "$JB_DIR/prices.json"
INFO_INVALID_P=$("$JB_DIR/report.sh" info)
assert_contains "info invalid prices" "updated invalid" "$INFO_INVALID_P"
rm -f "$JB_DIR/prices.json"
INFO_MISSING_P=$("$JB_DIR/report.sh" info)
assert_contains "info missing prices" "updated missing" "$INFO_MISSING_P"
mv "$JB_DIR/prices.json.bak" "$JB_DIR/prices.json"
mv "$JB_DIR/VERSION.bak" "$JB_DIR/VERSION"

# 6d. Responsive report width, Think column split, ANSI budget, and unified width alignment
assert_eq "split_model_think Medium" '{"base":"Gemini 4 Hydrogen","think":"Medium"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Gemini 4 Hydrogen (Medium)")')"
assert_eq "split_model_think High" '{"base":"Gemini 4 Hydrogen","think":"High"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Gemini 4 Hydrogen (High)")')"
assert_eq "split_model_think Low" '{"base":"Gemini 4 Hydrogen","think":"Low"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Gemini 4 Hydrogen (Low)")')"
assert_eq "split_model_think Minimal" '{"base":"Gemini 4 Hydrogen","think":"Minimal"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Gemini 4 Hydrogen (Minimal)")')"
assert_eq "split_model_think extra parens" '{"base":"Custom Model (v2)","think":"High"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Custom Model (v2) (High)")')"
assert_eq "split_model_think no think tier" '{"base":"Claude Opus 5.5","think":"-"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Claude Opus 5.5")')"
assert_eq "split_model_think empty" '{"base":"Unknown","think":"-"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("")')"
assert_eq "split_model_think null" '{"base":"Unknown","think":"-"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think(null)')"
assert_eq "split_model_think space-only base fallback" '{"base":" (High)","think":"High"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think(" (High)")')"
assert_eq "split_model_think case-insensitive lowercase" '{"base":"Model","think":"high"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Model (high)")')"
assert_eq "split_model_think case-insensitive minimal" '{"base":"Model","think":"minimal"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Model (minimal)")')"
assert_eq "split_model_think non-trailing parens unchanged" '{"base":"Model (High) v2","think":"-"}' "$(jq -L "$LIB_DIR" -cn 'include "common"; split_model_think("Model (High) v2")')"

assert_eq "merge_segments merges adjacent same-style" '[{"t":"ab","c":""},{"t":"cd","c":"bold"}]' "$(jq -L "$LIB_DIR" -cn 'include "common"; merge_segments([{t:"a",c:""},{t:"b",c:""},{t:"c",c:"bold"},{t:"d",c:"bold"}])')"
assert_eq "merge_segments empty" '[]' "$(jq -L "$LIB_DIR" -cn 'include "common"; merge_segments([])')"
assert_eq "merge_segments single" '[{"t":"x","c":"cyan"}]' "$(jq -L "$LIB_DIR" -cn 'include "common"; merge_segments([{t:"x",c:"cyan"}])')"
assert_eq "merge_segments alternating" '[{"t":"a","c":"dim"},{"t":"b","c":"cyan"},{"t":"c","c":"dim"}]' "$(jq -L "$LIB_DIR" -cn 'include "common"; merge_segments([{t:"a",c:"dim"},{t:"b",c:"cyan"},{t:"c",c:"dim"}])')"
assert_eq "merge_segments null/omitted t and c" '[{"t":"ab","c":""},{"t":"c","c":"dim"}]' "$(jq -L "$LIB_DIR" -cn 'include "common"; merge_segments([{t:"a"},{},{t:"b",c:null},{t:"c",c:"dim"}])')"

assert_eq "render_table 6-arg expands to target_w" "1" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_table(["A","B","C"]; ["l","r","r"]; [{sep_before:false,bold_row:false,cells:[{t:"x",c:""},{t:"1",c:""},{t:"2",c:""}]}]; true; false; 20)' | awk '{print length($0)}' | sort -u | wc -l)"
assert_eq "render_table 6-arg exact width 20" "20" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_table(["A","B","C"]; ["l","r","r"]; [{sep_before:false,bold_row:false,cells:[{t:"x",c:""},{t:"1",c:""},{t:"2",c:""}]}]; true; false; 20)' | head -n 1 | awk '{print length($0)}')"
assert_eq "render_table 6-arg 1-col stays min_w" "3" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_table(["Col"]; ["l"]; [{sep_before:false,bold_row:false,cells:[{t:"abc",c:""}]}]; true; false; 20)' | head -n 1 | awk '{print length($0)}')"
assert_eq "render_table 6-arg null target_w falls back to min_w" "4" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_table(["A","B"]; ["l","r"]; [{sep_before:false,bold_row:false,cells:[{t:"x",c:""},{t:"1",c:""}]}]; true; false; null)' | head -n 1 | awk '{print length($0)}')"
assert_eq "render_kpi_box 5-arg modern width 100" "100" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_kpi_box("Title"; [[{t:"hello",c:""}]]; false; false; 100)' | awk '{print length($0)}' | sort -u)"
assert_eq "render_kpi_box 5-arg plain width 100" "100" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_kpi_box("Title"; [[{t:"hello",c:""}]]; true; false; 100)' | awk '{print length($0)}' | sort -u)"
assert_eq "render_kpi_box 5-arg null target_w falls back to 76" "76" "$(jq -L "$LIB_DIR" -rn 'include "common"; render_kpi_box("Title"; [[{t:"hello",c:""}]]; true; false; null)' | head -n 1 | awk '{print length($0)}')"

rm -f "$JB_DIR/usage_logs"/*.json
cat << JSON > "$JB_DIR/usage_logs/s_h2.json"
{"timestamp":"$TODAY_D 12:00","session_id":"s_hyd_001","model":"Gemini 4 Hydrogen (Medium)","input_tokens":5000,"uncached_tokens":2000,"cache_tokens":3000,"output_tokens":400,"cost_usd":0.123,"subagent_cost_usd":0.01}
JSON

"$JB_DIR/report.sh" set theme modern >/dev/null
"$JB_DIR/report.sh" set color on >/dev/null
"$JB_DIR/report.sh" set history on >/dev/null
REP_W120=$(JENBACH_WIDTH=120 "$JB_DIR/report.sh" all)
assert_not_contains "wide 120 splits thinking mode from model name" "Gemini 4 Hydrogen (Medium)" "$REP_W120"
assert_eq "wide 120 shows base model in both tables" "2" "$(printf '%s\n' "$REP_W120" | grep -c 'Gemini 4 Hydrogen' || true)"
assert_eq "wide 120 shows Think header in both tables" "2" "$(printf '%s\n' "$REP_W120" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -c 'Think' || true)"
assert_eq "wide 120 shows Medium in Think column in both tables" "2" "$(printf '%s\n' "$REP_W120" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -c 'Medium' || true)"
assert_eq "wide 120 unified line width 104" "104" "$(printf '%s\n' "$REP_W120" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u)"

REP_W115=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_eq "width 115 unified line width 103" "103" "$(printf '%s\n' "$REP_W115" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u)"
MAX_RAW_W115=$(printf '%s\n' "$REP_W115" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
assert_eq "width 115 raw line length <= 160" "true" "$([ "$MAX_RAW_W115" -le 160 ] && echo true || echo false)"

REP_W200=$(JENBACH_WIDTH=200 "$JB_DIR/report.sh" all)
assert_eq "ultra-wide 200 capped at 104" "104" "$(printf '%s\n' "$REP_W200" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u)"

"$JB_DIR/report.sh" set theme compact >/dev/null
REP_COMPACT_W120=$(JENBACH_WIDTH=120 "$JB_DIR/report.sh" all)
assert_eq "compact wide 120 divider width 104" "104" "$(printf '%s\n' "$REP_COMPACT_W120" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^─+$' | awk '{print length($0)}' | sort -u)"

"$JB_DIR/report.sh" set theme plain >/dev/null
REP_PLAIN_W120=$(JENBACH_WIDTH=120 "$JB_DIR/report.sh" all)
assert_eq "plain wide 120 zero ESC" "0" "$(printf '%s' "$REP_PLAIN_W120" | grep -c $'\x1b' || true)"
assert_eq "plain wide 120 pure ASCII" "0" "$(LC_ALL=C grep -c '[^ -~]' <(printf '%s\n' "$REP_PLAIN_W120") || true)"
assert_eq "plain wide 120 unified width 104" "104" "$(printf '%s\n' "$REP_PLAIN_W120" | grep -E '^(\+--|\||\+|Model |-|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u)"

"$JB_DIR/report.sh" set theme modern >/dev/null
REP_W80=$(JENBACH_WIDTH=80 "$JB_DIR/report.sh" all)
assert_contains "narrow 80 falls back to short_model of base in RECENT SESSIONS" "4 Hydrogen" "$REP_W80"
W80_T2_LEN=$(printf '%s\n' "$REP_W80" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^Date ' | awk '{print length($0)}')
assert_eq "narrow 80 table 2 stays at natural min_w (91)" "91" "$W80_T2_LEN"

cat << JSON > "$JB_DIR/usage_logs/s_h2.json"
{"timestamp":"$TODAY_D 12:00","session_id":"s_fl_001","model":"Flash","input_tokens":500,"uncached_tokens":200,"cache_tokens":300,"output_tokens":40,"cost_usd":0.012,"subagent_cost_usd":0}
JSON
REP_W70=$(JENBACH_WIDTH=70 "$JB_DIR/report.sh" all)
W70_T1_LEN=$(printf '%s\n' "$REP_W70" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^Model ' | awk '{print length($0)}')
assert_eq "very narrow 70 table 1 stays at natural min_w 68 (not stretched to KPI 76)" "68" "$W70_T1_LEN"

cat << JSON > "$JB_DIR/usage_logs/s_h2.json"
{"timestamp":"$TODAY_D 12:00","session_id":"s_hyd_001","model":"Gemini 4 Hydrogen (Medium)","input_tokens":5000,"uncached_tokens":2000,"cache_tokens":3000,"output_tokens":400,"cost_usd":0.123,"subagent_cost_usd":0.01}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_h3.json"
{"timestamp":"$TODAY_D 12:05","session_id":"s_hyd_002","model":"Gemini 4 Hydrogen (Low)","input_tokens":2500,"uncached_tokens":1000,"cache_tokens":1500,"output_tokens":200,"cost_usd":0.061,"subagent_cost_usd":0}
JSON
REP_MULTI_THINK=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_eq "USAGE BY MODEL keeps distinct rows per thinking tier" "2" "$(printf '%s\n' "$REP_MULTI_THINK" | sed $'s/\x1b\\[[0-9;]*m//g' | awk '/^USAGE BY MODEL/,/^RECENT SESSIONS/' | grep -c 'Gemini 4 Hydrogen' || true)"
MAX_RAW_MULTI=$(printf '%s\n' "$REP_MULTI_THINK" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
assert_eq "multi-tier width 115 raw line length <= 160" "true" "$([ "$MAX_RAW_MULTI" -le 160 ] && echo true || echo false)"
rm -f "$JB_DIR/usage_logs/s_h3.json"

"$JB_DIR/report.sh" set history off >/dev/null
REP_NOHIST_W120=$(JENBACH_WIDTH=120 "$JB_DIR/report.sh" all)
assert_not_contains "show_history off omits RECENT SESSIONS" "RECENT SESSIONS" "$REP_NOHIST_W120"
assert_eq "show_history off unified width 104" "104" "$(printf '%s\n' "$REP_NOHIST_W120" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND )' | awk '{print length($0)}' | sort -u)"
"$JB_DIR/report.sh" set history on >/dev/null

REP_BADW=$(JENBACH_WIDTH=abc "$JB_DIR/report.sh" all)
assert_contains "invalid JENBACH_WIDTH falls back cleanly" "Gemini 4 Hydrogen" "$REP_BADW"

REP_SMALLW=$(JENBACH_WIDTH=20 "$JB_DIR/report.sh" all)
assert_contains "numeric JENBACH_WIDTH < 40 falls back cleanly" "Gemini 4 Hydrogen" "$REP_SMALLW"

REP_COLS100=$(env -u JENBACH_WIDTH COLUMNS=100 "$JB_DIR/report.sh" all)
assert_eq "COLUMNS=100 fallback aligns across all blocks" "1" "$(printf '%s\n' "$REP_COLS100" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u | wc -l)"

REP_W90=$(JENBACH_WIDTH=90 "$JB_DIR/report.sh" all)
assert_eq "wide 90 expands to content_min (> 78) across all blocks" "1" "$(printf '%s\n' "$REP_W90" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u | wc -l)"
assert_eq "wide 90 content_min > 78" "true" "$([ "$(printf '%s\n' "$REP_W90" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^Date ' | awk '{print length($0)}')" -gt 78 ] && echo true || echo false)"

REP_ZERO=$(JENBACH_WIDTH=085 "$JB_DIR/report.sh" all)
assert_contains "leading-zero JENBACH_WIDTH=085 normalized cleanly" "Gemini 4 Hydrogen" "$REP_ZERO"

cat << JSON > "$JB_DIR/usage_logs/s_h_high.json"
{"timestamp":"$TODAY_D 12:10","session_id":"s_hyd_003","model":"Gemini 4 Hydrogen (High)","input_tokens":5000,"uncached_tokens":2000,"cache_tokens":3000,"output_tokens":400,"cost_usd":0.123,"subagent_cost_usd":0}
JSON
cat << JSON > "$JB_DIR/usage_logs/s_h_low.json"
{"timestamp":"$TODAY_D 12:11","session_id":"s_hyd_004","model":"Gemini 4 Hydrogen (Low)","input_tokens":5000,"uncached_tokens":2000,"cache_tokens":3000,"output_tokens":400,"cost_usd":0.123,"subagent_cost_usd":0}
JSON
REP_COLORS=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_contains "think_color High emits bold (1m)" $'\x1b[1mHigh  \x1b[0m' "$REP_COLORS"
assert_not_contains "think_color Medium is not cyan (36m)" $'\x1b[36mMedium' "$REP_COLORS"
assert_not_contains "think_color Medium is not magenta (35m)" $'\x1b[35mMedium' "$REP_COLORS"
assert_contains "think_color Low emits dim (90m)" $'\x1b[90mLow   \x1b[0m' "$REP_COLORS"
KPI_L1_LINE=$(printf '%s\n' "$REP_COLORS" | grep 'Total Spend:')
assert_not_contains "KPI Main: is not painted magenta (35m)" $'\x1b[35m (Main:' "$KPI_L1_LINE"
assert_contains "KPI Sub: is painted magenta (35m)" $'\x1b[35mSub:' "$KPI_L1_LINE"
assert_not_contains "KPI cached tokens not painted cyan (36m)" $'\x1b[36m' "$(printf '%s\n' "$REP_COLORS" | grep 'Tokens:')"
KPI_L1_ESC=$(printf '%s\n' "$KPI_L1_LINE" | grep -o $'\x1b\\[[0-9;]*m' | wc -l)
assert_eq "KPI Line 1 merged ANSI count <= 12" "true" "$([ "$KPI_L1_ESC" -le 12 ] && echo true || echo false)"
MAX_RAW_COLORS_W115=$(printf '%s\n' "$REP_COLORS" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
assert_eq "REP_COLORS width 115 raw line length <= 160" "true" "$([ "$MAX_RAW_COLORS_W115" -le 160 ] && echo true || echo false)"
cp "$REPO_DIR/prices.json" "$JB_DIR/prices.json"
PRICES_COLOR_OUT=$("$JB_DIR/report.sh" prices)
assert_not_contains "prices Promo note not painted yellow (33m)" $'\x1b[33m' "$PRICES_COLOR_OUT"
assert_contains "prices Promo note emits bold (1m)" $'\x1b[1mPromo' "$PRICES_COLOR_OUT"

# Cycles semantic color checks with color on
QCYC_BAK=$(cat "$JB_DIR/quota_cycles.json" 2>/dev/null || echo "")
cat << 'JSON' > "$JB_DIR/quota_cycles.json"
{"buckets":{
  "gemini-weekly":{"cycle_started_at":"2026-11-20","last_remaining":0.20,"last_reset_time":"2026-11-27T00:00:00Z","resets":[{"detected_at":"2026-11-20 00:00","reason":"reset_time_changed","prev_remaining":0.10,"new_remaining":1.0,"reset_time":"2026-11-27T00:00:00Z"}]},
  "3p-weekly":{"cycle_started_at":"","last_remaining":0.50,"last_reset_time":"2026-11-27T00:00:00Z","resets":[]},
  "gemini-argon-wtu-weekly":{"cycle_started_at":"2026-11-20","last_remaining":0.10,"last_reset_time":"2026-11-27T00:00:00Z","resets":[]},
  "custom-null":{"cycle_started_at":"2026-11-20","last_remaining":null,"last_reset_time":"2026-11-27T00:00:00Z","resets":[]}
}}
JSON
CYCLES_COLOR_OUT=$("$JB_DIR/report.sh" cycles)
assert_contains "cycles Remaining 20% emits bold (1m)" $'\x1b[1m      20%\x1b[0m' "$CYCLES_COLOR_OUT"
assert_contains "cycles Remaining 50% emits green (32m)" $'\x1b[32m      50%\x1b[0m' "$CYCLES_COLOR_OUT"
assert_contains "cycles Remaining 10% emits bold_red (1;31m)" $'\x1b[1;31m      10%\x1b[0m' "$CYCLES_COLOR_OUT"
assert_contains "cycles Remaining null emits dim (90m)" $'\x1b[90m      N/A\x1b[0m' "$CYCLES_COLOR_OUT"
assert_not_contains "cycles does not emit plain yellow (33m)" $'\x1b[33m' "$CYCLES_COLOR_OUT"
assert_not_contains "cycles Cycle Start date not painted cyan (36m)" $'\x1b[36m2026-11-20' "$CYCLES_COLOR_OUT"
assert_contains "cycles Reason Scheduled reset uncolored" "Scheduled reset" "$CYCLES_COLOR_OUT"
if [ -n "$QCYC_BAK" ]; then printf '%s' "$QCYC_BAK" > "$JB_DIR/quota_cycles.json"; else rm -f "$JB_DIR/quota_cycles.json"; fi

# Statusline semantic color checks (Cache 3-tier, Ctx/Wk mid-tier bold, null & boundaries)
SL_MID=$(printf '%s' '{"session_id":"s_col_1","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":65,"current_usage":{"input_tokens":400,"cache_read_input_tokens":600}},"quota":{"gemini-weekly":{"remaining_fraction":0.20}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Cache 60% emits green (32m)" $'\x1b[32m(60%)\x1b[0m' "$SL_MID"
assert_contains "statusline Ctx 65% emits bold (1m)" $'\x1b[1m65%\x1b[0m' "$SL_MID"
assert_contains "statusline Wk 20% emits bold (1m)" $'\x1b[1m20%\x1b[0m' "$SL_MID"
assert_not_contains "statusline mid-tier does not emit plain yellow (33m)" $'\x1b[33m' "$SL_MID"

SL_HIGH=$(printf '%s' '{"session_id":"s_col_2","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":85,"current_usage":{"input_tokens":100,"cache_read_input_tokens":900}},"quota":{"gemini-weekly":{"remaining_fraction":0.10}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Cache 90% emits bold_green (1;32m)" $'\x1b[1;32m(90%)\x1b[0m' "$SL_HIGH"
assert_contains "statusline Ctx 85% emits bold_red (1;31m)" $'\x1b[1;31m85%\x1b[0m' "$SL_HIGH"
assert_contains "statusline Wk 10% emits bold_red (1;31m)" $'\x1b[1;31m10%\x1b[0m' "$SL_HIGH"

SL_LOW=$(printf '%s' '{"session_id":"s_col_3","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":20,"current_usage":{"input_tokens":800,"cache_read_input_tokens":200}},"quota":{"gemini-weekly":{"remaining_fraction":0.80}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Cache 20% emits dim (90m)" $'\x1b[90m(20%)\x1b[0m' "$SL_LOW"
assert_contains "statusline Ctx 20% emits green (32m)" $'\x1b[32m20%\x1b[0m' "$SL_LOW"
assert_contains "statusline Wk 80% emits green (32m)" $'\x1b[32m80%\x1b[0m' "$SL_LOW"

SL_NULL_WK=$(printf '%s' '{"session_id":"s_col_4","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":59,"current_usage":{"input_tokens":500,"cache_read_input_tokens":500}},"quota":{}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Wk null emits dim (90m)" $'\x1b[90mN/A\x1b[0m' "$SL_NULL_WK"
assert_contains "statusline Ctx 59% emits green (32m)" $'\x1b[32m59%\x1b[0m' "$SL_NULL_WK"

SL_BND1=$(printf '%s' '{"session_id":"s_col_5","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":60,"current_usage":{"input_tokens":500,"cache_read_input_tokens":500}},"quota":{"gemini-weekly":{"remaining_fraction":0.15}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Ctx 60% boundary emits bold (1m)" $'\x1b[1m60%\x1b[0m' "$SL_BND1"
assert_contains "statusline Wk 15% boundary emits bold (1m)" $'\x1b[1m15%\x1b[0m' "$SL_BND1"

SL_BND2=$(printf '%s' '{"session_id":"s_col_6","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":79,"current_usage":{"input_tokens":500,"cache_read_input_tokens":500}},"quota":{"gemini-weekly":{"remaining_fraction":0.30}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Ctx 79% boundary emits bold (1m)" $'\x1b[1m79%\x1b[0m' "$SL_BND2"
assert_contains "statusline Wk 30% boundary emits bold (1m)" $'\x1b[1m30%\x1b[0m' "$SL_BND2"

SL_BND3=$(printf '%s' '{"session_id":"s_col_7","model":{"display_name":"Gemini 4 Hydrogen"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":80,"current_usage":{"input_tokens":500,"cache_read_input_tokens":500}},"quota":{"gemini-weekly":{"remaining_fraction":0.31}}}' | "$JB_DIR/statusline.sh")
assert_contains "statusline Ctx 80% boundary emits bold_red (1;31m)" $'\x1b[1;31m80%\x1b[0m' "$SL_BND3"
assert_contains "statusline Wk 31% boundary emits green (32m)" $'\x1b[32m31%\x1b[0m' "$SL_BND3"
rm -f "$JB_DIR/usage_logs/s_h_high.json" "$JB_DIR/usage_logs/s_h_low.json"

cat << JSON > "$JB_DIR/usage_logs/s_long.json"
{"timestamp":"$TODAY_D 12:12","session_id":"s_long_01","model":"Extremely Long Custom Enterprise Model Name For Wide Table Expansion (High)","input_tokens":5000,"uncached_tokens":2000,"cache_tokens":3000,"output_tokens":400,"cost_usd":0.123,"subagent_cost_usd":0}
JSON
REP_LONG_W200=$(JENBACH_WIDTH=200 "$JB_DIR/report.sh" all)
LONG_W200_LEN=$(printf '%s\n' "$REP_LONG_W200" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^╭' | awk '{print length($0)}')
assert_eq "content_min > 104 expands unified width above 104" "true" "$([ "$LONG_W200_LEN" -gt 104 ] && echo true || echo false)"
assert_eq "content_min > 104 unifies all blocks" "1" "$(printf '%s\n' "$REP_LONG_W200" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |Extremely |GRAND |Date |[0-9]{2}-[0-9]{2} )' | awk '{print length($0)}' | sort -u | wc -l)"
rm -f "$JB_DIR/usage_logs/s_long.json"

# 6e. Live Subagent DB Sync, Animated Statusline Spinner, Tree Report & Accounting Invariants
cp "$REPO_DIR/prices.json" "$JB_DIR/prices.json"
rm -f "$JB_DIR/usage_logs"/*.json "$JB_DIR/usage_logs"/.sub_*.json "$JB_DIR/usage_logs"/.sub_*.ttl
rm -rf "$JB_DIR/usage_logs"/.sub_*.lock "$HOME/.gemini/antigravity-cli/brain" "$HOME/.gemini/antigravity-cli/conversations"

# Build realistic SQLite/Protobuf fixtures for root session + depth-1 + depth-2 + WAL + corrupted DB + cycle
ROOT_SID="root-sub-test-001"
SUB1_ID="sub-child-1111"
SUB2_ID="sub-nested-2222"
SUB_BAD_ID="sub-corrupt-3333"
BRAIN_DIR="$HOME/.gemini/antigravity-cli/brain"
CONV_DIR="$HOME/.gemini/antigravity-cli/conversations"
mkdir -p "$BRAIN_DIR/$ROOT_SID/.system_generated/subagents" "$BRAIN_DIR/$SUB1_ID/.system_generated/subagents" "$BRAIN_DIR/$SUB2_ID/.system_generated/subagents" "$CONV_DIR"

cat << JSON > "$BRAIN_DIR/$ROOT_SID/.system_generated/subagents/$SUB1_ID.json"
{"conversationId":"$SUB1_ID","subagentDescriptor":{"typeName":"research"}}
JSON
cat << JSON > "$BRAIN_DIR/$ROOT_SID/.system_generated/subagents/$SUB_BAD_ID.json"
{"conversationId":"$SUB_BAD_ID","subagentDescriptor":{"typeName":"broken"}}
JSON
cat << JSON > "$BRAIN_DIR/$SUB1_ID/.system_generated/subagents/$SUB2_ID.json"
{"conversationId":"$SUB2_ID","subagentDescriptor":{"typeName":"self"}}
JSON
# Cycle back to root_sid to verify cycle safety
cat << JSON > "$BRAIN_DIR/$SUB2_ID/.system_generated/subagents/$ROOT_SID.json"
{"conversationId":"$ROOT_SID","subagentDescriptor":{"typeName":"cycle"}}
JSON

python3 - "$CONV_DIR" "$SUB1_ID" "$SUB2_ID" "$SUB_BAD_ID" << 'PYEOF'
import sqlite3, sys
from pathlib import Path

conv_dir = Path(sys.argv[1])
sub1, sub2, sub_bad = sys.argv[2], sys.argv[3], sys.argv[4]

def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            break
    return bytes(out)

def field_bytes(fnum: int, data: bytes) -> bytes:
    return varint((fnum << 3) | 2) + varint(len(data)) + data

def field_varint(fnum: int, val: int) -> bytes:
    return varint((fnum << 3) | 0) + varint(val)

def make_blob(u: int, c: int, o: int, thoughts: int, mkey: str, mdisp: str) -> bytes:
    usage = field_varint(2, u) + field_varint(3, o) + field_varint(5, c) + field_varint(9, thoughts)
    inner = field_bytes(4, usage) + field_bytes(19, mkey.encode()) + field_bytes(21, mdisp.encode())
    return field_bytes(1, inner)

# SUB1: multi-turn, multi-model, plus thoughts=99999 (must be excluded)
c1 = sqlite3.connect(conv_dir / f"{sub1}.db")
c1.execute("CREATE TABLE gen_metadata (id INTEGER PRIMARY KEY, bytes BLOB)")
c1.execute("INSERT INTO gen_metadata (bytes) VALUES (?)", (make_blob(10000, 40000, 1000, 99999, "gemini-4-argon", "Gemini 4 Argon (Medium)"),))
c1.execute("INSERT INTO gen_metadata (bytes) VALUES (?)", (make_blob(5000, 10000, 500, 5000, "gemini-3.8-flash", "Gemini 3.8 Flash"),))
c1.commit()
c1.close()

# SUB2: WAL mode active with uncommitted WAL frame (held open by background reader during sync)
c2 = sqlite3.connect(conv_dir / f"{sub2}.db")
c2.execute("PRAGMA journal_mode=WAL")
c2.execute("PRAGMA wal_autocheckpoint=0")
c2.execute("CREATE TABLE gen_metadata (id INTEGER PRIMARY KEY, bytes BLOB)")
c2.commit()
c2.close()

# Corrupted DB
(conv_dir / f"{sub_bad}.db").write_bytes(b"NOT A SQLITE DB")
PYEOF

# Hold a read snapshot on sub2.db while writing a WAL frame, then run subagent_sync.py while -wal is live
WAL_HOLD_READY="$TMP_HOME/wal_ready"
WAL_HOLD_DONE="$TMP_HOME/wal_done"
python3 - "$CONV_DIR/$SUB2_ID.db" "$WAL_HOLD_READY" "$WAL_HOLD_DONE" << 'PYEOF' &
import sqlite3, sys, time
from pathlib import Path

db_path, ready_p, done_p = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        out.append(b | 0x80 if n else b)
        if not n: return bytes(out)
def field_bytes(f: int, d: bytes) -> bytes: return varint((f << 3) | 2) + varint(len(d)) + d
def field_varint(f: int, v: int) -> bytes: return varint((f << 3) | 0) + varint(v)
blob = field_bytes(1, field_bytes(4, field_varint(2, 2000) + field_varint(3, 200) + field_varint(5, 8000) + field_varint(9, 1234)) + field_bytes(19, b"gemini-4-argon") + field_bytes(21, b"Gemini 4 Argon (Medium)"))

cr = sqlite3.connect(db_path)
cr.execute("BEGIN").fetchall()
cw = sqlite3.connect(db_path)
cw.execute("PRAGMA wal_autocheckpoint=0")
cw.execute("INSERT INTO gen_metadata (bytes) VALUES (?)", (blob,))
cw.commit()
cw.close()
ready_p.write_text("1")
for _ in range(100):
    if done_p.exists(): break
    time.sleep(0.05)
cr.close()
PYEOF
WAL_PID=$!
for _ in $(seq 1 50); do [ -f "$WAL_HOLD_READY" ] && break; sleep 0.05; done

SIDECAR_OUT="$JB_DIR/usage_logs/.sub_${ROOT_SID}.json"
"$JB_DIR/lib/subagent_sync.py" \
  --sid "$ROOT_SID" \
  --brain-dir "$BRAIN_DIR" \
  --conv-dir "$CONV_DIR" \
  --prices "$JB_DIR/prices.json" \
  --out "$SIDECAR_OUT" \
  --now "$TODAY_D 12:00"
touch "$WAL_HOLD_DONE"
wait "$WAL_PID" 2>/dev/null || true

assert_eq "subagent_sync creates sidecar" "true" "$([ -f "$SIDECAR_OUT" ] && echo true || echo false)"
assert_eq "subagent_sync count is 2 (skips corrupt, avoids cycle)" "2" "$(jq -r '.subagent_count' "$SIDECAR_OUT")"
assert_eq "subagent_sync excludes thoughts usage[9] from output_tokens" "1700" "$(jq -r '.output_tokens' "$SIDECAR_OUT")"
assert_eq "subagent_sync uncached_tokens" "17000" "$(jq -r '.uncached_tokens' "$SIDECAR_OUT")"
assert_eq "subagent_sync cache_tokens" "58000" "$(jq -r '.cache_tokens' "$SIDECAR_OUT")"
# Argon: (12000*2 + 48000*0.5 + 1200*10)/1e6 = 0.060; Flash: (5000*0.75 + 10000*0.1875 + 500*3.75)/1e6 = 0.0075 -> total 0.0675
assert_eq "subagent_sync cost_usd exact" "0.0675" "$(jq -r '.cost_usd' "$SIDECAR_OUT")"

# Statusline non-blocking EOF test with sleeping mock python3 in PATH
MOCK_PY_DIR=$(mktemp -d)
cat << 'SH' > "$MOCK_PY_DIR/python3"
#!/usr/bin/env bash
sleep 5
SH
chmod +x "$MOCK_PY_DIR/python3"
rm -f "$JB_DIR/usage_logs/.sub_${ROOT_SID}.ttl"
rm -rf "$JB_DIR/usage_logs/.sub_${ROOT_SID}.lock"
PAYLOAD_SUB_RUN=$(jq -nc --arg sid "$ROOT_SID" '{session_id:$sid,model:{display_name:"Gemini 4 Argon (Medium)"},context_window:{total_input_tokens:5000,total_output_tokens:500,used_percentage:10,current_usage:{input_tokens:2000,cache_read_input_tokens:3000}},cost:{total_usd:0},subagents:[{id:"s1",status:"running"}],terminal_width:120}')
T_START=$(date +%s)
OUT_SUB_BUSY=$(PATH="$MOCK_PY_DIR:$PATH" bash -c 'printf "%s" "$1" | "$2"' _ "$PAYLOAD_SUB_RUN" "$JB_DIR/statusline.sh")
T_END=$(date +%s)
assert_eq "statusline non-blocking <= 2s on sleeping python3" "true" "$([ $((T_END - T_START)) -le 2 ] && echo true || echo false)"
assert_contains "statusline busy shows (Sub: ...)" "(Sub: \$0.068 " "$OUT_SUB_BUSY"
assert_eq "statusline modern busy has Braille spinner" "true" "$(printf '%s' "$OUT_SUB_BUSY" | grep -qE '[⠋⠙⠹⠸⠼⠴⠦⠧]' && echo true || echo false)"

# Plain spinner test
"$JB_DIR/report.sh" set theme plain >/dev/null
OUT_SUB_BUSY_PLAIN=$(printf '%s' "$PAYLOAD_SUB_RUN" | "$JB_DIR/statusline.sh")
assert_eq "statusline plain busy has ASCII spinner" "true" "$(printf '%s' "$OUT_SUB_BUSY_PLAIN" | grep -qE '\(Sub: \$0\.068 [|/\\-]\)' && echo true || echo false)"
"$JB_DIR/report.sh" set theme modern >/dev/null

# Clean up any sleeping mock python3 bg process and lock
pkill -f "$MOCK_PY_DIR/python3" 2>/dev/null || true
rm -rf "$MOCK_PY_DIR" "$JB_DIR/usage_logs/.sub_${ROOT_SID}.lock"

# set status-sub off hides (Sub: ...) while keeping spinner when busy
"$JB_DIR/report.sh" set status-sub off >/dev/null
OUT_SUB_OFF=$(printf '%s' "$PAYLOAD_SUB_RUN" | "$JB_DIR/statusline.sh")
assert_not_contains "status-sub off hides (Sub:" "(Sub:" "$OUT_SUB_OFF"
assert_eq "status-sub off still shows spinner when busy" "true" "$(printf '%s' "$OUT_SUB_OFF" | grep -qE '[⠋⠙⠹⠸⠼⠴⠦⠧]' && echo true || echo false)"
"$JB_DIR/report.sh" set status-sub on >/dev/null

# Zero double-counting across repeated ticks (Pro total_usd == 0 and API total_usd > 0)
PAYLOAD_SUB_DONE=$(jq -nc --arg sid "$ROOT_SID" '{session_id:$sid,model:{display_name:"Gemini 4 Argon (Medium)"},context_window:{total_input_tokens:5000,total_output_tokens:500,used_percentage:10,current_usage:{input_tokens:2000,cache_read_input_tokens:3000}},cost:{total_usd:0},subagents:[{id:"s1",status:"completed"}],terminal_width:120}')
printf '%s' "$PAYLOAD_SUB_DONE" | "$JB_DIR/statusline.sh" >/dev/null
COST_1=$(jq -r '.cost_usd' "$JB_DIR/usage_logs/${ROOT_SID}.json")
printf '%s' "$PAYLOAD_SUB_DONE" | "$JB_DIR/statusline.sh" >/dev/null
COST_2=$(jq -r '.cost_usd' "$JB_DIR/usage_logs/${ROOT_SID}.json")
assert_eq "Pro repeated statusline ticks zero double-counting" "$COST_1" "$COST_2"
assert_eq "has_subagents persisted true" "true" "$(jq -r '.has_subagents' "$JB_DIR/usage_logs/${ROOT_SID}.json")"

PAYLOAD_API_SUB='{"session_id":"api-sub-001","model":{"display_name":"Gemini 4 Argon (Medium)"},"context_window":{"total_input_tokens":5000,"total_output_tokens":500,"used_percentage":10,"current_usage":{"input_tokens":2000,"cache_read_input_tokens":3000}},"cost":{"total_usd":0.10,"subagent_usd":0.04},"terminal_width":120}'
printf '%s' "$PAYLOAD_API_SUB" | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "API main_cost_usd decoupled" "true" "$(jq -e '((.main_cost_usd - 0.06) | fabs) < 1e-9' "$JB_DIR/usage_logs/api-sub-001.json")"
assert_eq "API subagent_cost_usd preserved" "true" "$(jq -e '((.subagent_cost_usd - 0.04) | fabs) < 1e-9' "$JB_DIR/usage_logs/api-sub-001.json")"
assert_eq "API cost_usd preserved" "true" "$(jq -e '((.cost_usd - 0.10) | fabs) < 1e-9' "$JB_DIR/usage_logs/api-sub-001.json")"

# Tiny subagent cost <$0.001 formatting
OUT_TINY_SUB=$(printf '%s' '{"session_id":"tiny-sub","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0.002,"subagent_usd":0.0002},"terminal_width":120}' | "$JB_DIR/statusline.sh")
assert_contains "tiny subagent cost formats <$0.001" "(Sub: <\$0.001)" "$OUT_TINY_SUB"
rm -f "$JB_DIR/usage_logs/tiny-sub.json"

# Report tests: split mode tree view, USAGE BY MODEL unique Sess, token & cost equality, combined mode
"$JB_DIR/report.sh" set theme modern >/dev/null
"$JB_DIR/report.sh" set color on >/dev/null
"$JB_DIR/report.sh" set subagent-mode split >/dev/null
REP_SPLIT=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_contains "split KPI shows Main · Sub" "(Main: \$0.071 · Sub: \$0.108)" "$(printf '%s\n' "$REP_SPLIT" | sed $'s/\x1b\\[[0-9;]*m//g')"
assert_contains "split tree shows ├─" "├─ " "$REP_SPLIT"
assert_contains "split tree shows └─" "└─ " "$REP_SPLIT"
assert_contains "split shows Subagent (API) residual" "Subagent (API)" "$REP_SPLIT"
assert_eq "split width 115 raw line <= 160" "true" "$([ "$(printf '%s\n' "$REP_SPLIT" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')" -le 160 ] && echo true || echo false)"
assert_eq "split width 115 unified visible width 103" "103" "$(printf '%s\n' "$REP_SPLIT" | sed $'s/\x1b\\[[0-9;]*m//g' | grep -E '^(╭|│|╰|Model |─|Gemini |Subagent |GRAND |Date |[0-9]{2}-[0-9]{2} |├─ |└─ )' | awk '{print length($0)}' | sort -u)"

# Verify USAGE BY MODEL unique Sess for Gemini 4 Argon (Medium): root-sub-test-001 (parent+2 children) + api-sub-001 = 2 sessions (not 4!)
ARGON_SESS=$(printf '%s\n' "$REP_SPLIT" | sed $'s/\x1b\\[[0-9;]*m//g' | awk '/^USAGE BY MODEL/,/^RECENT SESSIONS/' | grep 'Gemini 4 Argon' | awk '{print $5}')
assert_eq "USAGE BY MODEL counts unique root_sid Sess (2)" "2" "$ARGON_SESS"

# Verify KPI Total Spend == GRAND TOTAL
KPI_SPEND=$(printf '%s\n' "$REP_SPLIT" | sed $'s/\x1b\\[[0-9;]*m//g' | grep 'Total Spend:' | sed -n 's/.*Total Spend: \([^ ]*\).*/\1/p')
GRAND_SPEND=$(printf '%s\n' "$REP_SPLIT" | sed $'s/\x1b\\[[0-9;]*m//g' | grep '^GRAND TOTAL' | awk '{print $NF}')
assert_eq "KPI Total Spend == GRAND TOTAL" "$KPI_SPEND" "$GRAND_SPEND"

# Plain split mode uses |- prefix and | separator
"$JB_DIR/report.sh" set theme plain >/dev/null
REP_SPLIT_PLAIN=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_contains "plain split uses |- prefix" "|- " "$REP_SPLIT_PLAIN"
assert_contains "plain split KPI uses | separator" "(Main: \$0.071 | Sub: \$0.108)" "$REP_SPLIT_PLAIN"
"$JB_DIR/report.sh" set theme modern >/dev/null

# Combined mode merges children into parent row, keeps USAGE BY MODEL identical
"$JB_DIR/report.sh" set subagent-mode combined >/dev/null
REP_COMB=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_not_contains "combined mode omits ├─" "├─ " "$REP_COMB"
assert_not_contains "combined mode omits Main · Sub in KPI" "(Main:" "$REP_COMB"
GRAND_COMB=$(printf '%s\n' "$REP_COMB" | sed $'s/\x1b\\[[0-9;]*m//g' | grep '^GRAND TOTAL' | awk '{print $NF}')
assert_eq "combined GRAND TOTAL == split GRAND TOTAL" "$GRAND_SPEND" "$GRAND_COMB"
"$JB_DIR/report.sh" set subagent-mode split >/dev/null

# On-read sync in report.sh refreshes missing sidecar for has_subagents: true, ignores legacy without has_subagents
rm -f "$SIDECAR_OUT"
cat << JSON > "$JB_DIR/usage_logs/legacy-no-sub.json"
{"timestamp":"$TODAY_D 11:00","session_id":"legacy-no-sub","model":"Flash","input_tokens":100,"uncached_tokens":100,"cache_tokens":0,"output_tokens":10,"cost_usd":0.001}
JSON
"$JB_DIR/report.sh" all >/dev/null
assert_eq "report.sh on-read sync recreated missing sidecar" "true" "$([ -f "$SIDECAR_OUT" ] && echo true || echo false)"
assert_eq "report.sh does not backfill legacy session" "false" "$([ -f "$JB_DIR/usage_logs/.sub_legacy-no-sub.json" ] && echo true || echo false)"

# CLI validation for subagent-mode and status-sub
for bad_sub in "set subagent-mode bogus" "set status-sub bogus"; do
  if "$JB_DIR/report.sh" $bad_sub >/dev/null 2>&1; then
    echo "FAIL: '$bad_sub' should exit 1" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done

# Additional edge-case tests: subagent_sync.py path traversal, depth>5, malformed JSON/prices, protobuf edge cases
PY_EDGE_OUT=$(PYTHONPATH="$REPO_DIR/lib" python3 -B - "$TMP_HOME" "$JB_DIR/prices.json" << 'PYEOF'
import json, sqlite3, tempfile
from pathlib import Path
import subagent_sync as ss

with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    brain = root / "brain"
    conv = root / "conv"
    conv.mkdir()

    # Path traversal & invalid JSON & missing DB & depth > 5
    sid = "edge-root"
    (brain / sid / ".system_generated" / "subagents").mkdir(parents=True)
    (brain / sid / ".system_generated" / "subagents" / "trav.json").write_text(json.dumps({"conversationId": "../../etc/passwd"}))
    (brain / sid / ".system_generated" / "subagents" / "badutf8.json").write_bytes(b"\xff\xfe{")
    (brain / sid / ".system_generated" / "subagents" / "nodb.json").write_text("{}")

    # Depth 1..6 chain
    cur = sid
    for d in range(1, 7):
        nxt = f"d{d}"
        (brain / cur / ".system_generated" / "subagents").mkdir(parents=True, exist_ok=True)
        (brain / cur / ".system_generated" / "subagents" / f"{nxt}.json").write_text(json.dumps({"conversationId": nxt}))
        cur = nxt
    disc = [x[0] for x in ss.discover_subagents(brain, sid, max_depth=5)]
    assert "d5" in disc and "d6" not in disc, f"depth failed: {disc}"
    assert not any("passwd" in x for x in disc), f"traversal leaked: {disc}"

    # Malformed prices.json, missing prices, non-dict models, null/invalid rates, match_rate fallback
    bad_p = root / "bad_prices.json"
    bad_p.write_text("[1,2,3]")
    rules, def_r = ss.load_prices(bad_p)
    assert rules == [] and def_r["in"] == 2.0
    assert ss.load_prices(root / "missing.json") == ([], ss.DEFAULT_RATE)
    corrupt_p = root / "corrupt_prices.json"
    corrupt_p.write_text("{")
    assert ss.load_prices(corrupt_p) == ([], ss.DEFAULT_RATE)
    non_utf8_p = root / "badutf8_prices.json"
    non_utf8_p.write_bytes(b"\xff\xfe")
    assert ss.load_prices(non_utf8_p) == ([], ss.DEFAULT_RATE)
    nondict_m = root / "nondict_models.json"
    nondict_m.write_text(json.dumps({"models": []}))
    assert ss.load_prices(nondict_m) == ([], ss.DEFAULT_RATE)
    nondict_def = root / "nondict_def.json"
    nondict_def.write_text(json.dumps({"models": {"default": "bad", "bad_entry": "x", "flash": {"in": 1, "cached": 0.2, "out": 2}}}))
    r2, d2 = ss.load_prices(nondict_def)
    assert len(r2) == 1 and d2 == ss.DEFAULT_RATE
    assert ss.match_rate("unknown-model", r2, d2) == d2
    assert ss._safe_float(None, 2.0) == 2.0
    assert ss._safe_float(True, 2.0) == 2.0
    assert ss._safe_float("nan", 2.0) == 2.0
    assert ss._safe_float("inf", 2.0) == 2.0
    assert ss._safe_float("abc", 2.0) == 2.0
    assert ss._safe_float([], 2.0) == 2.0
    assert ss._safe_float("1.5", 2.0) == 1.5

    # Trailing newline ID rejected, non-dict subagent JSON, invalid stem, invalid root_sid
    assert ss.discover_subagents(brain, "bad\n", max_depth=5) == []
    (brain / sid / ".system_generated" / "subagents" / "nondict.json").write_text("[]")
    (brain / sid / ".system_generated" / "subagents" / "bad.stem!.json").write_text("{}")

    # Protobuf edge cases: top-level overlong tag, truncated varint, wire types 1/2/5, field_num 0, invalid wire type 3, non-varint in usage, model fallbacks
    assert ss.parse_gen_metadata_blob(b"\x80" * 11) == []
    assert ss.read_varint(b"\x80" * 11, 0)[0] is None
    assert ss.parse_gen_metadata_blob(b"\x08\x80") == []
    assert ss.parse_gen_metadata_blob(b"\x00\x01") == []
    assert ss.parse_gen_metadata_blob(b"\x0b") == []
    assert ss.parse_gen_metadata_blob(b"\x09\x00\x00") == []
    assert ss.parse_gen_metadata_blob(b"\x0d\x00\x00") == []
    assert ss.parse_gen_metadata_blob(b"\x0a\x80") == []
    assert ss.parse_gen_metadata_blob(b"\x0a\x05\x01") == []
    # wire type 1 (8 bytes) + wire type 5 (4 bytes) + field 1 with 0-token turn
    blob_wt = b"\x09" + (b"\x00" * 8) + b"\x0d" + (b"\x00" * 4) + b"\x0a\x02\x98\x01"
    assert ss.parse_gen_metadata_blob(blob_wt) == []
    # usage with non-varint field + model_key only fallback + Unknown fallback
    def vi(n):
        o = bytearray()
        while True:
            b = n & 0x7F; n >>= 7
            o.append(b | 0x80 if n else b)
            if not n: return bytes(o)
    def fb(f, d): return vi((f << 3) | 2) + vi(len(d)) + d
    def fv(f, v): return vi((f << 3) | 0) + vi(v)
    u_blob = fv(2, 10) + fb(3, b"x")
    t_key_only = ss.parse_gen_metadata_blob(fb(1, fb(4, u_blob) + fb(19, b"mkey")))
    assert t_key_only[0][0] == "mkey"
    t_unk = ss.parse_gen_metadata_blob(fb(1, fb(4, u_blob)))
    assert t_unk[0][0] == "Unknown"

    # DB with NULL bytes column + extra blob column (must NOT misparse extra blob)
    null_db = conv / "d1.db"
    c = sqlite3.connect(null_db)
    c.execute("CREATE TABLE gen_metadata (id INTEGER PRIMARY KEY, bytes BLOB, extra BLOB)")
    c.execute("INSERT INTO gen_metadata (bytes, extra) VALUES (NULL, ?)", (b"\x0a\x05\x22\x02\x10\x05\x00",))
    c.commit()
    c.close()
    assert ss.read_gen_metadata_rows(null_db) == []

    # Table without 'bytes' column falls back to first BLOB column
    nobytes_db = conv / "d2.db"
    cnb = sqlite3.connect(nobytes_db)
    cnb.execute("CREATE TABLE gen_metadata (id INTEGER PRIMARY KEY, payload BLOB)")
    cnb.execute("INSERT INTO gen_metadata (payload) VALUES (?)", (fb(1, fb(4, fv(2, 100))),))
    cnb.commit()
    cnb.close()
    assert len(ss.read_gen_metadata_rows(nobytes_db)) == 1

    # format_timestamp fallbacks: missing db -> json_path -> fallback_now
    jf_only = root / "only.json"
    jf_only.write_text("{}")
    assert ss.format_timestamp(root / "missing.db", jf_only, "1999-01-01 00:00") != "1999-01-01 00:00"
    assert ss.format_timestamp(root / "missing.db", root / "missing.json", "1999-01-01 00:00") == "1999-01-01 00:00"

    res = ss.sync_subagents(sid, brain, conv, bad_p, root / "out.json", "2026-11-22 12:00")
    assert res["subagent_count"] == 1
    print("OK")
PYEOF
)
assert_eq "subagent_sync.py edge cases" "OK" "$PY_EDGE_OUT"

# jenbach_maybe_sync_subagents TTL hit, expired TTL, missing sidecar, sig-change bypass, active lock skip, stale lock recovery (no ts)
SYNC_TEST_DIR=$(mktemp -d)
(
  . "$JB_DIR/lib/auto_update.sh"
  NOW_EP=$(date +%s)
  # Early returns for none / 0_0
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "none" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_0" "2026-11-22 12:00"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s0" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "0_0" "2026-11-22 12:00"
  [ ! -d "$SYNC_TEST_DIR/.sub_none.lock" ] && [ ! -d "$SYNC_TEST_DIR/.sub_s0.lock" ] || exit 1

  # TTL hit with matching sig -> does not create lock
  printf '%s %s\n' "$((NOW_EP + 60))" "1_0" > "$SYNC_TEST_DIR/.sub_s1.ttl"
  printf '{}\n' > "$SYNC_TEST_DIR/.sub_s1.json"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s1" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_0" "2026-11-22 12:00"
  [ ! -d "$SYNC_TEST_DIR/.sub_s1.lock" ] || exit 1

  # Expired TTL -> re-triggers sync
  printf '%s %s\n' "$((NOW_EP - 10))" "1_0" > "$SYNC_TEST_DIR/.sub_s1.ttl"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s1" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_0" "2026-11-22 12:00"
  for _ in $(seq 1 30); do
    _ttl_v=$(cat "$SYNC_TEST_DIR/.sub_s1.ttl" 2>/dev/null || echo "0 0")
    [ "${_ttl_v%% *}" -gt "$NOW_EP" ] && break
    sleep 0.05
  done
  _ttl_v=$(cat "$SYNC_TEST_DIR/.sub_s1.ttl")
  [ "${_ttl_v%% *}" -gt "$NOW_EP" ] || exit 1

  # Valid TTL with missing sidecar -> re-triggers sync
  printf '%s %s\n' "$((NOW_EP + 60))" "1_0" > "$SYNC_TEST_DIR/.sub_s1m.ttl"
  rm -f "$SYNC_TEST_DIR/.sub_s1m.json"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s1m" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_0" "2026-11-22 12:00"
  for _ in $(seq 1 30); do [ -f "$SYNC_TEST_DIR/.sub_s1m.json" ] && break; sleep 0.05; done
  [ -f "$SYNC_TEST_DIR/.sub_s1m.json" ] || exit 1

  # Valid TTL + existing sidecar + changed SUB_SIG -> bypasses TTL and syncs
  printf '%s %s\n' "$((NOW_EP + 60))" "1_0" > "$SYNC_TEST_DIR/.sub_s1m.ttl"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s1m" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_1" "2026-11-22 12:00"
  for _ in $(seq 1 30); do
    _ttl_sig=$(cat "$SYNC_TEST_DIR/.sub_s1m.ttl" 2>/dev/null || echo "")
    [ "${_ttl_sig#* }" = "1_1" ] && break
    sleep 0.05
  done
  _ttl_sig=$(cat "$SYNC_TEST_DIR/.sub_s1m.ttl")
  [ "${_ttl_sig#* }" = "1_1" ] || exit 1

  # Active lock (<= 30s) -> returns 0 without overwriting TTL
  mkdir -p "$SYNC_TEST_DIR/.sub_s2.lock"
  printf '%s\n' "$NOW_EP" > "$SYNC_TEST_DIR/.sub_s2.lock/ts"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s2" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_1" "2026-11-22 12:00"
  [ ! -f "$SYNC_TEST_DIR/.sub_s2.ttl" ] || exit 1
  rm -rf "$SYNC_TEST_DIR/.sub_s2.lock"

  # Stale lock (> 30s) with ts and without ts (stat mtime fallback) -> recovers lock and spawns bg sync
  mkdir -p "$SYNC_TEST_DIR/.sub_s3.lock"
  printf '%s\n' "$((NOW_EP - 100))" > "$SYNC_TEST_DIR/.sub_s3.lock/ts"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s3" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_1" "2026-11-22 12:00"
  for _ in $(seq 1 30); do [ -f "$SYNC_TEST_DIR/.sub_s3.ttl" ] && break; sleep 0.05; done
  [ -f "$SYNC_TEST_DIR/.sub_s3.ttl" ] || exit 1

  mkdir -p "$SYNC_TEST_DIR/.sub_s4.lock"
  touch -d "2020-01-01 00:00:00" "$SYNC_TEST_DIR/.sub_s4.lock"
  jenbach_maybe_sync_subagents "$SYNC_TEST_DIR" "s4" "$HOME/.gemini/antigravity-cli" "$JB_DIR/prices.json" "$JB_DIR/lib" "1_1" "2026-11-22 12:00"
  for _ in $(seq 1 30); do [ -f "$SYNC_TEST_DIR/.sub_s4.ttl" ] && break; sleep 0.05; done
  [ -f "$SYNC_TEST_DIR/.sub_s4.ttl" ] || exit 1
)
assert_eq "jenbach_maybe_sync_subagents TTL/lock branches" "0" "$?"
rm -rf "$SYNC_TEST_DIR"

# Statusline narrow (<75) + zero-cost busy + non-array .subagents + legacy $prev + status-sub off idle + API total <= sub_cost
OUT_NAR_BUSY=$(printf '%s' "$PAYLOAD_SUB_RUN" | jq -c '. + {terminal_width: 60}' | "$JB_DIR/statusline.sh")
assert_not_contains "narrow busy hides (Sub: text" "(Sub:" "$OUT_NAR_BUSY"
assert_eq "narrow busy shows spinner" "true" "$(printf '%s' "$OUT_NAR_BUSY" | grep -qE '[⠋⠙⠹⠸⠼⠴⠦⠧]' && echo true || echo false)"

OUT_NAR_IDLE=$(printf '%s' "$PAYLOAD_SUB_DONE" | jq -c '. + {terminal_width: 60}' | "$JB_DIR/statusline.sh")
assert_not_contains "narrow idle hides (Sub: text" "(Sub:" "$OUT_NAR_IDLE"

OUT_BAD_SUB=$(printf '%s' '{"session_id":"bad-sub-arr","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0.01},"subagents":{"not":"array"},"terminal_width":120}' | "$JB_DIR/statusline.sh")
assert_contains "non-array .subagents still preserves session_id" "Flash" "$OUT_BAD_SUB"
assert_eq "non-array .subagents writes session log" "true" "$([ -f "$JB_DIR/usage_logs/bad-sub-arr.json" ] && echo true || echo false)"
rm -f "$JB_DIR/usage_logs/bad-sub-arr.json"

"$JB_DIR/report.sh" set status-sub off >/dev/null
for _ in $(seq 1 40); do [ ! -d "$JB_DIR/usage_logs/.sub_${ROOT_SID}.lock" ] && break; sleep 0.05; done
printf '%s %s\n' "$(( $(date +%s) + 60 ))" "1_1" > "$JB_DIR/usage_logs/.sub_${ROOT_SID}.ttl"
OUT_OFF_IDLE=$(printf '%s' "$PAYLOAD_SUB_DONE" | "$JB_DIR/statusline.sh")
assert_not_contains "status-sub off idle hides (Sub:" "(Sub:" "$OUT_OFF_IDLE"
assert_eq "status-sub off idle has no spinner" "false" "$(jq -rn --arg s "$OUT_OFF_IDLE" '$s | test("[⠋⠙⠹⠸⠼⠴⠦⠧]")')"
"$JB_DIR/report.sh" set status-sub on >/dev/null

# Legacy $prev without main_cost_usd (both orig_cost >= orig_sub and orig_cost < orig_sub)
cat << JSON > "$JB_DIR/usage_logs/leg-prev.json"
{"timestamp":"$TODAY_D 10:00","session_id":"leg-prev","last_turn_sig":"100_0_0","last_tot_in":100,"model":"Flash","uncached_tokens":100,"cache_tokens":0,"output_tokens":10,"cost_usd":0.02,"subagent_cost_usd":0.05}
JSON
printf '%s' '{"session_id":"leg-prev","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0},"terminal_width":120}' | "$JB_DIR/statusline.sh" >/dev/null
assert_eq "legacy prev orig_cost < orig_sub derives main_cost_usd=0.02" "true" "$(jq -e '((.main_cost_usd - 0.02) | fabs) < 1e-9' "$JB_DIR/usage_logs/leg-prev.json")"
rm -f "$JB_DIR/usage_logs/leg-prev.json"

# Report on-read stale refresh when .sub_<sid>.json exists but DB is newer, plus <$0.001 KPI subagent
sleep 1
touch "$CONV_DIR/$SUB1_ID.db"
"$JB_DIR/report.sh" all >/dev/null
assert_eq "report.sh refreshes stale existing sidecar" "true" "$([ "$SIDECAR_OUT" -nt "$CONV_DIR/$SUB1_ID.db" ] || [ ! "$CONV_DIR/$SUB1_ID.db" -nt "$SIDECAR_OUT" ] && echo true || echo false)"

OUT_ZERO_BUSY=$(printf '%s' '{"session_id":"zero-busy","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0},"subagents":[{"id":"a","status":"running"}],"terminal_width":120}' | "$JB_DIR/statusline.sh")
assert_contains "zero-cost busy shows (sp 1 sub)" "1 sub)" "$OUT_ZERO_BUSY"
OUT_ZERO_BUSY_NAR=$(printf '%s' '{"session_id":"zero-busy","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0},"subagents":[{"id":"a","status":"running"}],"terminal_width":60}' | "$JB_DIR/statusline.sh")
assert_not_contains "zero-cost busy narrow hides 1 sub)" "1 sub)" "$OUT_ZERO_BUSY_NAR"
assert_eq "zero-cost busy narrow shows spinner" "true" "$(jq -rn --arg s "$OUT_ZERO_BUSY_NAR" '$s | test("[⠋⠙⠹⠸⠼⠴⠦⠧]")')"
rm -f "$JB_DIR/usage_logs/zero-busy.json"

# Report: KPI <$0.001 subagent + residual Subagent (API) when sub_records_sum > 0 + nested _nsj staleness
TINY_DIR=$(mktemp -d)
HOME_BAK="$HOME"
export HOME="$TINY_DIR"
"$REPO_DIR/install.sh" >/dev/null
cat << JSON > "$TINY_DIR/.gemini/antigravity-cli/jenbach/usage_logs/tiny_kpi.json"
{"timestamp":"$TODAY_D 12:00","session_id":"tiny_kpi","model":"Flash","uncached_tokens":100,"cache_tokens":0,"output_tokens":10,"main_cost_usd":0.0002,"subagent_cost_usd":0.0052,"cost_usd":0.0054,"has_subagents":true,"subagent_records":[{"session_id":"s1","timestamp":"$TODAY_D 12:00","model":"Flash","uncached_tokens":100,"cache_tokens":0,"output_tokens":10,"cost_usd":0.0002}]}
JSON
REP_TINY_RES=$(JENBACH_WIDTH=115 "$TINY_DIR/.gemini/antigravity-cli/jenbach/report.sh" all)
assert_contains "KPI formats tiny main <$0.001" "Main: <\$0.001" "$REP_TINY_RES"
assert_contains "residual > 0.0005 on top of subagent_records emits Subagent (API)" "Subagent (API)" "$REP_TINY_RES"
export HOME="$HOME_BAK"
rm -rf "$TINY_DIR"

OUT_API_LE=$(printf '%s' '{"session_id":"api-le","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":100,"total_output_tokens":10,"used_percentage":1},"cost":{"total_usd":0.02,"subagent_usd":0.05},"terminal_width":120}' | "$JB_DIR/statusline.sh")
assert_eq "API total <= sub_cost clamps main=0 and fcost=sub" "0 0.05" "$(jq -r '"\(.main_cost_usd) \(.cost_usd)"' "$JB_DIR/usage_logs/api-le.json")"
rm -f "$JB_DIR/usage_logs/api-le.json"

# Corrupt sidecar for one session must not discard valid sidecars for other sessions
printf '{corrupt' > "$JB_DIR/usage_logs/.sub_corrupt-sess.json"
cat << JSON > "$JB_DIR/usage_logs/corrupt-sess.json"
{"timestamp":"$TODAY_D 10:00","session_id":"corrupt-sess","model":"Flash","input_tokens":100,"uncached_tokens":100,"cache_tokens":0,"output_tokens":10,"cost_usd":0.001,"has_subagents":true}
JSON
REP_CORRUPT_SC=$(JENBACH_WIDTH=115 "$JB_DIR/report.sh" all)
assert_contains "corrupt sidecar does not drop other session Subagent split" "Sub: \$0.108)" "$(printf '%s\n' "$REP_CORRUPT_SC" | sed $'s/\x1b\\[[0-9;]*m//g')"
rm -f "$JB_DIR/usage_logs/corrupt-sess.json" "$JB_DIR/usage_logs/.sub_corrupt-sess.json"

# Missing python3 graceful degradation
NO_PY_DIR=$(mktemp -d)
for bin in bash jq grep awk sed tr date cat mkdir rm mv; do
  bpath=$(command -v "$bin" 2>/dev/null || true)
  [ -n "$bpath" ] && ln -sf "$bpath" "$NO_PY_DIR/$bin"
done
OUT_NOPY=$(PATH="$NO_PY_DIR" "$JB_DIR/report.sh" info)
assert_contains "report info without python3 shows not found" "python3=not found" "$OUT_NOPY"
OUT_SL_NOPY=$(printf '%s' "$PAYLOAD_SUB_RUN" | PATH="$NO_PY_DIR" "$JB_DIR/statusline.sh")
assert_contains "statusline without python3 still renders" "Gemini 4 Argon" "$OUT_SL_NOPY"
rm -rf "$NO_PY_DIR"

# USER_INPUT prompt counting, 10-block KPI bar, and Msgs column tests
PROMPT_DIR=$(mktemp -d)
HOME_BAK="$HOME"
export HOME="$PROMPT_DIR"
"$REPO_DIR/install.sh" >/dev/null
P_BRAIN="$PROMPT_DIR/.gemini/antigravity-cli/brain"
P_LOGS="$PROMPT_DIR/.gemini/antigravity-cli/jenbach/usage_logs"
mkdir -p "$P_BRAIN/p_sess_01/.system_generated/logs"
cat << 'JSONL' > "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
{"type":"USER_INPUT","content":"hello"}
"USER_INPUT"
["USER_INPUT"]
123
null
{"type":"PLANNER_RESPONSE","content":"{\"type\":\"USER_INPUT\"}"}
{"type":"USER_INPUT","content":"second"}
{"type":"USER_INPUT","content":"third"}
{"type":"USER_INPUT","content":"truncated
JSONL
P_PAYLOAD='{"session_id":"p_sess_01","model":{"display_name":"Gemini 4 Hydrogen (Medium)"},"context_window":{"total_input_tokens":1000,"total_output_tokens":100,"used_percentage":10,"current_usage":{"input_tokens":500,"cache_read_input_tokens":500}},"cost":{"total_usd":0.01},"terminal_width":120}'
printf '%s' "$P_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline counts 3 valid USER_INPUT lines" "3" "$(jq -r '.user_prompts' "$P_LOGS/p_sess_01.json")"

# Idle tick when transcript.jsonl is older than log file skips re-parsing
cat << 'JSONL' >> "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
{"type":"USER_INPUT","content":"fourth"}
JSONL
touch -d "2020-01-01 00:00:00" "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
printf '%s' "$P_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline skips re-parse when transcript older than log" "3" "$(jq -r '.user_prompts' "$P_LOGS/p_sess_01.json")"

# Newer transcript updates user_prompts monotonically to 4
touch -d "2030-01-01 00:00:00" "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
printf '%s' "$P_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline updates user_prompts when transcript newer" "4" "$(jq -r '.user_prompts' "$P_LOGS/p_sess_01.json")"

# Monotonicity: truncated transcript does not reduce user_prompts
printf '{"type":"USER_INPUT","content":"only one"}\n' > "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
touch -d "2035-01-01 00:00:00" "$P_BRAIN/p_sess_01/.system_generated/logs/transcript.jsonl"
printf '%s' "$P_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline preserves max user_prompts monotonically" "4" "$(jq -r '.user_prompts' "$P_LOGS/p_sess_01.json")"

# Test .transcript_path payload override
CUSTOM_TP="$PROMPT_DIR/custom_transcript.jsonl"
printf '{"type":"USER_INPUT","content":"a"}\n{"type":"USER_INPUT","content":"b"}\n' > "$CUSTOM_TP"
P_TP_PAYLOAD=$(printf '{"session_id":"p_tp_01","transcript_path":"%s","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":50,"used_percentage":5,"current_usage":{"input_tokens":250,"cache_read_input_tokens":250}},"cost":{"total_usd":0.005},"terminal_width":120}' "$CUSTOM_TP")
printf '%s' "$P_TP_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline uses .transcript_path payload override" "2" "$(jq -r '.user_prompts' "$P_LOGS/p_tp_01.json")"

# Test statusline backfill when log lacks user_prompts even if transcript is older
mkdir -p "$P_BRAIN/p_backfill_01/.system_generated/logs"
printf '{"type":"USER_INPUT","content":"x"}\n{"type":"USER_INPUT","content":"y"}\n' > "$P_BRAIN/p_backfill_01/.system_generated/logs/transcript.jsonl"
touch -d "2020-01-01 00:00:00" "$P_BRAIN/p_backfill_01/.system_generated/logs/transcript.jsonl"
cat << JSON > "$P_LOGS/p_backfill_01.json"
{"timestamp":"$TODAY_D 10:00","session_id":"p_backfill_01","last_turn_sig":"500_250_250","last_tot_in":500,"model":"Flash","input_tokens":500,"uncached_tokens":250,"cache_tokens":250,"cache_pct":50,"output_tokens":50,"main_cost_usd":0.005,"subagent_cost_usd":0,"cost_usd":0.005,"has_subagents":false,"subagent_records":[]}
JSON
P_BF_PAYLOAD='{"session_id":"p_backfill_01","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":50,"used_percentage":5,"current_usage":{"input_tokens":250,"cache_read_input_tokens":250}},"cost":{"total_usd":0.005},"terminal_width":120}'
printf '%s' "$P_BF_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline backfills missing user_prompts even when transcript is older" "2" "$(jq -r '.user_prompts' "$P_LOGS/p_backfill_01.json")"

# Test statusline with 0 USER_INPUT lines writes user_prompts: 0, and repairs non-numeric prev.user_prompts
mkdir -p "$P_BRAIN/p_zero_sl/.system_generated/logs"
printf '{"type":"PLANNER_RESPONSE","content":"hi"}\n' > "$P_BRAIN/p_zero_sl/.system_generated/logs/transcript.jsonl"
P_ZSL_PAYLOAD='{"session_id":"p_zero_sl","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":50,"used_percentage":5,"current_usage":{"input_tokens":250,"cache_read_input_tokens":250}},"cost":{"total_usd":0.005},"terminal_width":120}'
printf '%s' "$P_ZSL_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline with 0 USER_INPUT writes user_prompts=0" "0" "$(jq -r '.user_prompts' "$P_LOGS/p_zero_sl.json")"

mkdir -p "$P_BRAIN/p_repair_sl/.system_generated/logs"
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$P_BRAIN/p_repair_sl/.system_generated/logs/transcript.jsonl"
cat << JSON > "$P_LOGS/p_repair_sl.json"
{"timestamp":"$TODAY_D 10:00","session_id":"p_repair_sl","last_turn_sig":"500_250_250","last_tot_in":500,"model":"Flash","input_tokens":500,"uncached_tokens":250,"cache_tokens":250,"cache_pct":50,"output_tokens":50,"main_cost_usd":0.005,"subagent_cost_usd":0,"cost_usd":0.005,"has_subagents":false,"subagent_records":[],"user_prompts":"bad"}
JSON
touch -d "2030-01-01 00:00:00" "$P_BRAIN/p_repair_sl/.system_generated/logs/transcript.jsonl"
P_REP_PAYLOAD='{"session_id":"p_repair_sl","model":{"display_name":"Flash"},"context_window":{"total_input_tokens":500,"total_output_tokens":50,"used_percentage":5,"current_usage":{"input_tokens":250,"cache_read_input_tokens":250}},"cost":{"total_usd":0.005},"terminal_width":120}'
printf '%s' "$P_REP_PAYLOAD" | "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/statusline.sh" >/dev/null
assert_eq "statusline repairs non-numeric prev.user_prompts" "2" "$(jq -r '.user_prompts' "$P_LOGS/p_repair_sl.json")"

# Session named "brain" must not break /brain/ path extraction
mkdir -p "$P_BRAIN/brain/.system_generated/logs"
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$P_BRAIN/brain/.system_generated/logs/transcript.jsonl"
cat << JSON > "$P_LOGS/brain.json"
{"timestamp":"$TODAY_D 10:02","session_id":"brain","model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010}
JSON

# Legacy session without user_prompts + child subagent record, plus newer transcript increasing user_prompts and 0-prompt parent
mkdir -p "$P_BRAIN/p_legacy_01/.system_generated/logs"
cat << 'JSONL' > "$P_BRAIN/p_legacy_01/.system_generated/logs/transcript.jsonl"
{"type":"USER_INPUT","content":"one"}
{"type":"PLANNER_RESPONSE","content":"{\"type\":\"USER_INPUT\"}"}
{"type":"USER_INPUT","content":"two"}
{"type":"USER_INPUT","content":"three"}
{"type":"USER_INPUT","truncated
JSONL
cat << JSON > "$P_LOGS/p_legacy_01.json"
{"timestamp":"$TODAY_D 11:00","session_id":"p_legacy_01","model":"Gemini 4 Hydrogen (Medium)","input_tokens":2000,"uncached_tokens":1000,"cache_tokens":1000,"output_tokens":200,"main_cost_usd":0.050,"subagent_cost_usd":0.010,"cost_usd":0.060,"has_subagents":true,"subagent_records":[{"session_id":"p_sub_01","timestamp":"$TODAY_D 11:01","model":"Gemini 4 Flash (Low)","uncached_tokens":500,"cache_tokens":500,"output_tokens":50,"cost_usd":0.010}]}
JSON

mkdir -p "$P_BRAIN/p_inc_01/.system_generated/logs"
cat << JSON > "$P_LOGS/p_inc_01.json"
{"timestamp":"$TODAY_D 11:05","session_id":"p_inc_01","model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":3}
JSON
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$P_BRAIN/p_inc_01/.system_generated/logs/transcript.jsonl"
touch -d "2030-01-01 00:00:00" "$P_BRAIN/p_inc_01/.system_generated/logs/transcript.jsonl"

cat << JSON > "$P_LOGS/p_zero_01.json"
{"timestamp":"$TODAY_D 10:30","session_id":"p_zero_01","model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":0}
JSON

# Report monotonicity (newer shrunk transcript keeps higher user_prompts) and skip-reparse (older transcript skipped)
mkdir -p "$P_BRAIN/p_mono_01/.system_generated/logs"
cat << JSON > "$P_LOGS/p_mono_01.json"
{"timestamp":"$TODAY_D 10:20","session_id":"p_mono_01","model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":4}
JSON
printf '{"type":"USER_INPUT"}\n' > "$P_BRAIN/p_mono_01/.system_generated/logs/transcript.jsonl"
touch -d "2030-01-01 00:00:00" "$P_BRAIN/p_mono_01/.system_generated/logs/transcript.jsonl"

mkdir -p "$P_BRAIN/p_skip_01/.system_generated/logs"
cat << JSON > "$P_LOGS/p_skip_01.json"
{"timestamp":"$TODAY_D 10:10","session_id":"p_skip_01","model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":2}
JSON
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$P_BRAIN/p_skip_01/.system_generated/logs/transcript.jsonl"
touch -d "2020-01-01 00:00:00" "$P_BRAIN/p_skip_01/.system_generated/logs/transcript.jsonl"

# Non-numeric user_prompts and numeric session_id resilience
cat << JSON > "$P_LOGS/p_bad_01.json"
{"timestamp":"$TODAY_D 10:05","session_id":99901,"model":"Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":"bad"}
JSON

REP_PROMPT=$(JENBACH_WIDTH=115 "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" all)
assert_contains "KPI cache bar has 10 blocks" "50% ▓▓▓▓▓░░░░░" "$REP_PROMPT"
assert_contains "RECENT SESSIONS header has Msgs column" "Msgs" "$REP_PROMPT"
REP_PROMPT_PLAIN_LINES=$(printf '%s\n' "$REP_PROMPT" | sed $'s/\x1b\\[[0-9;]*m//g')
LEGACY_PARENT_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_legacy')
LEGACY_CHILD_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_sub_01')
INC_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_inc_01')
ZERO_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_zero_0')
MONO_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_mono_0')
SKIP_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'p_skip_0')
BAD_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep '99901')
BRAIN_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep 'brain')
assert_contains "legacy parent row resolves Msgs=3 from transcript" " 3 " "$LEGACY_PARENT_ROW"
assert_contains "child subagent row shows - in Msgs" " - " "$LEGACY_CHILD_ROW"
assert_contains "newer transcript increases Msgs to 5 on read" " 5 " "$INC_ROW"
assert_contains "0-prompt parent row shows - in Msgs" " - " "$ZERO_ROW"
assert_contains "report preserves higher user_prompts monotonically" " 4 " "$MONO_ROW"
assert_contains "report skips re-parse when transcript older than log" " 2 " "$SKIP_ROW"
assert_contains "non-numeric user_prompts falls back to -" " - " "$BAD_ROW"
assert_contains "session named brain resolves Msgs=2" " 2 " "$BRAIN_ROW"
UNIFIED_W115=$(printf '%s\n' "$REP_PROMPT_PLAIN_LINES" | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} |└─ )' | awk '{print length($0)}' | sort -u)
assert_eq "JENBACH_WIDTH=115 unified visible width 103" "103" "$UNIFIED_W115"
MAX_RAW_PROMPT=$(printf '%s\n' "$REP_PROMPT" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
if [ "$MAX_RAW_PROMPT" -le 160 ]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: JENBACH_WIDTH=115 raw chars $MAX_RAW_PROMPT > 160" >&2
  FAIL=$((FAIL + 1))
fi

# Plain and compact KPI bar + combined mode Msgs check
"$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" set theme plain >/dev/null
"$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" set subagent-mode combined >/dev/null
REP_PROMPT_PLAIN=$(JENBACH_WIDTH=115 "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" all)
assert_contains "plain KPI cache bar has 10 blocks" "50% #####-----" "$REP_PROMPT_PLAIN"
LEGACY_COMBINED_ROW=$(printf '%s\n' "$REP_PROMPT_PLAIN" | grep 'p_legacy')
assert_contains "combined mode parent row shows Msgs=3" " 3 " "$LEGACY_COMBINED_ROW"

"$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" set theme compact >/dev/null
REP_PROMPT_COMPACT=$(JENBACH_WIDTH=115 "$PROMPT_DIR/.gemini/antigravity-cli/jenbach/report.sh" all)
assert_not_contains "compact KPI omits progress bar" "▓▓" "$REP_PROMPT_COMPACT"
assert_not_contains "compact KPI omits plain progress bar" "##" "$REP_PROMPT_COMPACT"

export HOME="$HOME_BAK"
rm -rf "$PROMPT_DIR"

# 14. user_prompts: 0 self-healing, ($TOTAL) $MAIN Cost column, terminal height auto-fit, and -n/--limit
FIT_DIR=$(mktemp -d)
export HOME="$FIT_DIR"
bash "$REPO_DIR/install.sh" >/dev/null
F_JB="$FIT_DIR/.gemini/antigravity-cli/jenbach"
F_LOGS="$F_JB/usage_logs"
F_BRAIN="$FIT_DIR/.gemini/antigravity-cli/brain"
mkdir -p "$F_LOGS" "$F_BRAIN"
TODAY_F=$(date +"%Y-%m-%d")

# 14a. statusline.sh user_prompts:0 recovery even when log mtime >= transcript mtime & unreadable transcript_path fallback
mkdir -p "$F_BRAIN/s_heal_01/.system_generated/logs"
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$F_BRAIN/s_heal_01/.system_generated/logs/transcript.jsonl"
touch -d "2020-01-01 00:00:00" "$F_BRAIN/s_heal_01/.system_generated/logs/transcript.jsonl"
cat << JSON > "$F_LOGS/s_heal_01.json"
{"timestamp":"$TODAY_F 12:00","session_id":"s_heal_01","last_turn_sig":"100_50","last_tot_in":150,"model":"Gemini 3 Flash","input_tokens":150,"uncached_tokens":100,"cache_tokens":50,"cache_pct":33,"output_tokens":20,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"has_subagents":false,"subagent_records":[],"user_prompts":0}
JSON
touch -d "2025-01-01 00:00:00" "$F_LOGS/s_heal_01.json"
printf '{"session_id":"s_heal_01","transcript_path":"/nonexistent/path/transcript.jsonl","model":{"display_name":"Gemini 3 Flash"},"context_window":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":50,"output_tokens":20}}}\n' | "$F_JB/statusline.sh" >/dev/null
HEALED_UP=$(jq -r '.user_prompts' "$F_LOGS/s_heal_01.json")
assert_eq "statusline.sh heals user_prompts:0 when log mtime > transcript mtime" "3" "$HEALED_UP"

# Empty transcript_path fallback in statusline.sh
cat << JSON > "$F_LOGS/s_heal_02.json"
{"timestamp":"$TODAY_F 12:00","session_id":"s_heal_01","last_turn_sig":"100_50","last_tot_in":150,"model":"Gemini 3 Flash","input_tokens":150,"uncached_tokens":100,"cache_tokens":50,"cache_pct":33,"output_tokens":20,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"has_subagents":false,"subagent_records":[],"user_prompts":0}
JSON
mv "$F_LOGS/s_heal_02.json" "$F_LOGS/s_heal_01.json"
printf '{"session_id":"s_heal_01","transcript_path":"","model":{"display_name":"Gemini 3 Flash"},"context_window":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":50,"output_tokens":20}}}\n' | "$F_JB/statusline.sh" >/dev/null
HEALED_UP_EMPTY=$(jq -r '.user_prompts' "$F_LOGS/s_heal_01.json")
assert_eq "statusline.sh heals user_prompts:0 with empty transcript_path" "3" "$HEALED_UP_EMPTY"
assert_eq "install.sh initializes auto_fit_height to true" "true" "$(jq -r '.auto_fit_height' "$F_JB/report_config.json")"

# Directory and 0-byte transcript_path fallback in statusline.sh
mkdir -p "$FIT_DIR/dir_transcript"
: > "$FIT_DIR/empty_transcript.jsonl"
jq '.user_prompts = 0' "$F_LOGS/s_heal_01.json" > "$F_LOGS/s_heal_01.tmp" && mv "$F_LOGS/s_heal_01.tmp" "$F_LOGS/s_heal_01.json"
printf '{"session_id":"s_heal_01","transcript_path":"%s","model":{"display_name":"Gemini 3 Flash"},"context_window":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":50,"output_tokens":20}}}\n' "$FIT_DIR/dir_transcript" | "$F_JB/statusline.sh" >/dev/null
assert_eq "statusline.sh heals user_prompts:0 when transcript_path is a directory" "3" "$(jq -r '.user_prompts' "$F_LOGS/s_heal_01.json")"

jq '.user_prompts = 0' "$F_LOGS/s_heal_01.json" > "$F_LOGS/s_heal_01.tmp" && mv "$F_LOGS/s_heal_01.tmp" "$F_LOGS/s_heal_01.json"
printf '{"session_id":"s_heal_01","transcript_path":"%s","model":{"display_name":"Gemini 3 Flash"},"context_window":{"current_usage":{"input_tokens":100,"cache_read_input_tokens":50,"output_tokens":20}}}\n' "$FIT_DIR/empty_transcript.jsonl" | "$F_JB/statusline.sh" >/dev/null
assert_eq "statusline.sh heals user_prompts:0 when transcript_path is 0-byte" "3" "$(jq -r '.user_prompts' "$F_LOGS/s_heal_01.json")"

# 14b. report.sh user_prompts:0 recovery even when log mtime > transcript mtime
mkdir -p "$F_BRAIN/r_heal_01/.system_generated/logs"
printf '{"type":"USER_INPUT"}\n{"type":"USER_INPUT"}\n' > "$F_BRAIN/r_heal_01/.system_generated/logs/transcript.jsonl"
touch -d "2020-01-01 00:00:00" "$F_BRAIN/r_heal_01/.system_generated/logs/transcript.jsonl"
cat << JSON > "$F_LOGS/r_heal_01.json"
{"timestamp":"$TODAY_F 12:01","session_id":"r_heal_01","model":"Gemini 3 Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.010,"subagent_cost_usd":0,"cost_usd":0.010,"user_prompts":0}
JSON
touch -d "2025-01-01 00:00:00" "$F_LOGS/r_heal_01.json"
REP_HEAL=$(JENBACH_WIDTH=115 "$F_JB/report.sh" all)
R_HEAL_ROW=$(printf '%s\n' "$REP_HEAL" | sed $'s/\x1b\\[[0-9;]*m//g' | grep 'r_heal_0')
assert_contains "report.sh heals user_prompts:0 when log mtime > transcript mtime" " 2 " "$R_HEAL_ROW"

# 14c. ($TOTAL) $MAIN Cost column in split mode, plain $MAIN on narrow/no-subagent, Total in combined, raw <= 160 at width 115
rm -f "$F_LOGS"/*.json
cat << JSON > "$F_LOGS/cost_sub_01.json"
{"timestamp":"$TODAY_F 14:00","session_id":"cost_sub_01","model":"Gemini 4 Hydrogen (Medium)","input_tokens":10000,"uncached_tokens":4000,"cache_tokens":6000,"output_tokens":1000,"main_cost_usd":0.990,"subagent_cost_usd":1.161,"cost_usd":2.151,"has_subagents":true,"subagent_records":[{"session_id":"sub_c_01","timestamp":"$TODAY_F 14:01","model":"Gemini 3 Flash","uncached_tokens":2000,"cache_tokens":1000,"output_tokens":500,"cost_usd":1.161}],"user_prompts":4}
JSON
cat << JSON > "$F_LOGS/cost_nosub_01.json"
{"timestamp":"$TODAY_F 13:50","session_id":"cost_nosub_01","model":"Gemini 3 Flash","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.120,"subagent_cost_usd":0,"cost_usd":0.120,"has_subagents":false,"subagent_records":[],"user_prompts":2}
JSON
"$F_JB/report.sh" set color on >/dev/null
REP_COST_W115=$(JENBACH_WIDTH=115 "$F_JB/report.sh" all)
REP_COST_PLAIN=$(printf '%s\n' "$REP_COST_W115" | sed $'s/\x1b\\[[0-9;]*m//g')
assert_contains "split mode RECENT SESSIONS header uses Cost" "Cost" "$(printf '%s\n' "$REP_COST_PLAIN" | grep 'Date')"
assert_contains "parent with subagents renders (\$2.151) \$0.990 at width 115" '($2.151) $0.990' "$(printf '%s\n' "$REP_COST_PLAIN" | grep 'cost_sub')"
assert_not_contains "parent without subagents omits rollup parens" '($0.120)' "$(printf '%s\n' "$REP_COST_PLAIN" | grep 'cost_nos')"
MAX_RAW_COST=$(printf '%s\n' "$REP_COST_W115" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
if [ "$MAX_RAW_COST" -le 160 ]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: cost rollup raw chars $MAX_RAW_COST > 160" >&2
  FAIL=$((FAIL + 1))
fi
UNIFIED_COST_W115=$(printf '%s\n' "$REP_COST_PLAIN" | grep -E '^(╭|│|╰|Model |─|Gemini |GRAND |Date |[0-9]{2}-[0-9]{2} |└─ )' | awk '{print length($0)}' | sort -u)
assert_eq "cost rollup JENBACH_WIDTH=115 unified visible width" "1" "$(printf '%s\n' "$UNIFIED_COST_W115" | wc -l | tr -d ' ')"

REP_COST_W85=$(JENBACH_WIDTH=85 "$F_JB/report.sh" all | sed $'s/\x1b\\[[0-9;]*m//g')
assert_not_contains "narrow width 85 omits (\$2.151) rollup" '($2.151)' "$(printf '%s\n' "$REP_COST_W85" | grep 'cost_sub')"
assert_contains "narrow width 85 keeps \$0.990" '$0.990' "$(printf '%s\n' "$REP_COST_W85" | grep 'cost_sub')"

REP_COST_W89=$(JENBACH_WIDTH=89 "$F_JB/report.sh" all | sed $'s/\x1b\\[[0-9;]*m//g')
assert_not_contains "boundary width 89 omits (\$2.151) rollup" '($2.151)' "$(printf '%s\n' "$REP_COST_W89" | grep 'cost_sub')"
REP_COST_W90=$(JENBACH_WIDTH=90 "$F_JB/report.sh" all | sed $'s/\x1b\\[[0-9;]*m//g')
assert_contains "boundary width 90 shows (\$2.151) \$0.990 rollup" '($2.151) $0.990' "$(printf '%s\n' "$REP_COST_W90" | grep 'cost_sub')"

"$F_JB/report.sh" set subagent-mode combined >/dev/null
REP_COST_COMB=$(JENBACH_WIDTH=115 "$F_JB/report.sh" all | sed $'s/\x1b\\[[0-9;]*m//g')
assert_contains "combined mode RECENT SESSIONS header uses Total" "Total" "$(printf '%s\n' "$REP_COST_COMB" | grep 'Date')"
"$F_JB/report.sh" set subagent-mode split >/dev/null
"$F_JB/report.sh" set color auto >/dev/null

# 14d. Tree-aware auto-fit height (JENBACH_HEIGHT=28 and JENBACH_HEIGHT=15) & -n/--limit & set auto-fit
rm -f "$F_LOGS"/*.json
# Create 15 sessions: newest (s_01) has 2 subagents (3 rows), second newest (s_02) has 2 subagents (3 rows), s_03..s_15 have 0 subagents
cat << JSON > "$F_LOGS/fit_01.json"
{"timestamp":"$TODAY_F 15:15","session_id":"fit_01_aa","model":"Gemini 4 Hydrogen (Medium)","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.200,"subagent_cost_usd":0.100,"cost_usd":0.300,"has_subagents":true,"subagent_records":[{"session_id":"sub_f1a","timestamp":"$TODAY_F 15:15","model":"Gemini 3 Flash","uncached_tokens":100,"cache_tokens":100,"output_tokens":20,"cost_usd":0.050},{"session_id":"sub_f1b","timestamp":"$TODAY_F 15:15","model":"Gemini 3 Flash","uncached_tokens":100,"cache_tokens":100,"output_tokens":20,"cost_usd":0.050}],"user_prompts":2}
JSON
cat << JSON > "$F_LOGS/fit_02.json"
{"timestamp":"$TODAY_F 15:14","session_id":"fit_02_bb","model":"Gemini 4 Hydrogen (Medium)","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.200,"subagent_cost_usd":0.100,"cost_usd":0.300,"has_subagents":true,"subagent_records":[{"session_id":"sub_f2a","timestamp":"$TODAY_F 15:14","model":"Gemini 3 Flash","uncached_tokens":100,"cache_tokens":100,"output_tokens":20,"cost_usd":0.050},{"session_id":"sub_f2b","timestamp":"$TODAY_F 15:14","model":"Gemini 3 Flash","uncached_tokens":100,"cache_tokens":100,"output_tokens":20,"cost_usd":0.050}],"user_prompts":2}
JSON
for i in $(seq -w 3 15); do
  printf -v _mm '%02d' $((15 - 10#$i))
  cat << JSON > "$F_LOGS/fit_${i}.json"
{"timestamp":"$TODAY_F 15:${_mm}","session_id":"fit_${i}_cc","model":"Gemini 4 Hydrogen (Medium)","input_tokens":1000,"uncached_tokens":500,"cache_tokens":500,"output_tokens":100,"main_cost_usd":0.100,"subagent_cost_usd":0,"cost_usd":0.100,"has_subagents":false,"subagent_records":[],"user_prompts":1}
JSON
done

# At JENBACH_HEIGHT=28: fixed_lines = 8 + 5 + (2+5) + 4 = 24 -> row_budget = 4 -> fit_01 (3 rows) fits, fit_02 (3 rows) does not fit -> shows 1 of 15
REP_FIT28=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" all)
assert_contains "JENBACH_HEIGHT=28 shows SHOWING 1 OF 15" "RECENT SESSIONS (SHOWING 1 OF 15)" "$REP_FIT28"
assert_contains "JENBACH_HEIGHT=28 includes fit_01 parent" "fit_01_a" "$REP_FIT28"
assert_contains "JENBACH_HEIGHT=28 includes fit_01 both children" "sub_f1b" "$REP_FIT28"
assert_not_contains "JENBACH_HEIGHT=28 atomically excludes fit_02" "fit_02_b" "$REP_FIT28"
assert_not_contains "JENBACH_HEIGHT=28 excludes fit_02 children" "sub_f2a" "$REP_FIT28"
assert_contains "JENBACH_HEIGHT=28 emits fit-to-terminal footer" "Showing 1 of 15 sessions (fit to terminal). Run 'jenbach -n 15' to view all." "$REP_FIT28"
FIT28_LINES=$(printf '%s\n' "$REP_FIT28" | wc -l | tr -d ' ')
if [ "$FIT28_LINES" -le 20 ]; then
  PASS=$((PASS + 1))
else
  echo "FAIL: JENBACH_HEIGHT=28 output lines $FIT28_LINES > 20" >&2
  FAIL=$((FAIL + 1))
fi

# Tiny terminal height JENBACH_HEIGHT=15 still shows at least 1 parent + all its subagents
REP_FIT15=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=15 "$F_JB/report.sh" all)
assert_contains "JENBACH_HEIGHT=15 shows at least 1 parent" "fit_01_a" "$REP_FIT15"
assert_contains "JENBACH_HEIGHT=15 keeps all subagents of first parent" "sub_f1b" "$REP_FIT15"

# -n 5 overrides auto-fit and shows non-fit footer
REP_N5=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" all -n 5)
assert_contains "-n 5 shows SHOWING 5 OF 15" "RECENT SESSIONS (SHOWING 5 OF 15)" "$REP_N5"
assert_contains "-n 5 includes fit_05" "fit_05_c" "$REP_N5"
assert_not_contains "-n 5 excludes fit_06" "fit_06_c" "$REP_N5"
assert_contains "-n 5 emits non-fit footer" "Showing 5 of 15 sessions. Run 'jenbach -n 15' to view all." "$REP_N5"
assert_not_contains "-n 5 omits (fit to terminal)" "(fit to terminal)" "$REP_N5"

# --limit 20 shows all 15 without footer
REP_N20=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" --limit 20 all)
assert_contains "--limit 20 shows LAST 20" "RECENT SESSIONS (LAST 20)" "$REP_N20"
assert_contains "--limit 20 includes fit_15" "fit_15_c" "$REP_N20"
assert_not_contains "--limit 20 omits footer" "Showing " "$REP_N20"

# Error cases for -n / --limit
for bad_n_args in "-n 0" "-n abc" "--limit" "--limit 0" "--limit abc" "-n 5 -n 10" "-n 5 --limit 10"; do
  if $F_JB/report.sh $bad_n_args >/dev/null 2>&1; then
    echo "FAIL: expected exit 1 for '$bad_n_args'" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
done

# cycle -n 5, cycle --limit 5, standalone -n 5
REP_CYC_N5=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" cycle -n 5)
assert_contains "cycle -n 5 shows SHOWING 5 OF 15" "RECENT SESSIONS (SHOWING 5 OF 15)" "$REP_CYC_N5"
REP_CYC_LIM5=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" cycle --limit 5)
assert_contains "cycle --limit 5 shows SHOWING 5 OF 15" "RECENT SESSIONS (SHOWING 5 OF 15)" "$REP_CYC_LIM5"
REP_DEF_N5=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" -n 5)
assert_contains "standalone -n 5 shows SHOWING 5 OF 15" "RECENT SESSIONS (SHOWING 5 OF 15)" "$REP_DEF_N5"

# combined mode auto-fit (1 row per parent -> 3 parents fit in row_budget=3)
"$F_JB/report.sh" set subagent-mode combined >/dev/null
REP_FIT_COMB=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" all)
assert_contains "combined mode auto-fit fits 3 parents" "RECENT SESSIONS (SHOWING 3 OF 15)" "$REP_FIT_COMB"
"$F_JB/report.sh" set subagent-mode split >/dev/null

# compact theme auto-fit ($fixed_lines uses 4 instead of 5 -> row_budget=5 -> fit_01=3 still fits, fit_02=3 does not)
"$F_JB/report.sh" set theme compact >/dev/null
REP_FIT_COMPACT=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" all)
assert_contains "compact theme auto-fit shows SHOWING 1 OF 15" "RECENT SESSIONS (SHOWING 1 OF 15)" "$REP_FIT_COMPACT"
"$F_JB/report.sh" set theme modern >/dev/null

# history_limit=5 with large JENBACH_HEIGHT=100 truncates via history_limit -> non-fit footer
"$F_JB/report.sh" set limit 5 >/dev/null
REP_LIM_TRUNC=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=100 "$F_JB/report.sh" all)
assert_contains "history_limit=5 at height 100 emits non-fit footer" "Showing 5 of 15 sessions. Run 'jenbach -n 15' to view all." "$REP_LIM_TRUNC"
assert_not_contains "history_limit=5 at height 100 omits (fit to terminal)" "(fit to terminal)" "$REP_LIM_TRUNC"
"$F_JB/report.sh" set limit 20 >/dev/null

# detect_term_size: octal-safe leading zero, LINES/COLUMNS fallback, non-numeric fallback
REP_OCTAL=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=028 "$F_JB/report.sh" all)
assert_contains "JENBACH_HEIGHT=028 parses octal-safely" "RECENT SESSIONS (SHOWING 1 OF 15)" "$REP_OCTAL"
REP_LINES=$(env -u JENBACH_HEIGHT -u JENBACH_WIDTH LINES=28 COLUMNS=115 "$F_JB/report.sh" all)
assert_contains "LINES=28 COLUMNS=115 fallback works" "RECENT SESSIONS (SHOWING 1 OF 15)" "$REP_LINES"
REP_NONNUM=$(JENBACH_WIDTH=abc JENBACH_HEIGHT=abc "$F_JB/report.sh" all)
assert_contains "non-numeric JENBACH_HEIGHT/WIDTH does not crash" "RECENT SESSIONS" "$REP_NONNUM"

# set auto-fit off / on / bogus & config output [13] / [14]
CFG_MENU_OUT=$("$F_JB/report.sh" set auto-fit off)
assert_contains "set auto-fit off updates [13]" "[13] Auto-Fit Terminal Height" "$CFG_MENU_OUT"
assert_contains "config menu shifts Reset to [14]" "[14] Reset / Clear All Session Logs" "$CFG_MENU_OUT"
REP_NOFIT=$(JENBACH_WIDTH=115 JENBACH_HEIGHT=28 "$F_JB/report.sh" all)
assert_contains "auto-fit off shows all 15 even at JENBACH_HEIGHT=28" "fit_15_c" "$REP_NOFIT"
"$F_JB/report.sh" set auto-fit on >/dev/null
if "$F_JB/report.sh" set auto-fit bogus >/dev/null 2>&1; then
  echo "FAIL: set auto-fit bogus should exit 1" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

export HOME="$HOME_BAK"
rm -rf "$FIT_DIR"

# reset cleans .sub_*.json, .sub_*.ttl, .sub_*.lock
mkdir -p "$JB_DIR/usage_logs/.sub_dummy.lock"
touch "$JB_DIR/usage_logs/.sub_dummy.ttl"
"$JB_DIR/report.sh" reset >/dev/null
assert_eq "reset removes .sub_*.json" "false" "$([ -f "$SIDECAR_OUT" ] && echo true || echo false)"
assert_eq "reset removes .sub_*.ttl" "false" "$([ -f "$JB_DIR/usage_logs/.sub_dummy.ttl" ] && echo true || echo false)"
assert_eq "reset removes .sub_*.lock" "false" "$([ -d "$JB_DIR/usage_logs/.sub_dummy.lock" ] && echo true || echo false)"

# Uninstall tests
if bash "$REPO_DIR/uninstall.sh" --bogus 2>/dev/null; then
  echo "FAIL: uninstall --bogus should exit 1" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi
touch "$JB_DIR/.quota_cycles.tmp.999" "$JB_DIR/usage_logs/.sub_u1.json" "$JB_DIR/usage_logs/.sub_u1.ttl"
mkdir -p "$JB_DIR/usage_logs/.sub_u1.lock" "$JB_DIR/lib/__pycache__"
touch "$JB_DIR/lib/__pycache__/subagent_sync.cpython-314.pyc"
bash "$REPO_DIR/uninstall.sh" >/dev/null
assert_eq "uninstall removes lib/common.jq" "false" "$([ -f "$JB_DIR/lib/common.jq" ] && echo true || echo false)"
assert_eq "uninstall removes lib/auto_update.sh" "false" "$([ -f "$JB_DIR/lib/auto_update.sh" ] && echo true || echo false)"
assert_eq "uninstall removes lib/subagent_sync.py" "false" "$([ -f "$JB_DIR/lib/subagent_sync.py" ] && echo true || echo false)"
assert_eq "uninstall removes lib/__pycache__" "false" "$([ -d "$JB_DIR/lib/__pycache__" ] && echo true || echo false)"
assert_eq "uninstall removes lib directory" "false" "$([ -d "$JB_DIR/lib" ] && echo true || echo false)"
assert_eq "uninstall removes .sub_*.json" "false" "$([ -f "$JB_DIR/usage_logs/.sub_u1.json" ] && echo true || echo false)"
assert_eq "uninstall removes .sub_*.ttl" "false" "$([ -f "$JB_DIR/usage_logs/.sub_u1.ttl" ] && echo true || echo false)"
assert_eq "uninstall removes .sub_*.lock" "false" "$([ -d "$JB_DIR/usage_logs/.sub_u1.lock" ] && echo true || echo false)"
assert_eq "uninstall removes VERSION" "false" "$([ -f "$JB_DIR/VERSION" ] && echo true || echo false)"
assert_eq "uninstall removes .quota_cycles.tmp.*" "false" "$([ -f "$JB_DIR/.quota_cycles.tmp.999" ] && echo true || echo false)"
assert_eq "uninstall removes .prices_next_check" "false" "$([ -f "$JB_DIR/.prices_next_check" ] && echo true || echo false)"
assert_eq "uninstall removes .prices.etag" "false" "$([ -f "$JB_DIR/.prices.etag" ] && echo true || echo false)"
assert_eq "uninstall preserves usage_logs" "true" "$([ -d "$JB_DIR/usage_logs" ] && echo true || echo false)"
assert_eq "uninstall preserves quota_cycles.json" "true" "$([ -f "$JB_DIR/quota_cycles.json" ] && echo true || echo false)"

bash "$REPO_DIR/uninstall.sh" --purge >/dev/null
assert_eq "uninstall --purge removes JB_DIR" "false" "$([ -d "$JB_DIR" ] && echo true || echo false)"

# Cross-platform system bin symlink install/uninstall tests
SYS_TMP="$TMP_HOME/sys_bin_test"
SYS_LOCAL_BIN="$SYS_TMP/usr_local_bin"
SYS_BREW_BIN="$SYS_TMP/brew_bin"
mkdir -p "$SYS_LOCAL_BIN" "$SYS_BREW_BIN"

# Writable JENBACH_USR_LOCAL_BIN and JENBACH_BREW_BIN create symlinks
JENBACH_USR_LOCAL_BIN="$SYS_LOCAL_BIN" JENBACH_BREW_BIN="$SYS_BREW_BIN" "$REPO_DIR/install.sh" >/dev/null
assert_eq "install creates usr/local/bin symlink" "true" "$([ -L "$SYS_LOCAL_BIN/jenbach" ] && echo true || echo false)"
assert_eq "install usr/local/bin symlink target" "$JB_DIR/report.sh" "$(readlink "$SYS_LOCAL_BIN/jenbach")"
assert_eq "install creates brew bin symlink" "true" "$([ -L "$SYS_BREW_BIN/jenbach" ] && echo true || echo false)"
assert_eq "install brew bin symlink target" "$JB_DIR/report.sh" "$(readlink "$SYS_BREW_BIN/jenbach")"

# Uninstall removes dangling symlinks even after target report.sh is deleted
rm -f "$JB_DIR/report.sh"
JENBACH_USR_LOCAL_BIN="$SYS_LOCAL_BIN" JENBACH_BREW_BIN="$SYS_BREW_BIN" bash "$REPO_DIR/uninstall.sh" --purge >/dev/null
assert_eq "uninstall removes dangling usr/local/bin symlink" "false" "$([ -L "$SYS_LOCAL_BIN/jenbach" ] && echo true || echo false)"
assert_eq "uninstall removes dangling brew bin symlink" "false" "$([ -L "$SYS_BREW_BIN/jenbach" ] && echo true || echo false)"

# Uninstall preserves regular non-symlink files
printf '#!/usr/bin/env bash\necho keep\n' > "$SYS_LOCAL_BIN/jenbach"
printf '#!/usr/bin/env bash\necho keep\n' > "$SYS_BREW_BIN/jenbach"
JENBACH_USR_LOCAL_BIN="$SYS_LOCAL_BIN" JENBACH_BREW_BIN="$SYS_BREW_BIN" bash "$REPO_DIR/uninstall.sh" >/dev/null
assert_eq "uninstall preserves regular file in usr/local/bin" "true" "$([ -f "$SYS_LOCAL_BIN/jenbach" ] && [ ! -L "$SYS_LOCAL_BIN/jenbach" ] && echo true || echo false)"
assert_eq "uninstall preserves regular file in brew bin" "true" "$([ -f "$SYS_BREW_BIN/jenbach" ] && [ ! -L "$SYS_BREW_BIN/jenbach" ] && echo true || echo false)"
rm -f "$SYS_LOCAL_BIN/jenbach" "$SYS_BREW_BIN/jenbach"

# Missing and read-only (chmod 555) system bin dirs do not fail install.sh or uninstall.sh
chmod 555 "$SYS_BREW_BIN"
JENBACH_USR_LOCAL_BIN="$SYS_TMP/missing_bin" JENBACH_BREW_BIN="$SYS_BREW_BIN" "$REPO_DIR/install.sh" >/dev/null
assert_eq "install succeeds with missing/readonly sys bins" "true" "$([ -L "$HOME/.local/bin/jenbach" ] && echo true || echo false)"
assert_eq "readonly brew bin has no symlink" "false" "$([ -L "$SYS_BREW_BIN/jenbach" ] && echo true || echo false)"
assert_eq "missing usr/local/bin not created" "false" "$([ -d "$SYS_TMP/missing_bin" ] && echo true || echo false)"

chmod 755 "$SYS_BREW_BIN"
ln -sf "$JB_DIR/report.sh" "$SYS_BREW_BIN/jenbach"
chmod 555 "$SYS_BREW_BIN"
JENBACH_USR_LOCAL_BIN="$SYS_TMP/missing_bin" JENBACH_BREW_BIN="$SYS_BREW_BIN" bash "$REPO_DIR/uninstall.sh" --purge >/dev/null
assert_eq "uninstall skips readonly brew bin symlink safely" "true" "$([ -L "$SYS_BREW_BIN/jenbach" ] && echo true || echo false)"
chmod 755 "$SYS_BREW_BIN"
rm -rf "$SYS_TMP"

echo "Tests finished: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
