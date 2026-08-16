---
name: chatgpt-codex-ops
description: Claude CodeからOpenAI公式Codex CLI（codex）経由でChatGPT（GPT系モデル）を呼び出すスキル。セカンドオピニオン取得、他モデルによるレビュー・調査・コード生成の相互検証などに使う。未インストール・未ログインの場合はセットアップ手順を提示する。「ChatGPTに聞いて」「Codexに確認して」「他のAIの意見も聞きたい」「GPTでレビューして」等の依頼で使用する。
---

# ChatGPT (Codex CLI) Operations Skill

## Goal

Claude CodeからOpenAI公式の **Codex CLI**（`codex` コマンド）経由でChatGPT/GPT系モデルを呼び出す。
Claude自身の回答に対するセカンドオピニオン取得、独立した視点でのコードレビュー、
調査結果のクロスチェックなどに使う。

## 前提・注意事項

- `codex` はOpenAI公式CLI（`@openai/codex`）。MCP経由ではなくCLI直接呼び出しで運用する
  （非公式MCPラッパーは信頼性が低いため採用しない）。
- 認証は ChatGPTアカウントログイン（`codex login`）または APIキー のいずれか。
  ログインはブラウザ操作が必須なため、Claude Codeの実行環境からは完結できない場合がある。
- 外部LLMに投げる内容に機密情報・顧客情報が含まれないか、送信前に必ず確認する
  （グローバルルール「6. セキュリティのルール」準拠）。

---

## Phase 0: セットアップ状態の確認

タスク開始時、必ず以下を確認する。

```bash
which codex
codex --version
codex doctor 2>&1 | grep -A6 -i "auth"
```

### ケースA: 未インストール（`codex` が見つからない）

```bash
npm install -g @openai/codex
```

を実行してよいかユーザーに確認してから実施する。

### ケースB: 未ログイン（`codex doctor` の auth 項目が未設定）

自動ログインを試みず、以下をユーザーに提示してストップする。

```
ChatGPT（Codex CLI）が未ログインです。
お使いの端末で以下を実行し、ブラウザでログインしてください。

codex login

ログイン後、以下で状態を確認できます。
codex doctor
```

APIキー方式を使いたい場合は `codex login --api-key <KEY>` も案内する。

---

## Phase 1: 非対話実行

質問・レビュー依頼は `codex exec` で非対話実行する。

```bash
codex exec "<プロンプト>"
```

- 標準出力の `codex` セクション以下が回答本文。`tokens used` 行以降は使用トークン数。
- ファイルを読ませて意見を聞きたい場合は、プロンプト内にパスまたは内容を含める。
- 実行ディレクトリ（workdir）はカレントディレクトリになる点に注意
  （コードレビュー等でリポジトリ内のファイルを参照させたい場合は該当ディレクトリで実行する）。
- デフォルトはread-onlyサンドボックス・approval never（安全側）。ファイル変更を伴う操作は
  依頼しない（変更が必要な場合はClaude Code側で行う）。

### 実行例

```bash
codex exec "次のコードの脆弱性を指摘して: $(cat app/Services/PaymentService.php)"
codex exec "この設計方針についてセカンドオピニオンが欲しい: リポジトリ層をやめてQueryBuilderを直接使う案"
```

---

## Phase 2: 使いどころ

- Claudeの回答・実装方針に対する独立レビュー（モデル間クロスチェック）
- 複数モデルの意見を並べて社長・ユーザーに提示したい場合
- 単純な事実確認・ライブラリ構文確認には使わない（`context7` / `WebSearch` を優先）

## 出力の扱い

- ChatGPT側の回答は「意見」として明示し、Claudeの結論と混同しない
  （グローバルルール「3. 判断のルール」＝事実と意見を分けて書く、に準拠）。
- 成果物に転記する場合は「（ChatGPT意見）」等の出典を明記する。
