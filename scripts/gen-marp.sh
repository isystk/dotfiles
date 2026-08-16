#!/bin/bash

# ==============================================================================
# 概要: AIを活用してMarpスライドやプレゼン原稿を自動生成・変換する
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

# 設定
MOUNT_POINT="$HOME/dotfiles/.config/marp"
STYLE_PATH="$MOUNT_POINT/style.css"
TMP_MD="temp_marp_slide.md"

# カスタムスタイルの読み込み
CUSTOM_STYLE=$( [ -f "$STYLE_PATH" ] && cat "$STYLE_PATH" || echo "/* No custom style found */" )

# Marp生成関数
generate_marp() {
    local input_path=$1
    if [[ ! -f "$input_path" ]]; then
        echo "❌ ファイルが見つかりません: $input_path"
        return 1
    fi

    echo "🤖 1/2: 初期Marpに変換中..."
    local input_text=$(cat "$input_path")
    local initial_gen=$(echo -e "【対象テキスト】\n$input_text" | gemini-cli -t gen-marp)

    if [[ -z "$initial_gen" ]]; then
        echo "❌ 初期生成に失敗しました。" >&2
        return 1
    fi

    echo "✨ 2/2: 元記事の内容に基づきブラッシュアップ中..."
    local prompt="
# 指示
以下の「元記事」と「AI生成結果」を比較し、AI生成結果をブラッシュアップしてください。

# 制約事項
1. **既存の構成を維持**: AI生成結果の構成やトーンは原則として維持してください。
2. **不足要素の補完**: 元記事に含まれている重要な情報（コマンド、設定値、ベストプラクティス等）が欠落している場合のみ、適切に追加してください。
3. **正確性の向上**: 技術的な誤りや古い情報の修正。
4. **構成**: 余計な解説は一切禁止。

# データ
## 元記事
$input_text

## AI生成結果
$initial_gen
"
    local polished=$(echo -e "$prompt" | gemini-cli)

    if [[ -z "$polished" ]]; then
        echo "⚠️ ブラッシュアップに失敗したため、初期生成版を出力します。" >&2
        polished="$initial_gen"
    fi

    local output_base="marp_$(date +%Y%m%d_%H%M%S).md"
    {
        echo "---"
        echo "marp: true"
        echo "theme: default"
        echo "paginate: true"
        echo "style: |"
        echo "$CUSTOM_STYLE" | sed 's/^/  /'
        echo "---"
        echo ""
        echo "$polished"
    } > "$output_base"

    echo "✅ 生成完了: $(pwd)/$output_base"
}

# PDFやパワーポイント形式のファイルに変換する関数
convert_marp() {
    local file=$1
    local type=$2
    local target_path="$MOUNT_POINT/$TMP_MD"

    # ファイルをコピー
    cp "$file" "$target_path"

    local output_file="slide_$(date +%Y%m%d_%H%M%S).$type"
    echo "📄 ${type^^}に変換中..."

    docker run --rm \
        -v "$MOUNT_POINT:/home/marp/app" \
        -u "$(id -u):$(id -g)" \
        -w "/home/marp/app" \
        marpteam/marp-cli "$TMP_MD" \
        --"$type" --no-sandbox \
        -o - > "$output_file"

    rm -f "$target_path"
    if [ -s "$output_file" ]; then
        echo "✅ 変換完了: $(pwd)/dist/$output_file"
    else
        echo "❌ 変換に失敗しました。"
    fi
}


md_list=$(find . -iname "*.md")
FILE_PATH=$(select_from_list "$md_list" "対象のMarkdownファイルを選択してください")

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ ファイルが存在しません。"
    exit 1
fi

options=(
    "1. Marpに変換する"
    "2. MarpからPDFに変換する"
    "3. MarpからPPTXに変換する"
    "4. Webエディタを開く"
    "5. 終了"
)

choice=$(select_from_list "$(printf "%s\n" "${options[@]}")" "実行する操作を選択してください")

case "$choice" in
    *Marpに変換する*)
        generate_marp "$FILE_PATH" ;;
    *MarpからPDFに変換する*)
        convert_marp "$FILE_PATH" "pdf" ;;
    *MarpからPPTXに変換する*)
        convert_marp "$FILE_PATH" "pptx" ;;
    *Webエディタを開く*)
        cat "$FILE_PATH" | copy_clipboard > /dev/null
        echo "🌐 クリップボードにコピーされました。"
        open_browser "https://marpwebeditor.app" ;;
    *終了*)
        echo "Bye!"
        exit 0 ;;
esac
