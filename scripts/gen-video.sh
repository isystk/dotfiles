#!/bin/bash

# ==============================================================================
# 概要: 選択したPDFと音声ファイルを合成し、動画を生成する
# ==============================================================================

set -euo pipefail

# --- 環境準備 ---
UTILS_SH=$(dirname "$0")/utils.sh

if [ -f "$UTILS_SH" ]; then
    source "$UTILS_SH"
else
    echo "❌ $UTILS_SH が見つかりません。select_from_list 関数が必要です。" >&2
    exit 1
fi

# --- ファイル選択 ---
pdf_list=$(find . -type f -name "*.pdf" -print)
if [ -z "$pdf_list" ]; then
    echo "❌ PDFファイルがカレントディレクトリ内に見つかりません。"
    exit 1
fi
PDF_PATH=$(select_from_list "$pdf_list" "PDFファイルを選択してください")

if [ ! -f "$PDF_PATH" ]; then
    echo "❌ PDFファイルが存在しません。"
    exit 1
fi

wav_list=$(find . -type f -name "*.wav" -print)
if [ -z "$wav_list" ]; then
    echo "❌ 音声ファイル（.wav）がカレントディレクトリ内に見つかりません。"
    exit 1
fi
WAV_PATH=$(select_from_list "$wav_list" "音声ファイルを選択してください")

if [ ! -f "$WAV_PATH" ]; then
    echo "❌ 音声ファイルが存在しません。"
    exit 1
fi

# --- 合成エンジンの確認 ---
generator="$(dirname "$0")/combine_pdf_audio.py"
if [ ! -f "$generator" ]; then
    echo "❌ $generator が見つかりません。" >&2
    exit 1
fi

# 実行権限がない場合は付与を試みる
if [ ! -x "$generator" ]; then
    chmod +x "$generator"
fi

# --- 動画生成実行 ---
OUTPUT_PATH="video_$(date +%Y%m%d_%H%M%S).mp4"

echo "--------------------------------------------"
echo "🚀 動画合成を開始します..."
echo "📄 PDF: $PDF_PATH"
echo "🎵 WAV: $WAV_PATH"
echo "🎬 OUT: $OUTPUT_PATH"
echo "--------------------------------------------"

if "$generator" "$PDF_PATH" "$WAV_PATH" -o "$OUTPUT_PATH"; then
    echo "--------------------------------------------"
    echo "✅ 完了しました！"
    echo "📁 出力先: $(pwd)/$OUTPUT_PATH"
    echo "--------------------------------------------"
else
    echo "❌ 動画生成中にエラーが発生しました。"
    exit 1
fi
