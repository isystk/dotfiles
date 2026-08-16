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
setup.bat

```

* **削除（クリーンアップ）**
```cmd
cleanup.bat

```

### 補足

* **Mac/WSL**: `uninstall.sh` はシンボリックリンクの解除と、一時的なキャッシュディレクトリの削除を行います。
* **Windows**: `cleanup.bat` は `mklink` で作成したリンクの削除と、コピーした `.wslconfig` の削除を行います。

---

## 🛠 OS別・依存パッケージの導入

### 🍎 Mac

```bash
brew install mise gh fzy ccat git-lfs

```

### 🐧 Linux (WSL / Ubuntu)

```bash
sudo apt update && sudo apt install -y zsh gh fzy git-lfs

# Neovim (AppImage)
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
sudo mv nvim.appimage /usr/local/bin/nvim

```

> **⚠️ git-lfs は必須**: `.gitconfig` の `core.hooksPath` により、ホーム配下で行う全ての `git clone`（Zinit / Neovimプラグインのインストール含む）で `post-checkout` フックが実行されます。`git-lfs` が未インストールだとこのフックが失敗し、`git clone` 自体がエラー終了してプラグインが導入されません。**必ず `install.sh` 実行前にインストールしてください。**

---

## 📦 主要ツールのセットアップ

| ツール | 説明 | 初期設定コマンド |
| --- | --- | --- |
| **Mise** | 言語ランタイム管理 | `mise install` |
| **GitHub CLI** | GitHub操作 | `gh auth login` |
| **git-secrets** | 認証情報の露出防止 | `git secrets --register-aws --global` |
| **tree-sitter CLI** | Neovim (nvim-treesitter) のパーサービルドに必要 | `npm install -g tree-sitter-cli`（`mise install` 後、`node`/`npm` が使える状態で実行） |

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
├── .ideavimrc            # JetBrains IDE用Vim設定 (Windows側)
├── .setenv.mac / .wsl / .linux / .local.example # OS固有の環境変数
├── .vimrc                # Vim設定
├── .wslconfig            # WSL全体設定 (Windows側)
├── .zshrc                # Zsh設定
├── editors/              # 開発エディタ設定（各ディレクトリのrsync.sh push/pullで手動反映）
│   ├── Antigravity/      # Antigravity設定
│   ├── PhpStorm/         # PhpStorm設定
│   └── VSCode/           # VSCode設定
├── install.sh            # Unix系用セットアップ
├── uninstall.sh          # Unix系用アンインストール
├── setup.bat             # Windows用セットアップ
├── cleanup.bat           # Windows用クリーンアップ
├── documents/            # ドキュメント群
├   └── cheatsheet.md     # コマンドリファレンス
└── scripts/              # 自作ユーティリティ

```

---

## ⚠️ 注意事項

* **AIエージェント用ルールファイルの運用**: `.claude/rule-templates/` に、Claude Code / Gemini CLI / Codex CLI 共通で使う言語・フレームワーク別ルール（PHP、JavaScript、Docker等）のテンプレートを配置しています。以前は `~/.claude/rules` としてシンボリックリンクで全プロジェクトへグローバル公開していましたが、クラウド実行環境（`~/.claude` が存在しない）でルールが参照できない問題があったため廃止しました。新規プロジェクトでルールを使う場合は、このテンプレートを各リポジトリの `.claude/rules/`（Gemini CLIは `.agent/rules/`）へ `cp` し、プロジェクト固有ルールとしてGit管理してください。
* **秘匿情報の管理**: APIキー等は `.gitignore` 対象の `.zshrc.local` や `.setenv.local` を各自作成して記述してください。Git認証情報は `.gitconfig.local`（`.gitconfig.local.example` を複製）でOS別の `credential.helper`（`osxkeychain` / `manager` / `cache` 等）を設定してください。
* **変更後の事前チェック (重要)**: 本リポジトリの設定やスクリプトを変更・更新した後は、Claude Code のスキル **`check-privacy-and-secrets`** を実行（例: 「プライベート情報や特定プロジェクトの情報が含まれていないかチェックして」と指示）し、APIキー・個人情報・個別プロジェクト依存のコードが誤って混入していないか事前チェックを行ってください。
* **改行コード**: `.gitattributes` により、Windows環境での編集時も `LF` が強制されます。
* **実行ファイル(exe)の非同梱**: Windows用の外部ツール（CapsLock変換、Vim用IME切替、WSL Gitクライアント連携）はリポジトリに含めていません。セキュリティソフトによる誤検知を避けるため、各自「📝 Windows 開発環境セットアップ TIPS」内のリンクから配布元公式サイト・GitHub Releasesよりダウンロードしてください。

---

## ⌨️ 使い方

[完全コマンドリファレンス](documents/cheatsheet.md) をご覧ください。

---

## 📝 Windows 開発環境セットアップ TIPS

### 1. CapsLock を Ctrl に変更する

キーボードの CapsLock キーを Ctrl キーとして機能させます。

* **配布元:** [ChgKey (Change Key)](https://satoshi3.sakura.ne.jp/f_soft/dw_win.htm)
* **手順:**
1. 上記配布元から `ChgKey.exe` をダウンロードします。
2. ダウンロードしたファイルを **管理者権限** で実行します。
3. 画面上の CapsLock キーを選択し、変更先に Ctrl キーを指定します。
4. 設定保存後、PCを再起動すると反映されます。

### 2. Vim: Esc 時に自動で英数入力へ切り替える

Vim（または他エディタのVimモード）でインサートモードを抜ける際、IMEを自動的にオフにします。

* **配布元:** [vimmer-ahk Releases](https://github.com/koirand/vimmer-ahk/releases)
* **設定方法:**
1. 上記配布元から `vimmer-ahk.exe` をダウンロードします。
2. `Win + R` キーを押し、`shell:startup` と入力して実行します。
3. 開いた「スタートアップ」フォルダに、ダウンロードした `vimmer-ahk.exe` をコピーします。
4. 次回ログイン時より自動で常駐し、機能が有効になります。

### 3. Windows版 Git クライアントから WSL の Git を利用する

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

### 4. 日英入力切替を Mac 方式に変更する

スペースキー両隣のキーで「英数 / 日本語」を切り替えられるように設定します。

* **手順:**
1. タスクバーの IME（あ/A）を右クリック ＞ **[設定]**。
2. **[キーとタッチのカスタマイズ]** を選択。
3. 「キーの割り当て」を **オン** に変更。
4. **無変換キー** を `IME-オフ`、**変換キー** を `IME-オン` に設定。

* **メリット:** 現在の入力モードを気にせず、左親指で「英数」、右親指で「日本語」と打ち分けることが可能になります。

---

## 🎫 Licence

[MIT](https://github.com/isystk/dotfiles/blob/master/LICENSE)

## 👀 Author

[isystk](https://github.com/isystk)
