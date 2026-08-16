#!/bin/bash

# ==============================================================================
# 概要: GitHub CLI (gh) を使用して、対話形式でプルリクエストを管理・操作する
# 
# 主な機能:
#   1. リモートのPRを一覧表示し、インタラクティブに選択
#   2. 選択したPRに対して、ブラウザ表示、チェックアウト、マージを実行
#   3. AI（gemini-cliコマンド）を使用して、特定のPRを即座にレビュー
#
# 前提条件:
#   - gh (GitHub CLI) がインストール・認証済みであること
#   - utils.sh (select_from_list関数) が存在すること
#   - gemini-cli コマンドおよび "ai-review" テンプレートが設定されていること
# ==============================================================================

# utils.sh が存在する場合のみ読み込み（select_from_list を使用するため）
if [ -f "$(dirname "$0")/utils.sh" ]; then
    source "$(dirname "$0")/utils.sh"
fi

set -euo pipefail

if ! GH_BIN=$(command -v gh); then
    echo "エラー: gh (GitHub CLI) がインストールされていないか、PATH にありません。" >&2
    exit 1
fi

# PRを一覧表示し、ユーザーに1つ選択させてその「番号」を返す関数
select_pr() {
    local pr_list
    pr_list=$("$GH_BIN" pr list --limit 50)

    if [ -z "$pr_list" ]; then
        echo "❌ プルリクエストが見つかりませんでした。" >&2
        return 1
    fi

    local selected_line
    selected_line=$(select_from_list "$pr_list" "操作したいPRを選択してください")

    if [ -n "$selected_line" ]; then
        echo "$selected_line" | awk '{print $1}'
    else
        return 1
    fi
}

# 選択したPRに対して何をするか選択する関数
select_action() {
    local pr_number=$1

    local options=(
        "ブラウザで開く"
        "チェックアウトする"
        "マージする"
        "AIレビューする"
        "キャンセル"
    )

    local pr_list_str
    pr_list_str=$(printf "%s\n" "${options[@]}")

    local opt
    opt=$(select_from_list "$pr_list_str" "PR #$pr_number に対するアクションを選択してください")

    case "$opt" in
        "ブラウザで開く")
            "$GH_BIN" pr view "$pr_number" --web
            ;;
        "チェックアウトする")
            "$GH_BIN" pr checkout "$pr_number"
            ;;
        "マージする")
            "$GH_BIN" pr merge "$pr_number"
            ;;
        "AIレビューする")
            echo "🔍 PR #$pr_number の情報を取得中..."
            PR_INFO=$($GH_BIN pr view "$pr_number" --json title,body,files)
            DIFF_CONTENT=$($GH_BIN pr diff "$pr_number")
            echo "🤖 AIでコードの変更をチェック中..."

            printf "# PR情報\n%s\n\n# 差分\n%s" "$PR_INFO" "$DIFF_CONTENT" | gemini-cli -t ai-review
            echo -e "\n--- ✨ 生成完了 ---"
            ;;
        "キャンセル" | "")
            echo "中止しました。"
            exit 0
            ;;
        *)
            echo "無効な選択です。"
            return 1
            ;;
    esac
}

PR_NUM=$(select_pr)

if [ -n "$PR_NUM" ]; then
    select_action "$PR_NUM"
else
    echo "PRが選択されませんでした。"
    exit 1
fi
