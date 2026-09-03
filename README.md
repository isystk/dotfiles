# 🌙 dotfiles

Mac (Homebrew)、WSL (Ubuntu/Debian)、および Windows (PhpStorm/IdeaVim) のマルチプラットフォームに対応した開発環境管理リポジトリです。

## 📗 プロジェクトの概要

自分専用の環境を爆速で再構築するための設定ファイル群です。
`Zsh` + `Zinit` による快適なシェル環境、`Mise` による言語ランタイム管理、`Neovim` / `IdeaVim` の設定を中心に構成しています。

---

## 🚀 導入手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/isystk/dotfiles.git ~/dotfiles
cd ~/dotfiles

```

### 2. 設定ファイルの適用（シンボリックリンク作成）

OSに合わせて以下のスクリプトを実行してください。

* **🍎 Mac / 🐧 WSL**
* **適用（インストール）**
```bash
chmod +x install.sh
./install.sh

```

* **削除（アンインストール）**
```bash
chmod +x uninstall.sh
./uninstall.sh

```

* **🪟 Windows**
  ※ **管理者権限**で実行してください。
* **適用（セットアップ）**
```cmd
windows\setup.bat

```

* **削除（クリーンアップ）**
```cmd
windows\cleanup.bat

```

### 補足

* **Mac/WSL**: `uninstall.sh` はシンボリックリンクの解除と、一時的なキャッシュディレクトリの削除を行います。
* **Windows**: `cleanup.bat` は `mklink` で作成したリンクの削除と、コピーした `.wslconfig` / Windows Terminal `settings.json` の削除を行います。

---

## 🛠 OS別・依存パッケージの導入

### 🍎 Mac

```bash
brew install mise fzy ccat git-lfs ripgrep

```

### 🐧 Linux (WSL / Ubuntu)

```bash
sudo apt update && sudo apt install -y zsh fzy git-lfs ripgrep

```

> **⚠️ git-lfs は必須**: `.gitconfig` の `core.hooksPath` により、ホーム配下で行う全ての `git clone`（Zinit / Neovimプラグインのインストール含む）で `post-checkout` フックが実行されます。`git-lfs` が未インストールだとこのフックが失敗し、`git clone` 自体がエラー終了してプラグインが導入されません。**必ず `install.sh` 実行前にインストールしてください。**

---

## 📦 主要ツールのセットアップ

| ツール | 説明 | 初期設定コマンド |
| --- | --- | --- |
| **Mise** | 言語ランタイム・CLIツール管理（`gh` / `jq` / `neovim` 含む） | `mise install` |
| **GitHub CLI** | GitHub操作 | `gh auth login` |
| **git-secrets** | 認証情報の露出防止 | `git secrets --register-aws --global` |
| **tree-sitter CLI** | Neovim (nvim-treesitter) のパーサービルドに必要 | `npm install -g tree-sitter-cli`（`mise install` 後、`node`/`npm` が使える状態で実行） |
| **lazygit** | Neovim (lazygit.nvim, `<leader>g`) から呼び出すgit TUI | [公式リリース](https://github.com/jesseduffield/lazygit/releases)から `/usr/local/bin` へ配置 |
| **ripgrep** | Neovim (telescope.nvim) のファイル検索 (`<C-p>` / `<Space><Space>` / `<leader>fg`) に必要 | 上記OS別依存パッケージ導入手順でインストール済み |

---

## 📂 ディレクトリ構造

```text
.
├── .bashrc / .bash_profile # Bash設定 (Zshへの切り替え促進)
├── .claude               # ClaudeCode設定（rule-templates/ = プロジェクトへコピーして使うルールテンプレート）
├── .codex                # Codex CLI設定 (AGENTS.md, config.toml)
├── .config/              # ツール別設定
│   ├── chatgpt-cli/      # ChatGPT CLI設定
│   ├── gemini-cli/       # Gemini CLI / プロンプト設定
│   ├── gh/               # GitHub CLI
│   ├── git/              # Git設定 (hooks)
│   ├── karabiner/        # Karabiner-Elements設定 (Mac)
│   ├── marp/             # Marpスライド設定
│   ├── mise/             # Mise (config.toml)
│   ├── nvim/             # Neovim設定
│   ├── voicevox/         # VOICEVOX読み辞書設定
│   └── wsl/              # WSL設定 (wsl.conf, resolv.conf)
├── .gemini               # Gemini&Antigravity設定
├── .github                # PRテンプレート等
├── .gitconfig            # Git設定
├── .gitignore / .gitignore_global # Git除外設定
├── .ideavimrc            # JetBrains IDE用Vim設定 (Mac/Windows側)
├── .setenv.mac / .wsl / .linux / .local.example # OS固有の環境変数
├── .vimrc                # Vim設定
├── .zshrc                # Zsh設定
├── editors/              # 開発エディタ設定（各ディレクトリのrsync.sh push/pullで手動反映）
│   ├── Antigravity/      # Antigravity設定
│   ├── PhpStorm/         # PhpStorm設定
│   └── VSCode/           # VSCode設定
├── install.sh            # Unix系用セットアップ
├── uninstall.sh          # Unix系用アンインストール
├── documents/            # ドキュメント群
├   └── cheatsheet.md     # コマンドリファレンス
├── scripts/              # 自作ユーティリティ
└── windows/              # Windows用ファイル一式
    ├── setup.bat            # Windows用セットアップ
    ├── cleanup.bat          # Windows用クリーンアップ
    ├── .wslconfig           # WSL全体設定 (Windows側にコピー配置)
    ├── windows-terminal/    # Windows Terminal設定 (settings.json、Windows側にコピー配置)
    └── tools/               # Windows側で動かす自作ツール (ime-watcher.ps1 等)

```

---

## ⚠️ 注意事項

* **AIエージェント用ルールファイルの運用**: `.claude/rule-templates/` に、Claude Code / Gemini CLI / Codex CLI 共通で使う言語・フレームワーク別ルール（PHP、JavaScript、Docker等）のテンプレートを配置しています。以前は `~/.claude/rules` としてシンボリックリンクで全プロジェクトへグローバル公開していましたが、クラウド実行環境（`~/.claude` が存在しない）でルールが参照できない問題があったため廃止しました。新規プロジェクトでルールを使う場合は、このテンプレートを各リポジトリの `.claude/rules/`（Gemini CLIは `.agent/rules/`）へ `cp` し、プロジェクト固有ルールとしてGit管理してください。
* **秘匿情報の管理**: APIキー等は `.gitignore` 対象の `.zshrc.local` や `.setenv.local` を各自作成して記述してください。Git認証情報は `.gitconfig.local`（`.gitconfig.local.example` を複製）でOS別の `credential.helper`（`osxkeychain` / `manager` / `cache` 等）を設定してください。
* **変更後の事前チェック (重要)**: 本リポジトリの設定やスクリプトを変更・更新した後は、Claude Code のスキル **`check-privacy-and-secrets`** を実行（例: 「プライベート情報や特定プロジェクトの情報が含まれていないかチェックして」と指示）し、APIキー・個人情報・個別プロジェクト依存のコードが誤って混入していないか事前チェックを行ってください。
* **Nerd Font**: Neovim (neo-tree.nvim / nvim-web-devicons) のファイルアイコン表示に、[Nerd Fonts](https://www.nerdfonts.com/) のパッチ済みフォントが必要です。未設定の場合、アイコン部分が文字化けまたは豆腐（□）表示になります。
  * **🍎 Mac**: `brew install --cask font-hack-nerd-font` を実行後、ターミナルアプリ（iTerm2 / Terminal.app等）のフォント設定で `Hack Nerd Font` を選択してください。
  * **🪟 WSL (Windows Terminal)**: 描画はWSL内ではなく**Windows側アプリ**が担当するため、Windows側でフォントを導入します。
    ```powershell
    winget install --id DEVCOM.JetBrainsMonoNerdFont -e
    ```
    インストール後、Windows Terminalの設定（対象プロファイル → 外観 → フォント）で `JetBrainsMono Nerd Font` を選択してください。反映されない場合は、`profiles.defaults` ではなく実際に使用している**個別プロファイル側**のフォント設定を直接確認・変更してください（個別設定が`defaults`を上書きするため）。
* **改行コード**: `.gitattributes` により、Windows環境での編集時も `LF` が強制されます。
* **実行ファイル(exe)の非同梱**: Windows用の外部ツール（Vim用IME切替、WSL Gitクライアント連携）はリポジトリに含めていません。各自「📝 Windows 開発環境セットアップ TIPS」内のリンクから配布元公式サイト・GitHub Releasesよりダウンロードしてください。CapsLock変換はリポジトリ同梱の PowerShell スクリプトで完結します。

---

## ⌨️ 使い方

[完全コマンドリファレンス](documents/cheatsheet.md) をご覧ください。

---

## 📝 Windows 開発環境セットアップ TIPS

### 1. CapsLock を Ctrl に変更する

キーボードの CapsLock キーを Ctrl キーとして機能させます。レジストリの Scancode Map を書き換える PowerShell スクリプト `windows/tools/toggle-capslock-ctrl.ps1` で行います（外部ツール不要）。実行するたびに現在の設定状態を自動判定し、「適用」「解除」をトグルします。

* **スクリプト:** `windows/tools/toggle-capslock-ctrl.ps1`
* **実行方法:**
1. PowerShell を **管理者として実行** で開きます（システム全体のレジストリキーを操作するため）。
2. 以下を実行します。

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\windows\tools\toggle-capslock-ctrl.ps1"
   ```

3. 現在の設定状態（未適用／適用済み）が表示されるので、確認プロンプトに `y` で応答します。
   * 未適用の場合 → CapsLock を Ctrl に変更
   * 適用済みの場合 → 元の CapsLock 動作に戻す
4. 反映には **サインアウトまたは再起動** が必要です。

補足: `-ExecutionPolicy Bypass` はこのプロセス内でのみ署名なしスクリプトの実行制限を回避するもので、システム設定を恒久変更するものではありません。

### 2. Windows版 Git クライアントから WSL の Git を利用する

Windows上のGUIクライアント（SourceTree等）から、WSL内にインストールされた Git を直接呼び出せるようにします。
これにより、WindowsとWSL間での文字コード等の不整合を防ぎ、一貫したGit操作が可能になります。

* **配布元:** [wslgit Releases](https://github.com/andy-5/wslgit/releases)
* **セットアップ:**
1. 上記配布元から `wslgit.zip` をダウンロードし、任意のフォルダに展開します（`wslgit\cmd\wslgit.exe` 等が含まれます）。
2. 展開したフォルダ内の `install.bat` を **管理者権限** で実行します。
3. 実行後、同フォルダ内に `cmd\git.exe` が生成されます。

* **クライアント設定:**
  利用しているGitクライアントの「Git実行ファイルのパス」設定にて、生成された `cmd\git.exe` を指定してください。

Windowsの標準設定だけで、Macのように「**無変換キーで英数**」「**変換キーで日本語**」に切り替える設定手順です。

### 3. 日英入力切替を Mac 方式に変更する

スペースキー両隣のキーで「英数 / 日本語」を切り替えられるように設定します。

* **手順:**
1. タスクバーの IME（あ/A）を右クリック ＞ **[設定]**。
2. **[キーとタッチのカスタマイズ]** を選択。
3. 「キーの割り当て」を **オン** に変更。
4. **無変換キー** を `IME-オフ`、**変換キー** を `IME-オン` に設定。

* **メリット:** 現在の入力モードを気にせず、左親指で「英数」、右親指で「日本語」と打ち分けることが可能になります。

### 4. Neovim: インサートモード終了・ウィンドウ移動時に自動で英数入力へ切り替える

WSL上のNeovim（またはVimモードのある他エディタ）でインサートモードを抜けた時・パネル移動（`<S-Tab>`等）した時に、IMEを自動的にオフにします。
本リポジトリ同梱の `windows/tools/ime-watcher.ps1`（IME操作の本体）と `windows/tools/ime-watcher-launcher.vbs`（タスクバーにアイコンを出さず起動するランチャー）をWindows側で常駐起動しておくことで実現します。

* **仕組み:** `init.lua` が `InsertLeave` ・ `WinLeave` 時にWindows側常駐プロセスへNamed Pipe（`nvim-ime-off`）で通知を送り、Windows側で常駐する `ime-watcher.ps1` が通知を受けてフォアグラウンドウィンドウのIMEをオフにします。（WSLから都度exeを起動してIME操作自体を行う方式は対象ウィンドウ判定がずれ動作しなかったため、実際のIME操作は常駐プロセス側で行い、WSL側は軽量な通知のみ送る設計にしています）
  `~/.nvim-ime-off-trigger` ファイルを `\\wsl.localhost` 経由でWindows側がポーリングする方式は、高頻度なUNC越しファイルアクセスがWSL2の9pファイルシステム層に負荷をかけWSLイメージ破損を招くため、push型のNamed Pipe通知方式にしています。
* **設定方法:**
1. `windows/tools/ime-watcher.ps1` と `windows/tools/ime-watcher-launcher.vbs` を**同じ**Windows側フォルダ（例: `C:\Users\<ユーザー名>\Tools`）へ配置します（vbsはps1と同じフォルダにある前提で動作します）。
   * 配置先フォルダは、システムの環境変数 `Path` に追加してください（＝OS標準の「PATHを通す」操作）。次の手順のショートカットはフルパス指定のため追加しなくても起動できますが、動作確認でPowerShellから `ime-watcher.ps1` とだけ打って手動実行したい場合に必要です。
     手順: `Win + R` → `sysdm.cpl` と入力して実行 → 「詳細設定」タブ → 「環境変数」ボタン → 「〇〇のユーザー環境変数」欄の `Path` を選択 → 「編集」 → 「新規」 → 配置先フォルダのパスを入力 → OKを押して全ウィンドウを閉じる → 以後は新しく開いたPowerShellウィンドウで反映されます。
2. `Win + R` → `shell:startup` で開いたスタートアップフォルダで、`ime-watcher-launcher.vbs` を右クリック→ショートカットの作成、でショートカットを作成します（`.ps1` を直接指定せず、必ずこの `.vbs` を対象にしてください）。
   * `powershell.exe -WindowStyle Hidden` を直接ショートカットに指定する方法もありますが、一瞬コンソールウィンドウが生成されてから非表示化される順序のためタスクバーにアイコンが残ることがあります。`.vbs` 経由（`WScript.Shell.Run` で非表示起動）だとコンソール自体が作られないため、タスクバーにも一切表示されません。
3. 次回ログイン時より自動で常駐し、機能が有効になります。今すぐ試す場合は、作成したショートカットをダブルクリックして手動起動してください（タスクマネージャーの詳細タブに `wscript.exe` と `powershell.exe` が常駐していれば起動成功。タスクバーには何も表示されないのが正常です）。

* **注意:** `ime-watcher.ps1` は必ずUTF-8 with BOMのまま配置してください。BOM無しUTF-8で保存するとWindows PowerShell 5.1がシステムロケール（日本語環境ではShift-JIS）として誤読し、日本語コメントの文字化けによりパースエラーで起動できません。`ime-watcher-launcher.vbs` はVBScriptがUTF-8を正式サポートしないため、コメントを含め全体をASCII文字のみで構成しています（改変時もASCII範囲を維持してください）。

---

## 🎫 Licence

[MIT](https://github.com/isystk/dotfiles/blob/master/LICENSE)

## 👀 Author

[isystk](https://github.com/isystk)
