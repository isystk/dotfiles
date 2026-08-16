#!/bin/bash
# dotfiles/PhpStorm/zip-settings.sh
cd "$(dirname "$0")"

SRC_DIR="src"
OUT_ZIP="import_settings.zip"

if [ ! -d "$SRC_DIR" ]; then
    echo "❌ $SRC_DIR がありません。"
    exit 1
fi

rm -f "$OUT_ZIP"

echo "📦 反映用Zipを作成中..."

# src の中身をルートとして固める
# これにより、IntelliJ IDEA Global Settings ファイルがZip直下に配置されます
(cd "$SRC_DIR" && zip -r "../$OUT_ZIP" .)

echo "✅ 作成完了: $OUT_ZIP"
