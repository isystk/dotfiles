#!/bin/bash

# ==============================================================================
# 概要: AIを活用してプルリクエスト（PR）の内容を自動生成し、作成まで行う
# 
# 動作フロー:
#   1. 比較対象のリモートブランチを選択（fetch --prune を実行して最新化）
#   2. プロジェクトのPRテンプレート（存在すれば）を読み込み
#   3. 指定ブランチと現在のHEADの差分（diff）を抽出
#   4. gemini-cliコマンド（gen-prテンプレート）でPRのタイトルと本文を生成
#   5. 内容を確認後、git push と gh pr create を実行
#
# 前提条件:
#   - utils.sh (select_from_list関数) が存在すること
#   - gemini-cli コマンドおよび GitHub CLI (gh) がインストール・認証済みであること
#   - gemini-cli に "gen-pr" というプロンプトテンプレートが登録されていること
# ==============================================================================

source "$(dirname "$0")/utils.sh"

echo "🔎 ブランチを取得中..."
git fetch --prune > /dev/null 2>&1
branches=$(git branch -r | sed -E 's|^\*?\s+||; s|remotes/||' | grep -v "HEAD" | sort -u)
selected_branch=$(select_from_list "$branches" "比較対象のブランチを選んでください")

if [ $? -ne 0 ]; then
    echo "👋 キャンセルされました。"
    exit 0
fi

base_branch=$(echo "$selected_branch" | sed 's|^origin/||')

## PRテンプレートの読み込み
TEMPLATE_PATH=".github/pull_request_template.md"
if [ -f "$TEMPLATE_PATH" ]; then
    PR_TEMPLATE=$(cat "$TEMPLATE_PATH")
    echo "📄 PRテンプレートを読み込みました ($TEMPLATE_PATH)"
else
    PR_TEMPLATE="## 概要\n## 変更点\n## 影響範囲"
    echo "⚠️ テンプレートが見つからないため、基本フォーマットを使用します。"
fi

## 差分の取得
DIFF_STAT=$(git diff --stat "$selected_branch"...HEAD | iconv -c -f UTF-8 -t UTF-8)
DIFF_CONTENT=$(git diff -w "$selected_branch"...HEAD | head -n 5000 | iconv -c -f UTF-8 -t UTF-8)

if [ -z "$DIFF_STAT" ]; then
    echo "✅ 差分はありません（現在のブランチは最新です）。"
    exit 0
fi

echo "🤖 AIでプルリクエストを生成中..."

## AIへの指示（プロンプト構築）
DATA="
# プルリクエストテンプレート
$PR_TEMPLATE

# git差分統計 (ファイル一覧)
$DIFF_STAT

# git差分内容 (コード抜粋)
$DIFF_CONTENT"

# AIで生成と表示
FULL_OUTPUT=$(echo "$DATA" | gemini-cli -t gen-pr)
PR_TITLE=$(echo "$FULL_OUTPUT" | head -n 1 | sed 's/^[#[:space:]]*//')
PR_BODY=$(echo "$FULL_OUTPUT" | sed '1,2d')

echo -e "\n--- 📝 生成された内容 ---"
echo -e "BASE: $base_branch <--- HEAD: $(git branch --show-current)"
echo -e "TITLE: $PR_TITLE"
echo -e "BODY: $PR_BODY"
echo -e "------------------------\n"

## gh pr create の実行
read -p "🚀 この内容でPRを作成しますか？ (y/N): " confirm
if [[ "$confirm" =~ ^[yY]$ ]]; then
    current_branch=$(git branch --show-current)
    
    echo "⬆️  $current_branch を push 中..."
    git push origin "$current_branch"

    # --base に正しい変数を渡す
    gh pr create --base "$base_branch" --head "$current_branch" --title "$PR_TITLE" --body "$PR_BODY"
    
    if [ $? -eq 0 ]; then
        echo "✅ PRが正常に作成されました！"
    else
        echo "❌ PRの作成に失敗しました。"
    fi
else
    echo "キャンセルしました。"
fi
