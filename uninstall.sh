#!/bin/bash

# ==============================================================================
# Script Name:  Dotfiles Cleanup Script
# Description:  ホームディレクトリ内の設定ファイル（シンボリックリンク）を解除し、
#               特定のキャッシュや設定ディレクトリを完全に削除します。
#               環境の再構築や初期化を行う際に使用します。
#
# Warning:      このスクリプトはディレクトリを 'rm -rf' で削除するため、
#               実行すると元に戻せません。注意して実行してください。
# ==============================================================================

set -e

# --- 実行確認処理 ---
echo "⚠️  警告: 設定ファイルの解除とキャッシュディレクトリの削除を開始します。"
echo "削除対象: .zshrc, .vimrc, .config/, .cache/ などの設定およびディレクトリ"
read -p "本当に実行してもよろしいですか？ (y/N): " confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "❌ 中断しました。何も変更されていません。"
    exit 1
fi

# --- 処理開始 ---

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/utils.sh"

# シンボリックリンクを安全に解除する関数
safe_unlink() {
    local target="$1"
    # シンボリックリンクが存在する場合のみ実行
    if [ -L "$target" ]; then
        echo "Unlinking: $target"
        unlink "$target"
    # リンクではなく実ファイルが存在する場合の警告
    elif [ -e "$target" ]; then
        echo "Notice: $target is a real file/dir, not a symlink. Skipping..."
    fi
}

# Shell / Env
safe_unlink "$HOME/.bash_profile"
safe_unlink "$HOME/.bashrc"
safe_unlink "$HOME/.zshrc"
safe_unlink "$HOME/.setenv.wsl"
safe_unlink "$HOME/.setenv.mac"
safe_unlink "$HOME/.setenv.linux"

# Git / Vim / Config
safe_unlink "$HOME/.gitconfig"
safe_unlink "$HOME/.vimrc"
safe_unlink "$HOME/.local/bin/gemini-cli"
safe_unlink "$HOME/.config/gemini-cli"
safe_unlink "$HOME/.local/bin/chatgpt-cli"
safe_unlink "$HOME/.config/chatgpt-cli"
safe_unlink "$HOME/.config/git"
safe_unlink "$HOME/.config/gh"
safe_unlink "$HOME/.config/nvim"
safe_unlink "$HOME/.config/mise"

# Claude
safe_unlink "$HOME/.claude/CLAUDE.md"
safe_unlink "$HOME/.claude/settings.json"
safe_unlink "$HOME/.claude/statusline.sh"
safe_unlink "$HOME/.claude/agents"
safe_unlink "$HOME/.claude/skills"

# Gemini / Antigravity
safe_unlink "$HOME/.gemini/GEMINI.md"
safe_unlink "$HOME/.gemini/settings.json"
safe_unlink "$HOME/.gemini/skills"

# Codex
safe_unlink "$HOME/.codex/AGENTS.md"
safe_unlink "$HOME/.codex/config.toml"
safe_unlink "$HOME/.codexignore"
safe_unlink "$HOME/.codex/skills"

if [ -n "$IS_MAC" ]; then
    # macOS固有の設定
    safe_unlink "$HOME/.ideavimrc"
    safe_unlink "$HOME/.config/karabiner/karabiner.json"
    safe_unlink "$HOME/.config/karabiner/assets/complex_modifications"
fi

#if [ -n "$IS_WSL" ]; then
#    # WSL固有の設定
#    echo "Cleaning up WSL system links..."
#    [ -f "/etc/wsl.conf" ] && sudo rm -f "/etc/wsl.conf"
#    [ -f "/etc/resolv.conf" ] && sudo rm -f "/etc/resolv.conf"
#fi

# キャッシュやディレクトリの削除
echo "Cleaning up directories..."
dirs_to_remove=(
    "$HOME/.local/share/zinit"
    "$HOME/.vim"
    "$HOME/.local/share/nvim"
    "$HOME/.cache"
)
for d in "${dirs_to_remove[@]}"; do
    if [ -d "$d" ]; then
        echo "Removing directory: $d"
        rm -rf "$d"
    fi
done

echo "✅ Cleanup complete!"
