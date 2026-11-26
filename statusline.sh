#!/usr/bin/env bash
AGY_DIR="$HOME/.gemini/antigravity-cli"
JB_DIR="$AGY_DIR/jenbach"
LOG_DIR="$JB_DIR/usage_logs"
CFG_FILE="$JB_DIR/report_config.json"
PRICES_FILE="$JB_DIR/prices.json"
LIB_DIR="$JB_DIR/lib"; [ -f "$LIB_DIR/common.jq" ] || LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"

[ -t 0 ] && { echo "Statusline ready..."; exit 0; }
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && { echo "Statusline ready..."; exit 0; }

printf -v NOW '%(%Y-%m-%d %H:%M)T' -1 2>/dev/null || true
[[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]] || NOW=$(date +"%Y-%m-%d %H:%M")

META=$(printf '%s' "$INPUT" | jq -r '
  (((.session_id // .conversation_id // "none") | tostring | gsub("[^A-Za-z0-9_-]"; "_")) | if . == "" then "none" else . end),
  (if (.subagents | type) == "array" and (.subagents | length) > 0 then
     "\(.subagents | length)_\([.subagents[]? | select((type == "object") and ((.status // "") == "completed"))] | length)"
   else "0_0" end),
  (if (.subagents | type) == "array" and ([.subagents[]? | select((type == "object") and ((.status // "") != "completed"))] | length) > 0 then "true" else "false" end),
  ((.transcript_path // "") | tostring | gsub("[\r\n]+"; ""))
' 2>/dev/null || true)
{
  IFS= read -r SID || true
  IFS= read -r SUB_SIG || true
  IFS= read -r SUB_RUNNING || true
  IFS= read -r TRANSCRIPT_PATH || true
} <<< "$META"
[ -z "$SID" ] && SID="none"
[ -z "$SUB_SIG" ] && SUB_SIG="0_0"
[ -z "$SUB_RUNNING" ] && SUB_RUNNING="false"

PREV_RAW=""; [ -r "$LOG_DIR/${SID}.json" ] && PREV_RAW=$(< "$LOG_DIR/${SID}.json")
if [ "$SID" != "none" ] && { [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ ! -r "$TRANSCRIPT_PATH" ] || [ ! -s "$TRANSCRIPT_PATH" ]; }; then
  TRANSCRIPT_PATH="$AGY_DIR/brain/${SID}/.system_generated/logs/transcript.jsonl"
fi
CUR_PROMPTS=0
_jb_up_re='"user_prompts"[[:space:]]*:[[:space:]]*[1-9]'
if [ "$SID" != "none" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -s "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  if [ ! -f "$LOG_DIR/${SID}.json" ] || [ ! "$LOG_DIR/${SID}.json" -nt "$TRANSCRIPT_PATH" ] || ! [[ "$PREV_RAW" =~ $_jb_up_re ]]; then
    CUR_PROMPTS=$(jq -Rn 'reduce inputs as $l (0; ($l | try fromjson catch null) as $o | if ($o | type) == "object" and $o.type == "USER_INPUT" then . + 1 else . end)' -- "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
    [[ "$CUR_PROMPTS" =~ ^[0-9]+$ ]] || CUR_PROMPTS=0
  fi
fi
CFG_RAW=""; [ -r "$CFG_FILE" ] && CFG_RAW=$(< "$CFG_FILE")
if [ -r "$LIB_DIR/auto_update.sh" ]; then
  . "$LIB_DIR/auto_update.sh"
  jenbach_maybe_update_prices "$JB_DIR" "$CFG_FILE" "$PRICES_FILE" "$CFG_RAW"
  jenbach_maybe_sync_subagents "$LOG_DIR" "$SID" "$AGY_DIR" "$PRICES_FILE" "$LIB_DIR" "$SUB_SIG" "$NOW"
fi
if [ -r "$LIB_DIR/app_update.sh" ]; then
  . "$LIB_DIR/app_update.sh"
  jenbach_maybe_check_app_update "$JB_DIR" "$CFG_FILE" "$CFG_RAW"
fi
PRICES_RAW=""; [ -r "$PRICES_FILE" ] && PRICES_RAW=$(< "$PRICES_FILE")
SUB_RAW=""; [ "$SID" != "none" ] && [ -r "$LOG_DIR/.sub_${SID}.json" ] && SUB_RAW=$(< "$LOG_DIR/.sub_${SID}.json")
SUB_SYNCING="false"; [ "$SID" != "none" ] && [ -d "$LOG_DIR/.sub_${SID}.lock" ] && SUB_SYNCING="true"

FRAME=0
_jb_rt="${EPOCHREALTIME:-}"
_jb_rt="${_jb_rt/,/.}"
if [[ "$_jb_rt" =~ ^([0-9]+)\.([0-9]+) ]]; then
  _jb_sec="${BASH_REMATCH[1]}"
  _jb_usec="${BASH_REMATCH[2]}000000"
  _jb_usec="${_jb_usec:0:6}"
  FRAME=$(( (10#$_jb_sec * 8 + (10#$_jb_usec * 8) / 1000000) % 8 ))
else
  FRAME=$(( ${SECONDS:-0} % 8 ))
fi

OUTPUT=$(printf '%s' "$INPUT" | jq -L "$LIB_DIR" -r --arg now "$NOW" --arg sid "$SID" --arg prev_raw "$PREV_RAW" --arg cfg_raw "$CFG_RAW" --arg prices_raw "$PRICES_RAW" --arg sub_raw "$SUB_RAW" --arg sub_running "$SUB_RUNNING" --arg sub_syncing "$SUB_SYNCING" --argjson sub_frame "$FRAME" --argjson cur_prompts "$CUR_PROMPTS" --arg no_color "${NO_COLOR:-}" '
  include "common";

  ($prev_raw | try fromjson catch {} | if type == "object" then . else {} end) as $prev |
  ($cfg_raw | try fromjson catch {} | if type == "object" then {"statusline_short_tokens":true,"statusline_subagent_detail":true,"chain_enabled":true,"theme":"modern","color":"auto"} + . else {"statusline_short_tokens":true,"statusline_subagent_detail":true,"chain_enabled":true,"theme":"modern","color":"auto"} end) as $cfg |
  ($prices_raw | try fromjson catch {} | if type == "object" then . else {} end) as $prices |
  ($sub_raw | try fromjson catch {} | if type == "object" then . else {} end) as $sub_sidecar |

  ($cfg.theme // "modern") as $theme |
  ($theme == "plain") as $plain |
  ($cfg.color // "auto") as $color_mode |
  (if ($plain or $color_mode == "off" or $no_color != "") then false else true end) as $use_color |
  ($cfg.statusline_short_tokens != false) as $short |
  (.terminal_width // 120) as $tw |

  def qfrac(q):
    if q != null and (q.disabled != true) then q.remaining_fraction else null end;

  ((.model.display_name? // .model.id? // .model // "Model") | tostring | gsub("[\r\n]+"; " ") | if . == "" then "Model" else . end) as $model |
  ($model | ascii_downcase) as $m_low |
  (.context_window.total_input_tokens // 0) as $tot_in |
  (.context_window.total_output_tokens // 0) as $tot_out |
  ((.context_window.used_percentage // 0) | floor) as $ctx_pct |
  ((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0)) as $turn_u |
  (.context_window.current_usage.cache_read_input_tokens // 0) as $cur_c |
  "\($tot_in)_\($turn_u)_\($cur_c)" as $sig |

  ($prev.last_turn_sig // "") as $raw_prev_sig |
  ($raw_prev_sig | split("_")) as $sig_parts |
  (if ($sig_parts | length) == 4 then "\($sig_parts[0])_\($sig_parts[2])_\($sig_parts[3])" else $raw_prev_sig end) as $norm_prev_sig |
  ($sig != $norm_prev_sig) as $sig_changed |

  ($prev.uncached_tokens // 0) as $pu |
  ($prev.cache_tokens // 0) as $pc |
  ($prev.output_tokens // 0) as $po |
  ($prev.last_tot_in // $prev.input_tokens // 0) as $prev_tot_in |
  (if $tot_in > $prev_tot_in then $tot_in else $prev_tot_in end) as $max_tot_in |

  (if ($tot_in > 0 and $sig_changed) then
     (if ($turn_u + $cur_c) > 0 then ($pu + $turn_u)
      else ($pu + (if $tot_in > $prev_tot_in then ($tot_in - $prev_tot_in) else 0 end)) end)
   else $pu end) as $cu |
  (if ($tot_in > 0 and $sig_changed) then ($pc + $cur_c) else $pc end) as $cc |
  (if $tot_out > $po then $tot_out else $po end) as $co |

  ($cu + $cc) as $ci |
  (if $ci > 0 then (($cc * 100 / $ci) | floor) else 0 end) as $cpct |

  (($prices.models | if type == "object" then . else {} end) | to_entries | map(select(.key as $k | $k != "default" and ($m_low | contains($k | ascii_downcase)))) | sort_by([-(.key | length), .key]) | .[0].value // ($prices.models.default? // {}) // {"in":2.0,"cached":0.5,"out":10.0}) as $r |

  ((.subagents | if type == "array" then length else 0 end)) as $sub_total |
  ($prev.main_cost_usd // (if ($prev.cost_usd // 0) >= ($prev.subagent_cost_usd // 0) then (($prev.cost_usd // 0) - ($prev.subagent_cost_usd // 0)) else ($prev.cost_usd // 0) end)) as $prev_main_cost |
  ((($cu - $pu) * ($r["in"] // 2.0) + ($cc - $pc) * ($r["cached"] // 0.5) + ($co - $po) * ($r["out"] // 10.0)) / 1000000) as $main_turn_cost |
  ((.cost.subagent_usd // 0) | if . < 0 then 0 else . end) as $raw_sub |
  ($prev.subagent_cost_usd // 0) as $prev_sub |
  ($sub_sidecar.cost_usd // 0) as $db_sub_cost |
  ($sub_sidecar.records // [] | if type == "array" then . else [] end) as $db_records |
  (if ($db_records | length) > 0 then $db_records else ($prev.subagent_records // [] | if type == "array" then . else [] end) end) as $sub_records |
  ([$prev_sub, $raw_sub, $db_sub_cost] | max) as $sub_cost |
  (if (.cost.total_usd // 0) > 0 then
     .cost.total_usd as $tot |
     (if $tot > $sub_cost then ($tot - $sub_cost) else 0 end)
   else
     ($prev_main_cost + $main_turn_cost)
   end) as $main_cost |
  (if (.cost.total_usd // 0) > 0 then ([.cost.total_usd, ($main_cost + $sub_cost)] | max) else ($main_cost + $sub_cost) end) as $fcost |
  (($sub_total > 0) or ($sub_cost > 0) or (($sub_records | length) > 0) or ($prev.has_subagents == true)) as $has_subagents |

  fmt_usd3($fcost) as $cost_str |
  (if $sub_cost > 0 then (if (($sub_cost * 1000) | round) == 0 then "<$0.001" else fmt_usd3($sub_cost) end) else "" end) as $sub_str |
  ($sub_running == "true" or $sub_syncing == "true") as $is_sub_busy |
  subagent_spinner($sub_frame; $plain) as $sp |
  ($cfg.statusline_subagent_detail != false) as $show_sub_detail |

  (if $show_sub_detail then
     if ($sub_cost > 0 and $is_sub_busy) then
       (if $tw >= 75 then "(Sub: \($sub_str) \($sp))" else $sp end)
     elif ($sub_cost > 0) then
       (if $tw >= 75 then "(Sub: \($sub_str))" else "" end)
     elif $is_sub_busy then
       (if $tw >= 75 then "(\($sp) \($sub_total) sub)" else $sp end)
     else "" end
   else
     (if $is_sub_busy then $sp else "" end)
   end) as $sub_badge |

  (if $sub_badge != "" then "\($cost_str) \($sub_badge)" else $cost_str end) as $cost_disp_plain |
  (paint($cost_str; "bold_yellow"; $use_color) + (if $sub_badge != "" then " " + paint($sub_badge; "magenta"; $use_color) else "" end)) as $cost_disp_color |

  model_quota_bucket($model) as $mbucket |
  (if $mbucket == "gemini-weekly" then qfrac(.quota["gemini-weekly"])
   else (qfrac(.quota[$mbucket]) // qfrac(.quota["gemini-weekly"])) end) as $wf |
  (if $wf != null then "\((($wf * 1000) | round) / 10)%" else "N/A" end) as $wrem |

  hit_color($cpct) as $cache_c |
  (if $ctx_pct < 60 then "green" elif $ctx_pct < 80 then "bold" else "bold_red" end) as $ctx_c |
  (if $wf == null then "dim" elif ($wf * 100) > 30 then "green" elif ($wf * 100) >= 15 then "bold" else "bold_red" end) as $wk_c |

  paint("│"; "dim"; $use_color) as $sep |
  paint("·"; "dim"; $use_color) as $dot |

  (if $plain then
    (if $tw >= 105 then
      "\($model) | In: \(fmt_tok($ci; $short)) (\($cpct)% cache) Out: \(fmt_tok($co; $short)) | Ctx [\(progress_bar($ctx_pct; 6; true))] \($ctx_pct)% | \($cost_disp_plain) | Wk [\(if $wf != null then progress_bar(($wf * 100); 6; true) else "------" end)] \($wrem)"
     elif $tw >= 75 then
      "\(short_model($model; true)) | In: \(fmt_tok($ci; $short)) (\($cpct)%) Out: \(fmt_tok($co; $short)) | Ctx: \($ctx_pct)% | \($cost_disp_plain) | Wk: \($wrem)"
     else
      "\(short_model($model; true)) | Ctx \($ctx_pct)% | \($cost_disp_plain) | Wk \($wrem)"
     end)
   elif ($theme == "modern" and $tw >= 105) then
    "\(paint("◆ \($model)"; "bold_cyan"; $use_color)) \($sep) ↓\(fmt_tok($ci; $short)) \(paint("(\($cpct)% cache)"; $cache_c; $use_color)) ↑\(fmt_tok($co; $short)) \($sep) Ctx \(paint(progress_bar($ctx_pct; 6; false); $ctx_c; $use_color)) \(paint("\($ctx_pct)%"; $ctx_c; $use_color)) \($sep) \($cost_disp_color) \($sep) Wk \(paint((if $wf != null then progress_bar(($wf * 100); 6; false) else "░░░░░░" end); $wk_c; $use_color)) \(paint($wrem; $wk_c; $use_color))"
   elif ($tw >= 75) then
    "\(paint("◆ \(short_model($model; false))"; "bold_cyan"; $use_color)) \($sep) ↓\(fmt_tok($ci; $short)) \(paint("(\($cpct)%)"; $cache_c; $use_color)) ↑\(fmt_tok($co; $short)) \($sep) Ctx \(paint("\($ctx_pct)%"; $ctx_c; $use_color)) \($sep) \($cost_disp_color) \($sep) Wk \(paint($wrem; $wk_c; $use_color))"
   else
    "\(paint("◆ \(short_model($model; false))"; "bold_cyan"; $use_color)) \($dot) Ctx \(paint("\($ctx_pct)%"; $ctx_c; $use_color)) \($dot) \($cost_disp_color) \($dot) Wk \(paint($wrem; $wk_c; $use_color))"
   end) as $hud_line |

  ([($prev.user_prompts | if type == "number" then . else 0 end), $cur_prompts] | max) as $user_prompts |
  (($cu != $pu) or ($cc != $pc) or ($co != $po) or ($max_tot_in != $prev_tot_in) or $sig_changed or ($model != ($prev.model // "")) or ($fcost != ($prev.cost_usd // 0)) or ($sub_cost != $prev_sub) or ($main_cost != ($prev.main_cost_usd // -1)) or ($has_subagents != ($prev.has_subagents // false)) or ($sub_records != ($prev.subagent_records // [])) or ($user_prompts != ($prev.user_prompts | if type == "number" then . else -1 end))) as $state_changed |

  $hud_line,
  (if (($ci > 0 or $fcost > 0) and $sid != "none" and $state_changed) then ({timestamp:$now, session_id:$sid, last_turn_sig:$sig, last_tot_in:$max_tot_in, model:$model, input_tokens:$ci, uncached_tokens:$cu, cache_tokens:$cc, cache_pct:$cpct, output_tokens:$co, main_cost_usd:$main_cost, subagent_cost_usd:$sub_cost, cost_usd:$fcost, has_subagents:$has_subagents, subagent_records:$sub_records, user_prompts:$user_prompts} | tojson) else "" end),
  (if ($cfg.chain_enabled == false) then "" else (($cfg.chained_command // "") | tostring | gsub("[\r\n]+"; " ")) end)
' 2>/dev/null)

if [ -n "$OUTPUT" ]; then
  {
    IFS= read -r LINE1 || true
    IFS= read -r JLOG || true
    IFS= read -r CHAIN_CMD || true
  } <<< "$OUTPUT"

  if [ -n "$JLOG" ] && [ "$SID" != "none" ]; then
    TMP_LOG="$LOG_DIR/.${SID}.tmp.$$"
    printf '%s\n' "$JLOG" > "$TMP_LOG" && mv "$TMP_LOG" "$LOG_DIR/${SID}.json"
  fi

  if [ -n "$CHAIN_CMD" ]; then
    CHAIN_OUT=$(printf '%s' "$INPUT" | eval "$CHAIN_CMD" 2>/dev/null) || true
    [ -n "$CHAIN_OUT" ] && printf '%s\n' "$CHAIN_OUT"
  fi

  printf '%s\n' "$LINE1"
else
  echo "Statusline ready..."
fi
exit 0
