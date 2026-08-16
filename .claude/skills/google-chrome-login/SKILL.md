---
name: google-chrome-login
description: Use when a Playwright MCP browser navigation redirects to accounts.google.com (Google Analytics, NotebookLM, Feedly Google OAuth, Google Drive, etc.), when Playwright MCP keeps losing its Google login between sessions, or before automating any Google-authenticated service through Playwright MCP for the first time.
---

# Google Chrome Login (Playwright MCP)

## Overview

Playwright MCPが使う永続Chromeプロファイル（`--user-data-dir`）にGoogleアカウントで
ログインし、以後のPlaywright MCPセッションでログイン状態を維持する。GA4・NotebookLM・
Feedly等、Googleログインが必要なPlaywright MCP操作の前提として他スキルから呼ばれる。

一度ログインすればプロファイルにcookieが永続化され、次回以降は再ログイン不要
（Googleセッション自体が失効した場合のみ再実施）。

## 既知のハマりどころ（絶対に省略しない・2026-08-05実績）

- **headless不可**: Googleがheadless Chromiumを検知しbot判定でログインを拒否する
  （ログイン画面のリダイレクトが繰り返されるだけで進まない）。Playwright MCPは必ず
  headed（`--headless`を付けない）で起動する。
- **`--storage-state`は効かない**: Playwright MCPのデフォルト永続コンテキストモードでは
  `--storage-state`オプションは無視される（公式ヘルプ上は"for isolated sessions"用）。
  cookieをエクスポート/インポートする方式ではなく、`--user-data-dir`で永続プロファイルを
  直接使う方式が正解。
- **設定ファイルが二重にある**: `~/.claude/mcp_config.json`
  （実体は`~/dotfiles/.claude/mcp_config.json`へのsymlinkのことが多い）は参照用に
  過ぎないことがある。実際に使われるのは`~/.claude.json`トップレベルの
  `mcpServers.playwright`（`projects.<cwd>.mcpServers`が空でなければそちらが優先）。
  両方確認し、実際に有効な方を修正する。
- **設定変更はMCP再起動必須**: 設定ファイルを直しても実行中のPlaywright MCPプロセスには
  反映されない。`ps aux | grep playwright/mcp` で起動時引数を確認できる。反映には
  Claude Codeプロセス自体の完全な再起動が必要（`/mcp`のような軽量リロードは存在しない）。

## セットアップ（初回・設定ズレ検出時のみ）

1. 実際に使われるMCP設定ファイルを特定する：
   ```bash
   readlink -f ~/.claude.json
   grep -n -A10 '"playwright"' ~/.claude.json
   ```
2. `playwright`サーバー定義の`args`を確認し、必要なら修正する：
   - `--headless` があれば削除する
   - `--user-data-dir /root/.claude/tools/google-auth/chrome-profile` がなければ追加する
     （ディレクトリが無ければ `mkdir -p` で作成）
   - `--storage-state` があれば削除する（効かないため無意味）
3. `~/dotfiles/.claude/mcp_config.json`（symlink先）にも同じ内容を反映しておく
   （実際は使われていなくても、将来の混乱防止のため実態と一致させる）
4. 変更した場合はユーザーに **Claude Codeの完全な再起動** を依頼し、再起動後にログイン
   フローへ進む。

## ログイン確認・実施フロー

1. 呼び出し元が指定したURL（未指定なら `https://myaccount.google.com/`）にPlaywright MCPで
   navigateする。
2. 遷移先URLが `accounts.google.com` ならログイン画面表示中＝未ログイン。それ以外の
   URLに到達していればログイン済み・完了。
3. 未ログインの場合、ユーザーに「Playwright MCPが開いたウィンドウ（実Chrome）で直接
   ログインしてください」と伝える。このブラウザは実画面表示されるheaded Chromiumなので
   ユーザーが直接操作できる。
4. ユーザーから完了報告を受けたら、同じURLに再度navigateして手順2を再確認する。
5. ログイン確認できたら呼び出し元スキルの処理に戻る。

## 他スキルからの呼び出し方

Google関連URLへのnavigateで `accounts.google.com` にリダイレクトされた場合、呼び出し元
スキルはこのスキルを呼び出す：

```
Skill: google-chrome-login
```

確認先URLを伝えたい場合は依頼文にURLを含めて呼び出す（例:「NotebookLMにログインして。
確認URLは https://notebooklm.google.com/ 」）。

## 注意

- `~/.claude/tools/google-auth/chrome-profile/` はGoogleログインセッション（cookie等）を
  保持する機密ディレクトリ。Git管理対象に絶対含めない。
- Playwright MCPは通常プロジェクト横断の単一プロセスのため、一度ログインすれば他プロジェクト
  のタスクでもログイン状態が共有される。
