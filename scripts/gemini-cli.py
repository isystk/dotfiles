#!/usr/bin/env python3
"""
Gemini API を直接呼び出す軽量CLI。

使い方:
  echo "$PROMPT" | gemini-cli                # テンプレートなし。標準入力をそのままユーザーメッセージとして送信
  echo "$PROMPT" | gemini-cli -t <template>   # .config/gemini-cli/templates/<template>.yaml を使用
  echo "$PROMPT" | gemini-cli -t <template> -a <file>  # ファイルを添付（Files APIへアップロードして参照）
  echo "$PROMPT" | gemini-cli --image -o <file.png>    # 画像を生成し、指定パスに保存

テンプレート yaml の仕様:
  system: |          # system_instruction として使用（省略可）
    ...
  prompt: |           # {{ input }} を標準入力全体に置換した文字列をユーザーメッセージにする（省略時は標準入力をそのまま使用）
    {{ input }}
  options:
    temperature: 0.1
    max_output_tokens: 4000

モデルは settings.json（GEMINI_CLI_PATH配下、既定 ~/.config/gemini-cli）で管理する。
  {
    "text_model": "...",   # 通常のテキスト生成で使用
    "image_model": "..."   # --image 指定時に使用
  }
APIキーは環境変数 GEMINI_API_KEY から取得する。
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

import yaml

CONFIG_DIR = os.path.expanduser(os.environ.get("GEMINI_CLI_PATH", "~/.config/gemini-cli"))
TEMPLATE_DIR = os.path.join(CONFIG_DIR, "templates")
SETTINGS_FILE = os.path.join(CONFIG_DIR, "settings.json")
API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
FILES_BASE = "https://generativelanguage.googleapis.com/v1beta"
UPLOAD_BASE = "https://generativelanguage.googleapis.com/upload/v1beta/files"


def load_settings():
    if not os.path.isfile(SETTINGS_FILE):
        sys.exit(f"エラー: 設定ファイルが見つかりません: {SETTINGS_FILE}")
    with open(SETTINGS_FILE, encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"エラー: {SETTINGS_FILE} の解析に失敗しました: {e}")


def load_model(settings, key):
    model = settings.get(key)
    if not model:
        sys.exit(f"エラー: {SETTINGS_FILE} に \"{key}\" が設定されていません。")
    return model.removeprefix("gemini/")


def load_template(name):
    path = os.path.join(TEMPLATE_DIR, f"{name}.yaml")
    if not os.path.isfile(path):
        sys.exit(f"エラー: テンプレートが見つかりません: {path}")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def upload_file(path, api_key):
    """ファイルを Gemini Files API にアップロードし、(file_uri, mime_type) を返す。"""
    if not os.path.isfile(path):
        sys.exit(f"エラー: 添付ファイルが見つかりません: {path}")

    mime_type = mimetypes.guess_type(path)[0] or "application/octet-stream"
    size = os.path.getsize(path)
    display_name = os.path.basename(path)

    start_req = urllib.request.Request(
        f"{UPLOAD_BASE}?key={api_key}",
        data=json.dumps({"file": {"display_name": display_name}}).encode("utf-8"),
        headers={
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": str(size),
            "X-Goog-Upload-Header-Content-Type": mime_type,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(start_req) as res:
            upload_url = res.headers.get("X-Goog-Upload-URL")
    except urllib.error.HTTPError as e:
        sys.exit(f"エラー: ファイルアップロード開始失敗 ({e.code}): {e.read().decode('utf-8', errors='ignore')}")

    if not upload_url:
        sys.exit("エラー: アップロードURLの取得に失敗しました。")

    with open(path, "rb") as f:
        file_bytes = f.read()

    upload_req = urllib.request.Request(
        upload_url,
        data=file_bytes,
        headers={
            "Content-Length": str(size),
            "X-Goog-Upload-Offset": "0",
            "X-Goog-Upload-Command": "upload, finalize",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(upload_req) as res:
            file_info = json.loads(res.read().decode("utf-8"))["file"]
    except urllib.error.HTTPError as e:
        sys.exit(f"エラー: ファイルアップロード失敗 ({e.code}): {e.read().decode('utf-8', errors='ignore')}")

    file_name = file_info["name"]
    state = file_info.get("state", "ACTIVE")

    # 動画・音声はサーバー側で処理中(PROCESSING)の場合があるため、ACTIVEになるまで待つ
    while state == "PROCESSING":
        time.sleep(2)
        status_req = urllib.request.Request(f"{FILES_BASE}/{file_name}?key={api_key}")
        with urllib.request.urlopen(status_req) as res:
            file_info = json.loads(res.read().decode("utf-8"))
        state = file_info.get("state", "ACTIVE")

    if state != "ACTIVE":
        sys.exit(f"エラー: ファイル処理に失敗しました (state={state})")

    return file_info["uri"], file_info.get("mimeType", mime_type)


def build_payload(template, stdin_text, attachment=None, image_mode=False):
    system_text = template.get("system")
    prompt_template = template.get("prompt")

    if prompt_template:
        user_text = prompt_template.replace("{{ input }}", stdin_text).replace("{{input}}", stdin_text)
    else:
        user_text = stdin_text

    parts = [{"text": user_text}]
    if attachment:
        file_uri, mime_type = attachment
        parts.append({"file_data": {"mime_type": mime_type, "file_uri": file_uri}})

    payload = {"contents": [{"role": "user", "parts": parts}]}

    if system_text:
        payload["system_instruction"] = {"parts": [{"text": system_text}]}

    options = template.get("options") or {}
    generation_config = {}
    if "temperature" in options:
        generation_config["temperature"] = options["temperature"]
    if "max_output_tokens" in options:
        generation_config["maxOutputTokens"] = options["max_output_tokens"]
    if image_mode:
        generation_config["responseModalities"] = ["IMAGE"]
    if generation_config:
        payload["generationConfig"] = generation_config

    return payload


def call_gemini(model, payload, api_key):
    url = f"{API_BASE}/{model}:generateContent?key={api_key}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        sys.exit(f"エラー: Gemini API呼び出し失敗 ({e.code}): {detail}")
    except urllib.error.URLError as e:
        sys.exit(f"エラー: Gemini APIに接続できません: {e.reason}")


def extract_text(response):
    try:
        parts = response["candidates"][0]["content"]["parts"]
        return "".join(p.get("text", "") for p in parts)
    except (KeyError, IndexError):
        sys.exit(f"エラー: レスポンス解析失敗: {json.dumps(response, ensure_ascii=False)}")


def save_image(response, output_path):
    try:
        parts = response["candidates"][0]["content"]["parts"]
    except (KeyError, IndexError):
        sys.exit(f"エラー: レスポンス解析失敗: {json.dumps(response, ensure_ascii=False)}")

    image_data = next((p["inline_data"]["data"] for p in parts if "inline_data" in p), None) \
        or next((p["inlineData"]["data"] for p in parts if "inlineData" in p), None)

    if not image_data:
        sys.exit(f"エラー: レスポンスに画像データが含まれていません: {json.dumps(response, ensure_ascii=False)}")

    with open(output_path, "wb") as f:
        f.write(base64.b64decode(image_data))


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-t", "--template", dest="template", default=None)
    parser.add_argument("-a", "--attach", dest="attach", default=None)
    parser.add_argument("--image", dest="image", action="store_true")
    parser.add_argument("-o", "--output", dest="output", default=None)
    args = parser.parse_args()

    if args.image and not args.output:
        sys.exit("エラー: --image 指定時は -o <出力先ファイル> が必須です。")

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        sys.exit("エラー: 環境変数 GEMINI_API_KEY が未設定です。")

    stdin_text = sys.stdin.read()
    template = load_template(args.template) if args.template else {}
    settings = load_settings()
    model = load_model(settings, "image_model" if args.image else "text_model")
    attachment = upload_file(args.attach, api_key) if args.attach else None

    payload = build_payload(template, stdin_text, attachment, image_mode=args.image)
    response = call_gemini(model, payload, api_key)

    if args.image:
        save_image(response, args.output)
        print(f"画像を保存しました: {args.output}")
    else:
        print(extract_text(response))


if __name__ == "__main__":
    main()
