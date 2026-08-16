---
name: create-pr
description: プルリクエストを作成する
---

# Pull Request 作成スキル

## 手順

### Step 1: 現在の状態を確認

以下を並行して実行する：

- `git status` で未コミットの変更を確認
- `git branch -r` でリモートブランチ一覧を確認
- `git log --oneline -10` で最近のコミット履歴を確認

### Step 2: ベースブランチをユーザーに確認

以下のように確認する：

```
PRのベースブランチ（マージ先）を教えてください。
リモートブランチ一覧: [git branch -r の結果を表示]
（デフォルト候補: main / develop / master）
```

ユーザーの回答を受けてからStep 3へ進む。

### Step 3: 変更差分を確認

ベースブランチが確定したら、**ローカルブランチではなくリモートブランチ（`origin/<ベースブランチ>`）と比較する**：

```bash
# リモートの最新状態を取得
git fetch origin

# コミット一覧（リモートとの差分）
git log origin/<ベースブランチ>..HEAD --oneline

# ファイル差分（リモートとの差分）
git diff origin/<ベースブランチ>...HEAD
```

> ローカルの `<ベースブランチ>` が古い場合、意図しない大量の差分が混入するため必ず `origin/` プレフィックスを使用すること。

### Step 4: PRテンプレートを取得

以下の優先順位でPRテンプレートを探す：

1. **プロジェクトローカル**: `.github/pull_request_template.md` が存在すれば使用
2. **グローバルデフォルト**: `/root/dotfiles/.github/pull_request_template.md` を使用
3. **テンプレートなし**: 後述のデフォルトフォーマットで作成

```bash
# 確認コマンド
[ -f ".github/pull_request_template.md" ] && echo "LOCAL" || echo "GLOBAL"
```

### Step 5: PR本文を作成

取得したテンプレートの構造を維持しつつ、Step 3で収集した変更内容をもとに各セクションを埋める。
テンプレートのコメント（`<!-- ... -->`）は除去し、プレースホルダーは実際の内容に置き換える。

**テンプレートが存在しない場合のデフォルトフォーマット：**

```markdown
## 概要

[変更の背景・目的]

## やったこと

- [ ] [変更内容1]
- [ ] [変更内容2]

## 影響範囲

- [ ] [影響を受ける機能・画面]

## テスト

- [ ] [確認済みのテスト項目]

## 備考

- [ ] 無し

🤖 Generated with [Claude Code](https://claude.ai/code)
```

### Step 6: リモートへプッシュ（必要な場合）

現在のブランチがリモートに存在しない、またはローカルが先行している場合：

```bash
git push -u origin HEAD
```

### Step 7: PR作成

```bash
gh pr create \
  --base <ベースブランチ> \
  --title "<PRタイトル（70文字以内）>" \
  --body "$(cat <<'EOF'
[Step 5で作成した本文]
EOF
)"
```

### Step 8: 完了報告

作成されたPRのURLをユーザーに提示する。

---

## 注意事項

- タイトルは70文字以内、詳細は本文に記載する
- `main` / `master` へのforce pushは行わない
- 未コミットの変更がある場合は先にコミットを促す
- ベースブランチは必ずユーザーに確認してから進める
