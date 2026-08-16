#!/bin/bash

# 引数チェック
if [ -z "$1" ]; then
    echo "Usage: $0 input.pdf [output_dir]"
    exit 1
fi

INPUT_PDF="$1"
# 第2引数があればそれを出力先に、なければデフォルト名を使用
OUTPUT_DIR="${2:-output_images}"

# 依存コマンドのチェック
if ! command -v pdftoppm &> /dev/null; then
    echo "❌ エラー: pdftoppm が見つかりません。'apt-get install poppler-utils' などでインストールしてください。"
    exit 1
fi

# ファイル存在チェック
if [ ! -f "$INPUT_PDF" ]; then
    echo "❌ エラー: ファイルが見つかりません: $INPUT_PDF"
    exit 1
fi

# 出力ディレクトリ作成
mkdir -p "$OUTPUT_DIR"

echo "⏳ 変換を開始します: $INPUT_PDF -> $OUTPUT_DIR/"

# pdftoppm 実行
# -jpeg: JPEG形式で出力
# -r 150: 解像度 (150dpi)
# -sep '_': ファイル名と連番の区切り文字
# 結果は page_1.jpg, page_2.jpg ... となります
pdftoppm -jpeg -r 150 -sep '_' "$INPUT_PDF" "$OUTPUT_DIR/page"

if [ $? -eq 0 ]; then
    echo "✨ 変換が完了しました。ファイルは '$OUTPUT_DIR' に保存されました。"
else
    echo "❌ 変換中にエラーが発生しました。"
    exit 1
fi
