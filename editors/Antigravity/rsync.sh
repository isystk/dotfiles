#!/bin/bash

DOT_VSC_DIR="$(cd "$(dirname "$0")"; pwd)"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS の設定
    VSCODE_USER_DIR="$HOME/Library/Application Support/Antigravity IDE/User"
    VSCODE_DOT_VSC_DIR="$HOME/.antigravity-ide"
    CODE_CMD=$(which antigravity-ide)
    if [ -z "$CODE_CMD" ]; then
        CODE_CMD="/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide"
    fi
else
    # Windows (WSL) の設定
    WIN_USER=$(powershell.exe -c "echo \$env:USERNAME" | tr -d '\r')
    VSCODE_USER_DIR="/mnt/c/Users/${WIN_USER}/AppData/Roaming/Antigravity IDE/User"
    VSCODE_DOT_VSC_DIR="/mnt/c/Users/${WIN_USER}/.antigravity-ide"
    CODE_CMD=$(which antigravity-ide)
    if [ -z "$CODE_CMD" ]; then
        CODE_CMD="/mnt/c/Users/${WIN_USER}/AppData/Local/Programs/Antigravity IDE/bin/antigravity-ide"
    fi
fi

case "$1" in
    "push")
        echo "Pushing settings to Antigravity IDE..."
        mkdir -p "$VSCODE_USER_DIR"
        mkdir -p "$VSCODE_DOT_VSC_DIR"
        
        [ -f "$DOT_VSC_DIR/settings.json" ]    && cp "$DOT_VSC_DIR/settings.json"    "$VSCODE_USER_DIR/settings.json"
        [ -f "$DOT_VSC_DIR/keybindings.json" ] && cp "$DOT_VSC_DIR/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
        [ -f "$DOT_VSC_DIR/argv.json" ]        && cp "$DOT_VSC_DIR/argv.json"        "$VSCODE_DOT_VSC_DIR/argv.json"

        if [ -f "$DOT_VSC_DIR/extensions.txt" ]; then
            cat "$DOT_VSC_DIR/extensions.txt" | xargs -L 1 "$CODE_CMD" --install-extension
        fi
        echo "Applied dotfiles to Antigravity IDE."
        ;;

    "pull")
        echo "Pulling settings from Antigravity IDE..."
        [ -f "$VSCODE_USER_DIR/settings.json" ]    && cp "$VSCODE_USER_DIR/settings.json"    "$DOT_VSC_DIR/settings.json"
        [ -f "$VSCODE_USER_DIR/keybindings.json" ] && cp "$VSCODE_USER_DIR/keybindings.json" "$DOT_VSC_DIR/keybindings.json"
        
        if [ -f "$VSCODE_DOT_VSC_DIR/argv.json" ]; then
            cp "$VSCODE_DOT_VSC_DIR/argv.json" "$DOT_VSC_DIR/argv.json"
            echo "  Successfully pulled argv.json"
        else
            echo "  Warning: argv.json not found in $VSCODE_DOT_VSC_DIR"
        fi

        "$CODE_CMD" --list-extensions > "$DOT_VSC_DIR/extensions.txt"
        echo "  Pulled all settings and extensions list."
        ;;
    *)
        echo "Usage: ./sync.sh [push|pull]"
        ;;
esac