#!/bin/bash

# ==============================================================================
# 概要: ブログ記事タイトルからアイキャッチ画像を自動生成する
#
# 動作フロー:
#   1. 記事タイトルから gen-blog-thumbnail テンプレートで画像生成プロンプトを作成
#   2. そのプロンプトを chatgpt-cli --image に渡し、画像ファイルを出力
# ==============================================================================

# 記事タイトル（引数）を結合して取得
if [ -n "$1" ]; then
    # 引数がある場合
    TITLE="$1"
elif [ ! -t 0 ]; then
    # 引数がなく、標準入力（パイプ）がある場合
    TITLE=$(cat -)
fi

if [ -z "$TITLE" ]; then
    echo "⚠️ 記事タイトルを引数に指定してください。"
    echo "使用例: $0 'Pythonの基本文法についての初心者向けガイド' [出力先パス]"
    exit 1
fi

OUTPUT="${2:-thumbnail.png}"

echo "🤖 1/2: 画像生成プロンプトを作成中..."
IMAGE_PROMPT=$(echo "$TITLE" | chatgpt-cli -t gen-blog-thumbnail)

if [ -z "$IMAGE_PROMPT" ]; then
    echo "❌ プロンプトの生成に失敗しました。"
    exit 1
fi

echo "🎨 2/2: アイキャッチ画像を生成中..."
echo "$IMAGE_PROMPT" | chatgpt-cli --image -t gen-blog-thumbnail-image -o "$OUTPUT"
