---
name: notebooklm-mcp-ops
description: Claude CodeからMCP経由でGoogle NotebookLMを直接操作する（notebooklm-mcp-cli / nlm）スキル。Notebook作成、URL/PDF/テキストのソース追加、Deep Research実行、要約取得までをMCP Tool経由で自動実行する。未インストール・未ログインの場合はインストール手順を提示しユーザーに実施を促す。「NotebookLMを操作して」「NotebookLMでDeep Researchして」「このPDFをNotebookLMに追加して」等の依頼で使用する。手動貼り付け指示書が欲しい場合はnotebooklm-blog-strategyスキルを使う。
---

# NotebookLM MCP Operations Skill

## Goal

Claude Codeから **notebooklm-mcp-cli**（コミュニティ製、非公式）のMCPサーバーを経由して、
NotebookLMをAPIレベルで直接操作する。Notebook作成・ソース追加・Deep Research実行・
要約取得までをClaude Codeの自然言語指示だけで完結させる。

未セットアップの環境で呼ばれた場合は、ここで自動インストールしようとせず、
**ユーザーにローカル端末での実施を促す**（`nlm login` はブラウザ操作が必須なため、
Claude Codeの実行環境からは完結できない）。

## 前提・注意事項（絶対に省略しない）

- 本ツールはGoogle公式APIではなく、NotebookLMの内部APIを利用する**コミュニティ製MCP**。
  Google側の仕様変更で動作しなくなる可能性がある。
- 認証情報はブラウザ経由のCookie等で保存される。一定期間で失効し `nlm login` の
  再実行が必要になる場合がある。
- Googleアカウント認証情報を扱うため、グローバルルール「6. セキュリティのルール」に従い
  取り扱いに注意する。

---

## Phase 0: セットアップ状態の確認

タスク開始時、必ず以下を確認してからPhase 1以降に進む。

```bash
which nlm notebooklm-mcp
claude mcp list | grep -i notebooklm
nlm login --check 2>&1
```

### ケースA: 未インストール（`nlm` / `notebooklm-mcp` が見つからない）

自動インストールを試みず、以下をユーザーに提示してストップする。

```
NotebookLM連携ツール（notebooklm-mcp-cli）が未インストールです。
お使いの端末（ローカル）で以下を実行してください。

# 1. uvのインストール（未導入の場合）
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. notebooklm-mcp-cliのインストール
uv tool install notebooklm-mcp-cli

# 3. インストール確認
nlm --help
notebooklm-mcp --help

# 4. Googleアカウントでログイン（ブラウザが起動します）
nlm login
nlm login --check

# 5. Claude CodeへMCPサーバーを登録
nlm setup add claude-code

# 6. Claude Codeを再起動 or /mcp で再読み込み

完了したら再度このスキルを呼び出してください。
```

インストール完了の申告を受けたら、Phase 0の確認コマンドを再実行して次に進む。

### ケースB: インストール済みだがMCP未登録（`claude mcp list` に notebooklm が出ない）

```bash
nlm setup add claude-code
```

の実行をユーザーに促す（またはユーザーの許可を得て代行実行し、`claude mcp list` で
登録確認する）。登録後はClaude Codeの再起動 or `/mcp` が必要な旨を伝える。

### ケースC: インストール・登録済みだが未ログイン（`nlm login --check` が失敗）

まず素直に `nlm login` を実行してみる。GUI環境（Mac/Linuxデスクトップ、WSLg有効なWSL）なら
ブラウザが直接開いてログイン可能。

**WSL2でブラウザが起動しない／`Error: No supported browser found`／
`Error: Chrome is already running`／`platform failed to initialize` 等が出る場合**：
GUI転送（WSLg）が使えない環境。以下の手順で確立済み（2026-08-02, 2026-08-07実績）。

**恒久的な制約（2026-08-07確認、WSL2 + rootログイン環境限定）**：この環境の
WSLログインユーザーはroot固定。root環境ではChromeが`--no-sandbox`なしで起動できないため、
`nlm login`単体では毎回失敗する。WSLユーザー変更は対応しない方針のため、**下記CDP直結手順が
今後も毎回必要**という前提で動く（都度「なぜ失敗するか」を再調査しない）。
**Mac等、非WSL環境ではこの制約自体が発生しない**（上記の通り`nlm login`単体で完結する）ため、
以下のWSL2固有ブロックは読み飛ばしてよい。

**重要な前提誤解の訂正（2026-08-02, 2026-08-07実績）**：`nlm login`が出す「Chrome is already running」
というエラーメッセージは誤解を招く。`ps aux | grep chrome` でWSL側にChromeプロセスが
実在しなくてもこのエラーは出る。**真因はメッセージ末尾の
`Running as root without --no-sandbox is not supported` の方**（rootではChromeの
sandbox機構が使えず起動自体に失敗している）。このエラーが出たら残存プロセス掃除や
ロックファイル削除を試す前に、まずWindows側Chromeへの直結（下記手順）に進んでよい。
`nlm login --wsl` 自体もrootでのsandbox制約を踏むため使わない。

以下、WSLからWindows側Chromeへ **CDP（Chrome DevTools Protocol）で直結**する手順。
ミラーモード／NATモードいずれのWSL2ネットワーキングでも通る（`cat /etc/wsl.conf` や
`ip addr show eth1` で確認は可能だが、下記手順ならモード判定は不要）。

1. WSL側で疎通確認（既存Chromeがデバッグポートで待受済みか）：
   `curl -s --max-time 5 http://localhost:9222/json/version`
   応答が返らない（`curl: (7) Failed to connect`）場合は2へ。
2. Windows側PowerShellでデバッグポート付きChromeを起動してもらう。
   **フルパスに空白を含むため `&`（呼び出し演算子）が必須**（省略すると
   `'--' 演算子は、変数またはプロパティに対してのみ機能します` という構文エラーになる）。
   **`--user-data-dir` も必ず明示指定する**（2026-08-13実績：省略すると、既に起動中の
   通常Chromeプロセスへ引数だけ渡されて新規プロセスが生成されず、
   `--remote-debugging-port` 自体が無視される。この場合 `netstat` で対象ポートが
   一切LISTENされていない状態になり、一見「まだ起動していない」ように見えて紛らわしい）：
   ```powershell
   & "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="C:\temp\chrome-debug-profile"
   ```
3. 起動後もWSL側から疎通しない場合（`curl`が「接続を拒否」ではなく「接続確立後すぐ
   リセットされる」という挙動なら特に）、**ポート9222がWindows側の別プロセス（`svchost`等）に
   占有されている可能性が高い**（2026-08-07実績・2026-08-13再発）。
   Windows側で以下を確認する：
   ```powershell
   Get-Process chrome | Format-Table Id,StartTime
   netstat -ano | findstr 9222
   ```
   **`netstat`の結果は必ずIPv4行（`0.0.0.0:9222` や `127.0.0.1:9222`）とIPv6行
   （`[::1]:9222`）を分けて見る**（2026-08-13実績で判明した罠）：Chrome自体は
   `[::1]:9222`（IPv6 loopback）の確保には成功していても、`0.0.0.0:9222`
   （IPv4含む全アドレス）を`svchost`等の別プロセスに先取りされているケースがある。
   このとき**Windows自身のブラウザで`http://localhost:9222/json/version`を開くと
   `localhost`がIPv6優先で解決されるため正常にChromeへ繋がって見えてしまう**が、
   WSL側は`127.0.0.1`（IPv4）で接続するため、そちらは非Chromeプロセスに到達し
   `Recv failure`（接続確立後すぐリセット）で失敗し続ける。「Windows側は正常なのに
   WSL側だけ繋がらない」状態が起きたら、まずこのIPv4/IPv6の食い違いを疑うこと。
   `Get-Process -Id <0.0.0.0:9222側のPID>` で実体を確認し、`chrome`でなければ
   （`svchost`等）別ポート（例: 9333）を`--user-data-dir`も新しいパスに変えて
   1〜2をやり直す：
   ```powershell
   & "C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9333 --user-data-dir="C:\temp\chrome-debug-profile2"
   ```
   切り替え後も同じ手順（`Get-Process chrome`+`netstat -ano | findstr <port>`、
   IPv4/IPv6両方確認）で、今度は`0.0.0.0:<port>`側のPIDがchromeであることを確認してから
   WSL側の疎通確認 `http://localhost:9333/json/version` に進む（`192.168.10.1:<port>`
   のようなゲートウェイIP経由は接続拒否になりやすく確認不要。localhostへの
   ポートフォワーディングがNAT/ミラーどちらのモードでも機能する）。
4. 疎通確認できたら `nlm login --provider openclaw --cdp-url http://127.0.0.1:<port> --force`
   を実行する。これは新規にChromeプロセスを起動させる（既存プロセスがあれば流用）ため
   sandbox制限にかからない。
   **実行するとすぐタイムアウトカウントが始まる。この時点でChromeはまだ手順2で開いた
   まっさらな別プロファイルの状態＝NotebookLM未ログインなので、コマンド実行前か
   実行直後に「起動したChromeウィンドウで`$ALLOWED_EMAIL`（環境変数未設定の場合は
   ユーザーにログイン用メールアドレスを確認する）にログインしてください」と
   ユーザーに明示的に依頼すること**（過去実績：これを伝え忘れ、1回目は
   `Error: Login timeout`で失敗した）。
   **`timeout`コマンドで外側から60秒等に短く区切ると、nlm内部の待機（デフォルト300秒）より
   先にプロセスが強制終了され「ログインしたのに失敗扱い」になる。外側タイムアウトは
   300秒以上（またはBash運用ならタイムアウト指定なし）にすること。**
5. ログイン成功後は `nlm login --check` で有効期限内は再認証不要。以降のセッションで
   `network_error: ClientAuthenticationError` 等が出たら、まず「認証切れ」と判断し
   上記1からやり直す（Cookie自体は保存されているので、真の原因はほぼ毎回
   sandbox制約＋デバッグポート確保の2点に帰着する）。
6. 手動Cookie貼り付け（`nlm login --manual --file <cookies.json>`）は最終手段。
   ブラウザ拡張機能でエクスポートしたCookieに `SID`/`HSID` 等の必須Cookieが欠けやすく、
   `network_error: ValueError` で失敗しがち。上記のopenclaw CDP直結の方が確実。
   **Cookie文字列は事実上パスワード相当の機密情報。チャット上に平文で貼らせない、
   ファイル書き込みはサンドボックスでブロックされる前提で扱う。**

### ケースD: 全て正常

Phase 1へ進む。本プロジェクトではMCPサーバー登録はせず、`nlm` CLIを直接Bashツールから
叩く運用（`export HOME=/root; nlm notebook list` 等）。MCP経由にする場合のみ
`ToolSearch` で `"notebooklm"` を検索してスキーマをロードする。

---

## Phase 1: 操作の受付

ユーザーの依頼を以下のいずれかに分類し、対応するMCP Toolを呼び出す（ツール名は
実際にToolSearchで取得した名称に従う。代表的な操作は以下）。

| 依頼例 | 対応操作 |
|---|---|
| 「Notebook一覧を見せて」 | notebook一覧取得 |
| 「〇〇というNotebookを作って」 | notebook作成 |
| 「このURL/PDF/テキストをNotebookLMに追加して」 | source追加（url / file / text） |
| 「NotebookLMでDeep Researchして」 | research開始 → 完了待ち → 結果取得 |
| 「Notebookの内容を要約して」 | notebook要約取得 |
| 「スライド資料を作って」「音声解説を作って」「動画で作って」「レポートにして」「インフォグラフィックにして」「マインドマップにして」 | スタジオ成果物生成（下記参照） |

各操作の実行前に、対象Notebook名・IDが曖昧な場合は一問一答で確認する
（グローバル設定の「質問は1つずつ」に従う）。

### スタジオ成果物生成（スライド・音声・動画・レポート・インフォグラフィック）

`nlm create slides / audio / video / report / infographic` は**必ず `--language ja` を明示指定する**。
省略するとデフォルトが英語（`en`）になり、日本語での出力にならない
（2026-08-02実績：`--language`未指定でスライドを生成した結果、全編英語で出力された）。

```bash
export HOME=/root
nlm create slides "$NB" --language ja --format presenter_slides --focus "<訴求内容>" --confirm --json
nlm create audio  "$NB" --language ja --format deep_dive       --focus "<訴求内容>" --confirm --json
nlm create video  "$NB" --language ja --format explainer       --focus "<訴求内容>" --confirm --json
nlm create report "$NB" --language ja --format "Blog Post"                          --confirm --json
```

`--focus` は生成対象Notebookのソース構成に強く引っ張られる。ソースが特定機能（例：見せ板検出）に
偏っている場合、`--focus`で汎用的な訴求を指定しても出力は元ソースの範囲に寄る。全体像を訴求する
成果物が必要な場合は、目的に合わせてソースを揃えた専用Notebookを作成すること。

**生成完了確認・ダウンロード時の既知バグ回避（2026-08-02実績）**：
`nlm status artifacts` / `nlm list artifacts` は本CLIバージョンで内部エラーになり使用不可
（`limit`パラメータの型処理バグ、`TypeError: '<=' not supported between instances of 'int' and 'OptionInfo'`）。
生成完了の確認は、対応する `nlm download <artifact-type>` コマンドを直接実行し、成功すれば完了・
失敗すれば未完了とみなして数十秒おきにリトライする運用で代替する。

```bash
nlm download slide-deck "$NB" --id <artifact_id> --format pdf --output /tmp/xxx.pdf --no-progress
# 失敗時（生成中）は Error: Download failed for slide_deck. が返る。30秒程度待って再試行する
```

---

## Phase 2: ブログ制作ワークフローへの連携（任意）

CMOのブログ制作フローで使う場合、以下の一連を自動実行できる。

```
記事素材のURL収集（WebSearch）
      ↓
NotebookLMへsource追加（本スキルのMCP操作）
      ↓
Deep Research実行（本スキルのMCP操作）
      ↓
結果取得・要約
      ↓
成果物Markdown生成（projects/{プロジェクト}/cmo/成果物/）
      ↓
該当役職のINDEX.md更新（CLAUDE.mdルール9準拠）
```

MCP経由の自動操作ではなく「手動でNotebookLMに貼り付ける指示書」が欲しい場合は、
`notebooklm-blog-strategy` スキルを使う（本スキルとは用途が異なるため両方残す）。

---

## 実行後の確認

- ソース追加・Deep Research等の操作後は、必ず結果（成功/失敗、取得内容の要約）を
  ユーザーに報告する。
- 失敗時はエラーメッセージをそのまま提示し、内部API仕様変更の可能性がある旨を添える。
