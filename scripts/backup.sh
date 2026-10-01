#! /bin/bash

set -e

BACKUP_LIST="$HOME/.backup-files"
LAST_SYNC_FILE="$HOME/.cache/dotfiles/last_backup"

confirm() {
    if [ "$FORCE" = true ]; then return 0; fi
    read -r -p "${1:-Are you sure?} [y/N]: " ans
    [[ $ans =~ ^[Yy] ]] && return 0 || return 1
}

get_backup_dest() {
    if [ -n "$BACKUP_DEST" ]; then
        echo "$BACKUP_DEST"
        return
    fi
    local win_user
    win_user=$(powershell.exe -c "echo \$env:USERNAME" | tr -d '\r')
    echo "/mnt/c/Users/${win_user}/backups"
}

load_backup_paths() {
    if [ ! -f "$BACKUP_LIST" ]; then
        echo "Error: $BACKUP_LIST not found." >&2
        exit 1
    fi
    grep -vE '^[[:space:]]*(#|$|!)' "$BACKUP_LIST" | sed "s|^~|$HOME|"
}

load_exclude_patterns() {
    if [ ! -f "$BACKUP_LIST" ]; then
        return
    fi
    grep -E '^[[:space:]]*!' "$BACKUP_LIST" | sed -E 's/^[[:space:]]*!//'
}

case "${1}" in

    push)
        mapfile -t paths < <(load_backup_paths)
        if [ "${#paths[@]}" -eq 0 ]; then
            echo "No paths to back up in $BACKUP_LIST."
            exit 0
        fi

        mapfile -t excludes < <(load_exclude_patterns)
        exclude_args=()
        for pattern in "${excludes[@]}"; do
            exclude_args+=(--exclude "$pattern")
        done

        dest="$(get_backup_dest)"
        echo "バックアップ先: $dest"
        if [ "${#excludes[@]}" -gt 0 ]; then
            exclude_list="$(printf '%s, ' "${excludes[@]}")"
            echo "除外パターン: ${exclude_list%, }"
        fi
        mkdir -p "$dest"

        if [ -d "$dest" ]; then
            deletions="$(rsync -a --relative --delete --dry-run "${exclude_args[@]}" "${paths[@]}" "$dest/" | grep -E '^deleting ' || true)"
            if [ -n "$deletions" ]; then
                echo "以下のファイルがバックアップ先から削除されます:"
                echo "$deletions"
                if ! confirm "削除を実行しますか？"; then
                    echo "削除をスキップし、追加・変更のみ反映します。"
                    rsync -av --relative "${exclude_args[@]}" "${paths[@]}" "$dest/"
                    mkdir -p "$(dirname "$LAST_SYNC_FILE")"
                    date +%s > "$LAST_SYNC_FILE"
                    echo "✅ バックアップが完了しました。"
                    exit 0
                fi
            fi
        fi
        rsync -av --relative --delete "${exclude_args[@]}" "${paths[@]}" "$dest/"

        mkdir -p "$(dirname "$LAST_SYNC_FILE")"
        date +%s > "$LAST_SYNC_FILE"
        echo "✅ バックアップが完了しました。"
        ;;

    pull)
        dest="$(get_backup_dest)"
        if [ ! -d "$dest" ]; then
            echo "Error: $dest not found." >&2
            exit 1
        fi

        echo "リストア元: $dest"
        if confirm "ローカルの既存ファイルを上書きします。続行しますか？"; then
            rsync -av "$dest/" /
            echo "✅ リストアが完了しました。"
        else
            echo "Aborted."
        fi
        ;;

    check-sync)
        if [ ! -f "$BACKUP_LIST" ]; then
            exit 0
        fi
        mapfile -t _check_paths < <(load_backup_paths)
        if [ "${#_check_paths[@]}" -eq 0 ]; then
            exit 0
        fi

        if [ -f "$LAST_SYNC_FILE" ]; then
            last_sync_epoch="$(cat "$LAST_SYNC_FILE")"
            if [ "$(date -d "@$last_sync_epoch" "+%Y-%m-%d")" = "$(date "+%Y-%m-%d")" ]; then
                exit 0
            fi
            last_sync="$(date -d "@$last_sync_epoch" "+%Y-%m-%d %H:%M:%S")"
            echo "最後の同期日時: $last_sync"
        else
            echo "最後の同期日時: 未同期"
        fi

        if confirm "今すぐバックアップを実行しますか？"; then
            "$0" push
        fi
        ;;

    *)
        echo "Usage: $0 [push|pull|check-sync]"
        ;;
esac
