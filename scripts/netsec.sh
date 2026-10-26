#!/bin/bash

# ==============================================================================
# 概要: 自宅ネットワークの簡易セキュリティ検査を対話メニューで実行する
#
# 主な機能:
#   - 検査項目（devices/ports/conns/arp/upnp/audit/dnswin/capture/external）の選択
#   - 各項目ごとのオプションをサブメニューで選択
#   - 引数付きで呼ばれた場合は netsec.py へ素通し（非対話）
#
# 前提条件:
#   - 同一ディレクトリに netsec.py / utils.sh が存在すること
# ==============================================================================

UTILS_PATH="$(dirname "$0")/utils.sh"
if [[ -f "$UTILS_PATH" ]]; then
    source "$UTILS_PATH"
else
    echo "Error: utils.sh not found."
    exit 1
fi

set -u

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
NETSEC="${SCRIPT_DIR}/netsec.py"

# 検査を実行して区切りを出す
exec_netsec() {
    echo
    "$NETSEC" "$@"
    local rc=$?
    echo
    return $rc
}

# 選択メニュー。選択されたラベルを出力し、キャンセル時は 1 を返す
menu() {
    local title="$1"
    shift
    select_from_list "$(printf '%s\n' "$@")" "$title"
}

# --- 各項目のサブメニュー（選択されたら 0、戻るなら 1） ---------------------

level_devices() {
    local sel
    sel=$(menu "devices: オプションを選択" \
        "実行（前回との差分を表示）" \
        "実行 + --deep（Mac/iOS の判定を30秒待つ）" \
        "--no-probe（端末種別の推定なし・高速）" \
        "--no-vendor（MACベンダーのオンライン照会なし）" \
        "--json（JSON出力）" \
        "戻る") || return 1
    case "$sel" in
        "実行 + --deep"*) exec_netsec devices --deep ;;
        "実行"*)        exec_netsec devices ;;
        "--no-probe"*)  exec_netsec devices --no-probe ;;
        "--no-vendor"*) exec_netsec devices --no-vendor ;;
        "--json"*)      exec_netsec devices --json ;;
        "戻る")         return 1 ;;
    esac
}

level_ports() {
    local sel
    sel=$(menu "ports: オプションを選択" \
        "実行（既定: 1ポート0.4秒待ち）" \
        "--timeout 0.2（高速・取りこぼし増）" \
        "--timeout 1.0（低速・確実）" \
        "--json（JSON出力）" \
        "戻る") || return 1
    case "$sel" in
        "実行"*)         exec_netsec ports ;;
        "--timeout 0.2"*) exec_netsec ports --timeout 0.2 ;;
        "--timeout 1.0"*) exec_netsec ports --timeout 1.0 ;;
        "--json"*)       exec_netsec ports --json ;;
        "戻る")          return 1 ;;
    esac
}

level_conns() {
    local sel
    sel=$(menu "conns: オプションを選択" \
        "実行（ASN/国/PTR/DNSBL 判定）" \
        "--json（JSON出力）" \
        "戻る") || return 1
    case "$sel" in
        "実行"*)   exec_netsec conns ;;
        "--json"*) exec_netsec conns --json ;;
        "戻る")    return 1 ;;
    esac
}

level_arp() {
    local sel
    sel=$(menu "arp: オプションを選択" \
        "実行（前回のGW MACと比較）" \
        "--no-save（ベースラインを更新しない）" \
        "--json（JSON出力）" \
        "戻る") || return 1
    case "$sel" in
        "実行"*)     exec_netsec arp ;;
        "--no-save"*) exec_netsec arp --no-save ;;
        "--json"*)   exec_netsec arp --json ;;
        "戻る")      return 1 ;;
    esac
}

level_upnp() {
    local sel
    sel=$(menu "upnp: オプションを選択" \
        "実行（SSDP待ち3秒）" \
        "--timeout 8（応答が遅いルーター向け）" \
        "--json（JSON出力）" \
        "戻る") || return 1
    case "$sel" in
        "実行"*)      exec_netsec upnp ;;
        "--timeout 8"*) exec_netsec upnp --timeout 8 ;;
        "--json"*)    exec_netsec upnp --json ;;
        "戻る")       return 1 ;;
    esac
}

level_audit() {
    local sel out default_out
    sel=$(menu "audit: 出力方法を選択" \
        "ファイルに出力（日付入りの既定名）" \
        "出力先を指定する" \
        "標準出力に表示" \
        "戻る") || return 1

    default_out="${HOME}/net-audit-$(date +%Y%m%d).md"
    case "$sel" in
        "ファイルに出力"*)
            exec_netsec audit --out "$default_out"
            ;;
        "出力先を指定"*)
            read -r -p "出力先 [${default_out}]: " out
            out="${out:-$default_out}"
            out="${out/#\~/$HOME}"
            exec_netsec audit --out "$out"
            ;;
        "標準出力"*)
            exec_netsec audit
            ;;
        "戻る")
            return 1
            ;;
    esac
}

level_dnswin() {
    local sel secs
    sel=$(menu "dnswin: 傍受時間を選択（Windows pktmon・UAC承認要）" \
        "30秒（既定）" \
        "10秒" \
        "60秒" \
        "戻る") || return 1
    case "$sel" in
        "30秒"*) secs=30 ;;
        "10秒"*) secs=10 ;;
        "60秒"*) secs=60 ;;
        "戻る")   return 1 ;;
    esac
    exec_netsec dnswin --seconds "$secs"
}

level_capture() {
    local sel ip port
    sel=$(menu "capture: 取得方法を選択（Windows pktmon・UAC承認要）" \
        "30秒（要約のみ）" \
        "30秒 + サイト一覧（DNS/SNI）" \
        "30秒 + Wiresharkで開く" \
        "10秒（要約のみ）" \
        "60秒（要約のみ）" \
        "60秒 + サイト一覧（DNS/SNI）" \
        "対象IPを指定して30秒" \
        "対象IP+ポートを指定して30秒" \
        "既存の pcapng を要約（取得しない）" \
        "戻る") || return 1
    case "$sel" in
        "30秒（要約のみ）"*)  exec_netsec capture --seconds 30 --pkt-size 128 ;;
        "30秒 + サイト"*)     exec_netsec capture --seconds 30 --pkt-size 128 --sites ;;
        "30秒 + Wireshark"*)  exec_netsec capture --seconds 30 --open ;;
        "10秒"*)              exec_netsec capture --seconds 10 --pkt-size 128 ;;
        "60秒（要約のみ）"*)  exec_netsec capture --seconds 60 --pkt-size 128 ;;
        "60秒 + サイト"*)     exec_netsec capture --seconds 60 --pkt-size 128 --sites ;;
        "既存の pcapng"*)
            read -r -p "pcapng のパス: " p
            [[ -z "$p" ]] && return 1
            p="${p/#\~/$HOME}"
            exec_netsec capture --read "$p"
            ;;
        "対象IPを指定"*)
            read -r -p "対象IP (例: 192.168.10.116): " ip
            [[ -z "$ip" ]] && return 1
            exec_netsec capture --seconds 30 --ip "$ip" --open
            ;;
        "対象IP+ポート"*)
            read -r -p "対象IP: " ip
            read -r -p "対象ポート (例: 443): " port
            [[ -z "$ip" || -z "$port" ]] && return 1
            exec_netsec capture --seconds 30 --ip "$ip" --port "$port" --open
            ;;
        "戻る")   return 1 ;;
    esac
}

level_external() {
    local sel
    sel=$(menu "external: 実行方法を選択" \
        "実行（第三者スキャンDBを参照）" \
        "戻る") || return 1
    case "$sel" in
        "実行"*) exec_netsec external ;;
        "戻る")  return 1 ;;
    esac
}

# --- メインメニュー（検査後はメインメニューへ戻る） ------------------------

main_menu() {
    local sel
    while true; do
        sel=$(menu "検査項目を選択" \
            "devices  LAN接続デバイス一覧・新規デバイス差分" \
            "ports    LAN内機器の危険ポート露出検査" \
            "conns    外向き通信と宛先の評判判定" \
            "arp      ARP異常（スプーフィング兆候）検知" \
            "upnp     UPnP(IGD)の外部公開ポート確認" \
            "audit    全項目を一括実行してレポート" \
            "dnswin   Windows側pktmonでDNS取得（UAC承認要）" \
            "capture  Windows側pktmonでパケット取得・要約（UAC承認要）" \
            "external 外から見えるポート（第三者スキャンDB）" \
            "終了") || return 0

        case "$sel" in
            devices*) level_devices ;;
            ports*)   level_ports ;;
            conns*)   level_conns ;;
            arp*)     level_arp ;;
            upnp*)    level_upnp ;;
            audit*)   level_audit ;;
            dnswin*)  level_dnswin ;;
            capture*) level_capture ;;
            external*) level_external ;;
            終了)     return 0 ;;
        esac
    done
}

# --- エントリポイント --------------------------------------------------------

# 引数あり = 非対話（run netsec devices / run netsec audit --out FILE など）
if [[ $# -gt 0 ]]; then
    exec "$NETSEC" "$@"
fi

# パイプ等の非TTYでは自動実行せずヘルプを出す
if [[ ! -t 0 ]]; then
    "$NETSEC" --help
    exit $?
fi

main_menu
