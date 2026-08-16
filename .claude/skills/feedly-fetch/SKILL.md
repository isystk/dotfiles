---
name: feedly-fetch
description: FeedlyのSaved for Later（保存記事）を、Playwright MCPの共有Googleログインプロファイルを使ってヘッドレス取得するスキル。Feedly公式Developer APIはFeedly Pro必須のため使わず、通常ログインセッション（永続Chromeプロファイル）を再利用して内部API応答を取得する。「Feedlyの保存記事を取得して」「Feedlyの記事を見て」等の依頼で使用する。
---

# Feedly Fetch Skill（Playwright方式）

## Goal

Feedlyの「保存済み記事（Saved for Later）」一覧を、ユーザー自身の無料アカウントの
通常ログインセッションを使って取得する。Feedly公式Developer API
（https://feedly.com/v3/auth/dev ）はFeedly Pro必須のため使用しない。

## 方式の概要

1. ログインは `google-chrome-login` スキルが管理する共有Chromeプロファイル
   （`~/.claude/tools/google-auth/chrome-profile`）で行う（Feedly自体はGoogleアカウントで
   なくメール/パスワードでもよいが、同じ共有プロファイルにログインしておけば流用できる）
2. `fetch_saved.mjs`（ヘッドレスPlaywright）が共有プロファイルを一時複製して読み込み、
   `feedly.com/i/saved` を開いて内部API（`api.feedly.com/v3/streams/contents?streamId=...global.saved...`）の
   レスポンスを傍受し、記事一覧をJSONで取得する

## 既知のハマりどころ（絶対に省略しない）

- **Node ESMはグローバルnode_modulesを解決しない**（`NODE_PATH`もESM importには効かない）。
  `scripts/node_modules` は `npm root -g` へのシンボリックリンクとして必須。削除すると
  `ERR_MODULE_NOT_FOUND: playwright` で起動不能になる
  ```bash
  ln -s "$(npm root -g)" ~/.claude/skills/feedly-fetch/scripts/node_modules
  ```
- **ログインはheadless不可**（Google OAuth・Cloudflare Turnstile双方がbot検知でheadless
  Chromiumを弾く）。ログイン自体は `google-chrome-login` スキル（headed共有プロファイル）
  に委譲し、本スキルはログイン後のプロファイルを読むだけに徹する。
- **プロファイルのロック競合回避**: 共有プロファイルはPlaywright MCPが常時使っている
  可能性があるため、`fetch_saved.mjs` は直接開かず一時ディレクトリに複製してから
  ヘッドレスで開く（`launchPersistentContext`）。複製元のログイン状態はそのまま
  引き継がれる。
- これはFeedly公式のAPI利用方法ではなく、Web UIのログインセッションを流用する手法。
  Feedly側の規約・仕様変更で動作しなくなる可能性がある（グローバルルール6準拠、
  取り扱いに注意）
- セッションは失効することがある（0件取得時はその可能性が高い）。
  その場合は `google-chrome-login` スキルで共有プロファイルに再ログインする
- `fetch_saved.mjs` は `page.waitForResponse()` で対象APIレスポンスを確実に待ってから
  `context.close()` する設計。`page.on('response', async...)` ＋固定`waitForTimeout`方式は
  イベントハンドラの非同期JSON解析が`close()`に間に合わずデータが失われる競合が発生しうる
  （実際に間欠的に0件になる不具合として発生済み）ため使わない
- 高頻度・大量アクセスはアカウント制限やアクセスブロックのリスクがあるため、
  必要な範囲のみ取得する

---

## Phase 0: ログイン状態の確認

Playwright MCPで `https://feedly.com/i/saved` にnavigateし、ログイン済みか確認する
（Googleアカウントでログインしている場合は `accounts.google.com` にリダイレクトされる）。

未ログイン・またはFeedly自体の再ログインが必要な場合は `google-chrome-login` スキルを
呼び出す（確認先URLとして `https://feedly.com/i/saved` を伝える）。共有プロファイルの
実Chromeウィンドウでユーザーに直接ログインしてもらう。

`scripts/node_modules` シンボリックリンクの存在も確認する（なければ上記コマンドで作成）。

---

## Phase 1: 保存記事の取得

```bash
node ~/.claude/skills/feedly-fetch/scripts/fetch_saved.mjs \
  ~/.claude/tools/google-auth/chrome-profile [件数上限]
```

- 第1引数（省略可）: 共有Chromeプロファイルのパス。省略時は
  `~/.claude/tools/google-auth/chrome-profile` を使う
- 第2引数（省略可）: 取得件数の上限。省略時はFeedly API既定の最大20件を返す
- 標準出力: `[{id, title, url, published, summary}, ...]` のJSON配列（新着順）
- 0件の場合は標準エラーに警告が出る → セッション失効の可能性 → Phase 0を再実施

取得後、ユーザーの依頼に応じて一覧表示・要約・フィルタリングをClaudeが行う。

---

## ファイル構成

```
feedly-fetch/
├── SKILL.md
└── scripts/
    ├── fetch_saved.mjs    # 共有プロファイルを一時複製し、ヘッドレスで保存記事取得
    └── node_modules -> $(npm root -g)  # シンボリックリンク（ESM解決に必須。削除不可）
```

ログインセッション本体は本スキル配下ではなく `~/.claude/tools/google-auth/chrome-profile`
（`google-chrome-login` スキル管理）に集約されている。
