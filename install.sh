#!/bin/bash

# 1. 未定義変数やエラーが発生した時点で停止させる
set -u

# 2. 実行ディレクトリの取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/scripts/utils.sh"

# ファイルコピー関数 (ターゲットが存在しない場合のみコピー)
# $1: ソース (コピー元ファイル)
# $2: ターゲット (作成するファイル)
copy_with_prompt() {
    local source="$1"
    local target="$2"

    if [ ! -e "$source" ]; then
        echo "Skip copy: Source $source does not exist."
        return
    fi

    if [ -e "$target" ]; then
        echo -n "Notice: $target already exists. Overwrite? (y/N): "
        read -r ans
        case "$ans" in
            [yY][eE][sS]|[yY])
                echo "Backing up existing file to $target.bak..."
                cp -R "$target" "$target.bak"
                ;;
            *)
                echo "Skipping copy..."
                return
                ;;
        esac
    fi

    # コピー実行セクション (既存ファイルは cp が上書きするため rm は行わない)
    echo "Copying: $source to $target"
    mkdir -p "$(dirname "$target")"
    cp -R "$source" "$target" # ディレクトリごとコピーできるよう -R を推奨
}

# シンボリックリンク作成関数
# $1: ソース (実体ファイル)
# $2: ターゲット (作成するリンクの場所)
symlink() {
    local source="$1"
    local target="$2"

    if [ ! -e "$source" ]; then
        echo "Skip: $source does not exist."
        return
    fi

    mkdir -p "$(dirname "$target")"

    if [ -e "$target" ] || [ -L "$target" ]; then
        # 既にリンクまたはファイルが存在する場合
        if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
            echo "Valid link already exists: $target"
            return
        fi

        echo -n "Warning: $target already exists. Overwrite? (y/N): "
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            # バックアップを作成して上書き
            rm -rf "$target"
            echo "Create link: $target"
            ln -snf "$source" "$target"
        else
            echo "Skipped: $target"
        fi
    else
        echo "Create link: $target"
        ln -s "$source" "$target"
    fi
}

# Claude MCP サーバー登録関数
# $1: mcp_config.json のパス ({"mcpServers": {...}} 形式)
setup_mcp() {
    local mcp_config="$1"

    if [ ! -f "$mcp_config" ]; then
        echo "Skip MCP setup: $mcp_config does not exist."
        return
    fi

    if ! command -v claude &>/dev/null; then
        echo "Skip MCP setup: claude command not found."
        return
    fi

    local servers
    servers=$(python3 -c "
import json, sys
print('\n'.join(json.load(open(sys.argv[1]))['mcpServers'].keys()))
" "$mcp_config")

    for server in $servers; do
        if claude mcp get "$server" &>/dev/null 2>&1; then
            echo "MCP already configured: $server"
            continue
        fi

        echo "Registering MCP: $server"

        local cmd_args=()
        while IFS= read -r arg; do
            # mcp_config.json内の $HOME プレースホルダーを実行環境の値へ展開する
            # (Mac/WSLでホームパスが異なるため、設定ファイル自体はハードコードしない)
            cmd_args+=("${arg//\$HOME/$HOME}")
        done < <(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['mcpServers'][sys.argv[2]]
print('\n'.join(d['args']))
" "$mcp_config" "$server")

        local command
        command=$(python3 -c "
import json, sys
print(json.load(open(sys.argv[1]))['mcpServers'][sys.argv[2]]['command'])
" "$mcp_config" "$server")

        local env_args=()
        local env_pairs
        env_pairs=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['mcpServers'][sys.argv[2]]
for k, v in d.get('env', {}).items():
    print(f'{k}={v}')
" "$mcp_config" "$server")
        while IFS= read -r pair; do
            [ -n "$pair" ] && env_args+=(--env "$pair")
        done <<< "$env_pairs"

        claude mcp add "$server" -s user "${env_args[@]+"${env_args[@]}"}" -- "$command" "${cmd_args[@]+"${cmd_args[@]}"}"
    done
}

# --- 実行セクション ---

# ローカル環境設定 (exampleをコピーして作成)
copy_with_prompt "$SCRIPT_DIR/.setenv.local.example" "$HOME/.setenv.local"
copy_with_prompt "$SCRIPT_DIR/.gitconfig.local.example" "$HOME/.gitconfig.local"

# Shell / Env (シンボリックリンク)
symlink "$SCRIPT_DIR/.bash_profile" "$HOME/.bash_profile"
symlink "$SCRIPT_DIR/.bashrc"       "$HOME/.bashrc"
symlink "$SCRIPT_DIR/.zshrc"        "$HOME/.zshrc"
symlink "$SCRIPT_DIR/.setenv.wsl"   "$HOME/.setenv.wsl"
symlink "$SCRIPT_DIR/.setenv.mac"   "$HOME/.setenv.mac"
symlink "$SCRIPT_DIR/.setenv.linux"   "$HOME/.setenv.linux"

# gemini-cli
symlink "$SCRIPT_DIR/scripts/gemini-cli.py" "$HOME/.local/bin/gemini-cli"

# chatgpt-cli
symlink "$SCRIPT_DIR/scripts/chatgpt-cli.py" "$HOME/.local/bin/chatgpt-cli"

# Git / Vim / Config
symlink "$SCRIPT_DIR/.gitconfig"    "$HOME/.gitconfig"
symlink "$SCRIPT_DIR/.vimrc"        "$HOME/.vimrc"
symlink "$SCRIPT_DIR/.config/gemini-cli" "$HOME/.config/gemini-cli"
symlink "$SCRIPT_DIR/.config/chatgpt-cli" "$HOME/.config/chatgpt-cli"
symlink "$SCRIPT_DIR/.config/git"    "$HOME/.config/git"
symlink "$SCRIPT_DIR/.config/gh"     "$HOME/.config/gh"
symlink "$SCRIPT_DIR/.config/nvim"   "$HOME/.config/nvim"
symlink "$SCRIPT_DIR/.config/mise"   "$HOME/.config/mise"

# Claude
symlink "$SCRIPT_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
symlink "$SCRIPT_DIR/.claude/settings.json" "$HOME/.claude/settings.json"
symlink "$SCRIPT_DIR/.claude/hooks" "$HOME/.claude/hooks"
symlink "$SCRIPT_DIR/.claude/statusline.sh" "$HOME/.claude/statusline.sh"
symlink "$SCRIPT_DIR/.claude/agents" "$HOME/.claude/agents"
symlink "$SCRIPT_DIR/.claude/skills" "$HOME/.claude/skills"
symlink "$SCRIPT_DIR/.claude/rules" "$HOME/.claude/rules"

# Gemini / Antigravity
symlink "$SCRIPT_DIR/.gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"
symlink "$SCRIPT_DIR/.gemini/settings.json" "$HOME/.gemini/settings.json"
symlink "$SCRIPT_DIR/.gemini/rules" "$HOME/.gemini/rules"
symlink "$SCRIPT_DIR/.gemini/skills" "$HOME/.gemini/skills"
symlink "$SCRIPT_DIR/.claude/mcp_config.json" "$HOME/.gemini/antigravity/mcp_config.json"

# Codex
symlink "$SCRIPT_DIR/.codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
# Codex の MCP 定義は ~/.codex/config.toml の [mcp_servers] を使う
symlink "$SCRIPT_DIR/.codex/config.toml" "$HOME/.codex/config.toml"
symlink "$SCRIPT_DIR/.codex/.codexignore" "$HOME/.codexignore"
symlink "$SCRIPT_DIR/.codex/rules" "$HOME/.codex/rules"
symlink "$SCRIPT_DIR/.codex/skills" "$HOME/.codex/skills"

if [ -n "$IS_MAC" ]; then
    # macOS固有の設定 (Karabiner-Elements)
    echo -n "Setup macOS config (Karabiner-Elements)? (y/N): "
    read -r mac_ans
    case "$mac_ans" in
        [yY][eE][sS]|[yY])
            symlink "$SCRIPT_DIR/.config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
            symlink "$SCRIPT_DIR/.config/karabiner/assets/complex_modifications" "$HOME/.config/karabiner/assets/complex_modifications"

            ;;
        *)
            echo "Skipping macOS config setup..."
            ;;
    esac
fi

if [ -n "$IS_WSL" ]; then
    # WSL固有の設定
    echo "Configuring WSL system files (requires sudo)..."
    if [ -f "$SCRIPT_DIR/.config/wsl/wsl.conf" ]; then
        copy_with_prompt "$SCRIPT_DIR/.config/wsl/wsl.conf" /etc/wsl.conf
    fi
    if [ -f "$SCRIPT_DIR/.config/wsl/resolv.conf" ]; then
        copy_with_prompt "$SCRIPT_DIR/.config/wsl/resolv.conf" /etc/resolv.conf
    fi
    if [ -f "$SCRIPT_DIR/.config/wsl/fstab" ]; then
        copy_with_prompt "$SCRIPT_DIR/.config/wsl/fstab" /etc/fstab
    fi
fi

# MCP サーバーの登録
echo -n "Register Claude MCP servers? (y/N): "
read -r mcp_ans
case "$mcp_ans" in
    [yY][eE][sS]|[yY])
        setup_mcp "$SCRIPT_DIR/.claude/mcp_config.json"
        ;;
    *)
        echo "Skipping MCP setup..."
        ;;
esac

# 5. 実行権限の付与
find . -name "*.sh" -exec chmod a+x {} +
chmod +x "$SCRIPT_DIR/scripts/gemini-cli.py"
chmod +x "$SCRIPT_DIR/scripts/chatgpt-cli.py"
chmod +x ~/.config/git/hooks/*

echo "Done!"
