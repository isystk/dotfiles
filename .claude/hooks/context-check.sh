#!/usr/bin/env bash
# UserPromptSubmit hook: transcriptサイズからコンテキスト増大を簡易検知し、
# 閾値を超えたら handover スキルでの引き継ぎファイル作成をClaudeへ促す。
# セッションごとに一度だけ通知する（/tmp のマーカーファイルで抑制）。

INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('transcript_path', ''))
" 2>/dev/null)

SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session_id', ''))
" 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

# transcript(JSONL)のバイト数をコンテキスト量の目安として使う
THRESHOLD_BYTES=$((8 * 1024 * 1024))
SIZE=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ')

if [ -z "$SIZE" ] || [ "$SIZE" -lt "$THRESHOLD_BYTES" ]; then
  exit 0
fi

MARKER="/tmp/claude-handover-warned-${SESSION_ID}"

if [ -f "$MARKER" ]; then
  exit 0
fi

touch "$MARKER"

python3 -c "
import json
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': 'コンテキストが大きくなっています。区切りが良ければ handover スキルで引き継ぎファイル(HANDOVER.md)を作成するかユーザーへ確認してください。'
    }
}))
"
exit 0
