#!/usr/bin/env bash
set -e
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required."; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_DIR="$HOME/.gemini/antigravity-cli"
JB_DIR="$AGY_DIR/jenbach"
SETTINGS_FILE="$AGY_DIR/settings.json"
CFG_FILE="$JB_DIR/report_config.json"

mkdir -p "$JB_DIR/usage_logs" "$JB_DIR/lib"
cp -n "$AGY_DIR/usage_logs"/*.json "$JB_DIR/usage_logs/" 2>/dev/null || true
cp "$SCRIPT_DIR/lib/common.jq" "$JB_DIR/lib/common.jq"
cp "$SCRIPT_DIR/lib/auto_update.sh" "$JB_DIR/lib/auto_update.sh"
cp "$SCRIPT_DIR/lib/subagent_sync.py" "$JB_DIR/lib/subagent_sync.py"
cp "$SCRIPT_DIR/statusline.sh" "$JB_DIR/statusline.sh"
cp "$SCRIPT_DIR/report.sh" "$JB_DIR/report.sh"
cp "$SCRIPT_DIR/VERSION" "$JB_DIR/VERSION"
chmod +x "$JB_DIR/statusline.sh" "$JB_DIR/report.sh" "$JB_DIR/lib/subagent_sync.py"

# Preserve newer prices.json if already present
if [ ! -f "$JB_DIR/prices.json" ]; then
  cp "$SCRIPT_DIR/prices.json" "$JB_DIR/prices.json"
else
  REPO_UPD=$(jq -r '.updated_at // "0000-00-00"' "$SCRIPT_DIR/prices.json" 2>/dev/null || echo "0000-00-00")
  CURR_UPD=$(jq -r '.updated_at // "0000-00-00"' "$JB_DIR/prices.json" 2>/dev/null || echo "0000-00-00")
  if [[ "$REPO_UPD" > "$CURR_UPD" ]]; then
    cp "$SCRIPT_DIR/prices.json" "$JB_DIR/prices.json"
  fi
fi

# Migrate or initialize report_config.json atomically without losing existing settings
DEFAULT_CFG='{"short_tokens":true,"statusline_short_tokens":true,"show_history":true,"history_limit":20,"auto_fit_height":true,"chain_enabled":true,"chained_command":"","theme":"modern","color":"auto","auto_update_prices":true,"price_check_interval_hours":24,"prices_url":"https://raw.githubusercontent.com/utariddev/jenbach/main/prices.json","default_view":"cycle","subagent_cost_mode":"split","statusline_subagent_detail":true}'
if [ ! -f "$CFG_FILE" ] || ! jq -e 'type == "object"' "$CFG_FILE" >/dev/null 2>&1; then
  printf '%s\n' "$DEFAULT_CFG" > "${CFG_FILE}.tmp.$$" && mv "${CFG_FILE}.tmp.$$" "$CFG_FILE"
else
  TMP_C=$(jq --argjson def "$DEFAULT_CFG" '$def * .' "$CFG_FILE")
  printf '%s\n' "$TMP_C" > "${CFG_FILE}.tmp.$$" && mv "${CFG_FILE}.tmp.$$" "$CFG_FILE"
fi

# Validate and back up settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{}\n' > "${SETTINGS_FILE}.tmp.$$" && mv "${SETTINGS_FILE}.tmp.$$" "$SETTINGS_FILE"
else
  if ! jq -e 'type == "object"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Error: $SETTINGS_FILE is not valid JSON. Aborting." >&2
    exit 1
  fi
  cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
fi

OLD_CMD=$(jq -r '.statusLine.command // ""' "$SETTINGS_FILE" 2>/dev/null)
if [ -n "$OLD_CMD" ] && [[ "$OLD_CMD" != *"jenbach"* ]]; then
  SKIP_CHAIN=false
  if [[ "$OLD_CMD" == *"antigravity-cli/statusline.sh"* ]] && grep -q "last_turn_sig" "$AGY_DIR/statusline.sh" 2>/dev/null; then
    SKIP_CHAIN=true
  fi
  if [ "$SKIP_CHAIN" = false ]; then
    TMP_C=$(jq --arg c "$OLD_CMD" '.chained_command = $c | .chain_enabled = true' "$CFG_FILE")
    printf '%s\n' "$TMP_C" > "${CFG_FILE}.tmp.$$" && mv "${CFG_FILE}.tmp.$$" "$CFG_FILE"
    echo "Chained previous statusline plugin: $OLD_CMD"
  fi
fi

if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
  mkdir -p "$HOME/bin"
  cp "$JB_DIR/report.sh" "$HOME/bin/jenbach"
  chmod +x "$HOME/bin/jenbach"

  if command -v cygpath >/dev/null 2>&1; then
    BASH_WIN=$(cygpath -w "$(command -v bash)")
    JB_MIXED=$(cygpath -m "$JB_DIR")
    printf '@echo off\r\n"%s" "%s/report.sh" %%*\r\n' "$BASH_WIN" "$JB_MIXED" > "$HOME/bin/jenbach.cmd"
    printf '@echo off\r\n"%s" "%s/statusline.sh"\r\n' "$BASH_WIN" "$JB_MIXED" > "$HOME/bin/jenbach-statusline.cmd"
  else
    cat << EOF > "$HOME/bin/jenbach.cmd"
@echo off
bash "%USERPROFILE%\\.gemini\\antigravity-cli\\jenbach\\report.sh" %*
EOF
    cat << EOF > "$HOME/bin/jenbach-statusline.cmd"
@echo off
bash "%USERPROFILE%\\.gemini\\antigravity-cli\\jenbach\\statusline.sh"
EOF
  fi

  SL_CMD="$HOME/bin/jenbach-statusline.cmd"
  if command -v cygpath >/dev/null 2>&1; then
    WIN_SL=$(cygpath -w "$SL_CMD")
    if [[ "$WIN_SL" == *" "* ]]; then
      WIN_SL=$(cygpath -d "$SL_CMD" 2>/dev/null || printf '%s' "$WIN_SL")
    fi
    SL_CMD="$WIN_SL"
  fi
else
  USR_LOCAL_BIN="${JENBACH_USR_LOCAL_BIN:-/usr/local/bin}"
  BREW_BIN="${JENBACH_BREW_BIN:-/opt/homebrew/bin}"
  mkdir -p "$HOME/.local/bin" && ln -sf "$JB_DIR/report.sh" "$HOME/.local/bin/jenbach"
  [ -d "$USR_LOCAL_BIN" ] && [ -w "$USR_LOCAL_BIN" ] && ln -sf "$JB_DIR/report.sh" "$USR_LOCAL_BIN/jenbach" || true
  [ -d "$BREW_BIN" ] && [ -w "$BREW_BIN" ] && ln -sf "$JB_DIR/report.sh" "$BREW_BIN/jenbach" || true
  SL_CMD="~/.gemini/antigravity-cli/jenbach/statusline.sh"
fi

TMP_S=$(jq --arg cmd "$SL_CMD" '.statusLine = {"type": "command", "command": $cmd, "enabled": true, "stack_with_default": true}' "$SETTINGS_FILE")
printf '%s\n' "$TMP_S" > "${SETTINGS_FILE}.tmp.$$" && mv "${SETTINGS_FILE}.tmp.$$" "$SETTINGS_FILE"

echo "Jenbach installed! Run '!jenbach' inside agy."
if ! command -v jenbach >/dev/null 2>&1; then
  if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
    echo "Note: Add \$HOME/bin to your PATH to run 'jenbach' from the terminal."
  else
    echo "Note: Add \$HOME/.local/bin to your PATH to run 'jenbach' from the terminal."
  fi
fi
