#!/usr/bin/env python3
"""
ChatGPT (OpenAI) API を直接呼び出す軽量CLI。

使い方:
  echo "$PROMPT" | chatgpt-cli                # テンプレートなし。標準入力をそのままユーザーメッセージとして送信
  echo "$PROMPT" | chatgpt-cli -t <template>   # .config/chatgpt-cli/templates/<template>.yaml を使用
  echo "$PROMPT" | chatgpt-cli -t <template> -a <file>  # ファイルを添付（Files APIへアップロードして参照）
  echo "$PROMPT" | chatgpt-cli --image -o <file.png>    # 画像を生成し、指定パスに保存

テンプレート yaml の仕様:
  system: |          # instructions として使用（省略可）
    ...
  prompt: |           # {{ input }} を標準入力全体に置換した文字列をユーザーメッセージにする（省略時は標準入力をそのまま使用）
    {{ input }}
  options:
    temperature: 0.1
    max_output_tokens: 4000

モデルは settings.json（CHATGPT_CLI_PATH配下、既定 ~/.config/chatgpt-cli）で管理する。
  {
    "text_model": "...",   # 通常のテキスト生成で使用（Responses API）
    "image_model": "..."   # --image 指定時に使用（Images API, 例: gpt-image-2）
  }
APIキーは環境変数 OPENAI_API_KEY から取得する。
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
import uuid

import yaml

CONFIG_DIR = os.path.expanduser(os.environ.get("CHATGPT_CLI_PATH", "~/.config/chatgpt-cli"))
TEMPLATE_DIR = os.path.join(CONFIG_DIR, "templates")
SETTINGS_FILE = os.path.join(CONFIG_DIR, "settings.json")
API_BASE = "https://api.openai.com/v1"


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
    return model


def load_template(name):
    path = os.path.join(TEMPLATE_DIR, f"{name}.yaml")
    if not os.path.isfile(path):
        sys.exit(f"エラー: テンプレートが見つかりません: {path}")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def upload_file(path, api_key):
    """ファイルを OpenAI Files API にアップロードし、(file_id, mime_type) を返す。

    画像は purpose=vision、それ以外は purpose=user_data でアップロードする。
    """
    if not os.path.isfile(path):
        sys.exit(f"エラー: 添付ファイルが見つかりません: {path}")

    mime_type = mimetypes.guess_type(path)[0] or "application/octet-stream"
    purpose = "vision" if mime_type.startswith("image/") else "user_data"
    filename = os.path.basename(path)

    with open(path, "rb") as f:
        file_bytes = f.read()

    boundary = uuid.uuid4().hex
    body = bytearray()

    def add_field(name, value):
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        body.extend(f"{value}\r\n".encode())

    add_field("purpose", purpose)
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode())
    body.extend(f"Content-Type: {mime_type}\r\n\r\n".encode())
    body.extend(file_bytes)
    body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())

    req = urllib.request.Request(
        f"{API_BASE}/files",
        data=bytes(body),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as res:
            file_info = json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"エラー: ファイルアップロード失敗 ({e.code}): {e.read().decode('utf-8', errors='ignore')}")

    return file_info["id"], mime_type


def build_payload(model, template, stdin_text, attachment=None):
    system_text = template.get("system")
    prompt_template = template.get("prompt")

    if prompt_template:
        user_text = prompt_template.replace("{{ input }}", stdin_text).replace("{{input}}", stdin_text)
    else:
        user_text = stdin_text

    content = [{"type": "input_text", "text": user_text}]
    if attachment:
        file_id, mime_type = attachment
        if mime_type.startswith("image/"):
            content.append({"type": "input_image", "file_id": file_id})
        else:
            content.append({"type": "input_file", "file_id": file_id})

    payload = {"model": model, "input": [{"role": "user", "content": content}]}

    if system_text:
        payload["instructions"] = system_text

    # gpt-5系などの推論モデルは temperature 未対応のため送信しない
    options = template.get("options") or {}
    if "max_output_tokens" in options:
        payload["max_output_tokens"] = options["max_output_tokens"]

    return payload


def build_image_payload(model, template, stdin_text):
    system_text = template.get("system")
    prompt_template = template.get("prompt")

    if prompt_template:
        user_text = prompt_template.replace("{{ input }}", stdin_text).replace("{{input}}", stdin_text)
    else:
        user_text = stdin_text

    prompt = f"{system_text}\n\n{user_text}" if system_text else user_text

    options = template.get("options") or {}
    size = options.get("size", "1024x1024")

    return {"model": model, "prompt": prompt, "n": 1, "size": size}


def call_api(path, payload, api_key):
    req = urllib.request.Request(
        f"{API_BASE}/{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        sys.exit(f"エラー: OpenAI API呼び出し失敗 ({e.code}): {detail}")
    except urllib.error.URLError as e:
        sys.exit(f"エラー: OpenAI APIに接続できません: {e.reason}")


def extract_text(response):
    try:
        texts = []
        for item in response["output"]:
            if item.get("type") != "message":
                continue
            for part in item.get("content", []):
                if part.get("type") == "output_text":
                    texts.append(part.get("text", ""))
        return "".join(texts)
    except (KeyError, IndexError):
        sys.exit(f"エラー: レスポンス解析失敗: {json.dumps(response, ensure_ascii=False)}")


def save_image(response, output_path):
    try:
        image_data = response["data"][0]["b64_json"]
    except (KeyError, IndexError):
        sys.exit(f"エラー: レスポンス解析失敗: {json.dumps(response, ensure_ascii=False)}")

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

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        sys.exit("エラー: 環境変数 OPENAI_API_KEY が未設定です。")

    stdin_text = sys.stdin.read()
    template = load_template(args.template) if args.template else {}
    settings = load_settings()
    model = load_model(settings, "image_model" if args.image else "text_model")

    if args.image:
        payload = build_image_payload(model, template, stdin_text)
        response = call_api("images/generations", payload, api_key)
        save_image(response, args.output)
        print(f"画像を保存しました: {args.output}")
    else:
        attachment = upload_file(args.attach, api_key) if args.attach else None
        payload = build_payload(model, template, stdin_text, attachment)
        response = call_api("responses", payload, api_key)
        print(extract_text(response))


if __name__ == "__main__":
    main()
