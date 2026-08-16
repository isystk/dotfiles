---
name: claude-code-web-dev
description: Claude Code on the web（クラウドサンドボックス）に開発タスクを委任し、進捗をポーリングしてPR作成まで伴走するスキル。ローカルでDocker等の開発環境を起動せずにコード修正・テスト実行・フォーマット適用を行いたい場合に使う。`gh issue comment`/`gh pr comment`で`@claude`メンションしてクラウドセッションを起動する方式を優先し、使えない場合のみ`claude --cloud`（ユーザー実行）にフォールバックする。「クラウドで開発して」「Claude Code on the webでやって」「ローカルの負荷をかけずに直して」「--cloudで投げて」「@claudeで投げて」等の依頼で使用する。ブラウザでの動作確認が必要なタスクには使えない。
---

# Claude Code on the Web 開発委任スキル

## 目的

ローカルにDocker等の開発環境を起動せず、Anthropic管理のクラウドVMへ開発タスクを委任し、
テスト実行・フォーマット適用・PR作成までを完結させる。

## 使えない場面

- ブラウザでの目視動作確認が必要なタスク（クラウドVMはポート公開・画面確認の手段がない）
- 4vCPU/16GB RAM/30GBディスクを超える負荷が想定されるタスク

このような場合は通常どおりローカルで対応する。

## 前提：クラウド起動には2方式ある

| 方式 | 起動コマンド | 実行者 | 進捗確認 |
|---|---|---|---|
| **A. `@claude`メンション（優先）** | `gh issue comment` / `gh pr comment` | **AI自身がBashで実行可能** | AI自身が`gh issue/pr view --comments`でポーリング可能 |
| B. `claude --cloud`（フォールバック） | `claude --cloud "<指示>"` | ユーザーの対話端末が必須 | ユーザーがブラウザのセッションURLで確認 |

**方式Aを優先する。** `gh issue comment`/`gh pr comment`は通常のAPIコールでありAI自身のBashツールから実行できるため、ユーザーの手を煩わせず、進捗確認まで自動化できる。方式Aが使える条件は「対象リポジトリ or Organizationに Claude GitHub App がインストール済み」であること。事前確認1.でこれを確認する。

方式Bは、方式Aが機能しない（未インストール、または送信後しばらく待っても反応がない）場合のフォールバックとして残す。`claude --cloud`は対話端末（TTY）必須のコマンドであり、**このスキルを実行しているAI自身（Bashツール経由の非対話実行）からは実行できない**（`--cloud requires an interactive terminal`で失敗する）。

いずれの方式でも、代替手段としてAgentツールの`isolation: "remote"`等で肩代わりしてはならない。それはAnthropic管理のクラウドVM（GitHubから対象リポジトリを新規clone、独立したgit資格情報を持つ）ではなく、このセッション自身が使っているローカルのワークツリーに対して作業する別物であり、「クラウドへ委任した」ことにならない（2026-08-06、x-growth-pulseでこの誤代用が発生し、ローカルワークツリーに未commit差分が生成されただけでgit commit/push/PRが権限エラーで実行できずStep 4以降が完遂できなかった実績あり）。

## 事前確認

### 1. GitHub連携（Step 1着手前に必ず済ませる）

**方式A（`@claude`メンション）が使えるかは事前に確実な判定手段がない。** `gh api repos/<owner>/<repo>/installation`等はGitHub App自身のJWT認証が必要でユーザートークンでは判定できないため、「Step 1で実際に送ってみて数分待ち、反応がなければ方式Bへ切り替える」運用で判定する。

**着手前に`.github/workflows/claude.yml`の有無と`gh secret list --repo <owner>/<repo>`を軽く確認しておく。** どちらか欠けている、または送信後に無反応・`is_error:true`即失敗（認証エラー）が出た場合は、`claude-github-app-setup`スキルへ切り替えて初回セットアップ・トラブルシューティングを行う（`/install-github-app`はGitHub Appのインストールまでしか行わず、ワークフローYAML作成・シークレット登録は別途手動が必要なため、未整備なまま方式Aだけ試して延々と反応待ちする事態を避ける）。

方式B（`claude --cloud`）を使う場合、以下のいずれかが済んでいるか確認する。**未確認・不明な場合は、Issue作成前にユーザーの対話端末で`/web-setup`を先に実行してもらい、`Connected as <username>`の表示が出ることを確認してから次へ進む**（後追い対応にしない）。

- Web版オンボーディングでClaude GitHub Appを認可済み
- 直近のセッションで`/web-setup`実行済みと確認が取れている

**注意:** `/web-setup`はローカルの`gh`トークンをClaudeアカウントに同期するだけで、GitHub App型のインストール（リポジトリのContents読み取り等の実権限）とは別物。`git_repository source`への`Authentication failed`が出た場合は、`/web-setup`ではなく以下を疑う。

1. https://github.com/settings/installations の「Installed GitHub Apps」にClaudeが無い、またはリポジトリアクセス許可に対象リポジトリが含まれていない → claude.ai/code のセッション作成画面（リポジトリ選択欄）からGitHub App型の権限設定を行うようユーザーへ案内する
2. それでも解決しない場合、claude.ai/code のWeb UI上で直接指示を入力してセッションを作る方が確実なことがある（`claude --cloud`経由よりWeb UI直接操作の方が認証経路が安定していた実績あり）

### 2. 対象リポジトリ・ブランチの未push差分

クラウドVMはGitHubからリポジトリをcloneする。ローカルにのみ存在するコミットは届かないため、
着手前に以下を確認する。

```bash
git status
git log @{u}.. --oneline   # ローカル先行コミットの有無
```

未pushコミットがあれば、着手前に `git push` するようユーザーに確認する。

### 3. タスク内容のヒアリング

以下が不明瞭な場合はユーザーに確認してから進める。

- 対象リポジトリ（複数プロジェクトを横断しない。1タスク1リポジトリ）
- 変更内容・完了条件（テスト通過、フォーマット適用、特定バグの修正など）
- Docker/DB（PostgreSQL・Redis等）を使う場合はその旨を明記する（クラウドVMにプリインストール済みだが、起動はClaudeへの指示が必要）

### 4. Issue/PRテンプレートの決定

Issue・PR作成には以下のテンプレートを使う。**優先順位: 対象リポジトリ内の既存テンプレート > dotfilesの共通テンプレート**。

- Issue: 対象リポジトリの `.github/issue_template.md`（または `.github/ISSUE_TEMPLATE/` 配下）があればそれを使う。なければ `~/dotfiles/.github/issue_template.md`
- PR: 対象リポジトリの `.github/pull_request_template.md` があればそれを使う。なければ `~/dotfiles/.github/pull_request_template.md`

クラウドVMは対象リポジトリのみをcloneし `~/dotfiles` は参照できない。dotfilesテンプレートを使う場合はStep 4の指示文にテンプレート本文をそのまま埋め込んで渡す。対象リポジトリ内のテンプレートを使う場合はクラウド側からも読めるため、「`.github/pull_request_template.md` の構成に従って」と指示するだけでよい。

## 手順

### Step 0: 実行計画立案 → Issue作成

1. タスク内容から実行計画（概要・対象・完了条件）を組み立て、決定したIssueテンプレート（上記4.）のフォーマットに当てはめて下書きする
2. 下書きをユーザーへ提示し、承認を得る（内容確認なしで作成しない）
3. 承認後にIssueを作成する

```bash
gh issue create --repo <org/repo> --title "<タイトル>" --body-file <下書きファイルパス>
```

### Step 1: クラウドセッション起動

#### 方式A（優先）: `@claude`メンションで起動 — AI自身が実行

Issueへ`@claude`メンション付きコメントを投稿する。これは通常の`gh`コマンドなのでAI自身のBashツールで実行してよい（ユーザーの手を借りる必要がない）。

```bash
gh issue comment <N> --repo <org/repo> --body "@claude Issue #<N> の内容を参照して実装してください。実装後は自己レビュー、既存テスト・フォーマッタ（該当プロジェクトの規約に従う）を実行して全て通ることを確認し、PRを作成してください。"
```

例：

```bash
gh issue comment 439 --repo your-org/your-repo --body "@claude Issue #439 の内容を参照して実装してください。実装後は自己レビュー、既存テスト・フォーマッタを実行して全て通ることを確認し、PRを作成してください。"
```

投稿後、5分程度待ってからStep 2の方法でコメント・関連PRの有無をポーリングする。**反応が一切なければ方式Aは使えない環境と判断し、方式Bへ切り替える。** その旨をユーザーへ報告してから切り替える（無反応をエラーとして即断せず、実行中の可能性もあるため2〜3回はポーリング間隔を空けて確認する）。

既存PRへの追加指示（CI失敗の修正依頼等）も同様に`gh pr comment`で送れる。

```bash
gh pr comment <PR番号> --repo <org/repo> --body "@claude CIが落ちているので修正してください。"
```

#### 方式B（フォールバック）: `claude --cloud`をユーザーに実行してもらう

方式Aが使えないと判断した場合のみ、以下の手順をユーザーへ提示して対話端末で実行してもらう。**必ず対象リポジトリのローカルディレクトリへ`cd`してから実行するよう明記する**（クラウドセッションは起動時のカレントディレクトリを対象リポジトリの手がかりに使うため、無関係なディレクトリで実行すると誤ったリポジトリへのpush権限確認が出ることがある。別リポジトリのディレクトリから実行し、無関係なリポジトリへのpush権限確認が出た実績あり）。

```bash
cd <対象リポジトリのローカルパス>
claude --cloud "<対象リポジトリ> の Issue #<N>（<Issue URL>）を参照して実装して。実装後は自己レビュー、既存テスト・フォーマッタ（該当プロジェクトの規約に従う）を実行して全て通ることを確認して"
```

実行すると`Created cloud session: ...`とセッションURL（`https://claude.ai/code/session_xxx`）が表示されてすぐ元のシェルに戻る。この出力をユーザーから共有してもらう。

##### `--cloud requires an interactive terminal` エラーが出た場合

このスキルの実行者（Bashツール経由の非対話実行）が誤って自分で`claude --cloud`を叩いた場合に発生する。このコマンドは常にユーザーに実行してもらう対象であり、自分で実行を試みないこと。

##### 接続エラー（GitHub連携・認証切れ）が出た場合

`/web-setup`を実行しても`Authentication failed while accessing the git_repository source`が再発する場合は、事前確認1.の「注意」記載の通りGitHub App型インストールの不足が原因のことが多い。ユーザーへclaude.ai/code側のリポジトリアクセス設定確認、またはWeb UI直接操作への切り替えを案内する。

### Step 2: 進捗ポーリング

**方式Aの場合、AI自身がBashで完結する。**

```bash
gh issue view <N> --repo <org/repo> --comments
# PRが作られていれば
gh pr view <PR番号> --repo <org/repo> --comments
gh pr list --repo <org/repo> --head claude/ --json number,title,url,updatedAt
```

Claudeからの返信コメントに質問が含まれる場合は代わりに判断せず、ユーザーへ確認する（不明点は推測しないルールに従う）。

**方式Bの場合**、`claude --cloud`はセッション作成後すぐ元のシェルに戻るため、そのシェル上で`/tasks`は使えない（`/tasks`はローカルの通常`claude`対話セッション内でのみ有効なコマンド）。進捗確認は、Step 1で表示されたセッションURL（`https://claude.ai/code/session_xxx`）をユーザーにブラウザで開いてもらう形で行う。

状況（実行中/権限確認待ち/質問待ち/完了/エラー）をユーザーから共有してもらう。

- **権限確認ダイアログ（`Claudeに...を許可しますか？`）が出た場合**、表示された`owner`/`repo`が意図した対象リポジトリと一致するか必ず確認してから許可するようユーザーに伝える。一致しない場合は許可せず「拒否」を選び、Step 1のディレクトリ指定を確認し直す
- Claudeが質問を投げてきた場合は代わりに判断せず、ユーザーへ確認する（不明点は推測しないルールに従う）

### Step 3: 完了確認

自己レビュー・テスト・フォーマットが通っていることを確認する。通っていなければ`gh issue comment`/`gh pr comment`（方式A）またはセッションへの追加指示（方式B）で修正を依頼する。

クラウド環境にDocker/DBが無くテスト実行が完結しないことがある（構文チェックとコードレビューのみで終える場合あり）。その場合はセッションの完了報告に「未検証」の記載がないか確認し、あればユーザーへローカルでのテスト実行を依頼する。

### Step 4: PR作成

方式Aでは、指示文に「PRを作成してください」を含めていれば自動でコミット・push・PR作成まで行われることが多い。方式Bの場合はそのセッションへ「変更をコミットしてPRを作成して」と指示する。PR本文は上記4.で決定したテンプレートの構成に従わせる（dotfilesテンプレートの場合は本文をそのまま指示文に埋め込む）。コミットメッセージは通常のgit運用ルール（Conventional Commits、範囲を絞ったコミット等）に従わせる。

対象PRが別の未マージPRに依存する変更の場合（ベースブランチをfeature branchにする等）、依存元PRがマージされたらリベースが必要になる可能性がある旨をPR説明や報告に明記する。

### Step 5: 完了報告

PR URLをユーザーへ報告する。未検証項目（テスト未実行等）があれば併せて報告する。方式Bでローカルレビューが必要な場合は以下で引き継げる。

```bash
claude --teleport <session-id>
```

## 注意事項

- 全コマンドはClaude経由で実行される（クラウドVMへの直接シェルアクセスはない）。テスト・フォーマッタも「〜を実行して」という指示の形で依頼する
- クラウド環境にはAPIキー等の専用シークレットストアがない。環境変数・setup scriptに機密情報を置かない
- セッションはアイドルで一定時間後に期限切れになる。長時間放置した場合は claude.ai/code から再開する
- 複数タスクを並列で投げる場合、方式Aなら`gh issue comment`を複数Issueに対して送ればよい。方式Bなら`claude --cloud`を複数回実行すれば独立したセッションになる

## コマンド早見

| コマンド | 用途 |
|---|---|
| `gh issue create --repo <org/repo> --title "<t>" --body-file <f>` | 実行計画をIssueとして登録 |
| `gh issue comment <N> --repo <org/repo> --body "@claude ..."` | **方式A（優先）**: `@claude`メンションでクラウドセッションを起動（AI自身が実行可） |
| `gh pr comment <N> --repo <org/repo> --body "@claude ..."` | **方式A**: 既存PRへ追加指示（CI修正依頼等） |
| `gh issue view <N> --repo <org/repo> --comments` / `gh pr view <N> --repo <org/repo> --comments` | **方式A**: 進捗ポーリング（AI自身が実行可） |
| `cd <repo> && claude --cloud "<指示>"` | **方式B（フォールバック）**: 対象リポジトリのルートで新規クラウドセッションを開始（**ユーザーが実行**） |
| セッションURL（`claude --cloud`実行時に表示）をブラウザで開く | **方式B**: 進捗確認（`/tasks`は`claude --cloud`実行後のシェルには効かない） |
| `claude --teleport <session-id>` | クラウドセッションをローカルへ引き継ぎ |
| `/web-setup` | ローカルの`gh`トークンをClaudeアカウントに同期（方式Bの事前準備） |
| `/remote-env` | CLIから使うデフォルトのcloud environmentを選択 |
