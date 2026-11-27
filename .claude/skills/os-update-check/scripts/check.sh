#!/usr/bin/env bash
# os-update-check: 更新有無の一括取得（読み取り専用）
# upgrade / install / uninstall / update 等の変更系コマンドは一切実行しない。
# 使い方: bash check.sh [--no-dev]   （--no-dev: 開発ツール層を省略）

set -u

WITH_DEV=1
[ "${1:-}" = "--no-dev" ] && WITH_DEV=0

have() { command -v "$1" >/dev/null 2>&1; }
sec() { printf '\n=== %s ===\n' "$1"; }
skip() { printf '(未導入のためスキップ: %s)\n' "$1"; }

# --- 環境判定 ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin) ENV=mac ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then ENV=wsl; else ENV=linux; fi
    ;;
  *) ENV=unknown ;;
esac
printf 'ENV=%s\n' "$ENV"

# --- OS層: Linux / WSL ------------------------------------------------------
if [ "$ENV" = linux ] || [ "$ENV" = wsl ]; then
  sec "apt (Linux)"
  if have apt; then
    stamp=/var/lib/apt/periodic/update-success-stamp
    [ -e "$stamp" ] || stamp=/var/lib/apt/lists
    if [ -e "$stamp" ]; then
      age_days=$(( ( $(date +%s) - $(stat -c %Y "$stamp") ) / 86400 ))
      printf 'apt索引の最終更新: %s日前%s\n' "$age_days" \
        "$([ "$age_days" -ge 7 ] && echo '（古い。ユーザーが sudo apt update を実行すると最新化できる）')"
    fi
    apt list --upgradable 2>/dev/null | grep -v '^Listing\|^一覧表示'
    [ -e /var/run/reboot-required ] && echo "再起動要求あり: /var/run/reboot-required"
  else
    skip apt
  fi

  sec "snap"
  if have snap; then snap refresh --list 2>&1; else skip snap; fi

  if have flatpak; then
    sec "flatpak"
    flatpak remote-ls --updates 2>&1
  fi
fi

# --- OS層: WSL の Windows 側 -------------------------------------------------
if [ "$ENV" = wsl ]; then
  sec "winget (Windows側)"
  if have winget.exe; then
    # CR 除去。--disable-interactivity で対話待ちを防ぐ
    timeout 120 winget.exe upgrade --disable-interactivity 2>&1 | tr -d '\r'
  else
    skip winget.exe
  fi
fi

# --- OS層: macOS ------------------------------------------------------------
if [ "$ENV" = mac ]; then
  sec "brew formula"
  if have brew; then brew outdated --verbose 2>&1; else skip brew; fi

  sec "brew cask"
  if have brew; then brew outdated --cask --verbose 2>&1; else skip brew; fi

  sec "Mac App Store (mas)"
  if have mas; then mas outdated 2>&1; else skip mas; fi

  sec "macOS (softwareupdate)"
  if have softwareupdate; then softwareupdate --list 2>&1; else skip softwareupdate; fi
fi

# --- 開発ツール層 -------------------------------------------------------------
if [ "$WITH_DEV" = 1 ]; then
  sec "mise"
  if have mise; then
    # --json で取得。mise は upgrade の 24 時間後に旧版を自動 prune する仕様のため、
    # 前後でインストール一覧を比較し、変化があれば報告する
    mise_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs"
    before=$(find "$mise_dir" -maxdepth 2 -mindepth 2 -type d 2>/dev/null | sort)
    if have jq; then
      mise outdated --json 2>&1 | jq -r 'to_entries[] | "\(.key)\t現在=\(.value.current // "-")\t最新=\(.value.latest // "-")\t指定=\(.value.requested // "-")"' 2>/dev/null \
        || mise outdated --json 2>&1
    else
      mise outdated --json 2>&1
    fi
    after=$(find "$mise_dir" -maxdepth 2 -mindepth 2 -type d 2>/dev/null | sort)
    if [ "$before" != "$after" ]; then
      echo "注意: 取得中に mise のインストール一覧が変化した（予約済み旧版の自動 prune の可能性）。差分:"
      diff <(printf '%s\n' "$before") <(printf '%s\n' "$after")
    fi
  else
    skip mise
  fi

  sec "npm -g"
  if have npm; then npm outdated -g 2>&1; else skip npm; fi

  sec "pip (outdated)"
  if have pip; then pip list --outdated --format=columns 2>&1 | head -50; else skip pip; fi
fi

printf '\n--- 完了（読み取りのみ。何も変更していない） ---\n'
