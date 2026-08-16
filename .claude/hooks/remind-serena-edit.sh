#!/usr/bin/env bash
# PreToolUse hook: コードファイルへの Edit/Write 呼び出し時に
# Serenaのシンボル編集ツール優先を促すリマインダーを注入する（非ブロッキング）

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ti = data.get('tool_input', {})
print(ti.get('file_path', ''))
" 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.php|*.py|*.go|*.rb|*.java|*.kt|*.cs|*.rs|*.vue|*.swift|*.c|*.h|*.cpp|*.hpp|*.scala)
    ;;
  *)
    exit 0
    ;;
esac

python3 -c "
import json
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'additionalContext': 'Serena reminder: for symbol-level or cross-file code changes (rename/move/delete, refactors), prefer Serena tools (rename_symbol / safe_delete_symbol / replace_in_files / replace_symbol_body) over native Edit/Write. Native Edit/Write is fine only for trivial single-file few-line fixes with no cross-file impact.'
    }
}))
"
exit 0
