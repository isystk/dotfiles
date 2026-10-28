#!/usr/bin/env bash
# DeepSeek を作業員として Claude Code (claude -p) 経由で実行するラッパー。
# 使い方: run.sh <作業ディレクトリ> <read|edit|full> < 指示文(stdin)
#   read : Read/Grep/Glob のみ（調査・レビュー）
#   edit : read + Edit/Write（作業ディレクトリ内のファイル編集）
#   full : edit + Bash（コマンド実行。最も危険。使用前にユーザー確認）
# 環境変数:
#   DEEPSEEK_API_KEY       APIキー（優先。~/dotfiles/.setenv.local で export）
#   DEEPSEEK_API_KEY_FILE  APIキーのファイル (未設定時の代替。既定: ~/.config/deepseek/api_key)
#   DEEPSEEK_MODEL         モデル名 (既定: deepseek-flash。高精度は deepseek-v4-pro)
#   DEEPSEEK_MAX_USD       上限金額USD (既定: 1)
set -euo pipefail

workdir="${1:-}"
mode="${2:-read}"

if [[ -z "$workdir" || ! -d "$workdir" ]]; then
  echo "usage: run.sh <workdir> <read|edit|full> < prompt" >&2
  exit 2
fi

# APIキー: 環境変数 DEEPSEEK_API_KEY を優先、なければキーファイル
api_key="${DEEPSEEK_API_KEY:-}"
if [[ -z "$api_key" ]]; then
  key_file="${DEEPSEEK_API_KEY_FILE:-$HOME/.config/deepseek/api_key}"
  if [[ -r "$key_file" ]]; then
    api_key="$(tr -d '[:space:]' < "$key_file")"
  fi
fi
if [[ -z "$api_key" ]]; then
  echo "APIキーが見つかりません: 環境変数 DEEPSEEK_API_KEY またはキーファイル (SKILL.md のセットアップ参照)" >&2
  exit 3
fi

case "$mode" in
  read) tools="Read,Grep,Glob" ;;
  edit) tools="Read,Grep,Glob,Edit,Write" ;;
  full) tools="Read,Grep,Glob,Edit,Write,Bash" ;;
  *) echo "mode は read|edit|full" >&2; exit 2 ;;
esac

# read モードでは Edit/Write の自動承認（acceptEdits）を無効にする
permission_mode="acceptEdits"
[[ "$mode" == "read" ]] && permission_mode="default"

model="${DEEPSEEK_MODEL:-deepseek-flash}"
max_usd="${DEEPSEEK_MAX_USD:-1}"

cd "$workdir"

# 秘密ファイルの読み書きは禁止する（下の --disallowedTools）。
# ただし full モードは Bash 経由で読めるため補助的なガードにすぎない。
# --bare: フック・CLAUDE.md自動読込・keychain・auto-memory を無効化
# （親セッションのフックや社内ルールが DeepSeek へ流出しない・干渉しない）
# --bare では Anthropic 認証が ANTHROPIC_API_KEY（または apiKeyHelper）に限定される。
# ANTHROPIC_AUTH_TOKEN へ変えると --bare では認証されないので置き換えないこと。
ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" \
ANTHROPIC_API_KEY="$api_key" \
ANTHROPIC_MODEL="$model" \
ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-flash" \
CLAUDE_CODE_SUBAGENT_MODEL="deepseek-flash" \
exec claude -p --bare \
  --model "$model" \
  --allowedTools "$tools" \
  --disallowedTools \
    "Read(**/.env*)" "Edit(**/.env*)" "Write(**/.env*)" \
    "Read(**/.setenv.local*)" "Edit(**/.setenv.local*)" "Write(**/.setenv.local*)" \
    "Read(**/*.pem)" "Edit(**/*.pem)" "Write(**/*.pem)" \
    "Read(**/*.key)" "Edit(**/*.key)" "Write(**/*.key)" \
    "Read(**/id_rsa*)" "Edit(**/id_rsa*)" "Write(**/id_rsa*)" \
    "Read(**/auth.json)" "Edit(**/auth.json)" "Write(**/auth.json)" \
    "Read(**/credentials*)" "Edit(**/credentials*)" "Write(**/credentials*)" \
  --permission-mode "$permission_mode" \
  --max-budget-usd "$max_usd" \
  --no-session-persistence \
  --output-format text
