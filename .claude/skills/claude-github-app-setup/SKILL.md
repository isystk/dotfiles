---
name: claude-github-app-setup
description: リポジトリに`.github/workflows/claude.yml`が無い、GitHub Issue/PRへの`@claude`メンションに反応がない、`/install-github-app`実行後もセットアップが完了していない疑いがある、またはClaude GitHub Actionsの実行が認証エラー（例:「Failed to authenticate. API Error: 401 Invalid bearer token」）で失敗する場合に使う。
---

# Claude GitHub App セットアップ

## Overview

`@claude`メンションでGitHub Issue/PRからクラウドセッションを起動する仕組み（`anthropics/claude-code-action`）の初回セットアップ手順とトラブルシューティング。`claude-code-web-dev`スキルの方式A（`@claude`メンション）が使えるようにする前提整備。

## 重要な誤解

`/install-github-app`は**GitHub Appのインストール（認可）までしか行わない**。ワークフローYAML作成・シークレット登録は別途手動が必要（自動でガイドされない場合がある）。`.github/workflows/`の有無と`gh secret list --repo <owner>/<repo>`の結果で、セットアップが完了しているか必ず確認すること。

## セットアップ手順

### 1. ワークフローファイル作成

公式サンプルを取得し配置する。

```bash
gh api repos/anthropics/claude-code-action/contents/examples/claude.yml --jq '.content' | base64 -d
```

`.github/workflows/claude.yml`として配置。プロジェクト固有のテスト/構文チェックコマンドを`claude_args`の`--allowedTools`に追加する（例: `Bash(make *),Bash(php -l *),Bash(vendor/bin/phpunit*)`）。Docker前提のmakeターゲットしかない場合、クラウド実行環境にDockerデーモンが無いことがあるため、単体コマンド（`php -l`等）へのフォールバックも許可しておく。

**注意**: `.github/workflows/*.yml`の新規作成・コミットはAuto Mode分類器にブロックされることがある。その場合はコマンドをユーザーに提示し、ユーザー側のターミナルで実行してもらう。

### 2. 認証方式を選ぶ（どちらか一方、対応を揃える）

| 方式 | 発行方法 | Secret名 | workflow側パラメータ |
|---|---|---|---|
| APIキー（従量課金） | console.anthropic.com/settings/keys | `ANTHROPIC_API_KEY` | `anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}` |
| OAuthトークン（Pro/Maxサブスク） | `claude setup-token` | `CLAUDE_CODE_OAUTH_TOKEN` | `claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` |

**Secret名とworkflowパラメータは必ずペアで一致させる**。`CLAUDE_CODE_OAUTH_TOKEN`という名前で登録したのに`anthropic_api_key`パラメータのままだと動かない（401エラーの典型原因）。

### 3. シークレット登録

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>
```

対話プロンプトで値を貼る。**ブラウザのWeb UI「Paste Secret」欄より`gh secret set`のCLI入力を推奨** — ブラウザ貼り付けは末尾に改行が混入しやすく、`Failed to authenticate. API Error: 401 Invalid bearer token`の原因になる（実際に発生した事例あり）。

**個人アカウント（Organizationではない）では組織シークレットが使えない**。`gh api users/<owner> --jq .type`で`User`か`Organization`か確認できる。`User`の場合、全リポジトリへ一括登録する方法はなく、リポジトリごとに`gh secret set`が必要。

### 4. GitHub Appのインストール範囲

https://github.com/settings/installations （個人・組織どちらも同じ画面）で対象リポジトリを「All repositories」に広げられる。ただし**ワークフローYAMLとシークレットはリポジトリ単位のまま**で、この設定だけでは動かない（1・3は別途必要）。

## 動作確認

```bash
gh issue comment <N> --repo <owner>/<repo> --body "@claude 簡単なタスクを指示"
# 数分待って
gh api repos/<owner>/<repo>/issues/<N>/comments --jq '.[-1].body'
```

## トラブルシューティング

**症状: コメント投稿から数秒で失敗、`total_cost_usd: 0`**

APIコール自体に到達せず即死しているサイン。ほぼ確実に認証エラー。原因を見るため`claude.yml`に一時的にデバッグ出力を追加する。

```yaml
- name: Run Claude Code
  uses: anthropics/claude-code-action@v1
  with:
    claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    show_full_output: true  # 原因特定後は必ず削除/falseに戻す
```

再実行後、`gh run view <run_id> --repo <owner>/<repo> --log`で`"text": "Failed to authenticate..."`のような実際のエラーメッセージが見える（`show_full_output`無しだとSDKログ全体が"hidden for security"で伏せられ、`is_error:true`しか分からない）。

**`show_full_output: true`は常時有効にしない** — SDKログ（プロンプト内容・コマンド出力）が平文でActionsログに残り、機密情報混入リスクがある。原因特定できたら削除するPRを別途出す。

**症状: 401 Invalid bearer token** → 手順3のトークン再発行・`gh secret set`での再登録（改行混入を避ける）。

**症状: `@claude`メンションに一切反応がない（コメントも付かない）** → GitHub Appがそのリポジトリにインストールされていない、または`.github/workflows/claude.yml`が存在しない/masterでない作業ブランチにしか無い。手順1・4を確認。

## claude-code-actionの仕様（誤解しやすい点）

- **PRは自動作成されない**。ブランチへのコミット・push＋「Create PR」の事前入力リンク提示までが仕様（`docs/capabilities-and-limitations.md`に明記）。リンクをクリックしてPR作成するのは人間の役目
- Claude botはPRの承認もできない（セキュリティ上の設計）
- デフォルトブランチ名はリポジトリごとに`master`/`main`と分かれる。作業ブランチを切る前に`gh repo view <owner>/<repo> --json defaultBranchRef -q .defaultBranchRef.name`で確認すること（取り違えて別ブランチ起点で作業した実例あり）
