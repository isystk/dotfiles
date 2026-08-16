#!/bin/bash

# ==============================================================================
# 概要: AIを活用して音声ファイルを自動生成する
# ==============================================================================

set -euo pipefail

UTILS_SH=$(dirname "$0")/utils.sh
if [ -f "$UTILS_SH" ]; then
    source "$UTILS_SH"
else
    echo "❌ $UTILS_SH が見つかりません。" >&2
    exit 1
fi

VOICEVOX_READING_DICT="$HOME/dotfiles/.config/voicevox/reading_dict.txt"
OUTPUT_DIR="$(pwd)/dist"
OUTPUT_FILE="$OUTPUT_DIR/script_for_reading.txt"

execute_voice_generation() {
    local script_text=$1
    
    mkdir -p "$OUTPUT_DIR"
    echo "$script_text" > "$OUTPUT_FILE"

    local generator="$(dirname "$0")/voice_generator.py"
    if [ ! -x "$generator" ]; then
        echo "❌ $generator が見つかりません。" >&2
        return 1
    fi

    local container_name="voicevox_engine_tmp"
    echo "🚀 VOICEVOXエンジンを起動中..."
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    docker run -d --name "$container_name" -p 50021:50021 voicevox/voicevox_engine:cpu-ubuntu20.04-latest > /dev/null
    trap 'docker stop "$container_name" > /dev/null 2>&1 && docker rm "$container_name" > /dev/null 2>&1' EXIT

    echo -n "⏳ 起動を待機中..."
    for i in {1..30}; do
        if curl -s "http://localhost:50021/version" > /dev/null; then
            echo " OK!"
            break
        fi
        echo -n "."
        sleep 1
    done

    "$generator" "$OUTPUT_FILE"

    echo "🛑 VOICEVOXエンジンを停止しています..."
    docker stop "$container_name" > /dev/null
    docker rm "$container_name" > /dev/null
    trap - EXIT
}

# --- 既存ファイルの確認 ---
SKIP_GENERATION=false
if [ -f "$OUTPUT_FILE" ]; then
    echo "⚠️ $OUTPUT_FILE は既に存在します。"
    read -p "上書きして新しく生成しますか？ (y/N): " ryn
    case "$ryn" in
        [yY]*) 
            SKIP_GENERATION=false 
            ;;
        *) 
            echo "既存のファイルを使用して音声生成を開始します。"
            SKIP_GENERATION=true 
            FINAL_SCRIPT=$(cat "$OUTPUT_FILE")
            ;;
    esac
fi

if [ "$SKIP_GENERATION" = false ]; then
    # --- モード選択 ---
    MODE_LIST=$(echo -e "シンプルモード（テキストをそのまま音声化）\nプレゼン用（構成とMarpを渡す）")
    SELECTED_MODE=$(select_from_list "$MODE_LIST" "実行モードを選択してください")

    DICT_CONTENT=$([ -f "$VOICEVOX_READING_DICT" ] && cat "$VOICEVOX_READING_DICT" || echo "")
    FINAL_SCRIPT=""

    case "$SELECTED_MODE" in
        "シンプルモード"*)
            file_list=$(find . -maxdepth 1 -type f \( -name "*.txt" -o -name "*.md" \))
            if [ -z "$file_list" ]; then
                echo "❌ テキストファイルが見つかりません。"
                exit 1
            fi
            SRC_FILE=$(select_from_list "$file_list" "音声化するファイルを選択してください")
            src_text=$(cat "$SRC_FILE")

            data="
【DICT_CONTENT】
$DICT_CONTENT

【INPUT】
$src_text"

            echo "🎙️ テキストを読み上げ用に最適化中..."
            FINAL_SCRIPT=$(echo -e "$data" | gemini-cli -t gen-voice)
            ;;

        "プレゼン用"*)
            md_list=$(find . -maxdepth 1 -iname "*.md")
            if [ -z "$md_list" ]; then
                echo "❌ Markdownファイルが見つかりません。"
                exit 1
            fi
            MARP_FILE=$(select_from_list "$md_list" "1. Marp（スライド構成）ファイルを選択してください")
            OUTLINE_FILE=$(select_from_list "$md_list" "2. Outline（読み上げ原稿）ファイルを選択してください")

            if [[ ! -f "$MARP_FILE" || ! -f "$OUTLINE_FILE" ]]; then
                echo "❌ 必要なファイルが選択されませんでした。"
                exit 1
            fi

            echo "🎙️ 技術解説ナレーションを生成中..."
            
            marp_clean_text=$(cat "$MARP_FILE" | sed -n '/^---/,$p' | sed '/<style>/,/<\/style>/d' | sed '/style: |/,/^---/d')
            outline_text=$(cat "$OUTLINE_FILE")

            data="
あなたは、入力テキストをVOICEVOXでの音声合成に最適化した「高精度な読み上げ用原稿」に整形する専門家です。
「Marp形式のプレゼン構成」と「詳細なアウトライン原稿」を統合し、VOICEVOXでの変換に最適化した「読み上げ用テキスト」に書き換えてください。
VOICEVOXの自然なイントネーションを活かすため、一般的な漢字は維持しつつ、読み間違いが発生しやすい「数値・記号・英単語」を優先的に修正します。

# 厳守事項：スライド区切り
- Marpの「---」はスライドの節目です。
- ナレーション原稿においても、Marpの「---」に対応する箇所で【必ず2行改行】を挿入し「---」を含めないでください。
- 1つのスライド（--- から --- まで）の内容を1つのブロックとして出力してください。

# 役割分担
- Marp: ページの「見出し」と「区切り」として使用。
- Outline: 話す内容のソース。ここにある解説ステップを省略せず、スライドの順序に従って構成してください。

【DICT_CONTENT】
$DICT_CONTENT

【INPUT】
## Marp形式のプレゼン構成
$marp_clean_text

## 詳細なアウトライン原稿
$outline_text"

            FINAL_SCRIPT=$(echo -e "$data" | gemini-cli -t gen-voice)
            ;;
    esac
fi

if [ -z "${FINAL_SCRIPT:-}" ]; then
    echo "❌ 原稿の取得または生成に失敗しました。"
    exit 1
fi

execute_voice_generation "$FINAL_SCRIPT"
echo "✅ 全ての処理が完了しました。"