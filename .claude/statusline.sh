#!/bin/bash
input=$(cat)
NOW=$(date +%s)

# --- ANSIカラー ---
CYAN='\033[36m' YELLOW='\033[33m' RED='\033[31m'
GREEN='\033[32m' MAGENTA='\033[35m' DIM='\033[2m' RESET='\033[0m'

# --- ユーティリティ関数 ---

color_for_pct() {
  if [ "$1" -ge 80 ] 2>/dev/null; then printf '%b' "$RED"
  elif [ "$1" -ge 50 ] 2>/dev/null; then printf '%b' "$YELLOW"
  else printf '%b' "$GREEN"; fi
}

progress_bar() {
  local f=$(( ($1 + 5) / 10 ))
  [ "$f" -gt 10 ] && f=10; [ "$f" -lt 0 ] && f=0
  local bar="▰▰▰▰▰▰▰▰▰▰"
  local empty="▱▱▱▱▱▱▱▱▱▱"
  printf '%s%s' "${bar:0:$f}" "${empty:0:$((10-f))}"
}

bar_line() {
  local label="$1" pct="$2" reset_str="${3:-}"
  if [ -n "$pct" ]; then
    printf '%b%s %s %3s%%%b%s' "$(color_for_pct "$pct")" "$label" "$(progress_bar "$pct")" "$pct" "$RESET" "$reset_str"
  else
    printf '%b%s ▱▱▱▱▱▱▱▱▱▱  --%% %b' "$DIM" "$label" "$RESET"
  fi
}

format_reset() {
  local epoch="$1"
  [ -z "$epoch" ] || [ "$epoch" = "0" ] || [ "$epoch" = "null" ] && return
  local rem=$(( epoch - NOW ))
  [ "$rem" -le 0 ] && return
  local d=$(( rem / 86400 )) h=$(( rem % 86400 / 3600 )) m=$(( rem % 3600 / 60 ))
  if [ "$d" -gt 0 ]; then   printf ' %d日 %2d時間 %2d分でリセット' "$d" "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf '     %2d時間 %2d分でリセット' "$h" "$m"
  else                       printf '            %2d分でリセット' "$m"; fi
}

# --- stdin JSON パース ---
eval "$(echo "$input" | jq -r '
  "MODEL=" + (.model.display_name // "Unknown" | @sh),
  "EFFORT=" + (.effort.level // "" | @sh),
  "CTX_SIZE=" + (.context_window.context_window_size // 200000 | tostring),
  "CTX_USED_PCT=" + (.context_window.used_percentage // 0 | tostring),
  "CTX_INPUT=" + ((.context_window.current_usage.input_tokens // 0) | tostring),
  "CTX_CACHE_CREATE=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
  "CTX_CACHE_READ=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
  "CTX_HAS_USAGE=" + (if .context_window.current_usage then "1" else "0" end),
  "CWD=" + (.workspace.current_dir // "." | @sh),
  "LINES_ADD=" + (.cost.total_lines_added // 0 | tostring),
  "LINES_DEL=" + (.cost.total_lines_removed // 0 | tostring),
  "FIVE_PCT=" + (.rate_limits.five_hour.used_percentage // empty | floor | tostring),
  "FIVE_RESET_EPOCH=" + (.rate_limits.five_hour.resets_at // 0 | tostring),
  "SEVEN_PCT=" + (.rate_limits.seven_day.used_percentage // empty | floor | tostring),
  "SEVEN_RESET_EPOCH=" + (.rate_limits.seven_day.resets_at // 0 | tostring)
' 2>/dev/null)"

if [ "$CTX_HAS_USAGE" = "1" ]; then
  CTX_PCT=$(( (CTX_INPUT + CTX_CACHE_CREATE + CTX_CACHE_READ) * 100 / CTX_SIZE ))
else
  CTX_PCT=${CTX_USED_PCT%%.*}
fi

# --- Gitブランチ ---
GIT_BRANCH=""
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null)
  [ -n "$BRANCH" ] && GIT_BRANCH=" | ${MAGENTA}${BRANCH}${RESET}"
fi

# --- レートリミット（stdin JSONから取得） ---
FIVE_RESET=$(format_reset "$FIVE_RESET_EPOCH")
SEVEN_RESET=$(format_reset "$SEVEN_RESET_EPOCH")

# --- 出力 ---
LINE_STATS=""
if [ "$LINES_ADD" -gt 0 ] 2>/dev/null || [ "$LINES_DEL" -gt 0 ] 2>/dev/null; then
  LINE_STATS=" | ${GREEN}+${LINES_ADD}${RESET}/${RED}-${LINES_DEL}${RESET}"
fi

EFFORT_STR=""
[ -n "$EFFORT" ] && EFFORT_STR=" ${DIM}[${EFFORT}]${RESET}"

printf '%b\n' "$(bar_line "cx" "$CTX_PCT") | ${CYAN}${MODEL}${RESET}${EFFORT_STR}${GIT_BRANCH}${LINE_STATS}"
printf '%b\n' "$(bar_line "5h" "$FIVE_PCT") |$FIVE_RESET"
printf '%b'   "$(bar_line "7d" "$SEVEN_PCT") |$SEVEN_RESET"
