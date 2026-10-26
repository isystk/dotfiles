#!/usr/bin/env bash
# 概要: 読み辞書（"- 表記 → よみ" 形式。既定は reading_dict.txt と tts_dict.txt）を VOICEVOX エンジンのユーザー辞書へ登録する
#       既存の同一表記は更新、無ければ追加（冪等）。アクセントは平板(0)で登録する。
# 使い方: voicevox-sync-dict.sh [辞書ファイル...]
# 環境変数: VOICEVOX_URL(既定 http://localhost:50022)

set -euo pipefail

if [ $# -gt 0 ]; then DICT_FILES=("$@"); else DICT_FILES=("$HOME/dotfiles/.config/voicevox/reading_dict.txt" "$HOME/dotfiles/.config/voicevox/tts_dict.txt"); fi
VOICEVOX_URL="${VOICEVOX_URL:-http://localhost:50022}"

DICT_FILES_JOINED="$(printf '%s\n' "${DICT_FILES[@]}")" VOICEVOX_URL="$VOICEVOX_URL" python3 -c '
import os, re, sys, json, unicodedata, urllib.request, urllib.parse

base = os.environ["VOICEVOX_URL"]

def call(method, path, params=None):
    url = base + path + ("?" + urllib.parse.urlencode(params) if params else "")
    with urllib.request.urlopen(urllib.request.Request(url, method=method), timeout=10) as r:
        body = r.read()
        return json.loads(body) if body else None

def to_katakana(s):
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in s)

try:
    nfkc = lambda x: unicodedata.normalize("NFKC", x)
    existing = {nfkc(w["surface"]): uid for uid, w in call("GET", "/user_dict").items()}
except Exception as e:
    sys.exit(f"VOICEVOX エンジンに接続できません ({base}): {e}")

added = updated = skipped = 0
for path in os.environ["DICT_FILES_JOINED"].split("\n"):
  if not os.path.isfile(path):
    print(f"skip (辞書ファイルなし): {path}"); continue
  with open(path, encoding="utf-8") as f:
    for line in f:
        m = re.match(r"^\s*-\s*(.+?)\s*→\s*(.+?)\s*$", line)
        if not m:
            continue
        surface, yomi = m.group(1), to_katakana(m.group(2))
        if not re.fullmatch(r"[ァ-ヶー]+", yomi):
            print(f"skip (読みがカタカナ/ひらがな以外): {surface} → {m.group(2)}")
            skipped += 1
            continue
        # surface は VOICEVOX 側で全角化されるため、NFKC 正規化して照合する
        uid = existing.get(nfkc(surface))
        params = {"surface": surface, "pronunciation": yomi, "accent_type": 0}
        try:
            if uid:
                call("PUT", f"/user_dict_word/{uid}", params); updated += 1
            else:
                call("POST", "/user_dict_word", params); added += 1
        except Exception as e:
            print(f"skip (登録失敗): {surface} → {m.group(2)}: {e}")
            skipped += 1

print(f"完了: 追加 {added} / 更新 {updated} / スキップ {skipped}")
'
