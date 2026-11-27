#!/usr/bin/env bash
# PreToolUse hook: セッション累計トークンが CLAUDE_COST_LIMIT_TOKENS を超えたら
# permissionDecision "ask" で続行確認を出す。閾値未満・失敗時は何も出力せず exit 0。
# 累計は transcript の message.usage を message.id で重複除去して加算する（追記分のみ読む）。

INPUT=$(cat)

python3 - "$INPUT" <<'PY'
import json
import os
import sys

DEFAULT_LIMIT = 30_000_000
MAX_IDS = 20_000


def main():
    try:
        data = json.loads(sys.argv[1] or "{}")
    except Exception:
        return
    path = data.get("transcript_path") or ""
    sid = data.get("session_id") or ""
    if not path or not sid or not os.path.isfile(path):
        return
    try:
        limit = int(os.environ.get("CLAUDE_COST_LIMIT_TOKENS", DEFAULT_LIMIT))
    except ValueError:
        limit = DEFAULT_LIMIT
    if limit <= 0:
        return

    state_path = "/tmp/claude-cost-%s.json" % sid
    offset, total, warned, seen = 0, 0, 0, set()
    try:
        with open(state_path) as f:
            state = json.load(f)
        offset = int(state.get("offset") or 0)
        total = int(state.get("total") or 0)
        warned = int(state.get("warned") or 0)
        seen = set(state.get("ids") or [])
    except Exception:
        pass

    try:
        size = os.path.getsize(path)
    except OSError:
        return
    # /clear・コンパクション等で transcript が縮んだら集計をやり直す
    if offset > size:
        offset, total, warned, seen = 0, 0, 0, set()

    if size > offset:
        with open(path, "rb") as f:
            f.seek(offset)
            chunk = f.read()
        cut = chunk.rfind(b"\n")
        if cut < 0:
            chunk = b""
        else:
            chunk = chunk[: cut + 1]
            offset += len(chunk)
        for line in chunk.split(b"\n"):
            if not line.strip():
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message")
            if not isinstance(m, dict):
                continue
            u = m.get("usage")
            if not isinstance(u, dict):
                continue
            mid = m.get("id")
            if mid:
                if mid in seen:
                    continue
                seen.add(mid)
            total += (u.get("input_tokens") or 0) + (u.get("output_tokens") or 0) \
                + (u.get("cache_creation_input_tokens") or 0) \
                + (u.get("cache_read_input_tokens") or 0)

    if len(seen) > MAX_IDS * 2:
        seen = set(list(seen)[-MAX_IDS:])

    fire = total >= limit and (warned == 0 or total >= warned + limit)
    if fire:
        warned = total

    try:
        with open(state_path, "w") as f:
            json.dump({"offset": offset, "total": total,
                       "warned": warned, "ids": list(seen)[-MAX_IDS:]}, f)
    except Exception:
        pass

    if not fire:
        return
    reason = ("このセッションの累計トークンが %s に達しました（目安: %s ≒ 実費1ドル相当）。"
              "続行しますか？ 拒否するとそのツール呼び出しは実行されず、作業が止まります。"
              % ("{:.1f}M".format(total / 1e6), "{:.0f}M".format(limit / 1e6)))
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))


try:
    main()
except Exception:
    pass
PY
exit 0
