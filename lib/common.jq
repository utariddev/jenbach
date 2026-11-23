def repeat_str($s; $n):
  if $n > 0 then ($s * $n) else "" end;

def fmt_tok($n; $short):
  if ($short == false) then ($n | tostring)
  elif $n >= 999950 then "\((($n / 100000) | round) / 10)M"
  elif $n >= 1000 then "\((($n / 100) | round) / 10)k"
  else ($n | tostring) end;

def fmt_usd3($x):
  ((($x // 0) | if . < 0 then 0 else . end) * 1000 | round) as $m |
  ($m / 1000 | floor) as $whole |
  ("000" + ($m % 1000 | tostring))[-3:] as $frac |
  "$\($whole).\($frac)";

def fmt_sub_cell($x):
  (($x // 0) | if . < 0 then 0 else . end) as $v |
  if $v <= 0 then "-"
  elif (($v * 1000) | round) == 0 then "<$0.001"
  else fmt_usd3($v) end;

def subagent_spinner($frame; $plain):
  (if $plain then ["|","/","-","\\","|","/","-","\\"] else ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧"] end) as $frames |
  ((($frame // 0) | floor | if . < 0 then -(. ) else . end) % 8) as $idx |
  $frames[$idx];

def ansi_code($name):
  if   $name == "reset"       then "\u001b[0m"
  elif $name == "bold"        then "\u001b[1m"
  elif $name == "dim"         then "\u001b[90m"
  elif $name == "red"         then "\u001b[31m"
  elif $name == "green"       then "\u001b[32m"
  elif $name == "yellow"      then "\u001b[33m"
  elif $name == "cyan"        then "\u001b[36m"
  elif $name == "magenta"     then "\u001b[35m"
  elif $name == "bold_cyan"   then "\u001b[1;36m"
  elif $name == "bold_yellow" then "\u001b[1;33m"
  elif $name == "bold_white"  then "\u001b[1;37m"
  elif $name == "bold_green"  then "\u001b[1;32m"
  elif $name == "bold_red"    then "\u001b[1;31m"
  else "" end;

def paint($text; $style; $use_color):
  if $use_color and $style != "" and $text != "" then
    ansi_code($style) + $text + ansi_code("reset")
  else $text end;

def hit_color($pct):
  if ($pct | type) != "number" then "dim"
  elif $pct >= 80 then "bold_green"
  elif $pct >= 50 then "green"
  else "dim" end;

def think_color($t):
  (($t // "") | tostring | ascii_downcase) as $tl |
  if $tl == "high" then "bold"
  elif $tl == "medium" then ""
  else "dim" end;

def progress_bar($pct; $width; $plain):
  (($pct // 0) | if . < 0 then 0 elif . > 100 then 100 else . end) as $p |
  (if $width <= 0 then 0
   elif $p <= 0 then 0
   elif $p >= 100 then $width
   elif $width == 1 then 1
   else (($p * $width / 100 | floor) | if . < 1 then 1 elif . >= $width then ($width - 1) else . end)
   end) as $f |
  if $plain then (repeat_str("#"; $f) + repeat_str("-"; $width - $f))
  else (repeat_str("▓"; $f) + repeat_str("░"; $width - $f)) end;

def pad_cell($text; $w; $align):
  ($w - ($text | length)) as $pad |
  if $align == "r" then (repeat_str(" "; $pad) + $text)
  else ($text + repeat_str(" "; $pad)) end;

def short_model($m; $plain):
  ($m | sub("^(Gemini|Claude|Google)[ ]+"; ""; "i")) as $s |
  if ($s | length) > 16 then
    if $plain then ($s[0:13] + "...") else ($s[0:15] + "…") end
  else $s end;

def split_model_think($m):
  (($m // "Unknown") | tostring | if . == "" then "Unknown" else . end) as $s |
  if ($s | test("^.+?[ ]*\\((Low|Medium|High|Minimal)\\)$"; "i")) then
    ($s | sub("[ ]*\\((Low|Medium|High|Minimal)\\)$"; ""; "i")) as $base |
    ($s | sub("^.*\\("; "") | sub("\\)$"; "")) as $think |
    {base: (if $base == "" then $s else $base end), think: $think}
  else
    {base: $s, think: "-"}
  end;

def merge_segments($segs):
  reduce $segs[] as $s (
    [];
    if (length > 0) and ((.[-1].c // "") == ($s.c // "")) then
      .[-1].t += ($s.t // "")
    else
      . + [{t: ($s.t // ""), c: ($s.c // "")}]
    end
  );

def render_table($headers; $aligns; $rows; $plain; $use_color; $target_w):
  ($headers | length) as $ncols |
  [range(0; $ncols) as $i |
    ([$headers[$i] | length] + [$rows[] | (.cells[$i].t // "" | length)]) | max
  ] as $widths |
  ($ncols - 1) as $ngaps |
  (($widths | add) + ($ngaps * 2)) as $min_w |
  (if $ngaps > 0 then ([ $min_w, ($target_w // 0) ] | max) else $min_w end) as $total_w |
  ($total_w - $min_w) as $extra |
  [range(0; $ngaps) as $g |
    (if $ngaps > 0 then (2 + (($extra / $ngaps) | floor) + (if $g < ($extra % $ngaps) then 1 else 0 end)) else 0 end) as $gw |
    repeat_str(" "; $gw)
  ] as $gaps |
  (if $plain then "-" else "─" end) as $sep_char |
  (repeat_str($sep_char; $total_w)) as $sep_line |
  (
    [range(0; $ncols) as $i |
      pad_cell($headers[$i]; $widths[$i]; $aligns[$i]) + (if $i < $ngaps then $gaps[$i] else "" end)
    ] | add | paint(.; "bold"; $use_color)
  ),
  paint($sep_line; "dim"; $use_color),
  (
    $rows[] |
    . as $row |
    (if $row.sep_before then paint($sep_line; "dim"; $use_color) else empty end),
    (
      [range(0; $ncols) as $i |
        ($row.cells[$i] // {t: "", c: ""}) as $cell |
        (if ($cell.c // "") != "" then $cell.c elif $row.bold_row then "bold" else "" end) as $style |
        (pad_cell(($cell.t // ""); $widths[$i]; $aligns[$i]) | paint(.; $style; $use_color)) + (if $i < $ngaps then $gaps[$i] else "" end)
      ] | add
    )
  );

def render_table($headers; $aligns; $rows; $plain; $use_color):
  render_table($headers; $aligns; $rows; $plain; $use_color; 0);

def render_kpi_box($title; $lines; $plain; $use_color; $target_w):
  ([$lines[] | (map(.t | length) | add // 0)] | max // 0) as $max_line_len |
  ([74, ($max_line_len + 4), (($title | length) + 6), (($target_w // 0) - 2)] | max) as $inner |
  (if $plain then
    ("+-- " + $title + " " + repeat_str("-"; $inner - ($title | length) - 4) + "+")
  else
    ("╭─ " + $title + " " + repeat_str("─"; $inner - ($title | length) - 3) + "╮")
  end) as $top |
  (if $plain then
    ("+" + repeat_str("-"; $inner) + "+")
  else
    ("╰" + repeat_str("─"; $inner) + "╯")
  end) as $bot |
  (if $plain then "|" else "│" end) as $vbar |
  paint($top; "dim"; $use_color),
  (
    $lines[] |
    merge_segments(.) as $m_line |
    ($m_line | map(.t | length) | add // 0) as $vis_len |
    ($m_line | map(paint(.t; (.c // ""); $use_color)) | add // "") as $body |
    (paint($vbar; "dim"; $use_color) + " " + $body + repeat_str(" "; $inner - $vis_len - 2) + " " + paint($vbar; "dim"; $use_color))
  ),
  paint($bot; "dim"; $use_color);

def render_kpi_box($title; $lines; $plain; $use_color):
  render_kpi_box($title; $lines; $plain; $use_color; 76);

def model_quota_bucket($m):
  (($m // "") | tostring | ascii_downcase) as $ml |
  if ($ml | contains("argon")) or ($ml | contains("carbon")) then "gemini-argon-wtu-weekly"
  elif ($ml | contains("gemini")) or ($ml | contains("flash")) or ($ml | contains("hydrogen")) or ($ml | contains("neon")) then "gemini-weekly"
  else "3p-weekly" end;

def fmt_bucket_name($b):
  if   $b == "gemini-weekly"           then "Gemini (Weekly)"
  elif $b == "gemini-argon-wtu-weekly" then "Gemini Argon (Weekly)"
  elif $b == "3p-weekly"               then "Claude / 3P (Weekly)"
  else ($b // "unknown" | tostring) end;

def parse_iso_epoch($s):
  (($s // "") | tostring | sub("\\.[0-9]+Z$"; "Z")) as $clean |
  if ($clean | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) then
    ($clean | try fromdateiso8601 catch 0)
  else 0 end;

def fmt_iso_utc($s):
  (($s // "") | tostring) as $raw |
  if ($raw | length) >= 16 and ($raw | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}")) then
    "\($raw[0:10]) \($raw[11:16])"
  elif ($raw | length) > 0 then $raw
  else "N/A" end;

def is_bogus_reset($r):
  (($r | type) == "object") and
  (($r.reason // "") == "reset_time_changed") and
  ((($r.prev_remaining | type) == "number") and ($r.prev_remaining >= 0.995)) and
  ((($r.new_remaining | type) == "number") and ($r.new_remaining >= 0.995));

def sanitize_quota_buckets($raw_buckets):
  ($raw_buckets | if type == "object" then . else {} end) |
  with_entries(
    select((.value | type) == "object") |
    (.value.resets | if type == "array" then . else [] end) as $raw_resets |
    ($raw_resets | map(select((type == "object") and (is_bogus_reset(.) | not)))) as $clean_resets |
    .value.resets = $clean_resets |
    if ($clean_resets | length) != ($raw_resets | length) then
      if ($clean_resets | length) == 0 then
        .value.cycle_started_at = ""
      else
        .value.cycle_started_at = ($clean_resets[-1].detected_at // .value.cycle_started_at // "")
      end
    else . end
  );
