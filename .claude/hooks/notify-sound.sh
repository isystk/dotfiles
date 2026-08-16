#!/usr/bin/env bash
# Stop hook: セッション終了時に通知音を鳴らす
# 端末のベル設定（多くの場合デフォルトで無効）に依存せず、OSごとに確実な方法で音を鳴らす

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/../../scripts/utils.sh"

if [ -n "$IS_MAC" ]; then
  # macOS: システムサウンドを再生
  afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 && exit 0
fi

if command -v powershell.exe >/dev/null 2>&1; then
  # WSL上のWindows: PowerShell経由でビープ音を鳴らす（Windows Terminalのベル設定に依存しない）
  powershell.exe -NoProfile -Command "[console]::beep(800,300)" >/dev/null 2>&1 && exit 0
fi

if command -v paplay >/dev/null 2>&1; then
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 && exit 0
fi

if command -v aplay >/dev/null 2>&1; then
  aplay /usr/share/sounds/alsa/Front_Center.wav >/dev/null 2>&1 && exit 0
fi

# フォールバック: 端末ベル
printf '\a' > /dev/tty 2>/dev/null || true
