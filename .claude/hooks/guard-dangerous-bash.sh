#!/usr/bin/env bash
# PreToolUse hook: 危険な Bash コマンドを遮断する
# exit 2 を返すと Claude Code はそのツール呼び出しをキャンセルする

# stdin から JSON を受け取る
INPUT=$(cat)

# tool_input.command を抽出する
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null)
PARSE_STATUS=$?

# python3不在・JSON解析失敗時はコマンド内容を検査できないため、安全側(ブロック)へ倒す
if [ $PARSE_STATUS -ne 0 ]; then
  echo "Guard: tool_input の解析に失敗したため、安全のため実行をブロックしました" >&2
  exit 2
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

# 禁止パターン（正規表現）
DANGEROUS_PATTERNS=(
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f'
  'rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r'
  'rm[[:space:]].*--recursive'
  'rm[[:space:]].*--force'
  'sudo[[:space:]]+rm'
  ':(){:|:&};:'
  'mkfs\.'
  'dd[[:space:]]+if='
  '>[[:space:]]*/dev/sd'
  'curl[^|]*\|[[:space:]]*(ba)?sh'
  'wget[^|]*\|[[:space:]]*(ba)?sh'
  'chmod[[:space:]]+777'
  'git[[:space:]]+push[[:space:]]+(-f|--force)'
)

for PATTERN in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$PATTERN"; then
    # stderr へのメッセージは Claude Code のログに表示される
    echo "Guard: 危険なコマンドパターンを検出したため実行をブロックしました: $COMMAND" >&2
    echo "Guard: パターン: $PATTERN" >&2
    exit 2
  fi
done

exit 0
