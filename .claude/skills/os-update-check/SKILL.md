---
name: os-update-check
description: Use when the user wants to know whether OS packages or installed tools have updates, asks "アップデートある？", "更新確認して", "バージョンアップが必要か見て", wants to check Windows-side updates from WSL (winget), Mac updates (brew / App Store), or dev tool updates (mise, npm -g, pip), and wants a recommendation before applying anything.
---

# os-update-check

## 概要

OS と開発ツールの更新有無を**読み取り専用**で確認し、一覧と推奨案を提示する。**ユーザーの承認なしに更新は一切適用しない。**

- 対象（OS層）: Linux = apt / snap / flatpak、WSL = 上記 + Windows 側 winget、macOS = brew / cask / mas / softwareupdate
- 対象（開発ツール層）: mise、npm -g、pip
- WSL では `winget.exe` を WSL から直接呼べるため、Windows 側も同じ流れで確認・適用できる

## 手順

1. **取得**: `bash ~/.claude/skills/os-update-check/scripts/check.sh` を実行（環境を自動判定。開発ツール層を省くなら `--no-dev`）。変更系コマンドは含まれない。
2. **一覧提示**: 層別（OS / Windows / 開発ツール）に「名前・現在版・最新版・更新幅（patch / minor / major）」を簡潔にまとめる。取得失敗・スキップした層は明記する。
3. **推奨案を提示**: 各項目を次の3区分に分け、理由を1行付ける。
   - **今すぐ推奨**: セキュリティ更新（apt の `-security`、ca-certificates、openssl 等）、patch 更新
   - **注意して適用**: 常駐プロセス・再起動への影響があるもの、minor 更新
     - docker-ce 系: デーモン再起動で稼働中コンテナが止まる可能性
     - カーネル / systemd 等: 再起動要求（`/var/run/reboot-required`）
     - Windows 側で起動中のアプリ（Teams / OBS 等）: 閉じてから適用、UAC が出ることがある
   - **見送り・要確認**: major 更新、`~/.config/mise/config.toml` で版を固定しているツール（go 1.21、php 8.4.25、neovim 0.12.4 等）、プロジェクトが版に依存しているもの
4. **承認を取る**: 適用対象を聞く（全部 / 区分単位 / 個別指定）。承認が出るまで更新系コマンドを実行しない。
5. **適用**（承認された対象のみ。`upgrade` 一括ではなく対象を明示する）:

   | 対象 | コマンド | 実行者 |
   |---|---|---|
   | apt | `sudo apt-get install --only-upgrade <pkg...>` | ユーザー（`! ` で実行。Claude は sudo を使えない） |
   | winget | `winget.exe upgrade --id <ID> --disable-interactivity` | Claude（UAC 事前通知） |
   | brew / cask | `brew upgrade <name>` / `brew upgrade --cask <name>` | Claude |
   | mas | `mas upgrade <id>` | Claude |
   | softwareupdate | `sudo softwareupdate -i <label>` | ユーザー |
   | snap | `sudo snap refresh <name>` | ユーザー |
   | mise | `mise upgrade <tool>` | Claude |
   | npm -g | `npm install -g <pkg>@latest` | Claude |
   | pip | `pip install -U <pkg>` | Claude |

6. **事後確認**: `check.sh` を再実行して残件を報告。再起動が必要なら案内する（WSL は Windows 側 PowerShell で `wsl --shutdown`）。

## 注意

- **apt の索引が古い**と最新が見えない。`check.sh` が経過日数を表示する。`sudo apt update` はユーザーに実行してもらう。
- **brew の最新化**（`brew update`）はメタデータ更新のみだが、書き込みを伴うので実行前に確認する。
- **mise の旧版削除**: `mise upgrade` は旧版を即削除せず「24 時間後に prune」と予約し、次回以降の mise 実行時（`mise outdated` 等）に削除される。取得コマンドの副作用ではなく mise の仕様（2026-11-06 確認）。承認時に「旧版は 24 時間後に自動削除される」と伝える。`check.sh` は念のためインストール一覧の前後比較を行う。
- **dpkg の `Invalid cross-device link`**: `/usr/bin/perf` 等がバインドマウントされていると、dpkg が上書きできず `linux-tools-common` などの更新が失敗する（`findmnt <path>` で確認）。復旧は `sudo umount <path>` → `sudo dpkg --configure -a` → 再 `apt-get install --only-upgrade`。適用前に、更新対象パッケージのファイルがマウントされていないか確認する。umount 後もマウントは自動で復活することがある（2026-11-06 確認、仕組みは未特定）ので、更新後に `findmnt` で状態を確認する。
- `winget.exe upgrade` は版が不明なアプリを出さない。必要なら `--include-unknown` を使う（誤更新のおそれがあるので個別確認）。
- `pip list --outdated` はグローバル環境の推移依存まで列挙する。major 更新（protobuf 5→7 等）は他パッケージを壊すため原則「見送り」とし、直接使っているものだけ個別に扱う。
- macOS の分岐（brew / mas / softwareupdate）は実機未検証。コマンド仕様に基づく。

## 禁止

- 承認前の `upgrade` / `install` / `uninstall` / `prune` の実行
- `sudo apt upgrade -y` のような一括適用（対象を明示して適用する）
- 副作用を観測したのに報告しないこと
