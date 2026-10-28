#! /bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/.."

confirm() {
    if [ "$FORCE" = true ]; then return 0; fi
    read -r -p "${1:-Are you sure?} [y/N]: " ans
    [[ $ans =~ ^[Yy] ]] && return 0 || return 1
}

usage() {
    awk '
        { lines[NR] = $0 }
        END {
            parent = ""
            desc = ""
            first = 1
            for (i = 1; i <= NR; i++) {
                line = lines[i]
                match(line, /^[[:space:]]*/); indent = RLENGTH

                # カテゴリ見出し（#[カテゴリ名]）
                if (line ~ /^[[:space:]]*#\[/) {
                    cat = line
                    sub(/^[[:space:]]*#\[/, "", cat)
                    sub(/\][[:space:]]*$/, "", cat)
                    printf "%s%s\n", (first ? "" : "\n"), cat
                    first = 0
                    parent = ""
                    desc = ""
                    continue
                }

                # 説明文の保持
                if (line ~ /^[[:space:]]*## /) {
                    desc = line
                    sub(/.*## /, "", desc)
                    continue
                }

                # 子階層の終了（親階層へ戻る）
                if (indent == 8 && line ~ /^[[:space:]]*esac/) {
                    parent = ""
                    continue
                }

                if (line ~ /^[[:space:]]*[a-zA-Z0-9_*| -]+\)/) {
                    cmd = line
                    sub(/^[[:space:]]*/, "", cmd)
                    sub(/\).*/, "", cmd)              # ")" 以降を削除
                    sub(/[[:space:]]*\|.*/, "", cmd)  # "|" があればそれ以降（*)など）を削除

                    # 次の兄弟コマンドが現れるまでの間に "case "${2}" in" があれば子階層を持つ親コマンド
                    if (indent == 4) {
                        is_parent = 0
                        for (j = i + 1; j <= NR; j++) {
                            line2 = lines[j]
                            match(line2, /^[[:space:]]*/); indent2 = RLENGTH
                            if (indent2 == 4 && line2 ~ /^[[:space:]]*[a-zA-Z0-9_*| -]+\)/) break
                            if (line2 ~ /case "\$\{2\}" in/) { is_parent = 1; break }
                        }
                        if (is_parent) {
                            parent = cmd
                            desc = ""
                            continue
                        }
                    }

                    if (desc != "") {
                        full = (parent != "" && cmd != parent) ? parent " " cmd : cmd
                        printf "  %-22s %s\n", full, desc
                        desc = ""
                    }
                }
            }
        }
    ' "$0"
}

case "${1}" in

    #[生成]

    ## 差分からPR説明文を生成
    pr-gen)
        "${SCRIPT_DIR}/pr-gen.sh"
        ;;

    ## Markdown形式で記事を生成
    blog-gen)
        "${SCRIPT_DIR}/blog-gen.sh" "${@:2}"
        ;;

    ## 記事タイトルからアイキャッチ画像を生成
    blog-thumb)
        "${SCRIPT_DIR}/blog-thumb.sh" "${@:2}"
        ;;

    ## Marpスライド・プレゼン原稿を生成
    slide-gen)
        "${SCRIPT_DIR}/slide-gen.sh" "${@:2}"
        ;;

    ## Markdownから音声を生成（VOICEVOX）
    voice-gen)
        "${SCRIPT_DIR}/voice-gen.sh"
        ;;

    ## PDFと音声から動画を生成
    video-gen)
        "${SCRIPT_DIR}/video-gen.sh"
        ;;

    ## 音声ファイルを文字起こし
    audio-transcribe)
        "${SCRIPT_DIR}/file-task.sh" -t=transcribe "${@:2}"
        ;;

    #[変換]

    ## 画像をWeb用に最適化（1200px・圧縮・EXIF削除）
    image-opt)
        "${SCRIPT_DIR}/image_opt.py" "${@:2}"
        ;;

    ## Webページを画像に変換
    web-shot)
        "${SCRIPT_DIR}/web_shot.py" "${@:2}"
        ;;

    ## 画像をPDFに変換
    image-to-pdf)
        "${SCRIPT_DIR}/image_to_pdf.py" "${@:2}"
        ;;

    #[GitHub]

    ## PRを選択して開く／チェックアウト／マージ／AIレビュー
    github)
        "${SCRIPT_DIR}/ghs.sh" "${@:2}"
        ;;

    #[データベース]

    ## MySQL操作（ログイン／インポート／エクスポート）
    mysql)
        "${SCRIPT_DIR}/mysql-ops.sh" "${@:2}"
        ;;

    #[Docker]

    docker)
        case "${2}" in

            ## 未使用リソースを確認して削除
            prune)
                echo "--- 削除対象のプレビュー ---"
                echo "[停止中のコンテナ]"
                docker ps -a -f status=exited -f status=created --format "{{.Names}} ({{.ID}})"
                echo -e "\n[未使用のイメージ]"
                docker images -f "dangling=true" --format "{{.Repository}}:{{.Tag}} ({{.ID}})"
                echo -e "\n[未使用のボリューム]"
                docker volume ls -qf dangling=true
                echo -e "\n--------------------------"
                read -p "これらの未使用リソースをすべて削除しますか？ (y/N): " chk
                if [[ "$chk" =~ ^[yY]([eE][sS])?$ ]]; then
                    echo "削除を開始します..."
                    docker container prune -f
                    docker image prune -f
                    docker volume prune -f
                    echo "クリーンアップが完了しました。"
                else
                    echo "キャンセルしました。"
                fi
                ;;

            ## コンテナ操作（入る／ログ／差分／再起動／削除）
            container | *)
                "${SCRIPT_DIR}/d-manage.sh"
                ;;
        esac
        ;;

    #[WordPress]

    ## WordPress管理（投稿一覧／表示／削除／カテゴリ）
    wordpress)
        "${SCRIPT_DIR}/wordpress.sh" "${@:2}"
        ;;

    #[ファイル]

    ## バックアップ対象リストを同期（push／pull／check-sync）
    backup)
        "${SCRIPT_DIR}/backup.sh" "${@:2}"
        ;;

    ## .DS_Store等のメタデータファイルを削除
    file-clean)
        target="${2:-.}"
        [ ! -d "$target" ] && echo "Error: $target not found." && exit 1
        files=$(find "$target" \( -name "*:Zone.Identifier" -o -name ".DS_Store" \) -type f 2>/dev/null)
        if [ -z "$files" ]; then
            echo "✅ 削除対象はありません。"
        else
            echo "🗑️  削除対象:"
            echo "$files" | sed 's/^/  /'
            read -p "実行しますか？ (y/N): " confirm
            [[ "$confirm" =~ ^[yY]$ ]] && echo "$files" | xargs -d '\n' rm -v && echo "✨ 完了" || echo "中止"
        fi
        ;;

    ## CRLFファイルを検出してLFへ変換
    file-crlf)
        target="${2:-.}"
        echo "Searching for files to convert in: $target"
        # git ls-files の引数としてターゲットを渡す（-C は使わない）
        files=$(git ls-files -c -o --exclude-standard "$target" | \
            xargs -I {} grep -Irl $'\r' "{}" 2>/dev/null || true)

        if [ -z "$files" ]; then
            echo "No CRLF files found."
            # exit 0 ではなく return や break (case文の中なので) にするか、そのまま終了させる
            return 0 2>/dev/null || exit 0
        fi
        echo "--- Target Files (Git managed & Non-ignored) ---"
        echo "$files"
        echo "------------------------------------------------"
        if confirm "Convert these files to LF?"; then
            # ファイルリストをループして変換を実行
            echo "$files" | xargs -I {} perl -pi -e 's/\r\n/\n/g' "{}"
            echo "Conversion complete."
        else
            echo "Aborted."
        fi
        ;;

    #[エディタ]

    vscode)
        case "${2}" in

            ## VSCodeの設定ファイルをバックアップ
            backup)
                pushd "${BASE_DIR}/editors/VSCode"
                ./rsync.sh pull
                popd
                ;;

            ## VSCodeの設定ファイルをリストア
            restore)
                pushd "${BASE_DIR}/editors/VSCode"
                ./rsync.sh push
                popd
                ;;
        esac
        ;;

    antigravity)
        case "${2}" in

            ## Antigravityの設定ファイルをバックアップ
            backup)
                pushd "${BASE_DIR}/editors/Antigravity"
                ./rsync.sh pull
                popd
                ;;

            ## Antigravityの設定ファイルをリストア
            restore)
                pushd "${BASE_DIR}/editors/Antigravity"
                ./rsync.sh push
                popd
                ;;
        esac
        ;;

    #[メンテナンス]

    ## 依存コマンドを一括チェック
    doctor)
        missing=0
        check() {
            # $1=必須(req)/任意(opt)  $2=コマンド名  $3=用途
            if command -v "$2" >/dev/null 2>&1; then
                printf "  [OK]      %-12s %s\n" "$2" "$3"
            elif [ "$1" = req ]; then
                printf "  [MISSING] %-12s %s\n" "$2" "$3"
                missing=$((missing + 1))
            else
                printf "  [warn]    %-12s %s (任意)\n" "$2" "$3"
            fi
        }
        echo "依存コマンドをチェックします。"
        check req git        "バージョン管理"
        check req curl       "HTTP取得"
        check req rsync      "backup / エディタ設定同期"
        check req jq         "JSON処理"
        check req gh         "github / pr-gen"
        check req docker     "docker / mysql / wordpress"
        check req python3    "各種Pythonスクリプト"
        check req mise       "ツール管理"
        check opt ffmpeg     "video-gen / audio-transcribe"
        check opt ai-cli     "pr-gen / blog-gen / slide-gen"
        check opt claude     "Claude Code"
        check opt mysql      "mysql"
        check opt avahi-browse "netsec devices (mDNS探索)"
        check opt dig        "netsec conns (ASN/DNSBL判定)"
        check opt ping       "netsec devices/ports (ホスト探索)"
        check opt tcpdump    "netsec dnswin (pcapng 解析)"
        if [ -n "$WSL_DISTRO_NAME" ]; then
            check req wsl.exe "WSL連携"
            check req fstrim  "wsl-compact"
        fi
        if [ "$missing" -gt 0 ]; then
            echo -e "\n必須コマンドが ${missing} 個不足しています。"
            exit 1
        fi
        echo -e "\n必須コマンドはすべてそろっています。"
        ;;

    ## apt・mise・npm・AI CLIを一括更新
    update-all)
        step() { echo -e "\n=== $1 ==="; }
        step "apt"
        sudo apt update && sudo apt upgrade -y || echo "WARN: apt の更新に失敗しました。"
        if command -v mise >/dev/null 2>&1; then
            step "mise"
            mise upgrade || echo "WARN: mise の更新に失敗しました。"
        fi
        if command -v npm >/dev/null 2>&1; then
            step "npm (global)"
            npm update -g || echo "WARN: npm の更新に失敗しました。"
        fi
        if command -v claude >/dev/null 2>&1; then
            step "claude"
            claude update || echo "WARN: claude の更新に失敗しました。"
        fi
        echo -e "\n更新が完了しました。"
        ;;

    ## powershell.exe連携の応急処置（binfmt_misc再登録）
    wsl-interop)
        echo ':WSLInterop:M::MZ::/init:P' | sudo tee /proc/sys/fs/binfmt_misc/register
        ;;

    ## WSLのext4.vhdx肥大化対策（fstrim＋sparse VHD）
    wsl-compact)
        if [ -z "$WSL_DISTRO_NAME" ]; then
            echo "Error: WSL環境でのみ実行できます。"
            exit 1
        fi
        echo "[1/2] 未使用ブロックを解放します (fstrim)"
        sudo fstrim -av
        echo "[2/2] sparse VHD を有効化します (wsl --shutdown → wsl --manage ${WSL_DISTRO_NAME} --set-sparse true)"
        echo "※ --set-sparse は停止中のディストロにしか実行できないため、Windows側の別PowerShellで実行します。"
        echo "※ WSLが停止し、このシェルも終了します。設定は一度のみで以降は自動で縮小されます。"
        if confirm "sparse VHD を有効化しますか？"; then
            powershell.exe -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile','-Command','wsl --shutdown; wsl --manage ${WSL_DISTRO_NAME} --set-sparse true; Read-Host ''完了。Enterで閉じる'''"
        else
            echo "スキップしました。"
        fi
        ;;

    #[セキュリティ]

    ## 自宅ネットワークの簡易セキュリティ検査（引数なしで対話メニュー）
    netsec)
        "${SCRIPT_DIR}/netsec.sh" "${@:2}"
        ;;

    #[その他]

    ## このヘルプを表示
    help|--help|-h)
        usage
        ;;

    *)

        usage
        ;;
esac
