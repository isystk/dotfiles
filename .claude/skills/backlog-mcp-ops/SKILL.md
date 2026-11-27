---
name: backlog-mcp-ops
description: Claude CodeからMCP経由でBacklog（課題・Wiki・プロジェクト）を参照・操作するスキル。公式 nulab/backlog-mcp-server を APIキー方式（npx・stdio）または OAuth方式（ローカル常駐・HTTP MCP）のどちらでも接続できる。未セットアップの場合は WSL 向けのセットアップ手順を案内する。書き込み系操作は実行前に必ずユーザー確認する。「Backlogの課題を見て」「Backlogに課題を登録して」「Backlog MCPをセットアップして」「Backlogに接続できない」等の依頼で使用する。
---

# Backlog MCP Operations Skill

## Goal

公式 **nulab/backlog-mcp-server** を Claude Code に接続し、Backlog の課題・Wiki・プロジェクトを操作する。
接続方式は2つ。**どちらか一方だけ**を `backlog` の名前で登録する。

- **APIキー方式**: `npx backlog-mcp-server` を stdio で Claude Code が自動起動する。常駐・再認可が不要。
- **OAuth方式**: サーバーをローカル常駐させ、`http://localhost:3333/mcp`（HTTP MCP）に接続する。APIキーを持たない。
  参考: https://dev.classmethod.jp/articles/backlog-mcp-server-oauth-claude-code-without-api-key/
  （記事は macOS/launchd 前提。本スキルは WSL2 + systemd + mise(Node 22) 向けに読み替えている）

## 前提・注意事項（絶対に省略しない）

共通:
- OAuth 記事時点の版は v0.23.3、全64ツール（うち書き込み系26）。版が変わるとツール数・名前も変わる。
- **1つの Backlog スペースにのみ対応**する運用とする（OAuth は仕様上1スペース。APIキー方式の複数組織設定は未検証で扱わない）。
- **どちらの方式も権限は本人と同じ**（OAuth にスコープが無く、APIキーも本人の全権限）。
  MCP サーバーに読み取り専用モードも無い。そのため本スキルでは **書き込み前のユーザー確認** を運用で担保する（Phase 1）。
- **APIキー・Client Secret はチャット・スキル・コミットに書かない**。env ファイルはユーザー自身が編集し、`chmod 600` にする。
  Claude は env ファイルの中身を読まない（雛形作成まで）。
- 対象スペースのドメインはスキルに直書きしない。セットアップ時にユーザーへ1つずつ確認する。

OAuth 方式のみ:
- **トークンはサーバーのメモリにのみ保存**される。サーバー再起動（WSL 再起動・Windows 再起動・`Restart=always` による自動再起動を含む）で **再認可が必要**。
- **サーバーは常時起動が必要**。Claude Code は自動起動しない。
- 待ち受けは `127.0.0.1` のまま。`0.0.0.0` にしない（他マシンから到達できてしまう）。

---

## 方式の選択

| 観点 | APIキー方式（既定の推奨） | OAuth方式 |
|---|---|---|
| 準備 | キー発行のみ。clone/build 不要 | アプリ登録・clone・build・systemd 常駐 |
| 起動 | Claude Code が自動起動（stdio） | 常時起動が必要（WSL 停止で止まる） |
| 認証の維持 | 失効するまで有効 | サーバー再起動のたびに再認可 |
| 秘密情報 | 長寿命のキーを env ファイルに保管 | Client Secret を env ファイルに保管。キー自体は持たない |

- どちらにするかはセットアップ時にユーザーへ聞く（迷うなら APIキー方式）。
- 登録名 `backlog` は1つだけ。切替は `claude mcp remove backlog` → 再登録。
- 併用はしない。OAuth 変数（`BACKLOG_OAUTH_CLIENT_ID` 等）が設定されると OAuth モードになり、README は併用可否を明記していない。

---

## Phase 0: 状態確認

タスク開始時、以下を確認してからケースを判定する。

```bash
claude mcp list 2>&1 | grep -i backlog
```

まず登録済みの方式を識別する。

- `backlog` の行が無い → **未登録**（ケース A / A'）
- 行が `http://localhost:3333/mcp` → **OAuth 方式**。続けて以下を確認:
  ```bash
  systemctl --user is-active backlog-mcp 2>&1
  curl -s -m 3 http://localhost:3333/.well-known/oauth-authorization-server | head -c 200
  ls ~/src/backlog-mcp-server/build/index.js 2>&1
  ```
- 行が `start-apikey.sh` 経由 → **APIキー方式**。systemd・curl・ビルドの確認は不要

| 状態 | ケース |
|---|---|
| 未登録（どちらの方式か未決） | 方式をユーザーに確認 → **A: OAuth セットアップ** または **A': APIキー セットアップ** |
| OAuth: unit はあるが inactive／curl が応答しない | **B: サーバー停止** → `systemctl --user start backlog-mcp`、`journalctl --user -u backlog-mcp -n 30` で原因確認 |
| OAuth: curl 応答あり・`claude mcp list` が `Needs authentication` | **C: 認証切れ** → ユーザーに `/mcp` → `backlog` → Authenticate を依頼（サーバー再起動後は毎回これ） |
| APIキー: `Failed to connect` | トラブルシュート表へ（キー・ドメイン・npx 初回 DL を確認） |
| `Connected` | **D: 正常** → Phase 1 へ |

---

## ケース A': APIキー方式セットアップ

役割分担: **キー発行と env への記入はユーザー**、雛形とラッパー作成・登録は Claude が承認後に実行する。
進める前に「これから実行する内容」を提示して承認を得る。Node 22 以上を `node -v` で確認する（README に必要版の記載は無い。OAuth 版と揃える）。

### A'-1. ユーザー作業: APIキー発行

Backlog にログイン → 個人設定 → API → APIキーを発行して控える。キーは本人の全権限で、失効（削除）するまで有効。

### A'-2. Claude 作業: env 雛形とラッパー

`~/.config/backlog-mcp/env`（**キーは空欄の雛形**、`chmod 600`）:

| 変数 | 値 |
|---|---|
| `BACKLOG_DOMAIN` | スペースのドメイン（`https://` 無し）← ユーザーに確認 |
| `BACKLOG_API_KEY` | ユーザーが記入 |
| `ENABLE_TOOLSETS` | `space,project,issue,wiki,document`（任意。省略で全有効。git・notifications を外すと表示ツールが減る） |

OAuth 変数は入れない。任意で `PREFIX`・`MAX_TOKENS`（既定50000）・`OPTIMIZE_RESPONSE=1`・`LOG_LEVEL` も指定できる。

`~/.config/backlog-mcp/start-apikey.sh`（`chmod 700`）。OAuth 用の変数が env に残っていても OAuth モードにならないよう `unset` する。
`npx` は mise の絶対パスで解決する（Claude Code 起動時の PATH に mise shims が無い場合に備える）:

```bash
#!/bin/bash
set -a
. "$HOME/.config/backlog-mcp/env"
set +a
unset BACKLOG_OAUTH_CLIENT_ID BACKLOG_OAUTH_CLIENT_SECRET MCP_SERVER_BASE_URL MCP_TRANSPORT MCP_HTTP_HOST MCP_HTTP_PORT
exec "$(dirname "$(mise which node)")/npx" -y backlog-mcp-server
```

構文は `bash -n` で確認する。`mise which node` が解決できない環境では `which npx` の絶対パスを直書きする。
ユーザーに `BACKLOG_API_KEY` を自分で記入してもらい、完了の返事を待つ（中身は読まない）。

### A'-3. 登録と確認

既存の `backlog` 登録があれば先に `claude mcp remove backlog`。

```bash
claude mcp add --scope user backlog -- /bin/bash "$HOME/.config/backlog-mcp/start-apikey.sh"
claude mcp list 2>&1 | grep -i backlog
```

`Connected` を確認し、読み取りツールで課題を1件取得して疎通を確認する。
**`claude mcp add -e BACKLOG_API_KEY=...` での直接登録はしない**（キーが `~/.claude.json` に平文で残るため）。
npx は初回にパッケージを取得するため、最初の接続が遅いことがある。

---

## ケース A: OAuth方式セットアップ

役割分担を守る。**Backlog 側のアプリ登録・Client Secret の記入・ブラウザ認可はユーザー**、
clone/build/雛形/unit 作成は Claude が承認後に実行する。進める前にユーザーへ「これから実行する内容」を提示して承認を得る。
同じ `~/.config/backlog-mcp/env` を APIキー方式と共有する場合、OAuth 方式では `BACKLOG_API_KEY` を入れない（OAuth 変数と混在させない）。

### A-1. ユーザー作業: Backlog にアプリ登録

1. Backlog Developer サイトのアプリケーション登録画面を開き、「Manage application」から Nulab アカウントでログイン
2. 「Register new application」→ 以下を入力して Create
   - **Redirect URI**: `http://localhost:3333/callback`（`MCP_SERVER_BASE_URL` + `/callback` と完全一致させる）
   - Application name: 任意（許可画面に表示される）
   - Description / Websites URL: 任意
3. 表示された **Client ID** と **Client Secret** を控える（Secret はパスワード同様に扱う）

管理者でなくても登録できた旨の報告が記事にある（公式に管理者限定の記載は無い）。

### A-2. Claude 作業: 取得とビルド

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/nulab/backlog-mcp-server.git
cd backlog-mcp-server
pnpm install
pnpm run build
```

- Node 22 以上が必要。`node -v` を先に確認する（mise の Node を使う）。
- `pnpm` が corepack のダウンロード確認で止まる場合は、ユーザーに `corepack enable` 済みか確認してから進める。
- `git` はシェル関数で `/mnt/*` 配下だけ `git.exe` になる。`~/src` は WSL 側なので `/usr/bin/git` が使われる。

### A-3. Claude 作業: env 雛形と起動スクリプト

`~/.config/backlog-mcp/env`（**Secret は空欄の雛形**を作り、`chmod 600`）:

| 変数 | 値 |
|---|---|
| `BACKLOG_DOMAIN` | スペースのドメイン（`https://` 無し。例 `example.backlog.com`）← ユーザーに確認 |
| `BACKLOG_OAUTH_CLIENT_ID` | ユーザーが記入（設定すると OAuth モードになる） |
| `BACKLOG_OAUTH_CLIENT_SECRET` | ユーザーが記入 |
| `MCP_SERVER_BASE_URL` | `http://localhost:3333` |
| `MCP_TRANSPORT` | `http`（既定は stdio） |
| `MCP_HTTP_HOST` | `127.0.0.1` |
| `MCP_HTTP_PORT` | `3333` |
| `ENABLE_TOOLSETS` | `space,project,issue,wiki,document`（git・notifications は外す。選択肢: space/project/issue/wiki/git/document/notifications） |

`~/.config/backlog-mcp/start.sh`（`chmod 700`）。systemd には mise の PATH が通らないので **node は絶対パスで指定**する:

```bash
#!/bin/bash
set -a
. "$HOME/.config/backlog-mcp/env"
set +a
exec "$(mise which node)" "$HOME/src/backlog-mcp-server/build/index.js"
```

`mise which node` が systemd 下で解決できない場合は、`which node` の結果（例 `~/.local/share/mise/installs/node/<ver>/bin/node`）を直書きする。
Node を更新したら start.sh のパスも更新する。

ユーザーに Client ID / Secret を env ファイルへ自分で記入してもらい、完了の返事を待つ（中身は読まない）。

### A-4. Claude 作業: 起動確認 → 常駐化

まず手動で起動確認（別ターミナル／バックグラウンドで）:

```bash
~/.config/backlog-mcp/start.sh &
curl -s http://localhost:3333/.well-known/oauth-authorization-server
```

`authorization_endpoint` / `token_endpoint` / `registration_endpoint` を含む JSON が返れば成功。確認後は停止する。

常駐化は systemd user service（WSL は `systemd=true` 前提。`/etc/wsl.conf` で確認）。
`~/.config/systemd/user/backlog-mcp.service`:

```ini
[Unit]
Description=Backlog MCP Server (OAuth)

[Service]
ExecStart=/bin/bash %h/.config/backlog-mcp/start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now backlog-mcp
systemctl --user status backlog-mcp --no-pager | head
```

- WSL は Windows 側のシャットダウン／WSL 停止でサーバーも止まる。次回起動後は再認可（ケース C）が必要。
- ログは `journalctl --user -u backlog-mcp -n 50`。

### A-5. Claude Code への登録と認証

既存の APIキー方式の `backlog` 登録があれば先に `claude mcp remove backlog`。

```bash
claude mcp add --transport http --scope user backlog http://localhost:3333/mcp
```

その後 **ユーザーが** Claude Code で:

1. `/mcp` を実行 → `backlog` を選び「Authenticate」
2. ブラウザで Backlog の許可画面（アプリ名を確認）→ 許可
3. `Status: connected` / `Auth: authenticated` になれば完了（記事の例では Tools 50件表示）

認証は2区間: Claude Code↔MCP サーバー（MCP 認可仕様の OAuth／DCR で自動）と、MCP サーバー↔Backlog（OAuth 2.0 Authorization Code Grant）。
Claude Code が受け取るのは MCP サーバー用トークンのみ。Backlog のアクセストークン（有効期限1時間）は自動更新され、サーバー内にとどまる。

---

## Phase 1: 操作

ツール名は `mcp__backlog__<ツール名>`。実際の一覧はセッション内の MCP ツールで確認する（名前を推測で決め打ちしない）。

### 読み取り（確認不要）

課題の検索・詳細取得、コメント一覧、プロジェクト／Wiki／ドキュメントの参照など。
出力は課題キー・件名・ステータス・担当者・期限・優先度の要点のみ。全文ダンプしない。

### 書き込み（**必ず実行前にユーザー確認**）

課題追加・更新・削除、コメント追加、関連課題・カテゴリ・マイルストーン・ウォッチ変更、
プロジェクト作成・更新、Wiki／ドキュメントの追加・更新など、**データを変更するツールすべて**。

実行前に次を提示し、明示的な承認を得てから実行する:

1. 対象（スペース／プロジェクトキー／課題キー）
2. 実行するツール名
3. 変更内容（追加・更新する値の全項目。更新は変更前→変更後）

- 承認なしで実行しない。複数件の一括変更は件数と一覧を示してから確認する。
- 削除系はとくに慎重に。取り消せない旨を明記して再確認する。
- 読み取り専用かどうかの判定は、名前の印象ではなくツールの `readOnlyHint` を根拠にする（`tools/list`）。
  判断に迷うツールは書き込み系として扱う。
- 承認が取れなかった・曖昧な場合は実行せず、確認を続ける。

---

## トラブルシュート

| 症状 | 原因・対処 |
|---|---|
| `/mcp` で再認可を求められ続ける | サーバー再起動でトークン消失。ケース C の手順で再 Authenticate |
| 接続できない（`Failed to connect`） | サーバー未起動。`systemctl --user start backlog-mcp`、`journalctl` で確認 |
| unit が起動直後に failed（node が無い） | systemd 下は PATH 無し。start.sh の node を絶対パス化 |
| ブラウザ認可で redirect エラー | Backlog 登録の Redirect URI が `http://localhost:3333/callback` と不一致、または `MCP_SERVER_BASE_URL` とずれている |
| 認可後も権限が足りない | OAuth の権限は許可したユーザー本人と同じ。そのユーザーのスペース／プロジェクト参加状況を確認 |
| 別スペースを使いたい | 1スペースのみの運用。`BACKLOG_DOMAIN` を差し替え（OAuth は OAuth アプリも差し替えて再起動・再認可、APIキーは新スペースのキーに差し替え） |
| APIキー方式で `Failed to connect`・認証エラー（401 等） | キー無効・失効、またはドメイン違い。Backlog でキーを再発行し、env の `BACKLOG_DOMAIN`（`https://` 無し）を確認。`start-apikey.sh` を手動実行して標準エラーを見る |
| APIキー方式の初回接続が遅い・止まる | npx の初回パッケージ取得待ち。しばらく待って `claude mcp list` を再実行 |
| 意図しない方式（OAuth モード）で動く | env に OAuth 変数が残っている。ラッパーの `unset` 行と env の内容を確認 |
| 方式を切り替えたい | `claude mcp remove backlog` → もう一方のケース（A / A'）で再登録。OAuth から APIキーへ切り替えたら `systemctl --user disable --now backlog-mcp` で常駐を止める |
| ビルドで pnpm が止まる | corepack のダウンロード確認。`corepack enable` を確認 |
| サーバー更新後にツールが増えた | 書き込み系が増えても Phase 1 の確認ルールは同じ。`readOnlyHint` で再判定する |

## 参考: 記事が扱うが本スキルで採用しないもの

- `permissions.deny` による書き込み系26ツールの個別禁止（本スキルは「実行前に毎回ユーザー確認」方式を採用）。
  確認方式では不安な場合のみ、deny 方式へ切替を検討する（deny は Claude Code 経由のみ有効、ツール増加時に保守が必要）。
- 1Password（`op run`）による Client Secret / APIキー管理（必要になれば別途追加）。
- Docker 起動（APIキー方式）、複数組織設定（`BACKLOG_ORG_<NAME>_*`）。必要になれば別途追加。
- launchd（macOS 専用。本環境は systemd user service で代替）。
