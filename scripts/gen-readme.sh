#!/bin/bash

# ==============================================================================
# 概要: プロジェクト情報を解析し、AIを活用してREADME.mdを自動生成する
#
# 動作フロー:
#   1. package.json や Git情報からプロジェクト名や依存関係を取得
#   2. ディレクトリ構造（treeコマンド等）を取得
#   3. READMEテンプレート（.github/readme_template.md等）を読み込み
#   4. gemini-cliコマンドに情報を渡し、Markdownを生成
#   5. 生成結果を確認し、README.md として保存
# ==============================================================================

# 1. 基本情報の収集
echo "🔍 プロジェクト情報を収集しています..."

if [ -f "package.json" ]; then
    PKG_NAME=$(jq -r '.name' package.json 2>/dev/null || grep -m1 '"name":' package.json | cut -d'"' -f4)
    PKG_DESC=$(jq -r '.description' package.json 2>/dev/null || grep -m1 '"description":' package.json | cut -d'"' -f4)
    PKG_DEPS=$(jq -r '.dependencies | keys | join(", ")' package.json 2>/dev/null)
    PKG_DEV_DEPS=$(jq -r '.devDependencies | keys | join(", ")' package.json 2>/dev/null)
else
    PKG_NAME=$(basename "$(pwd)")
    PKG_DESC="プロジェクトの説明がありません"
fi

GIT_REMOTE_URL=$(git config --get remote.origin.url | sed -e 's/git@github.com:/https:\/\/github.com\//' -e 's/\.git$//')

if command -v tree >/dev/null 2>&1; then
    DIR_STRUCTURE=$(tree -L 2 -I 'node_modules|vendor|.git|storage')
else
    DIR_STRUCTURE=$(find . -maxdepth 2 -not -path '*/.*' -not -path './node_modules*' -not -path './vendor*' | sort)
fi

# 2. README構成テンプレートの読み込み
TEMPLATE_PATH="$HOME/dotfiles/.github/readme_template.md"
if [ -f "$TEMPLATE_PATH" ]; then
    README_TEMPLATE_CONTENT=$(cat "$TEMPLATE_PATH")
    echo "📄 構成テンプレートを読み込みました ($TEMPLATE_PATH)"
else
    README_TEMPLATE_CONTENT="# {PROJECT_NAME}\n\n## 概要\n{DESCRIPTION}\n\n## 利用技術\n{TECH_STACK}\n\n## ディレクトリ構造\n\`\`\`\n{DIR_STRUCTURE}\n\`\`\`"
fi

# 3. AIへのプロンプト構築
echo "🤖 AIでREADMEを生成中..."

# gemini-cliテンプレート 'gen-readme' を呼び出し、各パラメータを渡す
DATA="
# プロジェクト情報
- Name: $PKG_NAME
- Description: $PKG_DESC
- GitHub URL: $GIT_REMOTE_URL
- Dependencies: $PKG_DEPS
- DevDependencies: $PKG_DEV_DEPS

# ディレクトリ構造
$DIR_STRUCTURE

# READMEテンプレート（この構成に従ってください）
$README_TEMPLATE_CONTENT"

GENERATED_README=$(echo "$DATA" | gemini-cli -t gen-readme)

# 4. 結果のプレビューと保存
echo -e "\n--- 📝 生成されたREADMEのプレビュー ---"
echo "$GENERATED_README"
echo -e "----------------------------------------\n"

read -p "🚀 README.md をこの内容で更新しますか？ (y/N): " confirm
if [[ "$confirm" =~ ^[yY]$ ]]; then
    echo "$GENERATED_README" > README.md
    echo "✅ README.md が正常に更新されました！"
else
    echo "キャンセルしました。"
fi
