#!/bin/bash

# mise.toml の dotfiles を配置し、確認付きで手動タスクを実行する

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/scripts/utils.sh"

if ! resolve_mise; then
    echo -n "mise が見つかりません。公式スクリプト (https://mise.run) で ~/.local/bin にインストールしますか? (y/N): "
    read -r mise_ans
    case "$mise_ans" in
        [yY][eE][sS]|[yY]) curl -fsSL https://mise.run | sh ;;
        *) echo "中断しました。mise をインストールしてから再実行してください (https://mise.jdx.dev)。" >&2; exit 1 ;;
    esac
    resolve_mise || { echo "mise のインストールに失敗しました。" >&2; exit 1; }
fi
export PATH="$(dirname "$MISE_BIN"):$PATH"
# タスク実行前の [tools] 自動導入を止める（導入は別途 mise install）
export MISE_TASK_RUN_AUTO_INSTALL=false

mise_env=""
[ -n "$IS_MAC" ] && mise_env="mac"
[ -n "$IS_WSL" ] && mise_env="wsl"
mise_cmd=(mise -C "$SCRIPT_DIR")
[ -n "$mise_env" ] && mise_cmd+=(-E "$mise_env")

for f in mise.toml mise.mac.toml mise.wsl.toml; do
    [ -f "$SCRIPT_DIR/$f" ] && mise trust "$SCRIPT_DIR/$f"
done

# mise は既存ファイルを上書きしないため、競合分は退避する
"${mise_cmd[@]}" bootstrap dotfiles status 2>/dev/null | awk '/ differs( |$)/ { print $1 }' | while read -r t; do
    target="${t/#\~/$HOME}"
    backup="$target.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backing up: $target -> $backup"
    mv "$target" "$backup"
done

"${mise_cmd[@]}" bootstrap --only dotfiles,task --yes

if [ -n "$IS_WSL" ]; then
    "${mise_cmd[@]}" run setup:wsl-etc
fi

if [ -n "$IS_MAC" ]; then
    echo -n "Install Homebrew packages (mise.mac.toml の [bootstrap.packages])? (y/N): "
    read -r pkg_ans
    case "$pkg_ans" in
        [yY][eE][sS]|[yY]) "${mise_cmd[@]}" bootstrap packages apply --yes ;;
        *) echo "Skipping Homebrew packages..." ;;
    esac

    echo -n "Setup macOS config (iTerm2)? (y/N): "
    read -r iterm_ans
    case "$iterm_ans" in
        [yY][eE][sS]|[yY]) "${mise_cmd[@]}" run setup:iterm2 ;;
        *) echo "Skipping iTerm2 config setup..." ;;
    esac
fi

echo -n "Register Claude MCP servers? (y/N): "
read -r mcp_ans
case "$mcp_ans" in
    [yY][eE][sS]|[yY]) "${mise_cmd[@]}" run setup:mcp ;;
    *) echo "Skipping MCP setup..." ;;
esac

# herdr プラグイン（ビルドに Rust が必要）
if command -v herdr >/dev/null 2>&1; then
    if ! herdr plugin list 2>/dev/null | grep -q "persiyanov.reviewr"; then
        echo -n "Install herdr plugin reviewr (diff review)? (y/N): "
        read -r ans
        case "$ans" in
            [yY][eE][sS]|[yY]) "${mise_cmd[@]}" run setup:herdr ;;
            *) echo "Skipping herdr plugin setup..." ;;
        esac
    fi
fi

echo "Done!"
