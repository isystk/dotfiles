#!/bin/bash
# dotfiles/PhpStorm/unzip-settings.sh
set -e

cd "$(dirname "$0")"

ZIP_FILE="settings.zip"
SRC_DIR="src"

# --- 抽出対象の設定 ---
TARGET_FILES=(
    "installed.txt"
    "codestyles/*"
    "inspection/*"
    "keymaps/*"
    "quicklists/*"
    "templates/*"
    "tools/*"
    "options/windows/keymap.xml"
    "options/editor.xml"
    "options/editor-font.xml"
    "options/terminal-font.xml"
    "options/terminal.xml"
    "options/filetypes.xml"
    "options/debugger.xml"
    "options/log_highlighting.xml"
    "options/databaseSettings.xml"
    "options/csvSettings.xml"
    "options/vim_settings.xml"
)

if [ ! -f "$ZIP_FILE" ]; then
    echo "❌ $ZIP_FILE が見つかりません。"
    exit 1
fi

echo "📂 設定ファイルを抽出中..."

rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"

# 1つずつ解凍を試みる（ファイルがなくてもエラーで止めない）
for file in "${TARGET_FILES[@]}"; do
    # エラー出力を捨てつつ、存在するファイルだけ解凍
    if ! unzip -o "$ZIP_FILE" "$file" -d "$SRC_DIR" > /dev/null 2>&1; then
        echo "  Notice: Skipped or not found: $file"
    else
        echo "  Extracted: $file"
    fi
done

# --- 処理後の微調整 ---
TERMINAL_XML="$SRC_DIR/options/terminal.xml"
if [ -f "$TERMINAL_XML" ]; then
    echo "🧹 terminal.xml の統計ノイズを削除しました。"
    perl -i -pe 's/.*enterKeyPressedTimes.*\n//g' "$TERMINAL_XML"
fi

# 識別用ファイルの作成
touch "$SRC_DIR/IntelliJ IDEA Global Settings"

echo "✅ 抽出完了しました（存在する設定のみ）"
