#!/usr/bin/env bash
# Stop hook: 最終応答の先頭部分を読み上げる
#   第1候補: VOICEVOX（ずんだもん）を常駐コンテナ経由で合成し、SoX の play で再生
#   第2候補: エンジン不達なら Windows SAPI (WSL の powershell.exe 経由) / macOS の say
# 無効化: ~/.claude/tts-off ファイルを作成する（スキル tts-toggle で切替可）
# 読み: reading_dict.txt / tts_dict.txt を VOICEVOX ユーザー辞書へ自動同期（scripts/voicevox-sync-dict.sh）
# 要約: 応答末尾の <!-- tts: 要約 --> を優先して読む（CLAUDE.md の指示で Claude が付与）
# 調整(環境変数): TTS_MAX_CHARS(既定200) / VOICEVOX_URL(未指定なら 50022 → 50021 の順で疎通した方を使用)
#                 VOICEVOX_SPEAKER(既定3=ずんだもん ノーマル) / VOICEVOX_SPEED(既定1.5, 範囲0.5〜2.0) / TTS_RATE(SAPI用, 既定1)
# 再生: afplay(macOS標準) があれば優先、無ければ SoX の play
# エンジン構築・起動: スキル tts-toggle の「環境セットアップ」を参照。手動なら:
#               docker run -d --name voicevox_engine_tts --restart unless-stopped \
#                 -p 50022:50021 voicevox/voicevox_engine:cpu-ubuntu20.04-latest

set -uo pipefail

# 状態ファイルはユーザー専用ディレクトリに置く（共有の /tmp 直下を避ける）
STATE_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-tts}"
mkdir -p "$STATE_DIR"
PID_FILE="$STATE_DIR/claude-tts.pid"

# --- ワーカーモード: 文ごとに合成し、再生しながら次の文を合成する（フック本体から切り離して実行） ---
if [ "${1:-}" = "--worker" ]; then
  TEXT_FILE="$2"
  # 終了時に PID ファイルを削除する（新しいワーカーが書いたものは消さない）
  trap '[ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ] && rm -f "$PID_FILE"' EXIT
  if [ -z "${VOICEVOX_URL:-}" ]; then
    VOICEVOX_URL="http://localhost:50022"
    for port in 50022 50021; do
      if curl -s -m 1 "http://localhost:$port/version" >/dev/null 2>&1; then
        VOICEVOX_URL="http://localhost:$port"; break
      fi
    done
  fi
  if command -v afplay >/dev/null 2>&1; then PLAYER=afplay; else PLAYER="play -q"; fi
  SPEAKER="${VOICEVOX_SPEAKER:-3}"
  SPEED="${VOICEVOX_SPEED:-1.5}"
  VOICEVOX_URL="$VOICEVOX_URL" PLAYER="$PLAYER" SPEAKER="$SPEAKER" SPEED="$SPEED" TEXT_FILE="$TEXT_FILE" python3 -c '
import os, re, json, queue, threading, subprocess, tempfile, urllib.request, urllib.parse, sys
base, spk, speed = os.environ["VOICEVOX_URL"], os.environ["SPEAKER"], float(os.environ["SPEED"])
text = open(os.environ["TEXT_FILE"], encoding="utf-8").read()
sents = [x for x in re.findall(r"[^。！？!?．]+[。！？!?．]?", text) if x.strip()]
q = queue.Queue()
def synth(t):
    qs = urllib.parse.urlencode({"text": t, "speaker": spk})
    query = json.load(urllib.request.urlopen(urllib.request.Request(f"{base}/audio_query?{qs}", method="POST"), timeout=5))
    query["speedScale"] = speed
    req = urllib.request.Request(f"{base}/synthesis?speaker={spk}", data=json.dumps(query).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    return urllib.request.urlopen(req, timeout=20).read()
def producer():
    for t in sents:
        try:
            wav = synth(t)
        except Exception:
            q.put(None); return
        fd, path = tempfile.mkstemp(suffix=".wav"); os.write(fd, wav); os.close(fd)
        q.put(path)
    q.put("")
threading.Thread(target=producer, daemon=True).start()
first = True
while True:
    item = q.get()
    if item is None:
        sys.exit(2 if first else 0)
    if item == "":
        break
    first = False
    subprocess.run(os.environ["PLAYER"].split() + [item], stderr=subprocess.DEVNULL)
    os.remove(item)
' >/dev/null 2>&1
  rc=$?
  if [ $rc -eq 2 ] && command -v say >/dev/null 2>&1; then
    # フォールバック: macOS say
    say -v Kyoko -f "$TEXT_FILE" >/dev/null 2>&1
  elif [ $rc -eq 2 ] && command -v powershell.exe >/dev/null 2>&1; then
    # フォールバック: Windows SAPI
    WIN_PATH="$(wslpath -w "$TEXT_FILE")"
    powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Speech
\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { \$s.SelectVoice('Microsoft Haruka Desktop') } catch {}
\$s.Rate = ${TTS_RATE:-1}
\$s.Speak([System.IO.File]::ReadAllText('$WIN_PATH', [System.Text.Encoding]::UTF8))
" >/dev/null 2>&1
  fi
  rm -f "$TEXT_FILE"
  exit 0
fi

[ -e "$HOME/.claude/tts-off" ] && exit 0

TEXT_FILE="$(mktemp "$STATE_DIR/claude-tts.XXXXXX")"
DICT_DIR="$HOME/dotfiles/.config/voicevox"

# transcript から最終 assistant テキストを抽出し、読み上げ向けに整形
python3 -c '
import sys, json, re, os
data = json.load(sys.stdin)
text = data.get("last_assistant_message") or ""
if not text:
    path = data.get("transcript_path", "")
    last = ""
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                m = e.get("message", {})
                if e.get("type") != "assistant" or m.get("role") != "assistant":
                    continue
                c = m.get("content", "")
                if isinstance(c, list):
                    c = "\n".join(b.get("text", "") for b in c if b.get("type") == "text")
                if c.strip():
                    last = c
    except Exception:
        pass
    text = last
# 応答末尾の読み上げ用要約 <!-- tts: ... --> があれば最後の1つだけを読む（無ければ従来どおり本文先頭）
tags = re.findall(r"<!--\s*tts:\s*(.*?)\s*-->", text, flags=re.S)
if tags and tags[-1].strip():
    text = tags[-1]
else:
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
text = re.sub(r"```.*?```", " ", text, flags=re.S)
text = re.sub(r"`[^`]*`", " ", text)
text = re.sub(r"https?://\S+", " ", text)
text = re.sub(r"(?:~|\.{1,2})?(?:/[\w.\-]+){2,}/?|~/[\w.\-/]*", " ", text)
text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
text = re.sub(r"[#*>|_~=-]{1,}", " ", text)
text = re.sub(r"\s+", " ", text).strip()
# 英単語をカタカナ化（辞書登録済みの語と全大文字の略語は VOICEVOX 側に任せる）
try:
    import alkana, e2k
    c2k = e2k.C2K()
    known = set()
    for fn in ("reading_dict.txt", "tts_dict.txt"):
        try:
            for ln in open(os.path.expanduser("~/dotfiles/.config/voicevox/" + fn), encoding="utf-8"):
                m = re.match(r"^\s*-\s*(.+?)\s*→", ln)
                if m:
                    known.update(w.lower() for w in re.findall(r"[A-Za-z0-9]+", m.group(1)))
        except Exception:
            pass
    def kana(m):
        w = m.group(0)
        if w.lower() in known or (w.isupper() and len(w) <= 6):
            return w
        # camelCase / PascalCase を分割して語ごとに変換
        parts = re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+", w)
        out = []
        for part in parts:
            lw = part.lower()
            if lw in known or (part.isupper() and len(part) <= 6):
                out.append(part)
            else:
                out.append(alkana.get_kana(lw) or c2k(lw))
        return "".join(out) if out else w
    text = re.sub(r"[A-Za-z]{2,}", kana, text)
except Exception:
    pass
limit = int(os.environ.get("TTS_MAX_CHARS", "200"))
if len(text) > limit:
    cut = text[:limit]
    idx = max(cut.rfind("。"), cut.rfind("．"), cut.rfind("."))
    text = cut[: idx + 1] if idx > 20 else cut
sys.stdout.write(text)
' > "$TEXT_FILE" 2>/dev/null

if [ ! -s "$TEXT_FILE" ]; then
  rm -f "$TEXT_FILE"
  exit 0
fi

# reading_dict.txt / tts_dict.txt が前回同期より新しければ VOICEVOX ユーザー辞書へ同期（失敗しても無視）
SYNC_STAMP="$HOME/.claude/state/voicevox-dict.stamp"
if [ ! -f "$SYNC_STAMP" ] || [ "$DICT_DIR/reading_dict.txt" -nt "$SYNC_STAMP" ] || [ "$DICT_DIR/tts_dict.txt" -nt "$SYNC_STAMP" ]; then
  mkdir -p "$(dirname "$SYNC_STAMP")"
  ( bash "$HOME/dotfiles/scripts/voicevox-sync-dict.sh" >/dev/null 2>&1 && touch "$SYNC_STAMP" ) &
  disown 2>/dev/null || true
fi

# 前回の再生が残っていれば停止（プロセスグループごと）
if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  # 数字以外が入っていたら kill しない（無関係なプロセスを止めないため）
  if [[ "$old_pid" =~ ^[0-9]+$ ]]; then
    kill -- "-$old_pid" 2>/dev/null || kill "$old_pid" 2>/dev/null || true
  fi
fi

# 合成・再生は別プロセスグループで実行し、フックは即終了する
if command -v setsid >/dev/null 2>&1; then
  setsid nohup bash "$(readlink -f "${BASH_SOURCE[0]}")" --worker "$TEXT_FILE" >/dev/null 2>&1 &
else
  # macOS: setsid コマンドが無いため perl で新セッション化する
  nohup perl -MPOSIX -e 'setsid(); exec @ARGV' bash "$(readlink -f "${BASH_SOURCE[0]}")" --worker "$TEXT_FILE" >/dev/null 2>&1 &
fi
echo $! > "$PID_FILE"
disown 2>/dev/null || true

exit 0
