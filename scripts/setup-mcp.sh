#!/bin/bash
# .claude/mcp_config.json の MCP サーバーを登録する
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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

setup_mcp "${1:-$SCRIPT_DIR/.claude/mcp_config.json}"
