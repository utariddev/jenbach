# Shared non-blocking GitHub Releases update checker and self-updater for Jenbach
# Sourced by statusline.sh and report.sh (Bash 3.2+ compatible, set -u safe).

_jenbach_promote_app_ttl() {
  local _jb_p_stamp="$1"
  local _jb_p_expected="$2"
  local _jb_p_st_tmp="$3"
  if [ -r "$_jb_p_stamp" ] && [ "$(< "$_jb_p_stamp")" = "$_jb_p_expected" ]; then
    local _jb_done_now=""
    printf -v _jb_done_now '%(%s)T' -1 2>/dev/null || true
    if [[ ! "$_jb_done_now" =~ ^[0-9]+$ ]]; then
      _jb_done_now=$(date +%s 2>/dev/null || echo 0)
    fi
    printf '%s\n' "$((_jb_done_now + 86400))" > "$_jb_p_st_tmp" 2>/dev/null && mv -f "$_jb_p_st_tmp" "$_jb_p_stamp" 2>/dev/null || rm -f "$_jb_p_st_tmp" 2>/dev/null || true
  fi
}

_jenbach_check_app_update_bg() {
  local _jb_dir="$1"
  local _jb_repo_url="$2"
  _jb_app_lock_dir="$3"
  local _jb_stamp_file="$4"
  local _jb_backoff_ts="$5"

  local _jb_pid="$$"
  _jb_app_hdr_tmp="${_jb_dir}/.app_update.hdr.${_jb_pid}"
  _jb_app_st_tmp="${_jb_stamp_file}.tmp.bg.${_jb_pid}"
  _jb_app_ver_tmp="${_jb_dir}/.latest_version.tmp.${_jb_pid}"
  trap 'rm -rf "$_jb_app_lock_dir" "$_jb_app_hdr_tmp" "$_jb_app_st_tmp" "$_jb_app_ver_tmp" 2>/dev/null || true' EXIT

  local _jb_http_code=""
  _jb_http_code=$(curl -sI --max-time 5 -D "$_jb_app_hdr_tmp" -o /dev/null -w '%{http_code}' "${_jb_repo_url%/}/releases/latest" 2>/dev/null || true)

  if [ "$_jb_http_code" = "302" ]; then
    local _jb_loc=""
    if [ -r "$_jb_app_hdr_tmp" ]; then
      _jb_loc=$(awk 'tolower($0) ~ /^location:[[:space:]]*/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); val=$0 } END { print val }' "$_jb_app_hdr_tmp" 2>/dev/null || true)
    fi
    local _jb_tag_re='/releases/tag/(v?([1-9][0-9]*))([/?#].*)?$'
    if [[ "$_jb_loc" =~ $_jb_tag_re ]]; then
      local _jb_remote_ver=$((10#${BASH_REMATCH[2]}))
      printf '%s\n' "$_jb_remote_ver" > "$_jb_app_ver_tmp" 2>/dev/null && mv -f "$_jb_app_ver_tmp" "${_jb_dir}/.latest_version" 2>/dev/null || rm -f "$_jb_app_ver_tmp" 2>/dev/null || true
      _jenbach_promote_app_ttl "$_jb_stamp_file" "$_jb_backoff_ts" "$_jb_app_st_tmp"
    else
      _jenbach_promote_app_ttl "$_jb_stamp_file" "$_jb_backoff_ts" "$_jb_app_st_tmp"
    fi
  elif [ "$_jb_http_code" = "404" ]; then
    _jenbach_promote_app_ttl "$_jb_stamp_file" "$_jb_backoff_ts" "$_jb_app_st_tmp"
  fi

  return 0
}

jenbach_maybe_check_app_update() {
  local _jb_dir="$1"
  local _jb_cfg_file="$2"
  local _jb_cfg="${3:-}"

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
  local _jb_re='"check_app_updates"[[:space:]]*:[[:space:]]*false'
  if [[ "$_jb_cfg" =~ $_jb_re ]]; then
    return 0
  fi

  # Pure-Bash TTL fast path (0 forks)
  local _jb_stamp_file="${_jb_dir}/.app_update_next_check"
  local _jb_next=""
  if [ -r "$_jb_stamp_file" ]; then
    _jb_next=$(< "$_jb_stamp_file")
    if [[ "$_jb_next" =~ ^[0-9]+$ ]] && [ "$_jb_now" -lt "$_jb_next" ]; then
      return 0
    fi
  fi

  # TTL expired or missing
  command -v jq >/dev/null 2>&1 || return 0

  local _jb_default_url="https://github.com/utariddev/jenbach"
  local _jb_enabled="true"
  local _jb_repo_url="$_jb_default_url"

  if [ -r "$_jb_cfg_file" ]; then
    local _jb_cfg_vals=""
    _jb_cfg_vals=$(jq -r --arg def_url "$_jb_default_url" '
      [
        (if .check_app_updates == false then "false" else "true" end),
        (.app_repo_url // $def_url | if type == "string" and length > 0 then . else $def_url end)
      ] | @tsv
    ' "$_jb_cfg_file" 2>/dev/null || true)
    if [ -n "$_jb_cfg_vals" ]; then
      IFS=$'\t' read -r _jb_enabled _jb_repo_url <<< "$_jb_cfg_vals"
    fi
  fi

  if [ "$_jb_enabled" = "false" ]; then
    [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || return 0
    local _jb_optout_next=$((_jb_now + 86400))
    printf '%s\n' "$_jb_optout_next" > "${_jb_stamp_file}.tmp.$$" 2>/dev/null && mv -f "${_jb_stamp_file}.tmp.$$" "$_jb_stamp_file" 2>/dev/null || rm -f "${_jb_stamp_file}.tmp.$$" 2>/dev/null || true
    return 0
  fi

  [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || return 0

  # Atomic mkdir lock with stale-lock recovery (> 120s)
  local _jb_lock_dir="${_jb_dir}/.app_update.lock"
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
  local _jb_backoff_ts=$((_jb_now + 900))
  printf '%s\n' "$_jb_backoff_ts" > "${_jb_stamp_file}.tmp.$$" 2>/dev/null && mv -f "${_jb_stamp_file}.tmp.$$" "$_jb_stamp_file" 2>/dev/null || rm -f "${_jb_stamp_file}.tmp.$$" 2>/dev/null || true

  # Spawn FD-closed detached background worker
  ( _jenbach_check_app_update_bg "$_jb_dir" "$_jb_repo_url" "$_jb_lock_dir" "$_jb_stamp_file" "$_jb_backoff_ts" ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  return 0
}

jenbach_run_app_update() {
  local _jb_dir="$1"
  local _jb_cfg_file="$2"
  local _jb_local_ver="$3"
  local _jb_force_flag="${4:-}"

  (
    _jb_run_tmp_dir=""
    trap 'rm -rf "$_jb_run_tmp_dir" 2>/dev/null || true' EXIT INT TERM

    if ! command -v curl >/dev/null 2>&1; then
      echo "Error: curl is required for 'jenbach update'." >&2
      exit 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
      echo "Error: tar is required for 'jenbach update'." >&2
      exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "Error: jq is required for 'jenbach update'." >&2
      exit 1
    fi

    local _jb_default_url="https://github.com/utariddev/jenbach"
    local _jb_repo_url="$_jb_default_url"
    if [ -r "$_jb_cfg_file" ]; then
      local _jb_cfg_url=""
      _jb_cfg_url=$(jq -r --arg def_url "$_jb_default_url" '.app_repo_url // $def_url | if type == "string" and length > 0 then . else $def_url end' "$_jb_cfg_file" 2>/dev/null || true)
      [ -n "$_jb_cfg_url" ] && _jb_repo_url="$_jb_cfg_url"
    fi
    _jb_repo_url="${_jb_repo_url%/}"

    _jb_run_tmp_dir=$(mktemp -d 2>/dev/null || true)
    if [ -z "$_jb_run_tmp_dir" ] || [ ! -d "$_jb_run_tmp_dir" ]; then
      echo "Error: Failed to create temporary directory." >&2
      exit 1
    fi
    local _jb_tmp_dir="$_jb_run_tmp_dir"

    local _jb_hdr_tmp="${_jb_tmp_dir}/headers.txt"
    local _jb_http_code=""
    _jb_http_code=$(curl -sI --max-time 15 -D "$_jb_hdr_tmp" -o /dev/null -w '%{http_code}' "${_jb_repo_url}/releases/latest" 2>/dev/null || true)

    local _jb_loc=""
    if [ -r "$_jb_hdr_tmp" ]; then
      _jb_loc=$(awk 'tolower($0) ~ /^location:[[:space:]]*/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); val=$0 } END { print val }' "$_jb_hdr_tmp" 2>/dev/null || true)
    fi

    local _jb_tag_re='/releases/tag/(v?([1-9][0-9]*))([/?#].*)?$'
    if [ "$_jb_http_code" != "302" ] || [[ ! "$_jb_loc" =~ $_jb_tag_re ]]; then
      echo "Error: No published GitHub release found at ${_jb_repo_url}/releases" >&2
      exit 1
    fi

    local _jb_remote_tag="${BASH_REMATCH[1]}"
    local _jb_remote_ver=$((10#${BASH_REMATCH[2]}))

    local _jb_now=""
    printf -v _jb_now '%(%s)T' -1 2>/dev/null || true
    if [[ ! "$_jb_now" =~ ^[0-9]+$ ]]; then
      _jb_now=$(date +%s 2>/dev/null || echo 0)
    fi

    if [ "$_jb_force_flag" != "--force" ] && [[ "$_jb_local_ver" =~ ^[1-9][0-9]*$ ]] && (( 10#$_jb_remote_ver <= 10#$_jb_local_ver )); then
      [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || true
      printf '%s\n' "$_jb_remote_ver" > "${_jb_dir}/.latest_version.tmp.$$" 2>/dev/null && mv -f "${_jb_dir}/.latest_version.tmp.$$" "${_jb_dir}/.latest_version" 2>/dev/null || rm -f "${_jb_dir}/.latest_version.tmp.$$" 2>/dev/null || true
      printf '%s\n' "$((_jb_now + 86400))" > "${_jb_dir}/.app_update_next_check.tmp.$$" 2>/dev/null && mv -f "${_jb_dir}/.app_update_next_check.tmp.$$" "${_jb_dir}/.app_update_next_check" 2>/dev/null || rm -f "${_jb_dir}/.app_update_next_check.tmp.$$" 2>/dev/null || true
      echo "Jenbach is already up to date (v${_jb_local_ver})."
      exit 0
    fi

    local _jb_tarball="${_jb_tmp_dir}/release.tar.gz"
    local _jb_archive_url="${_jb_repo_url}/archive/refs/tags/${_jb_remote_tag}.tar.gz"
    if ! curl -fsSL --max-time 60 "$_jb_archive_url" -o "$_jb_tarball" 2>/dev/null || [ ! -s "$_jb_tarball" ]; then
      echo "Error: Failed to download release archive from ${_jb_archive_url}" >&2
      exit 1
    fi

    local _jb_extract_dir="${_jb_tmp_dir}/extract"
    mkdir -p "$_jb_extract_dir"
    if ! tar -xzf "$_jb_tarball" -C "$_jb_extract_dir" 2>/dev/null; then
      echo "Error: Failed to extract release archive." >&2
      exit 1
    fi

    local _jb_src_dir=""
    local _jb_cand_count=0
    local _jb_d=""
    for _jb_d in "$_jb_extract_dir"/*; do
      if [ -d "$_jb_d" ] && [ -f "$_jb_d/install.sh" ]; then
        _jb_src_dir="$_jb_d"
        _jb_cand_count=$((_jb_cand_count + 1))
      fi
    done
    if [ "$_jb_cand_count" -eq 0 ] && [ -f "$_jb_extract_dir/install.sh" ]; then
      _jb_src_dir="$_jb_extract_dir"
      _jb_cand_count=1
    fi
    if [ "$_jb_cand_count" -ne 1 ] || [ -z "$_jb_src_dir" ]; then
      echo "Error: Release archive does not contain a valid Jenbach root directory." >&2
      exit 1
    fi

    local _jb_req_file=""
    for _jb_req_file in \
      "install.sh" \
      "uninstall.sh" \
      "statusline.sh" \
      "report.sh" \
      "VERSION" \
      "prices.json" \
      "lib/common.jq" \
      "lib/auto_update.sh" \
      "lib/app_update.sh" \
      "lib/subagent_sync.py"
    do
      if [ ! -f "${_jb_src_dir}/${_jb_req_file}" ] || [ ! -r "${_jb_src_dir}/${_jb_req_file}" ]; then
        echo "Error: Release archive is missing required file '${_jb_req_file}'." >&2
        exit 1
      fi
    done

    local _jb_sh_file=""
    for _jb_sh_file in \
      "${_jb_src_dir}/install.sh" \
      "${_jb_src_dir}/uninstall.sh" \
      "${_jb_src_dir}/statusline.sh" \
      "${_jb_src_dir}/report.sh" \
      "${_jb_src_dir}/lib/auto_update.sh" \
      "${_jb_src_dir}/lib/app_update.sh"
    do
      if ! bash -n "$_jb_sh_file" 2>/dev/null; then
        echo "Error: Release archive failed shell syntax verification." >&2
        exit 1
      fi
    done

    if ! jq empty "${_jb_src_dir}/prices.json" >/dev/null 2>&1; then
      echo "Error: Release archive contains invalid prices.json." >&2
      exit 1
    fi

    if ! bash "${_jb_src_dir}/install.sh" >/dev/null; then
      echo "Error: Failed to install release v${_jb_remote_ver}." >&2
      exit 1
    fi

    [ -d "$_jb_dir" ] || mkdir -p "$_jb_dir" 2>/dev/null || true
    printf '%s\n' "$_jb_remote_ver" > "${_jb_dir}/.latest_version.tmp.$$" 2>/dev/null && mv -f "${_jb_dir}/.latest_version.tmp.$$" "${_jb_dir}/.latest_version" 2>/dev/null || rm -f "${_jb_dir}/.latest_version.tmp.$$" 2>/dev/null || true
    printf '%s\n' "$((_jb_now + 86400))" > "${_jb_dir}/.app_update_next_check.tmp.$$" 2>/dev/null && mv -f "${_jb_dir}/.app_update_next_check.tmp.$$" "${_jb_dir}/.app_update_next_check" 2>/dev/null || rm -f "${_jb_dir}/.app_update_next_check.tmp.$$" 2>/dev/null || true

    echo "Jenbach updated: v${_jb_local_ver} -> v${_jb_remote_ver}"
    exit 0
  )
}
