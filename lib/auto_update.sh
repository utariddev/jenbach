# Shared non-blocking auto-updater for Jenbach prices.json
# Sourced by statusline.sh and report.sh (Bash 3.2+ compatible).

_jenbach_promote_prices_ttl() {
  local _jb_p_stamp="$1"
  local _jb_p_iv_sec="$2"
  local _jb_p_expected="$3"
  local _jb_p_st_tmp="$4"
  if [ -r "$_jb_p_stamp" ] && [ "$(< "$_jb_p_stamp")" = "$_jb_p_expected" ]; then
    local _jb_done_now=""
    printf -v _jb_done_now '%(%s)T' -1 2>/dev/null || true
    if [[ ! "$_jb_done_now" =~ ^[0-9]+$ ]]; then
      _jb_done_now=$(date +%s 2>/dev/null || echo 0)
    fi
    printf '%s\n' "$((_jb_done_now + _jb_p_iv_sec))" > "$_jb_p_st_tmp" 2>/dev/null && mv -f "$_jb_p_st_tmp" "$_jb_p_stamp" 2>/dev/null || rm -f "$_jb_p_st_tmp" 2>/dev/null || true
  fi
}

_jenbach_fetch_prices_bg() {
  local _jb_dir="$1"
  local _jb_prices_file="$2"
  local _jb_url="$3"
  _jb_lock_dir="$4"
  local _jb_stamp_file="$5"
  local _jb_interval_sec="$6"
  local _jb_backoff_ts="$7"

  local _jb_pid="$$"
  _jb_hdr_tmp="${_jb_dir}/.prices.hdr.${_jb_pid}"
  _jb_body_tmp="${_jb_dir}/.prices.body.${_jb_pid}"
  _jb_st_tmp="${_jb_stamp_file}.tmp.bg.${_jb_pid}"
  trap 'rm -rf "$_jb_lock_dir" "$_jb_hdr_tmp" "$_jb_body_tmp" "$_jb_st_tmp" 2>/dev/null || true' EXIT

  local _jb_etag=""
  if [ -s "$_jb_prices_file" ] && [ -r "${_jb_dir}/.prices.etag" ]; then
    _jb_etag=$(< "${_jb_dir}/.prices.etag")
  fi

  local _jb_http_code=""
  if [ -n "$_jb_etag" ]; then
    _jb_http_code=$(curl -sSL --max-time 5 -H "If-None-Match: ${_jb_etag}" -D "$_jb_hdr_tmp" -o "$_jb_body_tmp" -w '%{http_code}' "$_jb_url" 2>/dev/null || true)
  else
    _jb_http_code=$(curl -sSL --max-time 5 -D "$_jb_hdr_tmp" -o "$_jb_body_tmp" -w '%{http_code}' "$_jb_url" 2>/dev/null || true)
  fi

  if [ "$_jb_http_code" = "304" ]; then
    _jenbach_promote_prices_ttl "$_jb_stamp_file" "$_jb_interval_sec" "$_jb_backoff_ts" "$_jb_st_tmp"
    return 0
  fi

  if [ "$_jb_http_code" = "200" ] && [ -s "$_jb_body_tmp" ]; then
    if jq -e '
      (.models | type == "object") and
      (.models.default | type == "object") and
      ([.models[] | (
        (.["in"] | type == "number") and .["in"] > 0 and .["in"] < 500 and
        (.cached | type == "number") and .cached >= 0 and .cached <= .["in"] and
        (.out | type == "number") and .out > 0 and .out < 1000
      )] | all)
    ' "$_jb_body_tmp" >/dev/null 2>&1; then
      mv -f "$_jb_body_tmp" "$_jb_prices_file" 2>/dev/null || return 0
      local _jb_new_etag=""
      _jb_new_etag=$(awk 'tolower($0) ~ /^etag:[[:space:]]*/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); val=$0 } END { print val }' "$_jb_hdr_tmp" 2>/dev/null || true)
      if [ -n "$_jb_new_etag" ]; then
        printf '%s\n' "$_jb_new_etag" > "${_jb_dir}/.prices.etag.tmp.${_jb_pid}" 2>/dev/null && mv -f "${_jb_dir}/.prices.etag.tmp.${_jb_pid}" "${_jb_dir}/.prices.etag" 2>/dev/null || true
      fi
      _jenbach_promote_prices_ttl "$_jb_stamp_file" "$_jb_interval_sec" "$_jb_backoff_ts" "$_jb_st_tmp"
    fi
  fi

  return 0
}

jenbach_maybe_update_prices() {
  local _jb_dir="$1"
  local _jb_cfg_file="$2"
  local _jb_prices_file="$3"
  local _jb_cfg="${4:-}"

  command -v curl >/dev/null 2>&1 || return 0

  # Pure-Bash epoch (0 forks on Bash 4.2+, fallback on Bash 3.2)
  local _jb_now=""
  printf -v _jb_now '%(%s)T' -1 2>/dev/null || true
  if [[ ! "$_jb_now" =~ ^[0-9]+$ ]]; then
    _jb_now=$(date +%s 2>/dev/null || echo 0)
  fi

  # Pure-Bash opt-out check (variable-stored ERE for Bash 3.2 compatibility)
  if [ -z "$_jb_cfg" ] && [ -r "$_jb_cfg_file" ]; then
    _jb_cfg=$(< "$_jb_cfg_file")
  fi
  local _jb_re='"auto_update_prices"[[:space:]]*:[[:space:]]*false'
  if [[ "$_jb_cfg" =~ $_jb_re ]]; then
    return 0
  fi

  # Pure-Bash TTL fast path (0 forks)
  local _jb_stamp_file="${_jb_dir}/.prices_next_check"
  local _jb_next=""
  if [ -r "$_jb_stamp_file" ]; then
    _jb_next=$(< "$_jb_stamp_file")
    if [[ "$_jb_next" =~ ^[0-9]+$ ]] && [ "$_jb_now" -lt "$_jb_next" ]; then
      return 0
    fi
  fi

  # TTL expired or missing
  command -v jq >/dev/null 2>&1 || return 0

  local _jb_default_url="https://raw.githubusercontent.com/utariddev/jenbach/main/prices.json"
  local _jb_enabled="true"
  local _jb_interval=24
  local _jb_url="$_jb_default_url"

  if [ -r "$_jb_cfg_file" ]; then
    local _jb_cfg_vals=""
    _jb_cfg_vals=$(jq -r --arg def_url "$_jb_default_url" '
      [
        (if .auto_update_prices == false then "false" else "true" end),
        ((.price_check_interval_hours // 24) | tonumber? // 24 | floor | if . < 1 then 1 elif . > 720 then 720 else . end | tostring),
        (.prices_url // $def_url | if type == "string" and length > 0 then . else $def_url end)
      ] | @tsv
    ' "$_jb_cfg_file" 2>/dev/null || true)
    if [ -n "$_jb_cfg_vals" ]; then
      IFS=$'\t' read -r _jb_enabled _jb_interval _jb_url <<< "$_jb_cfg_vals"
    fi
  fi

  if [ "$_jb_enabled" = "false" ]; then
    [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || return 0
    local _jb_optout_next=$((_jb_now + 86400))
    printf '%s\n' "$_jb_optout_next" > "${_jb_stamp_file}.tmp.$$" 2>/dev/null && mv -f "${_jb_stamp_file}.tmp.$$" "$_jb_stamp_file" 2>/dev/null || true
    return 0
  fi

  [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || return 0

  # Atomic mkdir lock with stale-lock recovery (> 120s)
  local _jb_lock_dir="${_jb_dir}/.prices_update.lock"
  if ! mkdir "$_jb_lock_dir" 2>/dev/null; then
    local _jb_lock_ts=""
    if [ -r "${_jb_lock_dir}/ts" ]; then
      _jb_lock_ts=$(< "${_jb_lock_dir}/ts")
    else
      # Fallback to lock dir mtime to avoid TOCTOU race before ts is written
      _jb_lock_ts=$(stat -c %Y "$_jb_lock_dir" 2>/dev/null || stat -f %m "$_jb_lock_dir" 2>/dev/null || echo "$_jb_now")
    fi
    if [[ ! "$_jb_lock_ts" =~ ^[0-9]+$ ]] || [ $((_jb_now - _jb_lock_ts)) -gt 120 ]; then
      rm -rf "$_jb_lock_dir" 2>/dev/null || true
      mkdir "$_jb_lock_dir" 2>/dev/null || return 0
    else
      return 0
    fi
  fi
  printf '%s\n' "$_jb_now" > "${_jb_lock_dir}/ts" 2>/dev/null || true

  # Atomically write 15-minute retry backoff before spawning background worker
  local _jb_interval_sec=$((_jb_interval * 3600))
  local _jb_backoff_ts=$((_jb_now + 900))
  printf '%s\n' "$_jb_backoff_ts" > "${_jb_stamp_file}.tmp.$$" 2>/dev/null && mv -f "${_jb_stamp_file}.tmp.$$" "$_jb_stamp_file" 2>/dev/null || rm -f "${_jb_stamp_file}.tmp.$$" 2>/dev/null || true

  # Spawn FD-closed detached background worker
  ( _jenbach_fetch_prices_bg "$_jb_dir" "$_jb_prices_file" "$_jb_url" "$_jb_lock_dir" "$_jb_stamp_file" "$_jb_interval_sec" "$_jb_backoff_ts" ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  return 0
}

_jenbach_sync_subagents_bg() {
  local _jb_log_dir="$1"
  local _jb_sid="$2"
  local _jb_agy_dir="$3"
  local _jb_prices_file="$4"
  local _jb_lib_dir="$5"
  local _jb_sub_sig="$6"
  local _jb_now_str="$7"
  _jb_sub_lock_dir="$8"
  _jb_sub_lock_token="$9"

  trap 'if [ -r "${_jb_sub_lock_dir}/owner" ] && [ "$(< "${_jb_sub_lock_dir}/owner")" = "$_jb_sub_lock_token" ]; then rm -rf "$_jb_sub_lock_dir" 2>/dev/null || true; fi' EXIT

  python3 "${_jb_lib_dir}/subagent_sync.py" \
    --sid "$_jb_sid" \
    --brain-dir "${_jb_agy_dir}/brain" \
    --conv-dir "${_jb_agy_dir}/conversations" \
    --prices "$_jb_prices_file" \
    --out "${_jb_log_dir}/.sub_${_jb_sid}.json" \
    --now "$_jb_now_str" >/dev/null 2>&1 || true

  local _jb_done_now=""
  printf -v _jb_done_now '%(%s)T' -1 2>/dev/null || true
  if [[ ! "$_jb_done_now" =~ ^[0-9]+$ ]]; then
    _jb_done_now=$(date +%s 2>/dev/null || echo 0)
  fi
  local _jb_ttl_tmp="${_jb_log_dir}/.sub_${_jb_sid}.ttl.tmp.$$"
  printf '%s %s\n' "$((_jb_done_now + 3))" "$_jb_sub_sig" > "$_jb_ttl_tmp" 2>/dev/null && mv -f "$_jb_ttl_tmp" "${_jb_log_dir}/.sub_${_jb_sid}.ttl" 2>/dev/null || rm -f "$_jb_ttl_tmp" 2>/dev/null || true

  return 0
}

jenbach_maybe_sync_subagents() {
  local _jb_log_dir="$1"
  local _jb_sid="$2"
  local _jb_agy_dir="$3"
  local _jb_prices_file="$4"
  local _jb_lib_dir="$5"
  local _jb_sub_sig="$6"
  local _jb_now_str="${7:-}"

  [ -n "$_jb_sid" ] && [ "$_jb_sid" != "none" ] || return 0
  [ -n "$_jb_sub_sig" ] && [ "$_jb_sub_sig" != "0_0" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [ -r "${_jb_lib_dir}/subagent_sync.py" ] || return 0

  local _jb_now=""
  printf -v _jb_now '%(%s)T' -1 2>/dev/null || true
  if [[ ! "$_jb_now" =~ ^[0-9]+$ ]]; then
    _jb_now=$(date +%s 2>/dev/null || echo 0)
  fi

  local _jb_ttl_file="${_jb_log_dir}/.sub_${_jb_sid}.ttl"
  local _jb_sidecar_file="${_jb_log_dir}/.sub_${_jb_sid}.json"
  if [ -r "$_jb_ttl_file" ] && [ -r "$_jb_sidecar_file" ]; then
    local _jb_ttl_line=""
    _jb_ttl_line=$(< "$_jb_ttl_file")
    local _jb_next_ep="${_jb_ttl_line%% *}"
    local _jb_last_sig="${_jb_ttl_line#* }"
    if [[ "$_jb_next_ep" =~ ^[0-9]+$ ]] && [ "$_jb_now" -lt "$_jb_next_ep" ] && [ "$_jb_last_sig" = "$_jb_sub_sig" ]; then
      return 0
    fi
  fi

  [ -d "$_jb_log_dir" ] || mkdir -p "$_jb_log_dir" 2>/dev/null || return 0

  # Atomic mkdir lock with stale-lock recovery (> 30s); do NOT stamp TTL if lock is held
  local _jb_lock_dir="${_jb_log_dir}/.sub_${_jb_sid}.lock"
  if ! mkdir "$_jb_lock_dir" 2>/dev/null; then
    local _jb_lock_ts=""
    if [ -r "${_jb_lock_dir}/ts" ]; then
      _jb_lock_ts=$(< "${_jb_lock_dir}/ts")
    else
      _jb_lock_ts=$(stat -c %Y "$_jb_lock_dir" 2>/dev/null || stat -f %m "$_jb_lock_dir" 2>/dev/null || echo "$_jb_now")
    fi
    if [[ ! "$_jb_lock_ts" =~ ^[0-9]+$ ]] || [ $((_jb_now - _jb_lock_ts)) -gt 30 ]; then
      rm -rf "$_jb_lock_dir" 2>/dev/null || true
      mkdir "$_jb_lock_dir" 2>/dev/null || return 0
    else
      return 0
    fi
  fi
  local _jb_lock_token="${$}_${_jb_now}_${RANDOM:-0}"
  printf '%s\n' "$_jb_now" > "${_jb_lock_dir}/ts" 2>/dev/null || true
  printf '%s\n' "$_jb_lock_token" > "${_jb_lock_dir}/owner" 2>/dev/null || true

  # Spawn FD-closed detached background worker
  ( _jenbach_sync_subagents_bg "$_jb_log_dir" "$_jb_sid" "$_jb_agy_dir" "$_jb_prices_file" "$_jb_lib_dir" "$_jb_sub_sig" "$_jb_now_str" "$_jb_lock_dir" "$_jb_lock_token" ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  return 0
}
