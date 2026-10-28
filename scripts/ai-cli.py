#!/usr/bin/env python3
"""
利用するAIプロバイダを設定で切り替える薄いディスパッチャCLI。
実処理は gemini-cli / chatgpt-cli / claude-cli に委譲する（引数・標準入出力・終了コードは透過）。

使い方（引数は各プロバイダCLIと共通）:
  echo "$PROMPT" | ai-cli                          # 既定プロバイダで実行
  echo "$PROMPT" | ai-cli -t <template>             # テンプレート別のルーティングに従う
  echo "$PROMPT" | ai-cli -t <template> -a <file>   # ファイル添付
  echo "$PROMPT" | ai-cli --image -o <file.png>     # 画像生成
  echo "$PROMPT" | ai-cli -p claude                 # プロバイダを明示（最優先）

プロバイダの決定順:
  1. -p / --provider
  2. 環境変数 AI_PROVIDER
  3. settings.json の routing.templates[<template>]
  4. settings.json の routing.default.image / routing.default.text

設定は settings.json（AI_CLI_PATH配下、既定 ~/.config/ai-cli）で管理する。
  {
    "providers": {          # モデル設定（各プロバイダCLIが参照）
      "gemini": {
        "text_model": "...",
        "image_model": "..."
      },
      "chatgpt": {
        "text_model": "...",
        "image_model": "..."
      },
      "claude": {
        "text_model": "..."
      }
    },
    "routing": {
      "default": {
        "text": "gemini",
        "image": "chatgpt"
      },
      "templates": {
        "blog-thumb": "chatgpt"
      }
    }
  }
"""
import json
import os
import sys

CONFIG_DIR = os.path.expanduser(os.environ.get("AI_CLI_PATH", "~/.config/ai-cli"))
SETTINGS_FILE = os.path.join(CONFIG_DIR, "settings.json")

# プロバイダ名 -> (実行コマンド, 画像生成対応)
PROVIDERS = {
    "gemini": ("gemini-cli", True),
    "chatgpt": ("chatgpt-cli", True),
    "claude": ("claude-cli", False),
}


def load_settings():
    if not os.path.isfile(SETTINGS_FILE):
        sys.exit(f"エラー: 設定ファイルが見つかりません: {SETTINGS_FILE}")
    with open(SETTINGS_FILE, encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"エラー: {SETTINGS_FILE} の解析に失敗しました: {e}")


def split_args(argv):
    """-p/--provider を取り除き、(provider, template, image, 転送用引数) を返す。"""
    provider = None
    template = None
    image = False
    forward = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-p", "--provider"):
            if i + 1 >= len(argv):
                sys.exit(f"エラー: {arg} には値が必要です。")
            provider = argv[i + 1]
            i += 2
            continue
        if arg.startswith("--provider="):
            provider = arg.split("=", 1)[1]
            i += 1
            continue
        if arg in ("-t", "--template") and i + 1 < len(argv):
            template = argv[i + 1]
            forward += [arg, argv[i + 1]]
            i += 2
            continue
        if arg == "--image":
            image = True
        forward.append(arg)
        i += 1
    return provider, template, image, forward


def resolve_provider(explicit, template, image, settings):
    if explicit:
        return explicit, "-p"
    env = os.environ.get("AI_PROVIDER")
    if env:
        return env, "AI_PROVIDER"

    routing = settings.get("routing") or {}
    by_template = (routing.get("templates") or {}).get(template) if template else None
    if by_template:
        return by_template, f"routing.templates.{template}"

    kind = "image" if image else "text"
    default = (routing.get("default") or {}).get(kind)
    if not default:
        sys.exit(f"エラー: {SETTINGS_FILE} に \"routing.default.{kind}\" が設定されていません。")
    return default, f"routing.default.{kind}"


def main():
    explicit, template, image, forward = split_args(sys.argv[1:])
    settings = load_settings()
    provider, source = resolve_provider(explicit, template, image, settings)

    if provider not in PROVIDERS:
        sys.exit(f"エラー: 未対応のプロバイダです: {provider} ({source}) 対応: {', '.join(PROVIDERS)}")

    command, supports_image = PROVIDERS[provider]
    if image and not supports_image:
        sys.exit(f"エラー: プロバイダ {provider} ({source}) は画像生成(--image)に対応していません。")

    try:
        os.execvp(command, [command, *forward])
    except FileNotFoundError:
        sys.exit(f"エラー: {command} コマンドが見つかりません。install.sh を実行してください。")


if __name__ == "__main__":
    main()
