#!/bin/bash

# ==============================================================================
# 概要: WordPress REST API を使用して、対話形式で投稿やメディアを管理する
#
# 主な機能:
#   1. 最近の投稿一覧を表示し、詳細確認や削除を実行
#   2. ローカルの画像ファイルをメディアライブラリへアップロード
#   3. 特定の投稿情報の取得
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

if [ -z "${WORDPRESS_URL:-}" ]; then
    echo "Error: WORDPRESS_URL is not set." >&2
    exit 1
fi

if [ -z "${WORDPRESS_KEY:-}" ]; then
    echo "Error: WORDPRESS_KEY is not set." >&2
    exit 1
fi

WP_BASE_URL="$WORDPRESS_URL"
UPLOADS_DIR="./htdocs/wp-content/uploads"

# APIリクエスト共通関数
wp_api() {
    local method=$1
    local endpoint=$2
    shift 2
    curl -s -X "$method" "$WP_BASE_URL/$endpoint" \
         -H "Authorization: Basic $WORDPRESS_KEY" \
         "$@"
}

# 未使用画像のクリーンアップ
clean_unused_files() {
    echo "🔍 DBから登録済み画像パスを取得中..."
    local page=1
    local db_files=$(mktemp)

    while :; do
        local response=$(wp_api "GET" "media?per_page=100&page=$page")
        if [[ $(echo "$response" | jq -r 'type') != "array" || $(echo "$response" | jq '. | length') -eq 0 ]]; then
            break
        fi
        # フルサイズのパスを保存
        echo "$response" | jq -r '.[].source_url' | sed 's|.*/uploads/||' >> "$db_files"
        ((page++))
    done

    # DBにあるファイルの「ベース名（サイズ抜き）」のリストを作成
    local db_base_names=$(mktemp)
    sed -E 's/-[0-9]+x[0-9]+\.(jpg|jpeg|png|gif|webp)$/.\1/' "$db_files" | sort -u > "$db_base_names"

    if [ ! -d "$UPLOADS_DIR" ]; then
        echo "❌ $UPLOADS_DIR が見つかりません。"
        return 1
    fi

    echo "📂 ローカルファイルをスキャン中..."
    local orphan_files=$(mktemp)

    # 全ファイルをループして判定
    find "$UPLOADS_DIR" -type f -not -path '*/.*' | while read -r filepath; do
        local relative_path=${filepath#$UPLOADS_DIR/}
        # ローカルファイルの「ベース名」を作成（サイズ表記を除去）
        local base_name=$(echo "$relative_path" | sed -E 's/-[0-9]+x[0-9]+\.(jpg|jpeg|png|gif|webp)$/.\1/')

        # ベース名がDBに存在するかチェック
        if ! grep -qxF "$base_name" "$db_base_names"; then
            echo "$relative_path" >> "$orphan_files"
        fi
    done

    local count=$(wc -l < "$orphan_files" 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
        echo "✅ 全てのファイルはDBに登録されているか、そのサムネイルです。"
    else
        echo "⚠️ $count 件の孤立ファイルが見つかりました（サムネイルを含む）:"
        head -n 50 "$orphan_files"

        read -rp "これらのファイルを削除しますか？ (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            while IFS= read -r file; do
                rm -f "$UPLOADS_DIR/$file"
            done < "$orphan_files"
            echo "✨ 削除完了"
        fi
    fi

    rm -f "$db_files" "$db_base_names" "$orphan_files"
}

# 投稿を選択させる関数
select_post() {
    echo "🔍 最近の投稿を取得中..." >&2
    local posts
    posts=$(wp_api "GET" "posts?per_page=15&status=publish,draft,future,pending")

    if [[ $(echo "$posts" | jq -r 'type') != "array" ]]; then
        echo "❌ APIエラーが発生しました。" >&2
        return 1
    fi

    local post_list
    post_list=$(echo "$posts" | jq -r '.[] | "\(.id)\t\(.title.rendered)"')

    if [ -z "$post_list" ]; then
        echo "❌ 投稿が見つかりませんでした。" >&2
        return 1
    fi

    local selected_line
    # 外部関数の呼び出し
    selected_line=$(select_from_list "$post_list" "操作したい投稿を選択してください")

    if [ -n "$selected_line" ]; then
        echo "$selected_line" | awk '{print $1}'
    else
        return 1
    fi
}

# 投稿アクション
post_action_menu() {
    local post_id=$1

    local options=(
        "1. ブラウザで表示"
        "2. JSONを取得"
        "3. アイキャッチ画像を設定"
        "4. 削除"
        "5. キャンセル"
    )

    local choice
    choice=$(select_from_list "$(printf "%s\n" "${options[@]}")" "PR #$post_id に対する操作を選択してください")

    case "$choice" in
        *ブラウザで表示*)
            local link
            link=$(wp_api "GET" "posts/$post_id" | jq -r '.link')
            open_browser "$link"
            ;;
        *JSONを取得*)
            wp_api "GET" "posts/$post_id" | jq .
            ;;
        *アイキャッチ画像を設定*)
            read -rp "Media IDを入力してください: " media_id
            wp_api "POST" "posts/$post_id" --data "featured_media=$media_id" | jq '{id: .id, featured_media: .featured_media}'
            echo "✅ 更新完了"
            ;;
        *削除*)
            read -rp "本当に削除しますか？(y/N): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && wp_api "DELETE" "posts/$post_id" | jq '{id: .id, status: .status}'
            ;;
        *)
            echo "中止しました。"
            ;;
    esac
}

# カテゴリー一覧を表示する関数
show_categories() {
    echo "🔍 カテゴリー情報を取得中..." >&2
    local cats
    cats=$(wp_api "GET" "categories?per_page=100&orderby=id")

    if [[ $(echo "$cats" | jq -r 'type') != "array" ]]; then
        echo "❌ カテゴリーの取得に失敗しました。" >&2
        return 1
    fi

    echo "--------------------------------------------------"
    echo " ID   投稿数  名前 (スラッグ)"
    echo "--------------------------------------------------"
    echo "$cats" | jq -r '.[] |
        "[\(if .id < 10 then "  " elif .id < 100 then " " else "" end)\(.id)] " +
        "(\(if .count < 10 then "  " elif .count < 100 then " " else "" end)\(.count)) " +
        "\(if .parent != 0 then "  └─ " else "" end)\(.name) (\(.slug))"'
    echo "--------------------------------------------------"
}

# --- メインループ ---
main() {
    while true; do
        local main_options=(
            "投稿一覧から操作"
            "カテゴリー一覧を確認"
            "画像をアップロード"
            "未使用画像の削除(クリーンアップ)"
            "終了"
        )

        local main_choice
        main_choice=$(select_from_list "$(printf "%s\n" "${main_options[@]}")" "WordPress 管理メニュー")

        case "$main_choice" in
            "投稿一覧から操作")
                PID=$(select_post) || continue
                post_action_menu "$PID"
                ;;
            "カテゴリー一覧を確認")
                show_categories ;;
            "画像をアップロード")
                read -rp "ファイルパスを入力: " fpath
                if [ -f "$fpath" ]; then
                    local filename=$(basename "$fpath")
                    local mime_type=$(file --mime-type -b "$fpath")
                    echo "📤 $filename をアップロード中..."
                    wp_api "POST" "media" \
                        -H "Content-Disposition: attachment; filename=$filename" \
                        -H "Content-Type: $mime_type" \
                        --data-binary @"$fpath" | jq '{id: .id, link: .source_url}'
                else
                    echo "❌ ファイルが存在しません"
                fi
                ;;
            "未使用画像の削除(クリーンアップ)")
                clean_unused_files ;;
            "終了")
                echo "Bye!"
                exit 0
                ;;
        esac
    done
}

main
