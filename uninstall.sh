#!/bin/bash

# ==============================================================================
# Script Name:  Dotfiles Cleanup Script
# Description:  mise が配置した dotfiles のシンボリックリンクを解除し、
#               特定のキャッシュや設定ディレクトリを完全に削除します。
#               環境の再構築や初期化を行う際に使用します。
#
# Warning:      このスクリプトはディレクトリを 'rm -rf' で削除するため、
#               実行すると元に戻せません。注意して実行してください。
# ==============================================================================

set -e

# --- 実行確認処理 ---
echo "⚠️  警告: 設定ファイルの解除とキャッシュディレクトリの削除を開始します。"
echo "削除対象: dotfilesのシンボリックリンクと zinit / .vim / nvim データ (.cache は削除しない)"
read -p "本当に実行してもよろしいですか？ (y/N): " confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "❌ 中断しました。何も変更されていません。"
    exit 1
fi

# --- 処理開始 ---

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/utils.sh"

if ! resolve_mise; then
    echo "mise が見つかりません。リンク解除には mise が必要です。" >&2
    exit 1
fi
export PATH="$(dirname "$MISE_BIN"):$PATH"
export MISE_TASK_RUN_AUTO_INSTALL=false

mise_env=""
[ -n "$IS_MAC" ] && mise_env="mac"
[ -n "$IS_WSL" ] && mise_env="wsl"
mise_cmd=(mise -C "$SCRIPT_DIR")
[ -n "$mise_env" ] && mise_cmd+=(-E "$mise_env")

for f in mise.toml mise.mac.toml mise.wsl.toml; do
    [ -f "$SCRIPT_DIR/$f" ] && mise trust "$SCRIPT_DIR/$f"
done

# mise.toml の管理外
if [ -L "$HOME/.vimrc" ]; then
    echo "Unlinking: $HOME/.vimrc"
    unlink "$HOME/.vimrc"
fi

if [ -n "$IS_MAC" ] && defaults read com.googlecode.iterm2 PrefsCustomFolder &>/dev/null; then
    defaults delete com.googlecode.iterm2 PrefsCustomFolder
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool false
    echo "iTerm2: Reverted to local preferences (restart iTerm2 to apply)"
fi

# ~/.config/mise のリンクが消える前に実行する
"${mise_cmd[@]}" run cleanup:caches

"${mise_cmd[@]}" bootstrap dotfiles unapply --yes

echo "✅ Cleanup complete!"
