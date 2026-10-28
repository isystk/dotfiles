#!/usr/bin/env python3
"""
claude コマンド（Claude Code CLI）経由で Claude を呼び出す軽量CLI。
API を直接叩かず、ローカルにログイン済みの `claude` コマンドを subprocess 実行する。

使い方:
  echo "$PROMPT" | claude-cli                # テンプレートなし。標準入力をそのままユーザーメッセージとして送信
  echo "$PROMPT" | claude-cli -t <template>   # .config/ai-cli/templates/<template>.yaml を使用
  echo "$PROMPT" | claude-cli -t <template> -a <file>  # ファイルを添付（claude自身にReadさせる）

テンプレート yaml の仕様:
  system: |          # --system-prompt として使用（省略可）
    ...
  prompt: |           # {{ input }} を標準入力全体に置換した文字列をユーザーメッセージにする（省略時は標準入力をそのまま使用）
    {{ input }}
  options:             # 現時点では claude CLI に対応オプションが無いため未使用（将来拡張用に読み込みのみ行う）
    temperature: 0.1
    max_output_tokens: 4000

通常は ai-cli 経由で呼び出す（直接実行も可）。
モデルは settings.json（AI_CLI_PATH配下、既定 ~/.config/ai-cli）の providers.claude で管理する。
  {
    "text_model": "sonnet"   # claude --model に渡すエイリアス or フルネーム
  }
認証は claude コマンドのログインセッションに委譲する（APIキー不要）。
"""
import argparse
import json
import os
import subprocess
import sys

import yaml

PROVIDER = "claude"
CONFIG_DIR = os.path.expanduser(os.environ.get("AI_CLI_PATH", "~/.config/ai-cli"))
TEMPLATE_DIR = os.path.join(CONFIG_DIR, "templates")
SETTINGS_FILE = os.path.join(CONFIG_DIR, "settings.json")


def load_settings():
    if not os.path.isfile(SETTINGS_FILE):
        sys.exit(f"エラー: 設定ファイルが見つかりません: {SETTINGS_FILE}")
    with open(SETTINGS_FILE, encoding="utf-8") as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"エラー: {SETTINGS_FILE} の解析に失敗しました: {e}")
    provider_settings = (settings.get("providers") or {}).get(PROVIDER)
    if not provider_settings:
        sys.exit(f"エラー: {SETTINGS_FILE} に \"providers.{PROVIDER}\" が設定されていません。")
    return provider_settings


def load_model(settings):
    model = settings.get("text_model")
    if not model:
        sys.exit(f"エラー: {SETTINGS_FILE} に \"text_model\" が設定されていません。")
    return model


def load_template(name):
    path = os.path.join(TEMPLATE_DIR, f"{name}.yaml")
    if not os.path.isfile(path):
        sys.exit(f"エラー: テンプレートが見つかりません: {path}")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def build_user_text(template, stdin_text, attach_path=None):
    prompt_template = template.get("prompt")

    if prompt_template:
        user_text = prompt_template.replace("{{ input }}", stdin_text).replace("{{input}}", stdin_text)
    else:
        user_text = stdin_text

    if attach_path:
        user_text += f"\n\n添付ファイル: {attach_path}"

    return user_text


def build_command(model, system_text, attach_path):
    # ユーザーメッセージは引数ではなく標準入力で渡す（Linuxの単一引数上限128KiB超過 E2BIG 回避）
    cmd = [
        "claude", "-p",
        "--model", model,
        "--output-format", "text",
        "--allowedTools", "Read",
    ]
    if system_text:
        cmd += ["--system-prompt", system_text]
    if attach_path:
        cmd += ["--add-dir", os.path.dirname(os.path.abspath(attach_path))]
    return cmd


def call_claude(cmd, user_text):
    try:
        result = subprocess.run(cmd, input=user_text, capture_output=True, text=True)
    except FileNotFoundError:
        sys.exit("エラー: claude コマンドが見つかりません。インストール・PATH設定を確認してください。")

    if result.returncode != 0:
        sys.exit(f"エラー: claude コマンド実行失敗 (code={result.returncode}): {result.stderr}")

    return result.stdout


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-t", "--template", dest="template", default=None)
    parser.add_argument("-a", "--attach", dest="attach", default=None)
    args = parser.parse_args()

    if args.attach and not os.path.isfile(args.attach):
        sys.exit(f"エラー: 添付ファイルが見つかりません: {args.attach}")

    stdin_text = sys.stdin.read()
    template = load_template(args.template) if args.template else {}
    settings = load_settings()
    model = load_model(settings)

    system_text = template.get("system")
    user_text = build_user_text(template, stdin_text, args.attach)

    cmd = build_command(model, system_text, args.attach)
    print(call_claude(cmd, user_text), end="")


if __name__ == "__main__":
    main()
