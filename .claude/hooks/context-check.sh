#!/usr/bin/env bash
# UserPromptSubmit hook: transcript 末尾の usage から実コンテキストトークン量を算出し、
# 閾値(既定200k)超で /compact もしくは handover → /clear をClaudeへ促す。
# 一度通知したら、さらに STEP トークン増えるまで再通知しない（/tmp のマーカーで抑制）。

INPUT=$(cat)

python3 -c '
import sys, json, os
data = json.loads(sys.argv[1] or "{}")
path = data.get("transcript_path", "")
sid = data.get("session_id", "")
if not path or not os.path.isfile(path) or not sid:
    sys.exit(0)

THRESHOLD = int(os.environ.get("CONTEXT_WARN_TOKENS", 200000))
STEP = int(os.environ.get("CONTEXT_WARN_STEP", 100000))

used = 0
with open(path, errors="ignore") as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message")
        u = m.get("usage") if isinstance(m, dict) else None
        if u:
            used = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                    + u.get("cache_creation_input_tokens", 0))

if used < THRESHOLD:
    sys.exit(0)

marker = f"/tmp/claude-context-warned-{sid}"
last = 0
try:
    last = int(open(marker).read().strip() or 0)
except Exception:
    pass
# /compact 等で使用量が減った場合はマーカーをリセット扱いにする
if last > used:
    last = 0
if last and used < last + STEP:
    sys.exit(0)
open(marker, "w").write(str(used))

msg = (f"コンテキストが約{used//1000}kトークンに達しています（長いセッションほど毎ターンの消費が増える）。"
       "作業の区切りで、ユーザーへ次のいずれかを提案してください: "
       "(a) 同じ作業を続けるなら /compact、"
       "(b) 別作業へ移るなら handover スキルで HANDOVER.md を保存してから /clear。")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": msg}}))
' "$INPUT"
exit 0
