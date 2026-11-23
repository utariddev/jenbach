#!/usr/bin/env bash
PURGE=false
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=true ;;
    -h|--help|help)
      echo "Usage: ./uninstall.sh [--purge]"
      echo "  --purge   Also delete all recorded usage_logs and jenbach directory"
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$arg'" >&2
      echo "Usage: ./uninstall.sh [--purge]" >&2
      exit 1
      ;;
  esac
done

AGY_DIR="$HOME/.gemini/antigravity-cli"
JB_DIR="$AGY_DIR/jenbach"
SETTINGS_FILE="$AGY_DIR/settings.json"
CFG_FILE="$JB_DIR/report_config.json"

# Restore chained statusline command or remove .statusLine from settings.json
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
  if jq -e 'type == "object"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    CHAINED_CMD=""
    if [ -f "$CFG_FILE" ] && jq -e 'type == "object"' "$CFG_FILE" >/dev/null 2>&1; then
      CHAINED_CMD=$(jq -r '.chained_command // ""' "$CFG_FILE" 2>/dev/null)
    fi

    if [ -n "$CHAINED_CMD" ]; then
      if TMP_S=$(jq --arg cmd "$CHAINED_CMD" 'if (.statusLine | type) == "object" then .statusLine.command = $cmd else .statusLine = {"type": "command", "command": $cmd, "enabled": true} end' "$SETTINGS_FILE") && [ -n "$TMP_S" ]; then
        printf '%s\n' "$TMP_S" > "${SETTINGS_FILE}.tmp.$$" && mv "${SETTINGS_FILE}.tmp.$$" "$SETTINGS_FILE"
        echo "Restored previous statusline command: $CHAINED_CMD"
      fi
    else
      if TMP_S=$(jq 'del(.statusLine)' "$SETTINGS_FILE") && [ -n "$TMP_S" ]; then
        printf '%s\n' "$TMP_S" > "${SETTINGS_FILE}.tmp.$$" && mv "${SETTINGS_FILE}.tmp.$$" "$SETTINGS_FILE"
        echo "Removed statusLine from $SETTINGS_FILE"
      fi
    fi
  fi
fi

# Remove binaries and symlinks
USR_LOCAL_BIN="${JENBACH_USR_LOCAL_BIN:-/usr/local/bin}"
BREW_BIN="${JENBACH_BREW_BIN:-/opt/homebrew/bin}"
rm -f "$HOME/.local/bin/jenbach"
[ -L "$USR_LOCAL_BIN/jenbach" ] && [ -w "$USR_LOCAL_BIN" ] && rm -f "$USR_LOCAL_BIN/jenbach" || true
[ -L "$BREW_BIN/jenbach" ] && [ -w "$BREW_BIN" ] && rm -f "$BREW_BIN/jenbach" || true
rm -f "$HOME/bin/jenbach" "$HOME/bin/jenbach.cmd" "$HOME/bin/jenbach-statusline.cmd"

if [ "$PURGE" = true ]; then
  cd "$HOME" 2>/dev/null || true
  if [ -d "$JB_DIR" ]; then
    rm -rf "$JB_DIR" 2>/dev/null || echo "Warning: Could not completely remove $JB_DIR (some files may be in use)." >&2
  fi
  echo "Jenbach uninstalled and all usage logs purged."
else
  rm -f "$JB_DIR/statusline.sh" "$JB_DIR/report.sh" "$JB_DIR/VERSION" "$JB_DIR/prices.json" "$JB_DIR/report_config.json" "$JB_DIR/lib/common.jq" "$JB_DIR/lib/auto_update.sh" "$JB_DIR/lib/subagent_sync.py" "$JB_DIR/.prices_next_check" "$JB_DIR/.prices.etag" "$JB_DIR"/.quota_cycles.tmp.* "$JB_DIR/usage_logs"/.sub_*.json "$JB_DIR/usage_logs"/.sub_*.ttl
  rm -rf "$JB_DIR/.prices_update.lock" "$JB_DIR/usage_logs"/.sub_*.lock "$JB_DIR/lib/__pycache__"
  rmdir "$JB_DIR/lib" 2>/dev/null || true
  echo "Jenbach uninstalled. Usage logs preserved in $JB_DIR/usage_logs (use --purge to delete)."
fi
