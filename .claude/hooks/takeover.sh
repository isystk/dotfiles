#!/usr/bin/env bash
# SessionStart hook: プロジェクトルートに未読(read: false)の HANDOVER.md があれば
# 「takeoverスキルで引き継ぎ内容を確認するか」をClaudeへ確認させる。
# 本文は読まず、read フラグの書き換えも行わない（実際の読み込み・確認は takeover スキルが担当）。

INPUT=$(cat)

CWD=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('cwd', ''))
" 2>/dev/null)

if [ -z "$CWD" ]; then
  exit 0
fi

HANDOVER_FILE="$CWD/HANDOVER.md"

if [ ! -f "$HANDOVER_FILE" ]; then
  exit 0
fi

HANDOVER_FILE="$HANDOVER_FILE" python3 << 'EOF'
import os
import re
import json

path = os.environ["HANDOVER_FILE"]
with open(path, encoding="utf-8") as f:
    content = f.read()

m = re.match(r"^---\n(.*?)\n---\n(.*)$", content, re.DOTALL)
if not m:
    raise SystemExit(0)

frontmatter = m.group(1)

if not re.search(r"^read:\s*false\s*$", frontmatter, re.MULTILINE):
    raise SystemExit(0)

context = (
    "未読の引き継ぎファイル(HANDOVER.md)が見つかりました。"
    "内容は読み込んでいません。takeoverスキルで引き継ぎ内容を確認するかユーザーへ確認してください。"
)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context
    }
}))
EOF

exit 0
