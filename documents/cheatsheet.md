## 完全コマンドリファレンス

### 1. エディタ操作 (Neovim)

標準的なVim操作をベースにしつつ、Windowsのショートカットや挿入モードでの利便性を高める設定。

| 分類             | キー操作                    | 内容 / 挙動                                           |
|----------------|-------------------------|---------------------------------------------------|
| **Windows風**   | `Ctrl + a`              | **全選択** (ノーマルモード)                                 |
|                | `Ctrl + z` / `Ctrl + y` | **元に戻す (Undo)** / **やり直し (Redo)** ※挿入モード可         |
|                | `Ctrl + c` / `Ctrl + x` | コピー / 切り取り (ビジュアルモード)                             |
|                | `Ctrl + v`              | 貼り付け (挿入モードでもペースト可能)                              |
|                | `Ctrl + q`              | 矩形選択 (Visual Block) 開始                             |
|                | `p` / `Shift + p` (ビジュアル) | レジスタを上書きせず貼り付け（元の選択内容はレジスタへ退避）                 |
| **カーソル移動**     | `h/j/k/l`               | 上下左右に移動                                           |
|                | `gg` / `G`              | ファイルの最上端 / 最下端へ移動                                 |
|                | `Ctrl + u/d`            | 半画面分 上にスクロール / 下にスクロール                            |
|                | `Ctrl + h/j/k/l`        | **挿入モードのまま** 上下左右に移動                              |
|                | `Ctrl + a` / `e`        | **挿入モードのまま** 行頭 / 行末へ移動 (Emacs風)                  |
|                | `Tab`                   | 対応するカッコ `()` `{}` `[]` `<>` へのジャンプ                |
|                | `Ctrl + ←` / `Ctrl + →` | ジャンプリストを 戻る / 進む                                  |
|                | `Shift + Tab` (ノーマル)   | ウィンドウ切替 (`Ctrl-w w` 相当)                            |
| **単語移動**       | `w` / `b`               | 次の単語の先頭 / 前の単語の先頭へ移動                              |
|                | `e` / `ge`              | 単語の末尾 / 前の単語の末尾へ移動                                |
| **行内ジャンプ**     | `f [文字]` / `t [文字]`     | 指定文字まで右へジャンプ / その手前へジャンプ                          |
|                | `0` / `^` / `$`         | 行頭 / 行の最初の文字 / 行末へ移動                              |
| **検索・選択**      | `*` / `#`               | カーソル下の単語を次検索 / 前検索                                |
|                | `Tab` (選択中)             | 選択範囲を右へインデント（**選択状態を維持**）                         |
|                | `Esc Esc`               | 検索ハイライトを解除                                        |
| **置換**         | `:%s/A/B/g`             | ファイル全体の A を B に一括置換                               |
|                | `:%s/A/B/gc`            | 確認しながら一括置換                                        |
|                | `Ctrl + r` (ノーマル)      | `:%s//gc` 置換プロンプトをカーソル位置付きで起動                    |
|                | `Ctrl + r` (ビジュアル)     | 選択範囲を検索欄にセットして置換プロンプト起動                          |
| **テキストオブジェクト** | `ciw` / `diw` / `viw`   | **単語内**を消して挿入 / 削除 / 選択 (Inner Word)              |
| (範囲指定)         | `ci"` / `ci(` / `cit`   | **"..."内** / **(...)内** / **HTMLタグ内** を書き換え       |
|                | `ca"` / `ca(` / `cat`   | 囲み記号（" や ( や タグ）を**含めて**書き換え                      |
| **繰り返し操作**  | `.` (ピリオド)              | 直前の編集を繰り返す: 文字の削除・変更などを再実行 |
| **マクロ (記録)**   | `q[a-z]`                | **録画開始**: `qa` でレジスタ `a` に記録開始（左下に「Recording」と表示） |
|                | `q`                     | **録画終了**: 記録中に `q` を押すと保存                         |
| **マクロ (再生)**   | `@[a-z]`                | **録画再生**: `@a` でレジスタ `a` に記録した操作を実行               |
|                | `@@`                    | **直前のマクロを再実行**: 連続して使う場合に便利                       |
|                | `[数字]@[a-z]`            | **回数指定実行**: `10@a` で一気に10回繰り返す                    |

---

### 2. Neovim プラグイン操作

`init.lua` に設定した各プラグイン (Laravel.nvim / neo-tree.nvim / claudecode.nvim / lazygit.nvim / Telescope / Trouble / LSP) のキーマップ。

| 分類            | キー操作                    | 内容 / 挙動                                                |
|---------------|-------------------------|---------------------------------------------------------|
| **Laravel**   | `gf`                    | カーソル位置が Laravel のリソース（Controller のビュー名等）なら **Blade ファイルへジャンプ**、それ以外は通常の `gf` |
|               | `<leader>la`            | Artisan コマンドピッカー                                       |
|               | `<leader>lr`            | ルート(Routes)ピッカー                                        |
|               | `<leader>lo`            | 関連ファイル(Related)ピッカー                                    |
| **neo-tree**  | `<C-n>` / `<leader>e`   | ファイルツリー(neo-tree)の開閉                                   |
|               | `<leader>ts` (neo-tree内) | カーソル位置ファイルのパスをターミナルへ入力（実行はしない）                           |
|               | `<leader>as` (neo-tree内) | カーソル位置ファイルを **ClaudeCode パネルへパス入力**（ClaudeCodeTreeAdd） |
|               | `a` / `A`               | ファイル追加 / ディレクトリ追加                                      |
|               | `d` / `r`               | 削除 / リネーム                                              |
|               | `c` / `x` / `p`         | コピー / カット / 貼り付け                                       |
|               | `y`                     | クリップボードへコピー                                            |
|               | `R`                     | ツリー更新(Refresh)                                         |
|               | `?`                     | ヘルプ表示                                                  |
| **ClaudeCode** | `<leader>ac`            | ClaudeCode パネルの切替                                      |
|               | `<leader>af`            | ClaudeCode パネルへフォーカス                                   |
|               | `<leader>as` (visual)   | 選択範囲を ClaudeCode へ送信                                   |
|               | `<leader>aa` / `<leader>ad` | 差分を承認(Accept) / 却下(Deny)                              |
| **ターミナル**    | `<leader>tc`            | ターミナル切替                                                |
|               | `<leader>ts` (visual)   | 選択範囲をターミナルへ送信                                          |
| **lazygit**   | `<leader>g` / `,st`     | LazyGit 起動                                             |
|               | `<leader>G`             | LazyGit 起動（現在ファイルの履歴に絞り込み）                            |
| **LSP**       | `gd` / `K`              | 定義元へジャンプ / hover 表示                                    |
|               | `gr`                    | 参照箇所を表示                                                |
|               | `<leader>rn`            | リネーム                                                   |
|               | `<leader>ca`            | コードアクション                                               |
|               | `[d` / `]d`             | 前 / 次の診断へジャンプ                                          |
| **検索(Telescope)** | `<leader>fg`         | 全文検索                                                   |
|               | `<leader>fb`            | バッファ一覧                                                 |
|               | `<leader>fr`            | 最近使ったファイル                                              |
| **診断(Trouble)** | `<leader>xx`           | 診断一覧                                                   |
|               | `<leader>xr`            | 参照一覧                                                   |
| **検索置換(grug-far)** | `<leader>sr`       | プロジェクト横断の検索/置換パネルを開く                                 |
| **パンくず(dropbar)** | `<leader>;`         | パンくずをジャンプ選択                                            |
| **ヘルプ**       | `<leader>?`             | このチートシートをフローティングウィンドウで表示                                |

---

### 3. Git 操作 (git [コマンド])

`.gitconfig` のエイリアス。日常的なソース管理を爆速にします。

| 分類        | コマンド                 | 内容 / 元の命令                         |
|-----------|----------------------|-----------------------------------|
| **基本操作**  | `st` / `ad`          | 状態確認 / ステージング                     |
|           | `ca` / `cr`          | 直前コミット修正 / 作成者・日時を現在に更新して修正       |
|           | `cm`                 | **【AI】** 差分からメッセージを生成しVimで編集      |
|           | `co` / `sw`          | ブランチ切替 (`checkout` / `switch`)     |
|           | `cb`                 | 新規ブランチ作成（リモートにあれば追跡）              |
|           | `sa`                 | 未追跡・無視ファイルも含め全スタッシュ               |
|           | `rmc`                | Gitの管理対象から除外する                    |
|           | `root` / `alias`     | リポジトリのルート表示 / エイリアス一覧             |
| **取り消し**  | `undo`               | 直前のコミットを取り消し、変更はステージに残す (`reset --soft HEAD~`) |
|           | `unstage` / `discard` | ステージから外す / 作業ツリーの変更を破棄            |
|           | `fixup <commit>`     | 指定コミットへのfixupを作り autosquash で即統合   |
|           | `wip`                | 作業途中の内容を一時コミット (`--no-verify`)      |
| **同期**    | `up`                 | 同期,up,最新の取得と再配置 (`pull --rebase`) |
|           | `pu`                 | 初回プッシュと追跡設定 (`push -u origin`)    |
|           | `pf`                 | rebase後の安全なforce push (`--force-with-lease`) |
| **ブランチ**  | `ba` / `br` / `bv`   | 全ブランチ / リモートのみ / 追跡先付き表示          |
|           | `recent`             | 最近コミットしたブランチ15件を新しい順に表示           |
|           | `bd`                 | ローカルブランチを強制削除                     |
|           | `gone`               | リモートで削除済み (`[gone]`) のローカルブランチを一括削除 |
|           | `cleanup`            | `main` にマージ済みのローカルブランチを削除         |
| **確認・ログ** | `ll` / `ls`          | **グラフ付き詳細ログ** / 統計付き1行ログ          |
|           | `last`               | 直前のコミットの概要 (`log -1 --stat`)       |
|           | `lu` / `lf`          | 作成者でログを検索 / ファイル名でログを検索           |
|           | `bl`                 | 空白差分・移動/コピー元を考慮した `blame`         |
|           | `ta` / `tr`          | 全タグ表示 / リモートタグのみ表示                |
|           | `ranking` / `-all`   | 今月のコミット数ランキング / 全期間ランキング (著者別) |
| **差分・修正** | `di` / `dn`          | 差分表示 / 差分のあるファイル名のみ表示             |
|           | `dc` / `dw`          | ステージ済みの差分 / 単語単位の差分（日本語向け）        |
|           | `d1` 〜 `d5`          | 直近 1 〜 5 つ前のコミットとの比較              |
|           | `r1` 〜 `r5`          | 直近 1 〜 5 つのコミットを `rebase -i`      |
|           | `edit` / `-unmerged` | 変更あり（または衝突中）ファイルを一括Vim展開          |
|           | `resolve-conflict`   | **【AI】** Claude Code を使ってGitコンフリクトを自動解消  |
|           | `archive-diff`       | 比較元との差分をZIP化（納品用等）                |

---

### 3. Shell & OS 操作 (zsh)

`.zshrc` の操作。

| 分類              | コマンド / キー                         | 内容 / 実行例                                            |
|-----------------|-----------------------------------|-----------------------------------------------------|
| **ディレクトリ**      | `ll` / `...` / `....`             | 詳細リスト表示 / 2階層上へ / 3階層上へ                             |
|                 | `[dir]` / `cd [dir]`              | ディレクトリ名のみで移動 / **【enhancd】** 曖昧検索移動                 |
| **編集・AI**       | `vi` / `nvim-ide`                 | Neovim起動（Neo-tree非表示、`<C-n>`/`<leader>e`で手動表示） / パネル展開モードでNeovim起動（ClaudeCode+ターミナル+Neo-tree表示） |
|                 | `history`                         | 日時付き履歴表示                                          |
| **Claude Code**   | `deepseek on`                     | Claude Code の接続先を DeepSeek へ切替（そのターミナルセッションのみ。`claude` の再起動が必要）。`scripts/deepseek.zsh` を source するエイリアス。モデルは `DEEPSEEK_CC_MODEL`／`DEEPSEEK_MODEL`（既定 `deepseek-flash`）。APIキーは `DEEPSEEK_API_KEY`、未設定なら `~/.config/deepseek/api_key`（`DEEPSEEK_API_KEY_FILE` で変更）を読む |
|                 | `deepseek off`                    | Anthropic（既定）へ戻す（そのターミナルセッションのみ。`claude` の再起動が必要） |
|                 | `deepseek status`                 | 現在の切替状態（セッションの環境変数・`claude` ラッパーの有無・`~/.setenv.local` の残留ブロック）を表示 |
| **比較**          | `diff` / `zdiff`                  | 標準的な差分表示 / zip内ファイルの差分表示                            |
| **出力・連携**       | **`copy`**                        | コマンドの結果をクリップボードへコピー<br/>例：`echo "text" \| copy`     |
|                 | **`open`**                        | ブラウザで指定したURLを開く<br/>例：`open https://www.google.com` |
|                 | **`explorer`**                    | エクスプローラーで指定したURLを開く<br/>例：`explorer .`             |
| **キー操作**        | `Ctrl + r`                        | 履歴からコマンドを検索                                         |
|                 | `Tab` / `→`                       | 強力な入力補完 / オートサジェストを確定                               |

---

### 4. 独自スクリプト (run [コマンド])

AI 連携や GitHub CLI のラッパー機能。

| 分類               | コマンド                | 内容 / 実行例                                                  |
|------------------|---------------------|-----------------------------------------------------------|
| **生成**           | `pr-gen`            | 差分から PR 説明文を生成                                            |
|                  | `blog-gen`          | Markdown 形式で記事を生成                                        |
|                  | `blog-thumb`        | 記事タイトルからアイキャッチ画像を生成<br/>例：`run blog-thumb 'タイトル' out.png` |
|                  | `slide-gen`         | Marp スライド・プレゼン原稿を生成                                      |
|                  | `voice-gen`         | Markdown から音声を生成（VOICEVOX）                                 |
|                  | `video-gen`         | PDF と音声から動画を生成                                            |
|                  | `audio-transcribe`  | 音声ファイルの文字起こし（`file-task.sh`を利用）<br/>例：`run audio-transcribe meets.mp3` |
| **変換**           | `image-opt`         | 画像を Web 用に最適化（1200px・圧縮・EXIF 削除）。元ファイルを残し同フォルダに `_web` 付きで出力<br/>例：`run image-opt ~/pics/a.jpg ~/pics/`<br/>オプション：`-w` 最大幅（既定1200） `-q` 品質（既定82） `-o` 出力先 |
|                  | `web-shot`          | Web ページを画像に変換                                             |
|                  | `image-to-pdf`      | 画像を PDF に変換                                               |
| **GitHub**         | `github`            | PR を選択して開く／チェックアウト／マージ／AI レビュー                          |
| **データベース**    | `mysql`             | MySQL 操作（ログイン／インポート／エクスポート）                            |
|                  | `mysql query`       | 指定 SQL を実行                                               |
| **Docker**         | `docker`            | コンテナ操作（入る／ログ／差分／再起動／削除）                                |
|                  | `docker prune`      | 未使用のコンテナ・イメージ・ボリュームを確認して削除                             |
| **WordPress**      | `wordpress`         | WordPress 管理（投稿一覧／表示／削除／カテゴリ）                           |
| **セキュリティ**    | `netsec`            | 引数なしで検査項目を対話メニューから選択。引数付きなら直接実行（`run netsec devices` 等） |
|                  | `netsec devices`    | LAN 接続デバイス一覧（IP/MAC/ベンダー/**端末種別**/ホスト名）。前回実行時との差分で「新規」「IP変更」を表示<br/>種別は MACベンダー・ホスト名・開いているポート（62078=iOS、88/445/548/5900/3283=macOS共有）から推定。62078 を過去に検出した機器は記憶して表示<br/>オプション：`--deep [秒]` Mac/iOS の判定待ち（省略時30秒） `--no-probe` 種別推定なし（高速） `--no-vendor` ベンダー照会なし `--no-save` ベースライン更新なし |
|                  | `netsec ports`      | LAN 内機器の危険ポート露出検査（Telnet/SMB/RDP/VNC/Docker API/DB 等）<br/>例：`run netsec ports --timeout 0.3` |
|                  | `netsec conns`      | 外向き通信の一覧と宛先の評判判定（ASN・国・PTR・Spamhaus DNSBL）。0.0.0.0 待ち受けポートも表示 |
|                  | `netsec arp`        | ARP テーブル異常検知（同一MAC複数IP・ゲートウェイの MAC 変化＝スプーフィング兆候）        |
|                  | `netsec upnp`       | SSDP でルーター（IGD）を検出し、外部公開ポートマッピングを確認                        |
|                  | `netsec audit`      | 上記全項目を実行して Markdown レポートを出力（メニューからは既定名 `~/net-audit-YYYYMMDD.md`）<br/>例：`run netsec audit --out ~/net-audit.md` |
|                  | `netsec dnswin`     | Windows 側 `pktmon` で DNS を取得し WSL で解析（dnsTunneling 有効でも可）<br/>例：`run netsec dnswin --seconds 30`（UAC 承認が必要。`--keep` で pcapng を残す） |
|                  | `netsec capture`    | Windows 側 `pktmon` でパケットを取得し pcapng 保存＋要約（通信相手ランキング・プロトコル内訳・DNS）。既定 30 秒<br/>例：`run netsec capture --ip 192.168.10.116 --port 443 --open`（UAC 承認要。`--open` で Windows の Wireshark に渡す）<br/>保存先：`%USERPROFILE%\netsec-captures\capture-YYYYmmdd-HHMMSS.pcapng`（`--out` で変更可）<br/>`--read <pcapng>` で保存済みファイルを要約だけやり直せる。件数は pktmon が同一パケットを複数コンポーネントで記録するため実数より多い（実測 5〜8 倍。順位は有効）。全パケット 30 秒で約 270 MB → `--pkt-size 128` で軽くなる<br/>`--sites` で「接続したサイト（ドメイン単位）」一覧を出す（DNS 応答＋TLS SNI、Wireshark 同梱 `tshark.exe` を使用）。例：`run netsec capture --seconds 60 --pkt-size 128 --sites`<br/>**調べ方の型**：①取得開始 → ②調べたい操作を1つだけ行う → ③`PEER` とサイト一覧を読む。URL のパス・検索語は暗号化で不可（ページ履歴はブラウザ履歴で見る） |
|                  | `netsec external`   | 公開IPを取得し、第三者スキャンDB（Shodan InternetDB）から「外から見えるポート」を確認。自前スキャンはしない |
| **ファイル**        | `backup push`       | `~/.backup-files`記載のパスを同期先ディレクトリへバックアップ（BACKUP_DEST未設定時は`/mnt/c/Users/{ユーザー}/backups`） |
|                  | `backup pull`       | 同期先ディレクトリからローカルへリストア                                      |
|                  | `backup check-sync` | 最後の同期日時を表示し、必要ならバックアップを実行（Zshログイン時にWSLのみ自動実行）        |
|                  | `file-clean`        | .DS_Store 等のメタデータファイルを削除                                 |
|                  | `file-crlf`         | CRLF ファイルを検出して LF へ変換                                    |
| **エディタ**        | `vscode backup / restore`      | VSCode の設定ファイルをバックアップ / リストア                     |
|                  | `antigravity backup / restore` | Antigravity の設定ファイルをバックアップ / リストア                |
| **メンテナンス**    | `doctor`            | 依存コマンドの有無を一括チェック（必須が不足なら終了コード1）                        |
|                  | `update-all`        | apt・mise・npm グローバル・AI CLI をまとめて更新                            |
|                  | `wsl-interop`       | powershell.exe 連携が壊れた際の応急処置（binfmt_misc 再登録）               |
|                  | `wsl-compact`       | WSL の ext4.vhdx 肥大化対策。`fstrim`後、別 PowerShell で`wsl --shutdown`→`--set-sparse true`を実行（WSLが停止する。初回のみ） |

---

### 5. VSCode拡張機能 (自作)

`editors/VSCode/vscode-extensions/` に同梱しているLaravel向け自作拡張機能。

| 拡張機能                          | 内容 / 使い方                                                                 |
|--------------------------------|---------------------------------------------------------------------------|
| **laravel-phpunit-runner**     | PHPUnitをDockerコンテナ内で実行。`Ctrl+Shift+T`でカーソル位置のファイルのテスト実行、`Ctrl+Shift+Alt+T`でカーソル位置のメソッドのみ実行、`Ctrl+Shift+Alt+G`でテストファイルとの相互ジャンプ |
| **laravel-blade-goto-controller** | Bladeテンプレート上で`Ctrl+Alt+G`を押すと、そのビューを描画しているController Actionへジャンプ         |
| **laravel-phpstan-diagnostics** | PHPファイル保存時にDockerコンテナ内で`php -l`と`phpstan`を自動実行し、診断結果をエディタへ表示               |
| **laravel-goto-config**        | PHP/Blade内の`config()`呼び出しにカーソルを合わせ「定義へ移動」（`F12` / `Ctrl+クリック`）で対応する設定ファイルへジャンプ |
| **laravel-goto-route**         | PHP/Blade内の`route()`呼び出しにカーソルを合わせ「定義へ移動」（`F12` / `Ctrl+クリック`）で対応するルート定義へジャンプ |
| **laravel-blade-goto-vite**    | Blade内の`@vite()`ディレクティブにカーソルを合わせ「定義へ移動」（`F12` / `Ctrl+クリック`）で対象アセットファイルへジャンプ |
