#!/usr/bin/env bash
AGY_DIR="$HOME/.gemini/antigravity-cli"
JB_DIR="$AGY_DIR/jenbach"
LOG_DIR="$JB_DIR/usage_logs"
CFG_FILE="$JB_DIR/report_config.json"
PRICES_FILE="$JB_DIR/prices.json"
QUOTA_FILE="$JB_DIR/quota_cycles.json"
LIB_DIR="$JB_DIR/lib"; [ -f "$LIB_DIR/common.jq" ] || LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
VER_FILE="$JB_DIR/VERSION"; [ -f "$VER_FILE" ] || VER_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/VERSION"
IS_TTY="false"; [ -t 1 ] && IS_TTY="true"

detect_term_size() {
  local r="${JENBACH_HEIGHT:-${LINES:-}}"
  local c="${JENBACH_WIDTH:-${COLUMNS:-}}"
  [[ "$r" =~ ^[0-9]+$ ]] && r=$((10#$r))
  [[ "$c" =~ ^[0-9]+$ ]] && c=$((10#$c))
  if ! [[ "$r" =~ ^[0-9]+$ ]] || ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 40 ]; then
    local stty_out
    stty_out=$(stty size </dev/tty 2>/dev/null || true)
    if [[ "$stty_out" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
      local _st_r="${BASH_REMATCH[1]}" _st_c="${BASH_REMATCH[2]}"
      [[ "$r" =~ ^[0-9]+$ ]] || r=$((10#$_st_r))
      { [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 40 ]; } || c=$((10#$_st_c))
    fi
  fi
  if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 40 ]; then
    c=$(tput cols 2>/dev/null || true)
    [[ "$c" =~ ^[0-9]+$ ]] && c=$((10#$c))
  fi
  if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 40 ]; then
    c=115
  fi
  if ! [[ "$r" =~ ^[0-9]+$ ]]; then
    r=$(tput lines 2>/dev/null || true)
    [[ "$r" =~ ^[0-9]+$ ]] && r=$((10#$r))
  fi
  [[ "$r" =~ ^[0-9]+$ ]] || r=0
  TERM_ROWS="$r"
  TERM_COLS="$c"
}
detect_term_size

mkdir -p "$JB_DIR"

if [ ! -f "$CFG_FILE" ] || ! jq -e 'type == "object"' "$CFG_FILE" >/dev/null 2>&1; then
  cat << 'JSON' > "${CFG_FILE}.tmp.$$" && mv "${CFG_FILE}.tmp.$$" "$CFG_FILE"
{
  "short_tokens": true,
  "statusline_short_tokens": true,
  "show_history": true,
  "history_limit": 20,
  "auto_fit_height": true,
  "chain_enabled": true,
  "chained_command": "",
  "theme": "modern",
  "color": "auto",
  "auto_update_prices": true,
  "price_check_interval_hours": 24,
  "prices_url": "https://raw.githubusercontent.com/utariddev/jenbach/main/prices.json",
  "check_app_updates": true,
  "app_repo_url": "https://github.com/utariddev/jenbach",
  "default_view": "cycle",
  "subagent_cost_mode": "split",
  "statusline_subagent_detail": true
}
JSON
fi

case "${1:-}" in
  update|update-prices|-v|--version|help|-h|--help) ;;
  *)
    if ! { [ "${1:-}" = "set" ] && [ "${2:-}" = "auto-update" ]; }; then
      [ -r "$LIB_DIR/auto_update.sh" ] && . "$LIB_DIR/auto_update.sh" && jenbach_maybe_update_prices "$JB_DIR" "$CFG_FILE" "$PRICES_FILE"
    fi
    if ! { [ "${1:-}" = "set" ] && { [ "${2:-}" = "auto-update" ] || [ "${2:-}" = "check-updates" ]; }; }; then
      [ -r "$LIB_DIR/app_update.sh" ] && . "$LIB_DIR/app_update.sh" && jenbach_maybe_check_app_update "$JB_DIR" "$CFG_FILE"
    fi
    ;;
esac

write_cfg() {
  local content="$1"
  local tmp_file="${CFG_FILE}.tmp.$$"
  printf '%s\n' "$content" > "$tmp_file" && mv "$tmp_file" "$CFG_FILE"
}

read_version() {
  local v=""
  if [ -r "$VER_FILE" ]; then
    v=$(tr -d '[:space:]' < "$VER_FILE")
  fi
  [ -n "$v" ] || v="unknown"
  printf '%s' "$v"
}

get_app_update_ver() {
  local local_ver="$1"
  local latest_ver=""
  [ -r "$JB_DIR/.latest_version" ] && latest_ver=$(tr -d '[:space:]' < "$JB_DIR/.latest_version")
  if [[ "$local_ver" =~ ^[1-9][0-9]*$ ]] && [[ "$latest_ver" =~ ^[1-9][0-9]*$ ]] && (( 10#$latest_ver > 10#$local_ver )); then
    printf '%s' "$latest_ver"
  fi
}

validate_ymd() {
  local d="$1"
  [[ "$d" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
  jq -en --arg d "$d" '(try (($d | strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) == $d) catch false)' >/dev/null 2>&1
}

show_help() {
  cat << 'EOF'
Usage: jenbach [command|filter] [options]

Filters & Views:
  (no args)                      Show report using default_view (cycle or all)
  cycle [gemini|argon|3p]        Show current weekly quota cycle (all or specific bucket)
  cycles                         Show tracked weekly quota buckets and detected resets
  all                            Show all recorded sessions
  today                          Show sessions from today
  week                           Show sessions from the last 7 days
  --month YYYY-MM                Show sessions from a specific month
  --from YYYY-MM-DD [--to ...]   Show sessions within a date range
  -n <N>, --limit <N>            Show at most N recent sessions (disables auto-fit)

Commands:
  info                           Show version, paths, pricing status, and environment
  -v, --version                  Show version number
  config, -c, --config           Interactive settings menu (or print current settings)
  set short [on|off]             Toggle short token format in report
  set status-short [on|off]      Toggle short token format in statusline
  set history [on|off]           Toggle session history table
  set limit <N>                  Set session history row limit (N >= 1)
  set chain [on|off|clear]       Enable, disable, or clear chained statusline command
  set theme [modern|compact|plain]  Set UI theme
  set color [auto|on|off]        Set ANSI color mode
  set auto-update [on|off]       Toggle automatic background price checks
  set check-interval <1..720>    Set price check interval in hours
  set check-updates [on|off]     Toggle automatic background app update checks
  set default-view [cycle|all]   Set default report view
  set subagent-mode [split|combined]  Set subagent report display mode
  set status-sub [on|off]        Toggle subagent detail in statusline
  set auto-fit [on|off]          Toggle terminal height auto-fit for session history
  prices                         Show model pricing table
  update [--force]               Update Jenbach to latest GitHub release
  update-prices [url]            Fetch latest prices.json
  reset                          Clear all recorded session logs
  help, -h, --help               Show this help message
EOF
}

show_current_settings() {
  jq -L "$LIB_DIR" -r --arg is_tty "$IS_TTY" --arg no_color "${NO_COLOR:-}" '
    include "common";
    (.theme // "modern") as $theme |
    ($theme == "plain") as $plain |
    (.color // "auto") as $color_mode |
    (.default_view // "cycle") as $def_view |
    (.subagent_cost_mode // "split") as $sub_mode |
    (if ($plain or $color_mode == "off" or $no_color != "") then false elif $color_mode == "on" then true else ($is_tty == "true") end) as $use_color |
    def badge($on):
      if $plain then (if $on then "ON" else "OFF" end)
      elif $on then paint("● ON"; "green"; $use_color)
      else paint("○ OFF"; "dim"; $use_color) end;
    (if $plain then "======================================================" else paint("──────────────────────────────────────────────────────"; "dim"; $use_color) end),
    (if $plain then "              JENBACH SETTINGS" else paint("  JENBACH SETTINGS"; "bold_cyan"; $use_color) end),
    (if $plain then "======================================================" else paint("──────────────────────────────────────────────────────"; "dim"; $use_color) end),
    "[1] Short Token Format (1736 -> 1.7k) : " + badge(.short_tokens != false),
    "[2] Statusline Short Tokens           : " + badge(.statusline_short_tokens != false),
    "[3] Show Session History Table        : " + badge(.show_history != false),
    "[4] Session History Row Limit         : " + paint(((.history_limit // 20) | tostring); "bold_white"; $use_color),
    "[5] Chained Statusline                : " + badge(.chain_enabled != false) + (if (.chained_command // "") != "" then " (" + .chained_command + ")" else " (none)" end),
    "[6] UI Theme                          : " + paint($theme; "bold_cyan"; $use_color),
    "[7] Color Mode                        : " + paint($color_mode; "bold_cyan"; $use_color),
    "[8] Auto-Update Prices                : " + badge(.auto_update_prices != false),
    "[9] Price Check Interval (Hours)      : " + paint(((.price_check_interval_hours // 24) | tostring); "bold_white"; $use_color),
    "[10] Default Report View              : " + paint($def_view; "bold_cyan"; $use_color),
    "[11] Subagent Report Mode             : " + paint($sub_mode; "bold_cyan"; $use_color),
    "[12] Statusline Subagent Detail       : " + badge(.statusline_subagent_detail != false),
    "[13] Auto-Fit Terminal Height         : " + badge(.auto_fit_height != false),
    "[14] Check App Updates                : " + badge(.check_app_updates != false),
    "[15] Reset / Clear All Session Logs",
    (if $plain then "======================================================" else paint("──────────────────────────────────────────────────────"; "dim"; $use_color) end)
  ' "$CFG_FILE"
}

cycle_default_view() {
  local tmp
  tmp=$(jq '.default_view = (if (.default_view // "cycle") == "cycle" then "all" else "cycle" end)' "$CFG_FILE") && write_cfg "$tmp"
}

cycle_subagent_mode() {
  local tmp
  tmp=$(jq '.subagent_cost_mode = (if (.subagent_cost_mode // "split") == "split" then "combined" else "split" end)' "$CFG_FILE") && write_cfg "$tmp"
}

cycle_theme() {
  local tmp
  tmp=$(jq '.theme = (if (.theme // "modern") == "modern" then "compact" elif .theme == "compact" then "plain" else "modern" end)' "$CFG_FILE") && write_cfg "$tmp"
}

cycle_color() {
  local tmp
  tmp=$(jq '.color = (if (.color // "auto") == "auto" then "on" elif .color == "on" then "off" else "auto" end)' "$CFG_FILE") && write_cfg "$tmp"
}

toggle_bool() {
  local key="$1"
  local tmp
  tmp=$(jq ".$key = ((if .$key == null then true else .$key end) | not)" "$CFG_FILE") && write_cfg "$tmp"
}

set_bool() {
  local key="$1"
  local val="$2"
  local b=""
  case "$val" in
    on|true|1) b="true" ;;
    off|false|0) b="false" ;;
    *)
      echo "Error: Invalid boolean value '$val'. Use 'on' or 'off'." >&2
      exit 1
      ;;
  esac
  local tmp
  tmp=$(jq ".$key = $b" "$CFG_FILE") && write_cfg "$tmp"
}

# CLI Parameter Handling (Works inside !jenbach and terminal)
FILTER_MODE=""
CYCLE_BUCKET=""
FILTER_MONTH=""
FILTER_FROM=""
FILTER_TO=""
EXPLICIT_LIMIT=0

case "${1:-}" in
  help|-h|--help)
    show_help
    exit 0
    ;;
  -v|--version)
    _v=$(read_version)
    if [[ "$_v" =~ ^[0-9] ]]; then
      echo "jenbach v${_v}"
    else
      echo "jenbach ${_v}"
    fi
    exit 0
    ;;
  info)
    VER=$(read_version)
    APP_UPDATE_VER=$(get_app_update_ver "$VER")
    CFG_JSON=$(jq -c '.' "$CFG_FILE" 2>/dev/null)
    [ -z "$CFG_JSON" ] && CFG_JSON='{"theme":"modern","color":"auto","default_view":"cycle"}'
    PRICES_UPD="missing"
    if [ -f "$PRICES_FILE" ]; then
      PRICES_UPD=$(jq -r '.updated_at // "N/A"' "$PRICES_FILE" 2>/dev/null || echo "invalid")
    fi
    SESS_COUNT=0
    if [ -d "$LOG_DIR" ]; then
      shopt -s nullglob
      _info_files=("$LOG_DIR"/*.json)
      SESS_COUNT=${#_info_files[@]}
      shopt -u nullglob
    fi
    JQ_VER=$(jq --version 2>/dev/null || echo "missing")
    if command -v python3 >/dev/null 2>&1; then
      PY_VER=$(python3 --version 2>/dev/null | awk '{print $1" "$2}')
    else
      PY_VER="not found"
    fi
    if command -v curl >/dev/null 2>&1; then
      CURL_VER=$(curl --version 2>/dev/null | head -n 1 | awk '{print $1" "$2}')
    else
      CURL_VER="not found"
    fi
    jq -L "$LIB_DIR" -rn \
      --argjson cfg "$CFG_JSON" \
      --arg is_tty "$IS_TTY" \
      --arg no_color "${NO_COLOR:-}" \
      --arg ver "$VER" \
      --arg app_update_ver "$APP_UPDATE_VER" \
      --arg jb_dir "$JB_DIR" \
      --arg cfg_file "$CFG_FILE" \
      --arg prices_upd "$PRICES_UPD" \
      --arg sess_count "$SESS_COUNT" \
      --arg jq_ver "$JQ_VER" \
      --arg py_ver "$PY_VER" \
      --arg curl_ver "$CURL_VER" '
      include "common";
      ($cfg.theme // "modern") as $theme |
      ($theme == "plain") as $plain |
      ($cfg.color // "auto") as $color_mode |
      ($cfg.default_view // "cycle") as $def_view |
      ($cfg.subagent_cost_mode // "split") as $sub_mode |
      (if ($cfg.statusline_subagent_detail == false) then "off" else "on" end) as $status_sub |
      (if ($plain or $color_mode == "off" or $no_color != "") then false elif $color_mode == "on" then true else ($is_tty == "true") end) as $use_color |
      [
        [{t: "Version    : ", c: "bold"}, {t: $ver, c: "bold_cyan"}],
        (if ($cfg.check_app_updates != false and $app_update_ver != "") then
           [{t: "Update     : ", c: "bold"}, {t: "v\($ver) \(if $plain then "->" else "→" end) v\($app_update_ver) (run \u0027jenbach update\u0027)", c: "bold_cyan"}]
         else empty end),
        [{t: "GitHub     : ", c: "bold"}, {t: "https://github.com/utariddev/jenbach", c: "cyan"}],
        [{t: "Install Dir: ", c: "bold"}, {t: $jb_dir, c: ""}],
        [{t: "Config     : ", c: "bold"}, {t: $cfg_file, c: ""}],
        [{t: "Prices     : ", c: "bold"}, {t: "updated \($prices_upd)", c: (if $prices_upd == "missing" or $prices_upd == "invalid" then "red" else "green" end)}],
        [{t: "Sessions   : ", c: "bold"}, {t: "\($sess_count) recorded", c: "bold_white"}],
        [{t: "Settings   : ", c: "bold"}, {t: "theme=\($theme), color=\($color_mode), default_view=\($def_view), subagent_mode=\($sub_mode), status_sub=\($status_sub)", c: ""}],
        [{t: "Environment: ", c: "bold"}, {t: "jq=\($jq_ver), python3=\($py_ver), curl=\($curl_ver)", c: "dim"}]
      ] as $info_lines |
      (if $theme == "compact" then
        (
          ($info_lines[] | map(paint(.t; (.c // ""); $use_color)) | add),
          paint(repeat_str("─"; 74); "dim"; $use_color)
        )
       else
        render_kpi_box("Jenbach Info"; $info_lines; $plain; $use_color)
       end),
      "",
      paint("Named after the peaceful town of Jenbach."; "dim"; $use_color)
    '
    exit 0
    ;;
  cycles)
    if [ ! -f "$QUOTA_FILE" ] || ! jq -e '.buckets | type == "object" and (length > 0)' "$QUOTA_FILE" >/dev/null 2>&1; then
      echo "No weekly quota cycles tracked yet. Run statusline in agy to populate quota_cycles.json."
      exit 0
    fi
    CFG_JSON=$(jq -c '.' "$CFG_FILE" 2>/dev/null)
    [ -z "$CFG_JSON" ] && CFG_JSON='{"theme":"modern","color":"auto"}'
    CYCLES_OUT=$(jq -L "$LIB_DIR" -r --argjson cfg "$CFG_JSON" --arg is_tty "$IS_TTY" --arg no_color "${NO_COLOR:-}" '
      include "common";
      ($cfg.theme // "modern") as $theme |
      ($theme == "plain") as $plain |
      ($cfg.color // "auto") as $color_mode |
      (if ($plain or $color_mode == "off" or $no_color != "") then false elif $color_mode == "on" then true else ($is_tty == "true") end) as $use_color |
      def fmt_pct($f):
        if ($f | type) == "number" then "\((($f * 1000) | round) / 10)%" else "N/A" end;
      (.buckets | if type == "object" then . else {} end) as $raw_qbuckets |
      sanitize_quota_buckets($raw_qbuckets) as $qbuckets |
      (if $qbuckets != $raw_qbuckets then ({buckets: $qbuckets} | tojson) else "" end),
      paint("WEEKLY QUOTA CYCLES"; "bold_cyan"; $use_color),
      (
        [($qbuckets | to_entries | sort_by(.key)[]) |
          (.value.last_remaining) as $rem |
          (if (.value.cycle_started_at // "") == "" then "All recorded" else .value.cycle_started_at end) as $cs |
          fmt_iso_utc(.value.last_reset_time) as $rt |
          ((.value.resets // []) | length) as $rc |
          (if ($rem | type) != "number" then "dim" elif ($rem * 100) > 30 then "green" elif ($rem * 100) >= 15 then "bold" else "bold_red" end) as $rc_col |
          {
            sep_before: false,
            bold_row: false,
            cells: [
              {t: fmt_bucket_name(.key), c: "bold_white"},
              {t: fmt_pct($rem), c: $rc_col},
              {t: $cs, c: (if $cs == "All recorded" then "dim" else "" end)},
              {t: $rt, c: "dim"},
              {t: ($rc | tostring), c: ""}
            ]
          }
        ] as $brows |
        render_table(["Bucket", "Remaining", "Cycle Start", "Next Reset (UTC)", "Resets"]; ["l", "r", "l", "l", "r"]; $brows; $plain; $use_color)
      ),
      (
        [$qbuckets | to_entries[] | .key as $bk | (.value.resets // [])[] | . + {bucket: $bk}] |
        sort_by(.detected_at // "") | reverse | .[0:20]
      ) as $all_resets |
      if ($all_resets | length) > 0 then
        "",
        paint("RECENT DETECTED RESETS"; "bold_cyan"; $use_color),
        (
          [$all_resets[] |
            (if .reason == "reset_time_changed" then "Scheduled reset"
             elif .reason == "remaining_jump" then "Quota jump"
             else (.reason // "unknown") end) as $reason_lbl |
            {
              sep_before: false,
              bold_row: false,
              cells: [
                {t: (.detected_at // "N/A"), c: "dim"},
                {t: fmt_bucket_name(.bucket), c: "bold_white"},
                {t: $reason_lbl, c: ""},
                {t: fmt_pct(.prev_remaining), c: ""},
                {t: fmt_pct(.new_remaining), c: "green"},
                {t: fmt_iso_utc(.reset_time), c: "dim"}
              ]
            }
          ] as $rrows |
          render_table(["Detected At", "Bucket", "Reason", "Before", "After", "Next Reset (UTC)"]; ["l", "l", "l", "r", "r", "l"]; $rrows; $plain; $use_color)
        )
      else
        "",
        paint("No quota resets detected yet."; "dim"; $use_color)
      end
    ' "$QUOTA_FILE")
    SANITIZED_JSON="${CYCLES_OUT%%$'\n'*}"
    BODY="${CYCLES_OUT#*$'\n'}"
    if [ -n "$SANITIZED_JSON" ]; then
      TMP_Q="$JB_DIR/.quota_cycles.tmp.$$"
      printf '%s\n' "$SANITIZED_JSON" > "$TMP_Q" && mv -f "$TMP_Q" "$QUOTA_FILE"
    fi
    printf '%s\n' "$BODY"
    exit 0
    ;;
  set)
    case "${2:-}" in
      short)        set_bool "short_tokens" "${3:-}" ;;
      status-short) set_bool "statusline_short_tokens" "${3:-}" ;;
      history)      set_bool "show_history" "${3:-}" ;;
      limit)
        raw_lim="${3:-}"
        if [[ "$raw_lim" =~ ^[0-9]+$ ]]; then
          lim=$((10#$raw_lim))
          if [ "$lim" -ge 1 ]; then
            tmp=$(jq --argjson lim "$lim" '.history_limit = $lim' "$CFG_FILE") && write_cfg "$tmp"
          else
            echo "Error: Limit must be >= 1." >&2
            exit 1
          fi
        else
          echo "Error: Invalid limit '${raw_lim}'. Must be an integer >= 1." >&2
          exit 1
        fi
        ;;
      chain)
        case "${3:-}" in
          on|true|1)
            tmp=$(jq '.chain_enabled = true' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          off|false|0)
            tmp=$(jq '.chain_enabled = false' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          clear)
            tmp=$(jq '.chained_command = "" | .chain_enabled = false' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          *)
            echo "Usage: jenbach set chain [on|off|clear]" >&2
            exit 1
            ;;
        esac
        ;;
      theme)
        case "${3:-}" in
          modern|compact|plain)
            tmp=$(jq --arg v "${3}" '.theme = $v' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          *)
            echo "Error: Invalid theme '${3:-}'. Use 'modern', 'compact', or 'plain'." >&2
            exit 1
            ;;
        esac
        ;;
      color)
        case "${3:-}" in
          auto|on|off)
            tmp=$(jq --arg v "${3}" '.color = $v' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          *)
            echo "Error: Invalid color mode '${3:-}'. Use 'auto', 'on', or 'off'." >&2
            exit 1
            ;;
        esac
        ;;
      auto-update)
        set_bool "auto_update_prices" "${3:-}"
        case "${3:-}" in
          on|true|1) rm -f "$JB_DIR/.prices_next_check" ;;
        esac
        ;;
      check-interval)
        raw_iv="${3:-}"
        if [[ "$raw_iv" =~ ^[0-9]+$ ]]; then
          iv=$((10#$raw_iv))
          if [ "$iv" -ge 1 ] && [ "$iv" -le 720 ]; then
            tmp=$(jq --argjson iv "$iv" '.price_check_interval_hours = $iv' "$CFG_FILE") && write_cfg "$tmp"
            rm -f "$JB_DIR/.prices_next_check"
          else
            echo "Error: Check interval must be between 1 and 720 hours." >&2
            exit 1
          fi
        else
          echo "Error: Invalid check interval '${raw_iv}'. Must be an integer between 1 and 720." >&2
          exit 1
        fi
        ;;
      check-updates)
        set_bool "check_app_updates" "${3:-}"
        case "${3:-}" in
          on|true|1) rm -f "$JB_DIR/.app_update_next_check" ;;
        esac
        ;;
      default-view)
        case "${3:-}" in
          cycle|all)
            tmp=$(jq --arg v "${3}" '.default_view = $v' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          *)
            echo "Error: Invalid default view '${3:-}'. Use 'cycle' or 'all'." >&2
            exit 1
            ;;
        esac
        ;;
      subagent-mode)
        case "${3:-}" in
          split|combined)
            tmp=$(jq --arg v "${3}" '.subagent_cost_mode = $v' "$CFG_FILE") && write_cfg "$tmp"
            ;;
          *)
            echo "Error: Invalid subagent mode '${3:-}'. Use 'split' or 'combined'." >&2
            exit 1
            ;;
        esac
        ;;
      status-sub) set_bool "statusline_subagent_detail" "${3:-}" ;;
      auto-fit)   set_bool "auto_fit_height" "${3:-}" ;;
      *)
        echo "Usage: jenbach set [short|status-short|history|limit|chain|theme|color|auto-update|check-interval|check-updates|default-view|subagent-mode|status-sub|auto-fit] [value]" >&2
        exit 1
        ;;
    esac
    show_current_settings
    exit 0
    ;;
  prices)
    if [ ! -f "$PRICES_FILE" ] || ! jq -e '.models | type == "object"' "$PRICES_FILE" >/dev/null 2>&1; then
      echo "Error: Valid prices.json not found at $PRICES_FILE" >&2
      exit 1
    fi
    CFG_JSON=$(jq -c '.' "$CFG_FILE" 2>/dev/null)
    [ -z "$CFG_JSON" ] && CFG_JSON='{"theme":"modern","color":"auto"}'
    jq -L "$LIB_DIR" -r --argjson cfg "$CFG_JSON" --arg is_tty "$IS_TTY" --arg no_color "${NO_COLOR:-}" '
      include "common";
      ($cfg.theme // "modern") as $theme |
      ($theme == "plain") as $plain |
      ($cfg.color // "auto") as $color_mode |
      (if ($plain or $color_mode == "off" or $no_color != "") then false elif $color_mode == "on" then true else ($is_tty == "true") end) as $use_color |
      ("MODEL PRICING PER 1M TOKENS (Updated: \(.updated_at // "N/A"))") as $hdr |
      (if $plain then "======================================================================" else "" end),
      paint($hdr; "bold_cyan"; $use_color),
      (if $plain then "======================================================================" else "" end),
      (
        [.models | to_entries[] |
          (.value.note // "") as $note |
          (if ($note | contains("Promo")) then "bold" else "dim" end) as $note_c |
          {
            sep_before: false,
            bold_row: false,
            cells: [
              {t: .key, c: "bold_white"},
              {t: fmt_usd3(.value["in"] // 0), c: ""},
              {t: fmt_usd3(.value.cached // 0), c: ""},
              {t: fmt_usd3(.value.out // 0), c: ""},
              {t: $note, c: $note_c}
            ]
          }
        ] as $rows |
        render_table(["Model Key", "Input / 1M", "Cached / 1M", "Output / 1M", "Notes"]; ["l", "r", "r", "r", "l"]; $rows; $plain; $use_color)
      )
    ' "$PRICES_FILE"
    exit 0
    ;;
  update)
    if [ $# -gt 2 ] || { [ $# -eq 2 ] && [ "${2:-}" != "--force" ]; }; then
      echo "Usage: jenbach update [--force]" >&2
      exit 1
    fi
    if [ ! -r "$LIB_DIR/app_update.sh" ]; then
      echo "Error: $LIB_DIR/app_update.sh not found." >&2
      exit 1
    fi
    . "$LIB_DIR/app_update.sh"
    jenbach_run_app_update "$JB_DIR" "$CFG_FILE" "$(read_version)" "${2:-}"; exit $?
    ;;
  update-prices)
    CFG_URL=$(jq -r '.prices_url // ""' "$CFG_FILE" 2>/dev/null || true)
    [ -z "$CFG_URL" ] && CFG_URL="https://raw.githubusercontent.com/utariddev/jenbach/main/prices.json"
    REPO_URL="${2:-$CFG_URL}"
    TMP_PRICES="${PRICES_FILE}.tmp.$$"
    if curl -fsSL --max-time 20 "$REPO_URL" -o "$TMP_PRICES" && jq -e '
      (.models | type == "object") and
      (.models.default | type == "object") and
      ([.models[] | (
        (.["in"] | type == "number") and .["in"] > 0 and .["in"] < 500 and
        (.cached | type == "number") and .cached >= 0 and .cached <= .["in"] and
        (.out | type == "number") and .out > 0 and .out < 1000
      )] | all)
    ' "$TMP_PRICES" >/dev/null 2>&1; then
      mv "$TMP_PRICES" "$PRICES_FILE"
      rm -f "$JB_DIR/.prices.etag"
      _upd_iv=$(jq -r '(.price_check_interval_hours // 24) | tonumber? // 24 | floor | if . < 1 then 1 elif . > 720 then 720 else . end' "$CFG_FILE" 2>/dev/null || echo 24)
      printf -v _upd_now '%(%s)T' -1 2>/dev/null || true
      [[ "$_upd_now" =~ ^[0-9]+$ ]] || _upd_now=$(date +%s 2>/dev/null || echo 0)
      printf '%s\n' "$((_upd_now + _upd_iv * 3600))" > "${JB_DIR}/.prices_next_check.tmp.$$" && mv -f "${JB_DIR}/.prices_next_check.tmp.$$" "${JB_DIR}/.prices_next_check"
      echo "Prices updated successfully to version: $(jq -r '.updated_at // "N/A"' "$PRICES_FILE")"
    else
      rm -f "$TMP_PRICES"
      echo "Error: Failed to fetch valid prices.json from $REPO_URL" >&2
      exit 1
    fi
    exit 0
    ;;
  reset)
    rm -f "$LOG_DIR"/*.json "$LOG_DIR"/.*.tmp.* "$LOG_DIR"/.sub_*.json "$LOG_DIR"/.sub_*.ttl 2>/dev/null
    rm -rf "$LOG_DIR"/.sub_*.lock 2>/dev/null
    echo "All recorded session logs have been cleared."
    exit 0
    ;;
  config|-c|--config)
    if [ -t 0 ] && [ -t 1 ]; then
      while true; do
        clear 2>/dev/null || true
        show_current_settings
        echo "[q] Save & Exit"
        echo "------------------------------------------------------"
        read -r -p "Select option [1-15, q]: " choice
        case "$choice" in
          1) toggle_bool "short_tokens" ;;
          2) toggle_bool "statusline_short_tokens" ;;
          3) toggle_bool "show_history" ;;
          4)
            read -r -p "Enter new history limit (e.g. 10, 20, 50): " raw_lim
            if [[ "$raw_lim" =~ ^[0-9]+$ ]]; then
              lim=$((10#$raw_lim))
              if [ "$lim" -ge 1 ]; then
                tmp=$(jq --argjson lim "$lim" '.history_limit = $lim' "$CFG_FILE") && write_cfg "$tmp"
              fi
            fi
            ;;
          5) toggle_bool "chain_enabled" ;;
          6) cycle_theme ;;
          7) cycle_color ;;
          8)
            toggle_bool "auto_update_prices"
            if [ "$(jq -r '.auto_update_prices != false' "$CFG_FILE" 2>/dev/null)" = "true" ]; then
              rm -f "$JB_DIR/.prices_next_check"
            fi
            ;;
          9)
            read -r -p "Enter price check interval in hours (1-720): " raw_iv
            if [[ "$raw_iv" =~ ^[0-9]+$ ]]; then
              iv=$((10#$raw_iv))
              if [ "$iv" -ge 1 ] && [ "$iv" -le 720 ]; then
                tmp=$(jq --argjson iv "$iv" '.price_check_interval_hours = $iv' "$CFG_FILE") && write_cfg "$tmp"
                rm -f "$JB_DIR/.prices_next_check"
              fi
            fi
            ;;
          10) cycle_default_view ;;
          11) cycle_subagent_mode ;;
          12) toggle_bool "statusline_subagent_detail" ;;
          13) toggle_bool "auto_fit_height" ;;
          14)
            toggle_bool "check_app_updates"
            if [ "$(jq -r '.check_app_updates != false' "$CFG_FILE" 2>/dev/null)" = "true" ]; then
              rm -f "$JB_DIR/.app_update_next_check"
            fi
            ;;
          15)
            read -r -p "Are you sure you want to delete all logs? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
              rm -f "$LOG_DIR"/*.json "$LOG_DIR"/.*.tmp.* "$LOG_DIR"/.sub_*.json "$LOG_DIR"/.sub_*.ttl 2>/dev/null
              rm -rf "$LOG_DIR"/.sub_*.lock 2>/dev/null
              echo "Logs cleared. Press Enter..."
              read -r
            fi
            ;;
          q|Q|"") break ;;
        esac
      done
    else
      show_current_settings
      echo ""
      echo "Quick commands inside agy (!jenbach):"
      echo "  !jenbach set short [on|off]"
      echo "  !jenbach set status-short [on|off]"
      echo "  !jenbach set history [on|off]"
      echo "  !jenbach set limit <number>"
      echo "  !jenbach set chain [on|off|clear]"
      echo "  !jenbach set theme [modern|compact|plain]"
      echo "  !jenbach set color [auto|on|off]"
      echo "  !jenbach set auto-update [on|off]"
      echo "  !jenbach set check-interval <hours>"
      echo "  !jenbach set check-updates [on|off]"
      echo "  !jenbach set default-view [cycle|all]"
      echo "  !jenbach set subagent-mode [split|combined]"
      echo "  !jenbach set status-sub [on|off]"
      echo "  !jenbach set auto-fit [on|off]"
      echo "  !jenbach update [--force]"
      echo "  !jenbach reset"
    fi
    exit 0
    ;;
  *)
    while [ $# -gt 0 ]; do
      case "$1" in
        all|today|week)
          if [ -n "$FILTER_MODE" ]; then
            echo "Error: Conflicting filter option '$1'." >&2
            exit 1
          fi
          FILTER_MODE="$1"
          shift
          ;;
        cycle)
          if [ -n "$FILTER_MODE" ]; then
            echo "Error: Conflicting filter option '$1'." >&2
            exit 1
          fi
          FILTER_MODE="cycle"
          shift
          if [ $# -gt 0 ]; then
            case "$1" in
              gemini) CYCLE_BUCKET="gemini-weekly"; shift ;;
              argon)  CYCLE_BUCKET="gemini-argon-wtu-weekly"; shift ;;
              3p)     CYCLE_BUCKET="3p-weekly"; shift ;;
              -*)     ;;
              *)
                echo "Error: Invalid cycle bucket '$1'. Use 'gemini', 'argon', or '3p'." >&2
                exit 1
                ;;
            esac
          fi
          ;;
        --month)
          if [ -n "$FILTER_MODE" ]; then
            echo "Error: Conflicting filter option '$1'." >&2
            exit 1
          fi
          if [ $# -lt 2 ] || ! [[ "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
            echo "Error: --month requires YYYY-MM format." >&2
            exit 1
          fi
          FILTER_MODE="month"
          FILTER_MONTH="$2"
          shift 2
          ;;
        --from)
          if [ -n "$FILTER_MODE" ] && [ "$FILTER_MODE" != "range" ]; then
            echo "Error: Conflicting filter option '$1'." >&2
            exit 1
          fi
          if [ -n "$FILTER_FROM" ]; then
            echo "Error: Duplicate --from option." >&2
            exit 1
          fi
          if [ $# -lt 2 ] || ! validate_ymd "$2"; then
            echo "Error: --from requires a valid YYYY-MM-DD date." >&2
            exit 1
          fi
          FILTER_MODE="range"
          FILTER_FROM="$2"
          shift 2
          ;;
        --to)
          if [ -n "$FILTER_MODE" ] && [ "$FILTER_MODE" != "range" ]; then
            echo "Error: Conflicting filter option '$1'." >&2
            exit 1
          fi
          if [ -n "$FILTER_TO" ]; then
            echo "Error: Duplicate --to option." >&2
            exit 1
          fi
          if [ $# -lt 2 ] || ! validate_ymd "$2"; then
            echo "Error: --to requires a valid YYYY-MM-DD date." >&2
            exit 1
          fi
          FILTER_MODE="range"
          FILTER_TO="$2"
          shift 2
          ;;
        -n|--limit)
          if [ "$EXPLICIT_LIMIT" -gt 0 ]; then
            echo "Error: Duplicate $1 option." >&2
            exit 1
          fi
          if [ $# -lt 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$((10#$2))" -lt 1 ]; then
            echo "Error: $1 requires an integer >= 1." >&2
            exit 1
          fi
          EXPLICIT_LIMIT=$((10#$2))
          shift 2
          ;;
        *)
          echo "Error: Unknown command '${1}'." >&2
          show_help >&2
          exit 1
          ;;
      esac
    done
    ;;
esac

if [ "$FILTER_MODE" = "range" ] && [ -n "$FILTER_FROM" ] && [ -n "$FILTER_TO" ] && [[ "$FILTER_FROM" > "$FILTER_TO" ]]; then
  echo "Error: --from date ($FILTER_FROM) cannot be after --to date ($FILTER_TO)." >&2
  exit 1
fi

if [ ! -d "$LOG_DIR" ]; then
  echo "No recorded sessions found yet in $LOG_DIR"
  exit 0
fi

shopt -s nullglob
LOG_FILES=()
for f in "$LOG_DIR"/*.json; do
  if jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    LOG_FILES+=("$f")
  fi
done

if [ ${#LOG_FILES[@]} -eq 0 ]; then
  echo "No recorded sessions found yet in $LOG_DIR"
  exit 0
fi

CFG_JSON=$(jq -c '.' "$CFG_FILE" 2>/dev/null)
[ -z "$CFG_JSON" ] && CFG_JSON='{"short_tokens":true,"show_history":true,"history_limit":20,"auto_fit_height":true,"theme":"modern","color":"auto","check_app_updates":true,"app_repo_url":"https://github.com/utariddev/jenbach","default_view":"cycle","subagent_cost_mode":"split","statusline_subagent_detail":true}'
LOCAL_VER=$(read_version)
APP_UPDATE_VER=$(get_app_update_ver "$LOCAL_VER")

if [ -z "$FILTER_MODE" ]; then
  FILTER_MODE=$(printf '%s' "$CFG_JSON" | jq -r 'if (.default_view // "cycle") == "all" then "all" else "cycle" end')
fi

QUOTA_RAW=""; [ -r "$QUOTA_FILE" ] && QUOTA_RAW=$(< "$QUOTA_FILE")
PRICES_RAW=""; [ -r "$PRICES_FILE" ] && PRICES_RAW=$(< "$PRICES_FILE")
printf -v TODAY_YMD '%(%Y-%m-%d)T' -1 2>/dev/null || true
[[ "$TODAY_YMD" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || TODAY_YMD=$(date +"%Y-%m-%d")
printf -v NOW_STR '%(%Y-%m-%d %H:%M)T' -1 2>/dev/null || true
[[ "$NOW_STR" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]] || NOW_STR=$(date +"%Y-%m-%d %H:%M")

HAS_PY3=false
if command -v python3 >/dev/null 2>&1 && [ -r "$LIB_DIR/subagent_sync.py" ]; then
  HAS_PY3=true
fi

SIDECAR_FILES=()
TRANSCRIPT_FILES=()
for f in "${LOG_FILES[@]}"; do
  _t_sid="${f##*/}"
  _t_sid="${_t_sid%.json}"
  _t_path="$AGY_DIR/brain/${_t_sid}/.system_generated/logs/transcript.jsonl"
  if [ -s "$_t_path" ] && [ -r "$_t_path" ]; then
    if [ ! "$f" -nt "$_t_path" ] || ! grep -q '"user_prompts"[[:space:]]*:[[:space:]]*[1-9]' "$f" 2>/dev/null; then
      TRANSCRIPT_FILES+=("$_t_path")
    fi
  fi
  if grep -q '"has_subagents"[[:space:]]*:[[:space:]]*true' "$f" 2>/dev/null; then
    _r_sid="${f##*/}"
    _r_sid="${_r_sid%.json}"
    _r_sidecar="$LOG_DIR/.sub_${_r_sid}.json"
    if [ "$HAS_PY3" = true ]; then
      _r_stale=false
      if [ ! -r "$_r_sidecar" ]; then
        _r_stale=true
      else
        for _sj in "$AGY_DIR/brain/${_r_sid}/.system_generated/subagents"/*.json; do
          [ -e "$_sj" ] || continue
          if [ "$_sj" -nt "$_r_sidecar" ]; then
            _r_stale=true
            break
          fi
          _sub_id="${_sj##*/}"
          _sub_id="${_sub_id%.json}"
          if [ "$AGY_DIR/conversations/${_sub_id}.db" -nt "$_r_sidecar" ] || [ "$AGY_DIR/conversations/${_sub_id}.db-wal" -nt "$_r_sidecar" ]; then
            _r_stale=true
            break
          fi
          for _nsj in "$AGY_DIR/brain/${_sub_id}/.system_generated/subagents"/*.json; do
            [ -e "$_nsj" ] || continue
            if [ "$_nsj" -nt "$_r_sidecar" ]; then
              _r_stale=true
              break 2
            fi
          done
        done
        if [ "$_r_stale" = false ]; then
          while IFS= read -r _rec_sid; do
            [ -n "$_rec_sid" ] || continue
            if [ "$AGY_DIR/conversations/${_rec_sid}.db" -nt "$_r_sidecar" ] || [ "$AGY_DIR/conversations/${_rec_sid}.db-wal" -nt "$_r_sidecar" ]; then
              _r_stale=true
              break
            fi
            for _nsj in "$AGY_DIR/brain/${_rec_sid}/.system_generated/subagents"/*.json; do
              [ -e "$_nsj" ] || continue
              if [ "$_nsj" -nt "$_r_sidecar" ]; then
                _r_stale=true
                break 2
              fi
            done
          done < <(jq -r '.records[]?.session_id // empty' "$_r_sidecar" 2>/dev/null | sort -u)
        fi
      fi
      if [ "$_r_stale" = true ]; then
        python3 "$LIB_DIR/subagent_sync.py" \
          --sid "$_r_sid" \
          --brain-dir "$AGY_DIR/brain" \
          --conv-dir "$AGY_DIR/conversations" \
          --prices "$PRICES_FILE" \
          --out "$_r_sidecar" \
          --now "$NOW_STR" >/dev/null 2>&1 || true
      fi
    fi
    if [ -r "$_r_sidecar" ]; then
      SIDECAR_FILES+=("$_r_sidecar")
    fi
  fi
done

TMP_SIDECAR_MAP="$JB_DIR/.sidecars.tmp.$$"
TMP_PROMPT_MAP="$JB_DIR/.prompts.tmp.$$"
trap 'rm -f "$TMP_SIDECAR_MAP" "$TMP_PROMPT_MAP" 2>/dev/null || true' EXIT
if [ ${#SIDECAR_FILES[@]} -gt 0 ]; then
  {
    for _sc in "${SIDECAR_FILES[@]}"; do
      jq -c 'select(type == "object" and (.sid | type) == "string")' "$_sc" 2>/dev/null || true
    done
  } | jq -s 'INDEX(.[]; .sid)' > "$TMP_SIDECAR_MAP" 2>/dev/null || printf '{}\n' > "$TMP_SIDECAR_MAP"
else
  printf '{}\n' > "$TMP_SIDECAR_MAP"
fi

if [ ${#TRANSCRIPT_FILES[@]} -gt 0 ]; then
  _pt_jq='
    reduce inputs as $l ({};
      input_filename as $fn |
      ($l | try fromjson catch null) as $o |
      if ($o | type) == "object" and $o.type == "USER_INPUT" then
        ($fn | sub("^.*?/brain/"; "") | sub("/\\.system_generated/logs/transcript\\.jsonl$"; "")) as $sid |
        .[$sid] = ((.[$sid] // 0) + 1)
      else . end
    )
  '
  if ! jq -Rn "$_pt_jq" -- "${TRANSCRIPT_FILES[@]}" > "$TMP_PROMPT_MAP" 2>/dev/null || [ ! -s "$TMP_PROMPT_MAP" ]; then
    {
      for _tf in "${TRANSCRIPT_FILES[@]}"; do
        [ -f "$_tf" ] && [ -r "$_tf" ] && jq -Rn "$_pt_jq" -- "$_tf" 2>/dev/null || true
      done
    } | jq -s 'reduce .[] as $item ({}; reduce ($item | to_entries[]) as $e (.; .[$e.key] = ((.[$e.key] // 0) + $e.value)))' > "$TMP_PROMPT_MAP" 2>/dev/null || printf '{}\n' > "$TMP_PROMPT_MAP"
  fi
else
  printf '{}\n' > "$TMP_PROMPT_MAP"
fi

jq -L "$LIB_DIR" -r -s \
  --argjson cfg "$CFG_JSON" \
  --slurpfile sidecars_arr "$TMP_SIDECAR_MAP" \
  --slurpfile prompt_counts_arr "$TMP_PROMPT_MAP" \
  --argjson term_cols "$TERM_COLS" \
  --argjson term_rows "$TERM_ROWS" \
  --argjson explicit_limit "$EXPLICIT_LIMIT" \
  --arg is_tty "$IS_TTY" \
  --arg no_color "${NO_COLOR:-}" \
  --arg quota_raw "$QUOTA_RAW" \
  --arg prices_raw "$PRICES_RAW" \
  --arg filter_mode "$FILTER_MODE" \
  --arg cycle_bucket "$CYCLE_BUCKET" \
  --arg filter_month "$FILTER_MONTH" \
  --arg filter_from "$FILTER_FROM" \
  --arg filter_to "$FILTER_TO" \
  --arg today_ymd "$TODAY_YMD" \
  --arg local_ver "$LOCAL_VER" \
  --arg app_update_ver "$APP_UPDATE_VER" '
  include "common";

  ($sidecars_arr[0] // {} | if type == "object" then . else {} end) as $sidecars |
  ($prompt_counts_arr[0] // {} | if type == "object" then . else {} end) as $prompt_counts |
  ($cfg.theme // "modern") as $theme |
  ($theme == "plain") as $plain |
  ($cfg.color // "auto") as $color_mode |
  (if ($plain or $color_mode == "off" or $no_color != "") then false elif $color_mode == "on" then true else ($is_tty == "true") end) as $use_color |
  ($cfg.short_tokens != false) as $short |
  ($cfg.subagent_cost_mode // "split") as $sub_mode |
  ($cfg.check_app_updates != false and $app_update_ver != "") as $has_app_update |

  def norm_model(m):
    (m // "Unknown" | tostring | if . == "" then "Unknown" else . end);
  def effective_cycle_start($qbuckets; $b):
    if ($qbuckets | has($b)) and (($qbuckets[$b] | type) == "object") then
      ($qbuckets[$b].cycle_started_at // "" | tostring)
    elif ($qbuckets | has("gemini-weekly")) and (($qbuckets["gemini-weekly"] | type) == "object") then
      ($qbuckets["gemini-weekly"].cycle_started_at // "" | tostring)
    else "" end;
  def table_min_w($headers; $rows):
    ($headers | length) as $nc |
    ([range(0; $nc) as $i | ([$headers[$i] | length] + [$rows[] | (.cells[$i].t // "" | length)] | max)] | add) + (2 * ($nc - 1));

  ($quota_raw | try fromjson catch {} | if type == "object" then . else {} end) as $qstate |
  sanitize_quota_buckets($qstate.buckets) as $qbuckets |
  ($prices_raw | try fromjson catch null |
    if (type == "object") and ((.updated_at | type) == "string") and (.updated_at | test("\\A[0-9A-Za-z._:-]{1,20}\\z")) then
      .updated_at
    else "N/A" end
  ) as $prices_upd |
  ((($today_ymd + "T12:00:00Z") | fromdateiso8601) - (6 * 86400) | strftime("%Y-%m-%d")) as $week_start |

  map(
    (.cost_usd // 0) as $orig_cost |
    (.subagent_cost_usd // 0) as $orig_sub |
    (.main_cost_usd // (if $orig_cost >= $orig_sub then ($orig_cost - $orig_sub) else $orig_cost end)) as $base_main |
    (.session_id // "" | tostring) as $sid_key |
    (if (.has_subagents == true) and (($sidecars[$sid_key] | type) == "object") then
       ($sidecars[$sid_key]) as $sc |
       (if (($sc.records // []) | length) > 0 then $sc.records else (.subagent_records // []) end) as $m_rec |
       ([$orig_sub, ($sc.cost_usd // 0)] | max) as $m_sub |
       . + {
         main_cost_usd: $base_main,
         subagent_cost_usd: $m_sub,
         subagent_records: $m_rec,
         cost_usd: ([$orig_cost, ($base_main + $m_sub)] | max)
       }
     else
       . + {main_cost_usd: $base_main}
     end) |
    (.subagent_records // [] | if type == "array" then . else [] end) as $raw_recs |
    ($raw_recs | map(.cost_usd // 0) | add // 0) as $sub_records_sum |
    ((.subagent_cost_usd // 0) - $sub_records_sum) as $residual |
    (if ($residual > 0.0005) or ($sub_records_sum == 0 and (.subagent_cost_usd // 0) > 0) then
       $raw_recs + [{
         session_id: "api",
         timestamp: (.timestamp // "N/A"),
         model: "Subagent (API)",
         uncached_tokens: 0,
         cache_tokens: 0,
         output_tokens: 0,
         cost_usd: $residual
       }]
     else
       $raw_recs
     end) as $display_children |
    . + {display_children: $display_children, user_prompts: ([(.user_prompts | if type == "number" then . else 0 end), ($prompt_counts[(.session_id // "" | tostring)] // 0)] | max)}
  ) |

  (
    if $filter_mode == "all" then .
    elif $filter_mode == "today" then
      map(select((.timestamp // "" | tostring)[0:10] == $today_ymd))
    elif $filter_mode == "week" then
      map(select(((.timestamp // "" | tostring)[0:10]) as $d | $d >= $week_start and $d <= $today_ymd))
    elif $filter_mode == "month" then
      map(select((.timestamp // "" | tostring)[0:7] == $filter_month))
    elif $filter_mode == "range" then
      map(select(((.timestamp // "" | tostring)[0:10]) as $d | $d != "" and ($filter_from == "" or $d >= $filter_from) and ($filter_to == "" or $d <= $filter_to)))
    else
      if $cycle_bucket != "" then
        effective_cycle_start($qbuckets; $cycle_bucket) as $cs |
        map(select(model_quota_bucket(.model) == $cycle_bucket and ($cs == "" or (.timestamp // "" | tostring) >= $cs)))
      else
        map(select(effective_cycle_start($qbuckets; model_quota_bucket(.model)) as $cs | ($cs == "" or (.timestamp // "" | tostring) >= $cs)))
      end
    end
  ) as $sessions |

  (
    if $filter_mode == "all" then "all"
    elif $filter_mode == "today" then "today (\($today_ymd))"
    elif $filter_mode == "week" then "week (\($week_start)..\($today_ymd))"
    elif $filter_mode == "month" then "month \($filter_month)"
    elif $filter_mode == "range" then "range \(if $filter_from == "" then "*" else $filter_from end)..\(if $filter_to == "" then "*" else $filter_to end)"
    elif $cycle_bucket != "" then "cycle: \($cycle_bucket)"
    else "cycle"
    end
  ) as $filter_label |

  if ($sessions | length) == 0 then
    "No sessions match filter \u0027\($filter_label)\u0027. Run \u0027jenbach all\u0027 to view all recorded sessions."
  else
    $sessions | (
      [
        $sessions[] |
        (.session_id // "none" | tostring | if . == "" then "none" else . end) as $psid |
        {
          root_sid: $psid,
          model: norm_model(.model),
          u: (.uncached_tokens // .input_tokens // 0),
          c: (.cache_tokens // 0),
          o: (.output_tokens // 0),
          cost: (.main_cost_usd // 0)
        },
        ((.display_children // [])[] | {
          root_sid: $psid,
          model: norm_model(.model),
          u: (.uncached_tokens // 0),
          c: (.cache_tokens // 0),
          o: (.output_tokens // 0),
          cost: (.cost_usd // 0)
        })
      ] as $expanded_entries |
      ($expanded_entries | map(.u) | add // 0) as $gu_in |
      ($expanded_entries | map(.c) | add // 0) as $gc_in |
      ($gu_in + $gc_in) as $gt_in |
      (if $gt_in > 0 then (($gc_in * 100 / $gt_in) | floor) else 0 end) as $g_hit |
      ($expanded_entries | map(.o) | add // 0) as $go_tok |
      ($sessions | map(.main_cost_usd // 0) | add // 0) as $g_main |
      ($sessions | map(.subagent_cost_usd // 0) | add // 0) as $g_sub |
      ($g_main + $g_sub) as $g_cost |
      (length) as $n_sess |
      (if $g_main > 0 then (if (($g_main * 1000) | round) == 0 then "<$0.001" else fmt_usd3($g_main) end) else fmt_usd3(0) end) as $g_main_str |
      (if $g_sub > 0 then (if (($g_sub * 1000) | round) == 0 then "<$0.001" else fmt_usd3($g_sub) end) else "" end) as $g_sub_str |
      (if $plain then " | " else "  │  " end) as $ksep |
      (if $plain then " | " else " · " end) as $kdot |
      ("Jenbach Usage" + (if $plain then " (\($filter_label))" else " · \($filter_label)" end)) as $box_title |

      [
        [
          {t: "Total Spend: ", c: ""},
          {t: fmt_usd3($g_cost), c: "bold_yellow"},
          (if ($sub_mode == "split" and $g_sub > 0) then
             {t: " (Main: \($g_main_str)\(if $plain then " | " else " · " end)", c: ""},
             {t: "Sub: \($g_sub_str)", c: "magenta"},
             {t: ")", c: ""}
           else empty end),
          {t: $ksep, c: ""},
          {t: "Sessions: \($n_sess)", c: ""},
          {t: $ksep, c: ""},
          {t: "Cache: ", c: ""},
          {t: ("\($g_hit)%" + (if $theme != "compact" then (" " + progress_bar($g_hit; 10; $plain)) else "" end)), c: hit_color($g_hit)}
        ],
        [
          {t: "Tokens: ", c: ""},
          (if $plain then {t: "In: \(fmt_tok($gu_in; $short)) uncached", c: ""} else {t: "↓\(fmt_tok($gu_in; $short)) uncached", c: ""} end),
          {t: $kdot, c: ""},
          {t: (if $plain then "Cached: \(fmt_tok($gc_in; $short))" else "\(fmt_tok($gc_in; $short)) cached" end), c: ""},
          {t: $kdot, c: ""},
          (if $plain then {t: "Out: \(fmt_tok($go_tok; $short))", c: ""} else {t: "↑\(fmt_tok($go_tok; $short)) output", c: ""} end)
        ]
      ] as $kpi_lines |

      [
        ($expanded_entries | group_by(.model)[] |
          split_model_think(.[0].model) as $mt |
          (map(.root_sid) | unique | length) as $u_sess |
          (map(.u) | add // 0) as $u_in |
          (map(.c) | add // 0) as $c_in |
          ($u_in + $c_in) as $t_in |
          (if $t_in > 0 then (($c_in * 100 / $t_in) | floor) else 0 end) as $hit |
          (map(.o) | add // 0) as $o_tok |
          (map(.cost) | add // 0) as $cost |
          {
            sep_before: false,
            bold_row: false,
            cells: [
              {t: $mt.base, c: "bold_white"},
              {t: $mt.think, c: think_color($mt.think)},
              {t: ($u_sess | tostring), c: ""},
              {t: fmt_tok($u_in; $short), c: ""},
              {t: fmt_tok($c_in; $short), c: ""},
              {t: "\($hit)%", c: hit_color($hit)},
              {t: fmt_tok($o_tok; $short), c: ""},
              {t: fmt_usd3($cost), c: "bold_yellow"}
            ]
          }
        ),
        {
          sep_before: true,
          bold_row: false,
          cells: [
            {t: "GRAND TOTAL", c: "bold_white"},
            {t: "-", c: "dim"},
            {t: ($n_sess | tostring), c: ""},
            {t: fmt_tok($gu_in; $short), c: ""},
            {t: fmt_tok($gc_in; $short), c: ""},
            {t: "\($g_hit)%", c: hit_color($g_hit)},
            {t: fmt_tok($go_tok; $short), c: ""},
            {t: fmt_usd3($g_cost), c: "bold_yellow"}
          ]
        }
      ] as $model_rows |

      (if $sub_mode == "split" then
        ["Date", "Model", "Think", "Msgs", "Uncached", "Cached", "Hit%", "Out", "Cost", "ID"]
       else
        ["Date", "Model", "Think", "Msgs", "Uncached", "Cached", "Hit%", "Out", "Total", "ID"]
       end) as $t2_headers |
      ($sessions | sort_by(.timestamp // "") | reverse) as $sorted_sessions |
      (if $explicit_limit > 0 then $explicit_limit else ($cfg.history_limit // 20) end) as $max_parents |
      ($sorted_sessions[0:$max_parents]) as $cand_parents |
      ($cfg.auto_fit_height != false and $explicit_limit == 0 and $term_rows > 0) as $do_fit |
      (if $do_fit then
         (8 + (if $theme == "compact" then 4 else 5 end) + (($model_rows | length) + 5) + 4 + (if $has_app_update then 1 else 0 end)) as $fixed_lines |
         ([ ($term_rows - $fixed_lines), 3 ] | max) as $row_budget |
         (reduce $cand_parents[] as $s (
            {items: [], used: 0, stopped: false};
            (if $sub_mode == "split" then (1 + (($s.display_children // []) | length)) else 1 end) as $need |
            if .stopped then .
            elif (.items | length) == 0 or ((.used + $need) <= $row_budget) then
              .items += [$s] | .used += $need
            else
              .stopped = true
            end
          ) | .items)
       else
         $cand_parents
       end) as $shown_sessions |

      (if ($cfg.show_history != false) then
        [
          $shown_sessions[] |
          split_model_think(norm_model(.model)) as $mt |
          (.display_children // []) as $children |
          ($children | length) as $n_sub |
          (.timestamp // "N/A" | tostring | if . == "" then "N/A" elif length >= 16 then .[5:16] else . end) as $dt |
          (.user_prompts // 0) as $u_prompts |
          if $sub_mode == "split" then
            (.uncached_tokens // .input_tokens // 0) as $u_in |
            (.cache_tokens // 0) as $c_in |
            ($u_in + $c_in) as $t_in |
            (if $t_in > 0 then (($c_in * 100 / $t_in) | floor) else 0 end) as $hit |
            (.main_cost_usd // 0) as $cost |
            ((.main_cost_usd // 0) + (.subagent_cost_usd // 0)) as $sess_total |
            (if ($n_sub > 0) and ($term_cols >= 90) then
               "(\(fmt_usd3($sess_total))) \(fmt_usd3($cost))"
             else
               fmt_usd3($cost)
             end) as $parent_cost_str |
            {
              sep_before: false,
              bold_row: false,
              cells: [
                {t: $dt, c: "dim"},
                {t: (if $term_cols >= 85 then $mt.base else short_model($mt.base; $plain) end), c: ""},
                {t: $mt.think, c: think_color($mt.think)},
                {t: (if $u_prompts > 0 then ($u_prompts | tostring) else "-" end), c: ""},
                {t: fmt_tok($u_in; $short), c: ""},
                {t: fmt_tok($c_in; $short), c: ""},
                {t: "\($hit)%", c: hit_color($hit)},
                {t: fmt_tok((.output_tokens // 0); $short), c: ""},
                {t: $parent_cost_str, c: "bold_yellow"},
                {t: ((.session_id // "none" | tostring | if . == "" then "none" else . end)[0:8]), c: "dim"}
              ]
            },
            (range(0; $n_sub) as $idx |
              $children[$idx] as $ch |
              split_model_think(norm_model($ch.model)) as $cmt |
              ($ch.uncached_tokens // 0) as $cu_in |
              ($ch.cache_tokens // 0) as $cc_in |
              ($cu_in + $cc_in) as $ct_in |
              (if $ct_in > 0 then (($cc_in * 100 / $ct_in) | floor) else 0 end) as $chit |
              ($ch.timestamp // "N/A" | tostring | if . == "" then "N/A" elif length >= 16 then .[5:16] else . end) as $child_dt |
              (if $plain then "|- " else (if $idx == ($n_sub - 1) then "└─ " else "├─ " end) end) as $prefix |
              {
                sep_before: false,
                bold_row: false,
                cells: [
                  {t: ($prefix + $child_dt), c: "dim"},
                  {t: (if $term_cols >= 85 then $cmt.base else short_model($cmt.base; $plain) end), c: ""},
                  {t: $cmt.think, c: think_color($cmt.think)},
                  {t: "-", c: ""},
                  {t: fmt_tok($cu_in; $short), c: ""},
                  {t: fmt_tok($cc_in; $short), c: ""},
                  {t: "\($chit)%", c: hit_color($chit)},
                  {t: fmt_tok(($ch.output_tokens // 0); $short), c: ""},
                  {t: fmt_sub_cell($ch.cost_usd // 0), c: "magenta"},
                  {t: ((($ch.session_id // "none" | tostring | if . == "" then "none" else . end))[0:8]), c: "dim"}
                ]
              }
            )
          else
            ((.uncached_tokens // .input_tokens // 0) + ($children | map(.uncached_tokens // 0) | add // 0)) as $u_in |
            ((.cache_tokens // 0) + ($children | map(.cache_tokens // 0) | add // 0)) as $c_in |
            ($u_in + $c_in) as $t_in |
            (if $t_in > 0 then (($c_in * 100 / $t_in) | floor) else 0 end) as $hit |
            ((.output_tokens // 0) + ($children | map(.output_tokens // 0) | add // 0)) as $o_tok |
            ((.main_cost_usd // 0) + (.subagent_cost_usd // 0)) as $cost |
            {
              sep_before: false,
              bold_row: false,
              cells: [
                {t: $dt, c: "dim"},
                {t: (if $term_cols >= 85 then $mt.base else short_model($mt.base; $plain) end), c: ""},
                {t: $mt.think, c: think_color($mt.think)},
                {t: (if $u_prompts > 0 then ($u_prompts | tostring) else "-" end), c: ""},
                {t: fmt_tok($u_in; $short), c: ""},
                {t: fmt_tok($c_in; $short), c: ""},
                {t: "\($hit)%", c: hit_color($hit)},
                {t: fmt_tok($o_tok; $short), c: ""},
                {t: fmt_usd3($cost), c: "bold_yellow"},
                {t: ((.session_id // "none" | tostring | if . == "" then "none" else . end)[0:8]), c: "dim"}
              ]
            }
          end
        ]
      else [] end) as $hist_rows |

      (([$kpi_lines[] | (map(.t | length) | add // 0)] | max // 0) + 6) as $kpi_content_w |
      ([76, $kpi_content_w, (($box_title | length) + 8)] | max) as $kpi_min |
      table_min_w(["Model", "Think", "Sess", "Uncached", "Cached", "Hit%", "Output", "Total"]; $model_rows) as $t1_min |
      (if ($cfg.show_history != false) then
         table_min_w($t2_headers; $hist_rows)
       else 0 end) as $t2_min |
      ([$kpi_min, $t1_min, $t2_min] | max) as $content_min |
      (if $term_cols >= 85 then
         ([ $content_min, ([ ($term_cols - 12), 104 ] | min) ] | max)
       else
         ([ ($term_cols - 2), 40 ] | max)
       end) as $target_w |

      (if $theme == "compact" then
        (
          ($kpi_lines[] | merge_segments(.) | map(paint(.t; (.c // ""); $use_color)) | add),
          paint(repeat_str((if $plain then "-" else "─" end); $target_w); "dim"; $use_color)
        )
       else
        render_kpi_box($box_title; $kpi_lines; $plain; $use_color; $target_w)
       end),
      "",
      paint("USAGE BY MODEL"; "bold_cyan"; $use_color),
      render_table(["Model", "Think", "Sess", "Uncached", "Cached", "Hit%", "Output", "Total"]; ["l", "l", "r", "r", "r", "r", "r", "r"]; $model_rows; $plain; $use_color; $target_w),
      (if ($cfg.show_history != false) then
        "",
        paint(
          (if ($shown_sessions | length) < $n_sess then
             "RECENT SESSIONS (SHOWING \($shown_sessions | length) OF \($n_sess))"
           else
             "RECENT SESSIONS (LAST \($max_parents))"
           end);
          "bold_cyan"; $use_color
        ),
        render_table($t2_headers; ["l", "l", "l", "r", "r", "r", "r", "r", "r", "l"]; $hist_rows; $plain; $use_color; $target_w),
        (if ($shown_sessions | length) < $n_sess then
           (if $term_cols >= 100 then "\(if $plain then " | " else " · " end)Prices: \($prices_upd)" else "" end) as $p_sfx |
           (if $do_fit and (($shown_sessions | length) < ($cand_parents | length)) then
              paint("Showing \($shown_sessions | length) of \($n_sess) sessions (fit to terminal). Run \u0027jenbach -n \($n_sess)\u0027 to view all.\($p_sfx)"; "dim"; $use_color)
            else
              paint("Showing \($shown_sessions | length) of \($n_sess) sessions. Run \u0027jenbach -n \($n_sess)\u0027 to view all.\($p_sfx)"; "dim"; $use_color)
            end)
         else
           paint("Prices updated: \($prices_upd)"; "dim"; $use_color)
         end)
      else
        paint("Prices updated: \($prices_upd)"; "dim"; $use_color)
      end),
      (if $has_app_update then
         paint("Update available: v\($local_ver) \(if $plain then "->" else "→" end) v\($app_update_ver) \(if $plain then "-" else "—" end) run \u0027jenbach update\u0027"; "bold_cyan"; $use_color)
       else empty end)
    )
  end
' "${LOG_FILES[@]}"
