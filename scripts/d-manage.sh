#!/bin/bash

# ==============================================================================
# 概要: 実行中のDockerコンテナを一覧表示し、選択したコンテナに対して各種操作を行う
#
# 主な機能:
#   - 実行中コンテナのインタラクティブな選択
#   - シェル接続 (bash/sh 自動切り替え)
#   - ログ監視、詳細確認 (Inspect)、ファイル差分 (Diff)
#   - コンテナの再起動および削除 (確認プロンプト付き)
#
# 前提条件:
#   - 同一ディレクトリに utils.sh (select_from_list関数を含む) が存在すること
#   - Dockerがインストールされ、実行権限があること
# ==============================================================================# utils.sh が存在する場合のみ読み込む

# 外部ユーティリティの読み込み
UTILS_PATH="$(dirname "$0")/utils.sh"
if [[ -f "$UTILS_PATH" ]]; then
    source "$UTILS_PATH"
else
    echo "Error: utils.sh not found."
    exit 1
fi

set -euo pipefail

function manage_docker_containers() {
    local container_list
    local select_container
    local container
    local options
    local opt

    # 1. コンテナ情報の抽出
    container_list=$(docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}")
    if [[ -z "$container_list" ]]; then
        echo "実行中のコンテナはありません。"
        return 0
    fi

    # 2. コンテナ名を選択
    select_container=$(select_from_list "$container_list" "操作するコンテナを選択してください")

    # 選択なし（Ctrl+Cや空エンター）のハンドリング
    if [[ -z "$select_container" ]]; then
        echo "キャンセルされました。"
        return 0
    fi

    container=$(echo "$select_container" | cut -f1)
    echo -e "\n--- コンテナ: $container に対する操作 ---"

    # 3. アクションの定義
    options=(
        "コンテナに入る (bash/sh)"
        "ログを見る (Tail -f)"
        "詳細情報を見る (Inspect)"
        "差分を確認する (Diff)"
        "コンテナを再起動 (Restart)"
        "コンテナを削除 (Stop & Remove)"
        "キャンセル"
    )

    # 4. 選択メニューの表示
    PS3="アクションを選択してください (1-${#options[@]}): "

    # selectループ内でのエラーでスクリプトが落ちないよう一時的に設定を緩める
    set +e
    select opt in "${options[@]}"; do
        case "$opt" in
            "コンテナに入る (bash/sh)")
                docker exec -it "$container" /bin/bash || docker exec -it "$container" /bin/sh
                ;;
            "ログを見る (Tail -f)")
                echo "Ctrl+C で戻ります"
                docker logs -f "$container"
                ;;
            "詳細情報を見る (Inspect)")
                docker inspect "$container" --format '
==================================================
【基本情報】
コンテナID:   {{.Id}}
名前:         {{.Name}}
イメージ:     {{.Config.Image}} (ID: {{.Image}})
作成日時:     {{.Created}}
起動引数:     {{.Path}} {{range .Args}}{{.}} {{end}}

【ステータス】
状態:         {{.State.Status}}
再起動回数:   {{.RestartCount}}
{{- if index .State "Health" }}
健康状態:     {{.State.Health.Status}}
{{- end }}
開始時刻:     {{.State.StartedAt}}
終了時刻:     {{.State.FinishedAt}}

【ネットワーク】
IPアドレス:   {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}
ゲートウェイ: {{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}
MACアドレス:  {{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}
所属ネットワーク: {{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}

【ポートマッピング】
ポート設定:   {{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{range $conf}}{{.HostIp}}:{{.HostPort}}{{end}} {{end}}

【リソース制限】
メモリ制限:   {{.HostConfig.Memory}} bytes (0は無制限)
CPUシェア:    {{.HostConfig.CpuShares}}
再起動ポリシー: {{.HostConfig.RestartPolicy.Name}}

【ストレージ / マウント】
ログパス:     {{.LogPath}}
マウント一覧: {{range .Mounts}}
  - [{{.Type}}] {{.Source}}
    -> {{.Destination}} (ReadOnly: {{if .RW}}false{{else}}true{{end}}) {{end}}

【環境変数】
{{range .Config.Env}}- {{.}}
{{end}}
=================================================='

                ;;
            "差分を確認する (Diff)")
                docker diff "$container"
                ;;
            "コンテナを再起動 (Restart)")
                docker restart "$container" && echo "再起動完了。"
                ;;
            "コンテナを削除 (Stop & Remove)")
                read -p "本当に削除しますか？ (y/N): " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    echo "停止および削除中..."
                    docker stop "$container" >/dev/null && docker rm "$container" >/dev/null
                    echo "完了しました。"
                else
                    echo "キャンセルしました。"
                fi
                ;;
            "キャンセル")
                echo "中止しました。"
                ;;
            *)
                echo "無効な選択です。1から${#options[@]}の番号を入力してください。"
                continue
                ;;
        esac
        break
    done
    set -e
}

# 実行
manage_docker_containers
