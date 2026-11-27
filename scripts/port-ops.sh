#!/bin/bash

# ==============================================================================
# 概要: 待受中（LISTEN）のポートを一覧表示し、選択したポートに対して各種操作を行う
#
# 対応環境と一覧の先頭ラベル:
#   [WSL]   WSL 内のプロセス (ss)
#   [Win]   WSL から見た Windows 側のプロセス (netstat.exe / tasklist.exe)
#   [Mac]   macOS (lsof)
#   [Linux] ネイティブ Linux (ss)
#
# 主な機能:
#   - TCP/UDP の待受ポート一覧（ポート番号の昇順）
#   - 詳細表示（プロセス情報・接続数・開いているソケット・公開中のDockerコンテナ）
#   - プロセスの終了 / 強制終了（確認プロンプト付き）
#     Win は taskkill.exe（昇格はしない。権限不足なら案内のみ）
#
# 使い方:
#   run port           一覧から選択
#   run port <ポート>  指定ポートを直接操作
#
# 前提条件:
#   - 同一ディレクトリに utils.sh (select_from_list関数・IS_MAC/IS_WSL を含む) が存在すること
#   - Linux/WSL: ss / ps、Mac: lsof / ps（docker は任意）
#   - 他ユーザー所有のプロセスは、パスワード不要の sudo が使えるときだけ一覧に出す
# ==============================================================================

UTILS_PATH="$(dirname "$0")/utils.sh"
if [[ -f "$UTILS_PATH" ]]; then
    source "$UTILS_PATH"
else
    echo "Error: utils.sh not found."
    exit 1
fi

set -euo pipefail

# --- 環境判定 -----------------------------------------------------------------

if [[ -n "${IS_MAC:-}" ]]; then
    LOCAL_LABEL="Mac"
elif [[ -n "${IS_WSL:-}" ]]; then
    LOCAL_LABEL="WSL"
else
    LOCAL_LABEL="Linux"
fi

# WSL かつ Windows 側コマンドが使えるときだけ Windows 側も対象にする
HAS_WIN=""
if [[ -n "${IS_WSL:-}" ]] && command -v netstat.exe >/dev/null 2>&1 \
    && command -v tasklist.exe >/dev/null 2>&1 && command -v taskkill.exe >/dev/null 2>&1; then
    HAS_WIN=1
fi

# パスワード不要の sudo が使えるか（他ユーザー所有のプロセス名を見るため。パスワードは要求しない）
SUDO_OK=""
if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO_OK=1
fi

# 読み取り用コマンドの実行。sudo -n が使えるときだけ sudo 付き
priv() {
    if [[ -n "$SUDO_OK" ]]; then
        sudo -n "$@"
    else
        "$@"
    fi
}

# Windows コマンドの出力（CP932・CRLF）を UTF-8 に変換する
to_utf8() {
    if command -v iconv >/dev/null 2>&1; then
        iconv -f CP932 -t UTF-8 -c 2>/dev/null
    else
        cat
    fi
}
win() { "$@" </dev/null 2>/dev/null | tr -d '\r' | to_utf8; }  # 解析用（stderr は捨てる）
winx() { "$@" </dev/null 2>&1 | tr -d '\r' | to_utf8; }        # 結果表示用（stderr も含める）

# --- 一覧収集（出力: ラベル<TAB>proto<TAB>addr<TAB>pid<TAB>名前） -----------------------

collect_ss() {
    priv ss -tulnpH 2>/dev/null | awk -v label="$LOCAL_LABEL" '
        {
            pid = "-"; name = "-"
            if (match($0, /\(\("[^"]*",pid=[0-9]+/)) {
                s = substr($0, RSTART, RLENGTH)
                name = s; sub(/^\(\("/, "", name); sub(/",pid=.*/, "", name)
                pid = s; sub(/.*pid=/, "", pid)
            }
            printf "%s\t%s\t%s\t%s\t%s\n", label, $1, $5, pid, name
        }' || true
}

collect_win() {
    [[ -n "$HAS_WIN" ]] || return 0
    # 1つ目: tasklist（PID→名前）、2つ目: netstat
    awk '
        FILENAME == ARGV[1] {
            m = split($0, f, "\",\"")
            if (m >= 2) { nm = f[1]; sub(/^"/, "", nm); nmap[f[2]] = nm }
            next
        }
        $1 == "TCP" && $4 == "LISTENING" { printf "Win\ttcp\t%s\t%s\t%s\n", $2, $5, ($5 in nmap ? nmap[$5] : "-") }
        $1 == "UDP" && NF >= 4 { printf "Win\tudp\t%s\t%s\t%s\n", $2, $4, ($4 in nmap ? nmap[$4] : "-") }
    ' <(win tasklist.exe /FO CSV /NH || true) <(win netstat.exe -ano || true) || true
}

collect_mac() {
    local proto
    for proto in tcp udp; do
        if [[ "$proto" == "tcp" ]]; then
            priv lsof -nP -iTCP -sTCP:LISTEN -F pcn 2>/dev/null || true
        else
            priv lsof -nP -iUDP -F pcn 2>/dev/null || true
        fi | awk -v proto="$proto" -v label="$LOCAL_LABEL" '
            /^p/ { pid = substr($0, 2) }
            /^c/ { cmd = substr($0, 2) }
            /^n/ {
                a = substr($0, 2)
                sub(/->.*/, "", a)
                if (a == "*:*") next
                if (a ~ /^\*:/) a = "0.0.0.0" substr(a, 2)
                printf "%s\t%s\t%s\t%s\t%s\n", label, proto, a, pid, cmd
            }' || true
    done
}

collect_all() {
    if [[ -n "${IS_MAC:-}" ]]; then
        collect_mac
    else
        collect_ss
        collect_win
    fi
}

# 「ポート<TAB>コンテナ名」の行を出力（公開ポートが無ければ空）
docker_port_map() {
    command -v docker >/dev/null 2>&1 || return 0
    docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | awk -F'\t' '
        {
            n = split($2, a, ", ")
            for (i = 1; i <= n; i++)
                if (match(a[i], /:[0-9]+->/)) print substr(a[i], RSTART + 1, RLENGTH - 3) "\t" $1
        }' || true
}

# $1=ポート。そのポートを公開しているDockerコンテナ名を出力（無ければ空）
docker_container_of_port() {
    docker_port_map | awk -F'\t' -v p="$1" '$1 == p { print $2; exit }'
}

# 待受ポート一覧を「[環境] PROTO ADDR:PORT PID 名前」の行で出力する（ポート昇順）
# 名前が取れないときは Docker コンテナ名、無ければ /etc/services のサービス名を (括弧) で補う
list_ports() {
    local dmap hint=""
    dmap=$(docker_port_map | tr '\n' ';')
    if command -v getent >/dev/null 2>&1; then hint=1; fi

    collect_all | awk -F'\t' -v dmap="$dmap" '
        BEGIN {
            n = split(dmap, ent, ";")
            for (i = 1; i <= n; i++) { split(ent[i], kv, "\t"); if (kv[1] != "") cont[kv[1]] = kv[2] }
        }
        {
            port = $3; sub(/.*:/, "", port)
            name = $5
            ln = tolower(name)
            if ((name == "-" || ln == "docker-proxy" || ln ~ /^com\.docker/) && (port in cont)) name = "(docker: " cont[port] ")"
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", port, $1, $2, $3, $4, name
        }' | sort -n -s -k1,1 | awk -F'\t' -v hint="$hint" '
        {
            name = $6
            if (name == "-" && hint != "") {
                cmd = "getent services " $1 "/" ($3 == "udp" ? "udp" : "tcp") " 2>/dev/null"
                if ((cmd | getline svc) > 0) { split(svc, f, " "); name = "(" f[1] "?)" }
                close(cmd)
            }
            printf "%-7s %-4s %-28s %-8s %s\n", "[" $2 "]", $3, $4, $5, name
        }' | awk '!s[$0]++'
}

# --- 詳細表示 -----------------------------------------------------------------

show_detail_win() {
    local port=$1 pid=$2
    echo "[接続中の数 (ESTABLISHED)]"
    win netstat.exe -ano | awk -v p="$port" '
        $1 == "TCP" && $4 == "ESTABLISHED" { n = split($2, a, ":"); if (a[n] == p) c++ }
        END { print c + 0 }' || true

    echo -e "\n[プロセス]"
    win tasklist.exe /V /FI "PID eq $pid" /FO LIST || true

    if command -v powershell.exe >/dev/null 2>&1; then
        echo -e "\n[コマンドライン]"
        powershell.exe -NoProfile -Command \
            "[Console]::OutputEncoding=[Text.Encoding]::UTF8; (Get-CimInstance Win32_Process -Filter 'ProcessId=$pid').CommandLine" \
            </dev/null 2>/dev/null | tr -d '\r' || true
    fi
}

show_detail_local() {
    local port=$1 pid=$2 container
    echo "[接続中の数 (ESTABLISHED)]"
    if [[ -n "${IS_MAC:-}" ]]; then
        priv lsof -nP -iTCP:"$port" -sTCP:ESTABLISHED 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' || true
    else
        ss -tnH state established "( sport = :$port )" 2>/dev/null | wc -l || true
    fi

    container=$(docker_container_of_port "$port")
    if [[ -n "$container" ]]; then
        echo -e "\n[公開しているDockerコンテナ]"
        echo "$container"
    fi

    if [[ "$pid" == "-" ]]; then
        echo -e "\nプロセス情報なし（他ユーザー所有、またはコンテナ経由）。"
        if [[ -n "${IS_MAC:-}" ]]; then
            echo "詳細が必要なら: sudo lsof -nP -i :$port"
        else
            echo "詳細が必要なら: sudo ss -tulnp | grep ':$port '"
        fi
        return 0
    fi

    echo -e "\n[プロセス]"
    ps -o pid,ppid,user,etime,%cpu,%mem,command -p "$pid" || echo "プロセスが既に終了しています。"
    if command -v lsof >/dev/null 2>&1; then
        echo -e "\n[開いているネットワークソケット]"
        priv lsof -nP -a -p "$pid" -i 2>/dev/null || true
    fi
}

# $1=ラベル $2=ポート $3=PID
show_detail() {
    local label=$1 port=$2 pid=$3
    echo -e "\n--- [$label] ポート $port の詳細 ---"
    if [[ "$label" == "Win" ]]; then
        show_detail_win "$port" "$pid"
    else
        show_detail_local "$port" "$pid"
    fi
}

# $1=ラベル $2=ポート。このポートへ接続中の相手（TCP のみ）を接続元アドレスごとに件数表示する
show_connections() {
    local label=$1 port=$2
    echo -e "\n--- [$label] ポート $port への接続元 (TCP ESTABLISHED) ---"
    if [[ "$label" == "Win" ]]; then
        win netstat.exe -ano | awk -v p="$port" '
            $1 == "TCP" && $4 == "ESTABLISHED" { n = split($2, a, ":"); if (a[n] == p) print $3 }' | sort | uniq -c || true
    elif [[ -n "${IS_MAC:-}" ]]; then
        priv lsof -nP -iTCP:"$port" -sTCP:ESTABLISHED 2>/dev/null | awk '
            NR > 1 { a = $9; sub(/.*->/, "", a); print a }' | sort | uniq -c || true
    else
        priv ss -tnH state established "( sport = :$port )" 2>/dev/null | awk '{ print $4 }' | sort | uniq -c || true
    fi
    echo "（列: 件数 接続元IP:ポート。空なら接続なし）"
}

# --- 終了 -----------------------------------------------------------------

# $1=ラベル $2=PID。生きていれば 0
is_alive() {
    local label=$1 pid=$2
    if [[ "$label" == "Win" ]]; then
        win tasklist.exe /FI "PID eq $pid" /FO CSV /NH | grep -q "\"$pid\""
    else
        ps -p "$pid" >/dev/null 2>&1
    fi
}

# $1=ラベル $2=ポート $3=PID $4=名前 $5=TERM|KILL
kill_process() {
    local label=$1 port=$2 pid=$3 name=$4 sig=$5 container confirm out
    local -a targs

    container=$(docker_container_of_port "$port")
    if [[ "$name" == "docker-proxy" || "$name" == "(docker:"* || -n "$container" ]]; then
        echo "⚠️  Dockerが公開しているポートです。プロセスは kill せず、コンテナを操作してください。"
        if [[ -n "$container" ]]; then echo "   docker stop $container"; fi
        return 0
    fi

    if [[ "$sig" == "KILL" ]]; then
        echo "⚠️  強制終了: クリーンアップ処理なしで即時終了します。"
    fi
    read -r -p "[$label] PID $pid ($name) を ${sig} で終了しますか？ (y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo "キャンセルしました。"
        return 0
    fi

    if [[ "$label" == "Win" ]]; then
        targs=(/PID "$pid")
        if [[ "$sig" == "KILL" ]]; then targs+=(/F); fi
        if ! out=$(winx taskkill.exe "${targs[@]}"); then
            echo "$out"
            if [[ "$out" == *"アクセス"* || "$out" == *[Aa]ccess* ]]; then
                echo "❌ 権限不足です。管理者として実行した PowerShell で次を実行してください:"
                echo "   taskkill /PID $pid /F"
            else
                echo "❌ 終了できませんでした。"
            fi
            return 1
        fi
    else
        # 権限不足（他ユーザー所有）のときだけ、確認済みの対象に限って sudo で再試行する
        if ! kill "-$sig" "$pid" 2>/dev/null; then
            echo "権限不足のため sudo で再試行します。"
            if ! sudo kill "-$sig" "$pid"; then
                echo "❌ 終了できませんでした。"
                return 1
            fi
        fi
    fi

    sleep 1
    if is_alive "$label" "$pid"; then
        echo "⚠️  まだ動作中です。強制終了 (SIGKILL) を試してください。"
    else
        echo "✅ 終了しました。"
    fi
}

# --- メニュー -----------------------------------------------------------------

# 選択したポートに対する操作メニュー。詳細表示のあとはメニューへ戻る。
# 戻り値: 0=終了操作を行った / 1=戻る・キャンセル
port_action_menu() {
    local label=$1 port=$2 pid=$3 name=$4 proto=$5 action
    local -a options

    options=("詳細を見る")
    # 接続元は TCP のみ（UDP は接続を持たない）
    if [[ "$proto" == "tcp" ]]; then
        options+=("接続元を見る")
    fi
    if [[ "$pid" != "-" ]]; then
        options+=("終了する (SIGTERM)" "強制終了する (SIGKILL)")
    fi
    options+=("戻る")

    while true; do
        echo -e "\n--- [$label] $proto ポート $port (PID: $pid, プロセス: $name) に対する操作 ---"
        action=$(select_from_list "$(printf '%s\n' "${options[@]}")" "操作を選択してください") || return 1
        case "$action" in
            "詳細を見る")             show_detail "$label" "$port" "$pid" ;;
            "接続元を見る")           show_connections "$label" "$port" ;;
            "終了する (SIGTERM)")     kill_process "$label" "$port" "$pid" "$name" TERM || true; return 0 ;;
            "強制終了する (SIGKILL)") kill_process "$label" "$port" "$pid" "$name" KILL || true; return 0 ;;
            *)                        return 1 ;;
        esac
    done
}

manage_ports() {
    local target_port="${1:-}" port_list selected label port pid name proto count

    if [[ -n "$target_port" && ! "$target_port" =~ ^[0-9]+$ ]]; then
        echo "ポート番号は数字で指定してください: $target_port"
        return 1
    fi

    while true; do
        port_list=$(list_ports)
        if [[ -n "$target_port" ]]; then
            # 同一 環境+PID（IPv4/IPv6等）は1行にまとめる
            port_list=$(echo "$port_list" | awk -v p="$target_port" '
                { a = $3; sub(/.*:/, "", a); if (a == p && !seen[$1 " " $4]++) print }')
            if [[ -z "$port_list" ]]; then
                echo "ポート $target_port は待受されていません。"
                return 0
            fi
            count=$(echo "$port_list" | wc -l | tr -d ' ')
            if [[ "$count" == "1" ]]; then
                selected="$port_list"
            else
                selected=$(select_from_list "$port_list" "操作する対象を選択してください") || {
                    echo "終了します。"
                    return 0
                }
            fi
        else
            if [[ -z "$port_list" ]]; then
                echo "待受中のポートはありません。"
                return 0
            fi
            selected=$(select_from_list "$port_list" "操作するポートを選択してください  [環境 PROTO ADDR:PORT PID 名前]") || {
                echo "終了します。"
                return 0
            }
        fi

        label=$(echo "$selected" | awk '{ l = $1; gsub(/[][]/, "", l); print l }')
        proto=$(echo "$selected" | awk '{ print $2 }')
        port=$(echo "$selected" | awk '{ a = $3; sub(/.*:/, "", a); print a }')
        pid=$(echo "$selected" | awk '{ print $4 }')
        name=$(echo "$selected" | awk '{ $1 = $2 = $3 = $4 = ""; sub(/^ +/, ""); print }')

        port_action_menu "$label" "$port" "$pid" "$name" "$proto" || true

        # 直接指定時は1回で終了。一覧選択時は操作後に一覧へ戻る。
        if [[ -n "$target_port" ]]; then
            return 0
        fi
    done
}

manage_ports "${1:-}"
