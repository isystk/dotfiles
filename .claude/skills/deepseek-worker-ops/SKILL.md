---
name: deepseek-worker-ops
description: Claude Codeを司令塔にして、DeepSeekを作業員として動かすスキル。DeepSeekのAnthropic互換エンドポイントに接続した別プロセスの `claude -p` を起動し、ファイルの読み書きを伴う作業（下書き作成、コード実装の叩き台、大量ファイルの調査・要約・機械的編集）を委任する。「ディープシークにやらせて」「DeepSeekで作業して」「安いモデルに任せて」等の依頼で使用する。機密情報を含む作業には使わない。
---

# DeepSeek Worker Operations Skill

## Goal

Claude Code（司令塔）が作業を分解し、定型・大量・下書き系の作業を DeepSeek（作業員）に委任する。
結果の検収・統合・最終判断は必ず司令塔（Claude）が行う。

## 仕組み

- DeepSeek は Anthropic 互換エンドポイント `https://api.deepseek.com/anthropic` を公開している
  （公式: https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code ）。
- `scripts/run.sh` が環境変数を差し替えて別プロセスの `claude -p --bare` を起動する。
  親セッションの環境は変えない。
- `--bare` によりフック・CLAUDE.md自動読込・keychain・auto-memory は無効。
  親の社内ルールや認証情報は DeepSeek に渡らない。必要な文脈は指示文に明記して渡す。
- `--bare` では Anthropic 認証が `ANTHROPIC_API_KEY`（または apiKeyHelper）に限定される。
  `run.sh` が `ANTHROPIC_API_KEY` を使うのはこのため。`ANTHROPIC_AUTH_TOKEN` へ変えると
  `--bare` では認証されないので置き換えない。`deepseek on`（`scripts/deepseek.zsh`。Claude Code 本体を
  そのターミナルだけ DeepSeek へ向ける）も同じ変数に揃えている。
- モデル既定は `deepseek-flash`。高精度が必要なときのみ `DEEPSEEK_MODEL=deepseek-v4-pro`（料金は高い）。
  旧名の `deepseek-v4-flash` は廃止済み（`deepseek-flash` に統合され、V4.1-Flash で課金される）。

## セットアップ（初回のみ。Claude は自動実行しない）

ユーザーに以下を案内して止まる。

1. https://platform.deepseek.com でAPIキーを取得（要チャージ）。
2. `~/.setenv.local`（Git管理外）に `export DEEPSEEK_API_KEY=キー` を追記する
   （雛形は `~/dotfiles/.setenv.local.example`。`.zshrc` が `~/.setenv.local` を source する）。キー文字列をチャットに貼らない。
   追記後、シェルを再読込し、Claude Code を再起動する（環境変数は起動時に継承されるため）。
3. 代替: 環境変数を使わない場合は `~/.config/deepseek/api_key`（権限600）にキーのみを保存しても動く。
   環境変数が設定されていればそちらを優先する。

Claude はキーの値を読まない・表示しない。環境変数の一覧表示（`env` 等）もしない。

## 送信前チェック（必須）

DeepSeek は中国企業のサービス。送信内容は同社のサーバーに渡る。次を含む作業は委任しない。

- 顧客情報・個人情報・従業員管理配下・健康情報
- APIキー・トークン・`.env`・本番の接続情報
- 社外秘の財務数値・未公開の契約情報

`run.sh` は `.env*`・`.setenv.local*`・`*.pem`・`*.key`・`id_rsa*`・`auth.json`・`credentials*` の読み書きを禁止している（`--disallowedTools`）。
ただしこれは補助であり、他の秘密ファイルが作業ディレクトリにないかは委任前に確認する。
`full` モード（Bash 許可）では `cat` 等で回避できるため、この禁止は実質無効になる。`full` を使う前に作業ディレクトリ内に秘密ファイルが無いことを確認する。

作業ディレクトリは、委任に必要な最小範囲に限定する（リポジトリ全体ではなく対象サブディレクトリ）。
不安なときは `check-privacy-and-secrets` スキルで先に確認する。

## 実行手順

1. 委任する作業を決め、完了条件・対象ファイル・禁止事項を含む指示文を書く。
2. 権限モードを最小で選ぶ。
   - `read`: 調査・レビュー・要約（ファイル変更なし）
   - `edit`: 作業ディレクトリ内のファイル編集
   - `full`: コマンド実行も許可。使う前に毎回ユーザーへ確認する
3. 実行（指示文は stdin）:

```bash
bash ~/.claude/skills/deepseek-worker-ops/scripts/run.sh <作業ディレクトリ> <read|edit|full> <<'EOF'
（指示文）
EOF
```

- 上限金額は既定 1 USD（`DEEPSEEK_MAX_USD` で変更）。
- `edit` / `full` の後は必ず `git diff` で変更内容を検収する。範囲外の変更は元に戻す。
- 長時間になりうる作業は `run_in_background` で実行する。ハングに備える場合は `timeout 300 bash ...` のように前置する。

## 司令塔の責務

- DeepSeek の出力は「作業員の成果物」として扱い、検証（テスト・diff確認）してから採用する。
- 事実確認が必要な内容は鵜呑みにしない（ハルシネーションの可能性）。
- 成果物に転記する場合は出典に「（DeepSeek作成・Claude検収）」と明記する。
- 設計判断・仕様の確定・コミット・外部公開は Claude とユーザーが行う。DeepSeek に任せない。

## 向き・不向き

- 向く: 大量ファイルの機械的編集、翻訳、下書き、定型コード生成、広範囲の読み取り調査。
- 不向き: 機密を含む作業、複雑な設計判断、日本語の最終文面の品質が重要な成果物、セキュリティ関連の変更。

## トラブル対応

- `APIキーが見つかりません` → セットアップ手順を案内。
- `[claude-code:unrecognized_model] {"model":"deepseek-flash"}` が stderr に出る → DeepSeek 側でモデル名を解決するため実害なし。無視してよい。
- 400エラー（model not supported）→ モデル名を `deepseek-flash` または `deepseek-v4-pro` にする。
- 認証エラー → キーの失効・残高不足を疑い、ユーザーに DeepSeek Platform の確認を依頼する。
- 最新の変数名・モデル名は公式ページで再確認する（仕様は変わりうる）。
