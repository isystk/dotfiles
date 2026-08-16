#!/bin/bash

# OSの判定
IS_MAC=$( [ "$(uname)" = "Darwin" ] && echo 1 || : )
IS_WSL=$( grep -qi "microsoft" /proc/version 2>/dev/null && echo 1 || : )
IS_LINUX=$( [ -z "$IS_MAC$IS_WSL" ] && echo 1 || : )

# 汎用選択関数
# 第1引数: 改行区切りのリスト文字列
# 第2引数: (任意) ヘッダーメッセージ
select_from_list() {
    local list_data="$1"
    local header_msg="${2:-❓ 項目を選択してください}" # 第2引数が空ならデフォルトメッセージ

    if [ -z "$list_data" ]; then
        echo "❌ 選択肢となるデータが空です。" >&2
        return 1
    fi

    local selected_item=""
    echo "$header_msg" >&2

    if command -v $ENHANCD_FILTER >/dev/null 2>&1; then
        # fzy での選択
        selected_item=$(echo "$list_data" | $ENHANCD_FILTER)
    else
        # fzy がない場合の select
        PS3="番号を入力: "
        # list_dataを配列に変換してselectに渡す
        local IFS=$'\n'
        local options=($list_data)
        select opt in "${options[@]}"; do
            if [ -n "$opt" ]; then
                selected_item=$opt
                break
            else
                echo "⚠️ 無効な選択です。" >&2
            fi
        done
    fi

    if [ -z "$selected_item" ]; then
        return 1
    fi

    echo "$selected_item" | tr -d '\r\n' | xargs
}


# 比較モードに応じたファイル名のリストを取得する
# 第1引数:
#   $1: 比較モード
#       - "branch": 対話形式でブランチを選択し、そのブランチとの差分を取得
#       - "staged": ステージング（Index）されているファイルの差分を取得
#       - [文字列]: 特定のブランチ名として扱い、そのブランチとの差分を取得
get_diff_files() {
    local mode=$1

    if [ -z "$mode" ]; then
        echo "❌ エラー: 比較モード（branch, staged, またはブランチ名）を指定してください。" >&2
        exit 1
    fi

    if [ "$mode" = "branch" ]; then
        # --- ブランチ選択モード ---
        local branch_list=$(git branch -a --format='%(refname:short)' | grep -v "HEAD")
        local selected_branch=$(select_from_list "$branch_list" "🌿 比較対象のブランチを選択してください")
        [ -z "$selected_branch" ] && { echo "🚫 キャンセルされました。" >&2; exit 1; }

        git diff --name-only "$selected_branch...HEAD"

    elif [ "$mode" = "staged" ]; then
        # --- ステージング（Index）モード ---
        git diff --name-only --cached

    else
        # --- 直接ブランチ名指定モード ---
        # 指定された文字列がブランチとして存在するか確認
        if git rev-parse --verify "$mode" >/dev/null 2>&1; then
            git diff --name-only "$mode...HEAD"
        else
            echo "❌ エラー: ブランチ '$mode' が見つかりません。" >&2
            exit 1
        fi
    fi
}

# OSに応じてURLをブラウザで開く関数
# 引数: 開きたいURL
open_browser() {
    if [ -n "$IS_MAC" ]; then
        /usr/bin/open "$@"
    elif [ -n "$IS_WSL" ]; then
        powershell.exe -Command "Start-Process '$1'"
    elif [ -n "$IS_LINUX" ]; then
        xdg-open "$@"
    else
        echo "Unsupported OS"
    fi
}

# OSに応じてパスをエクスプローラーで開く関数
# 引数: 開きたいフォルダパス
open_explorer() {
    if [ -n "$IS_MAC" ]; then
        open "${1:-.}"
    elif [ -n "$IS_WSL" ]; then
        explorer.exe "${1:-.}"
    elif [ -n "$IS_LINUX" ]; then
        xdg-open "${1:-.}"
    else
        echo "Unsupported OS"
    fi
}

# OSに応じてクリップボードにコピーする関数
# 引数: コピーしたいテキスト
copy_clipboard() {
    if [ -n "$IS_MAC" ]; then
        tee /dev/tty | pbcopy
    elif [ -n "$IS_WSL" ]; then
        tee /dev/tty | xclip -sel clipboard
    elif [ -n "$IS_LINUX" ]; then
        tee /dev/tty | xclip -sel clipboard
    else
        echo "Unsupported OS"
    fi
}

# ZIPファイルの中身を一時フォルダに解凍して比較する関数
# 引数:  $1: ZIPファイル1
#         $2: ZIPファイル2
zipdiff_all() {
    if [ $# -ne 2 ]; then
        echo "Usage: zipdiff_all file1.zip file2.zip"
        return 1
    fi

    local dir1=$(mktemp -d)
    local dir2=$(mktemp -d)

    unzip -q "$1" -d "$dir1"
    unzip -q "$2" -d "$dir2"

    # ディレクトリ同士を比較して、その「結果（diffテキスト）」をnvimで開く
    # -N は新規ファイルを空ファイルと比較、-r は再帰的、-u はUnified形式
    diff -Nur "$dir1" "$dir2" | nvim -R -c 'set ft=diff' -

    rm -rf "$dir1" "$dir2"
}
