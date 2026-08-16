#!/bin/bash

# ==============================================================================
# 概要: 特定のファイルを読み込み、AIにその内容の解説や編集、抽出などを指示する
# 
# 特徴:
#   - Windows形式のパスとWSL形式のパスの両方に対応
#   - 自動的に対象ファイルのあるディレクトリへ移動してから実行
#   - gemini-cliコマンドの添付機能 (-a) を利用してファイルの内容を確実にAIへ渡す
#
# 前提条件:
#   - gemini-cli コマンドがインストールされ、"ai-read" テンプレートが設定されていること
# ==============================================================================

TEMPLATE=""
ARGS=()

for arg in "$@"; do
    case "$arg" in
        -t=*) TEMPLATE="${arg#*=}" ;;
        *) ARGS+=("$arg") ;;
    esac
done

INPUT_FILE="${ARGS[0]}"
USER_INSTRUCTION="${ARGS[1]}"

if [ -z "$INPUT_FILE" ]; then
    echo -n "対象のファイルパスを入力してください: "
    read -e -r INPUT_FILE
fi

# --- パス自動判定・変換ロジック ---
FIXED_INPUT=$(echo "$INPUT_FILE" | sed 's/\\ / /g')
ACTUAL_PATH=$(wslpath -u "$FIXED_INPUT" 2>/dev/null || echo "$FIXED_INPUT")
ACTUAL_PATH=$(realpath "$ACTUAL_PATH" 2>/dev/null)

# ファイルの存在確認
if [ ! -f "$ACTUAL_PATH" ]; then
    echo "エラー: ファイル「$ACTUAL_PATH」が見つかりません。"
    exit 1
fi

# ファイルのあるディレクトリを取得
TARGET_DIR=$(dirname "$ACTUAL_PATH")
# ファイル名のみを取得
FILE_NAME=$(basename "$ACTUAL_PATH")

cd "$TARGET_DIR" || { echo "エラー: ディレクトリに移動できませんでした。"; exit 1; }
# --------------------------------

# 2. 作業内容の入力
if [ -z "$USER_INSTRUCTION" ]; then
    if [ "$TEMPLATE" = "transcribe" ]; then
        USER_INSTRUCTION="この音声ファイルを文字起こしして、内容を要約しください。"
    else
        echo -n "AIへの指示: "
        read -e -r USER_INSTRUCTION
    fi
fi

# 5. AIを実行
echo "📖 ファイルを読み込んでいます: $FILE_NAME"
echo "🤖 解析中 (現在のディレクトリ: $(pwd))..."
echo "---"
(echo "指示: $USER_INSTRUCTION";) | gemini-cli -t ${TEMPLATE:-ai-read} -a "$FILE_NAME"
