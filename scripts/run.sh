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
        # 親階層の開始
        /^[[:space:]]*(docker|vscode|antigravity)\)/ { parent = $1; sub(/\).*/, "", parent); next }
        # 親階層の終了
        /^[[:space:]]*esac/ { parent = "" }
        # 説明文の保持
        /^[[:space:]]*## / { desc = $0; sub(/.*## /, "", desc); next }
        # コマンドの出力
        /^[[:space:]]*[a-zA-Z0-9_*| -]+\)/ && desc {
            cmd = $1; 
            sub(/\).*/, "", cmd);      # ")" 以降を削除
            sub(/[[:space:]]*\|.*/, "", cmd); # "|" があればそれ以降（*)など）を削除
            
            full = (parent && cmd != parent && cmd !~ /help/) ? parent " " cmd : cmd
            printf "  %-25s %s\n", full, desc
            desc = ""
        }
    ' "$0"
}

case "${1}" in

    ## PR用の説明文を自動生成します。
    gen-pr)
        "${SCRIPT_DIR}/gen-pr.sh"
        ;;

    ## Github用のREADME.mdを自動生成します。
    gen-readme)
        "${SCRIPT_DIR}/gen-readme.sh"
        ;;

    ## Github PRを選択して操作(ブラウザで開く、チェックアウト、マージ、AIレビュー)
    github)
        "${SCRIPT_DIR}/ghs.sh" "${@:2}"
        ;;
    
    ## Dockerの管理を行います。
    docker)
        case "${2}" in
       
            ## 未使用のリソースを表示し、確認後に削除します。
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
      
            ## Dockerコンテナに関する各種操作を行います。
            container | *)
                "${SCRIPT_DIR}/d-manage.sh"
                ;;
        esac
        ;;

    ## MySQLデータベースに関する各種操作を行います。
    mysql)
        "${SCRIPT_DIR}/mysql-ops.sh" "${@:2}"
        ;;

    ## マークダウン形式で記事を生成します。
    gen-blog)
        "${SCRIPT_DIR}/gen-blog.sh" "${@:2}"
        ;;

    ## ブログ記事のアイキャッチ画像を生成します。
    gen-blog-thumbnail)
        "${SCRIPT_DIR}/gen-blog-thumbnail.sh" "${@:2}"
        ;;

    ## Marpスライドやプレゼン原稿を自動生成・変換します。
    gen-marp)
        "${SCRIPT_DIR}/gen-marp.sh" "${@:2}"
        ;;

    ## マークダウンから音声ファイルを生成します。
    gen-voice)
        "${SCRIPT_DIR}/gen-voice.sh"
        ;;

    ## 音声ファイルの文字起こしをします。
    audio-transcribe)
        "${SCRIPT_DIR}/file-task.sh" -t=transcribe "${@:2}"
        ;;

    ## PDFと音声ファイルを組み合わせて動画を生成します。
    gen-video)
        "${SCRIPT_DIR}/gen-video.sh"
        ;;

    ## WordPressの管理を行います。
    wordpress)
        "${SCRIPT_DIR}/wordpress.sh" "${@:2}"
        ;;

    ## Webページを画像ファイルに変換します。
    web-screenshot)
        "${SCRIPT_DIR}/web_screenshot.py" "${@:2}"
        ;;

    ## 画像ファイルをPDFに変換します。
    images-to-pdf)
        "${SCRIPT_DIR}/images_to_pdf.py" "${@:2}"
        ;;

    ## PDFファイルを画像ファイルに変換します。
    pdf-to-images)
        "${SCRIPT_DIR}/pdf_to_images.py" "${@:2}"
        ;;

    ## 不要なメタデータファイル（Zone.Identifierと.DS_Store）を一括削除します。
    cleanup)
        target="${2:-.}"
        [ ! -d "$target" ] && echo "Error: $target not found." && return 1
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

    ## CRLFファイルを検索後、確認してからLFに変換します。
    find-crlf)
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

    vscode)
        case "${2}" in
          
            ## VSCodeの設定ファイルをバックアップします。
            backup)
                pushd "${BASE_DIR}/editors/VSCode"
                ./rsync.sh pull
                popd
                ;;

            ## VSCodeの設定ファイルをリストアします。
            restore)
                pushd "${BASE_DIR}/editors/VSCode"
                ./rsync.sh push
                popd
                ;;
        esac
        ;;

    antigravity)
        case "${2}" in
          
            ## Antigravityの設定ファイルをバックアップします。
            backup)
                pushd "${BASE_DIR}/editors/Antigravity"
                ./rsync.sh pull
                popd
                ;;

            ## Antigravityの設定ファイルをリストアします。
            restore)
                pushd "${BASE_DIR}/editors/Antigravity"
                ./rsync.sh push
                popd
                ;;
        esac
        ;;

    ## ヘルプを表示します。
    help|--help|-h)
        usage
        ;;

    *)
        usage
        ;;
esac
