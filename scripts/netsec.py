#!/usr/bin/env python3
"""自宅ネットワークの簡易セキュリティ検査ツール（手動実行・root 不要）。

サブコマンド:
  devices  LAN 接続デバイス一覧・種別推定・新規デバイス差分
  ports    LAN 内機器の危険ポート露出検査
  conns    外向き通信の一覧と宛先の評判判定
  arp      ARP テーブル異常（スプーフィング兆候）検知
  upnp     UPnP(IGD) の検出と外部公開ポート確認
  audit    上記を一括実行して Markdown レポートを出力
  dnswin   Windows 側 pktmon で DNS を取得（dnsTunneling 有効時の代替・UAC 承認要）
  capture  Windows 側 pktmon でパケットを取得し pcapng 保存・要約（UAC 承認要）
  external 第三者スキャンDB から「外から見えるポート」を確認

制約:
  - dnswin / capture 以外はパケット傍受を行わない（root 不要）。
  - 常時監視はしない。検査できるのは実行した瞬間の状態のみ。
"""
import argparse
import concurrent.futures
import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

VERSION = "1.0"

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "netsec"
BASELINE_PATH = CACHE_DIR / "baseline.json"
OUI_CACHE_PATH = CACHE_DIR / "oui.json"
DNS_SEEN_PATH = CACHE_DIR / "dns-seen.json"

# LAN 内で露出していると危険なポート（port: (名称, 重要度)）
RISKY_PORTS = {
    21: ("FTP", "high"),
    22: ("SSH", "medium"),
    23: ("Telnet", "critical"),
    139: ("NetBIOS", "high"),
    445: ("SMB", "critical"),
    554: ("RTSP", "medium"),
    1883: ("MQTT", "high"),
    2375: ("Docker API", "critical"),
    3306: ("MySQL", "high"),
    3389: ("RDP", "critical"),
    5000: ("HTTP-alt(UPnP等)", "low"),
    5432: ("PostgreSQL", "high"),
    5900: ("VNC", "high"),
    6379: ("Redis", "high"),
    7547: ("TR-069", "high"),
    8080: ("HTTP-alt", "medium"),
    8554: ("RTSP-alt", "medium"),
    9200: ("Elasticsearch", "high"),
    27017: ("MongoDB", "high"),
}

SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
SEVERITY_LABEL = {
    "critical": "重大",
    "high": "高",
    "medium": "中",
    "low": "低",
    "info": "情報",
}

# ホスト探索の ICMP 不応答時の TCP フォールバック
PROBE_PORTS = (80, 443, 22, 445, 62078, 8080)

OUI_FILES = (
    "/usr/share/ieee-data/oui.txt",
    "/usr/share/misc/oui.txt",
    "/var/lib/ieee-data/oui.txt",
    "/usr/share/nmap/nmap-mac-prefixes",
)

# 同一プロセス内でのホスト探索結果キャッシュ（netsec audit の二重スキャン防止）
_SCAN_CACHE = {}


# ---------------------------------------------------------------- 汎用


def info(msg):
    print(msg, file=sys.stderr, flush=True)


def sh(cmd, timeout=10):
    """コマンドを実行して標準出力を返す（失敗時は空文字）。"""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def dig(args, timeout=5):
    """dig +short の結果を返す。"""
    return sh(["dig", "+time=2", "+tries=1", "+short"] + args, timeout=timeout).strip()


def disp_width(text):
    """全角を 2 桁として数えた表示幅。"""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def clip_disp(text, width):
    """表示幅 width に収まるよう切り詰める（超過分は … に置換）。"""
    if disp_width(text) <= width:
        return text
    out, used = "", 0
    for c in text:
        w = 2 if unicodedata.east_asian_width(c) in "WF" else 1
        if used + w > width - 1:
            break
        out += c
        used += w
    return out + "…"


def pad_disp(text, width):
    """表示幅で右詰めパディングする。"""
    text = clip_disp(text, width)
    return text + " " * (width - disp_width(text))


def ip_sort_key(ip):
    """IPv4 を先に、数値順で並べるためのキー。"""
    if ":" in ip:
        return (1, 0)
    try:
        return (0, int(ipaddress.ip_address(ip)))
    except ValueError:
        return (2, 0)


def is_private(ip):
    try:
        return ipaddress.ip_address(ip).is_private
    except ValueError:
        return True


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


# ---------------------------------------------------------------- ネットワーク特定


def resolve_network(cidr=None):
    """検査対象のネットワークとインターフェースを決める。"""
    if cidr:
        return None, ipaddress.ip_network(cidr, strict=False)

    candidates = []
    for line in sh(["ip", "-4", "-o", "addr", "show", "scope", "global"]).splitlines():
        parts = line.split()
        if len(parts) < 4 or "inet" not in parts:
            continue
        iface = parts[1].rstrip(":")
        try:
            cidr_str = parts[parts.index("inet") + 1]
        except (IndexError, ValueError):
            continue
        if iface.startswith(("docker", "br-", "veth", "virbr", "tun", "tap", "zt")):
            continue
        candidates.append((iface, cidr_str))

    if not candidates:
        raise SystemExit("ネットワークを特定できませんでした。--cidr で指定してください。")

    default_dev = None
    for line in sh(["ip", "route", "show", "default"]).splitlines():
        m = re.search(r"\bdev\s+(\S+)", line)
        if m:
            default_dev = m.group(1)
            break

    for iface, cidr_str in candidates:
        if iface == default_dev:
            return iface, ipaddress.ip_network(cidr_str, strict=False)
    iface, cidr_str = candidates[0]
    return iface, ipaddress.ip_network(cidr_str, strict=False)


def default_gateway():
    """デフォルトゲートウェイの (IP, iface) を返す。"""
    for line in sh(["ip", "route", "show", "default"]).splitlines():
        m = re.search(r"\bvia\s+(\S+)", line)
        if not m:
            continue
        dev = re.search(r"\bdev\s+(\S+)", line)
        return m.group(1), (dev.group(1) if dev else None)
    return None, None


# ---------------------------------------------------------------- 近隣テーブル


def read_neigh():
    """ip neigh の結果を {ip: {"mac":..., "state":...}} で返す。"""
    result = {}
    for line in sh(["ip", "neigh", "show"]).splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        ip = parts[0]
        mac = None
        if "lladdr" in parts:
            try:
                mac = parts[parts.index("lladdr") + 1].lower()
            except IndexError:
                mac = None
        state = parts[-1].upper()
        if state in ("FAILED", "INCOMPLETE"):
            continue
        if ip.startswith("fe80::"):
            continue
        result[ip] = {"mac": mac, "state": state}
    return result


def own_ipv4_addresses():
    ips = set()
    for line in sh(["ip", "-4", "-o", "addr", "show"]).splitlines():
        m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", line)
        if m:
            ips.add(m.group(1))
    return ips


def ignored_networks():
    """Docker 等のローカルブリッジ（近隣テーブルのノイズ）を返す。"""
    nets = [ipaddress.ip_network("169.254.0.0/16")]
    for line in sh(["ip", "-4", "-o", "addr", "show"]).splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        iface = parts[1].rstrip(":")
        if not iface.startswith(("docker", "br-", "veth", "virbr")):
            continue
        m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+/\d+)", line)
        if m:
            nets.append(ipaddress.ip_network(m.group(1), strict=False))
    return nets


def proc_name(value):
    """'users:(("ssh",pid=1,fd=3))' から実行ファイル名を抜く。"""
    m = re.search(r'users:\(\("([^"]+)"', value)
    return m.group(1) if m else ""


def is_local_mac(mac):
    """ローカル管理 MAC（ランダム化/仮想）かどうか。"""
    try:
        return bool(int(mac.split(":")[0], 16) & 0x02)
    except (ValueError, IndexError, AttributeError):
        return False


# ---------------------------------------------------------------- ホスト探索


def ping(ip, wait=1):
    try:
        return subprocess.run(
            ["ping", "-c", "1", "-W", str(wait), "-n", str(ip)],
            capture_output=True,
            timeout=wait + 3,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def tcp_open(ip, port, timeout=0.4):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            return s.connect_ex((str(ip), port)) == 0
    except OSError:
        return False


def discover_host(ip):
    ip = str(ip)
    if ping(ip):
        return ip, "icmp"
    for port in PROBE_PORTS:
        if tcp_open(ip, port):
            return ip, "tcp/%d" % port
    return ip, None


def scan_hosts(network, workers=64):
    """ICMP + TCP で応答するホストを探す。=> {ip: 検出方法}

    同一プロセス内（netsec audit）で複数回呼ばれた場合は結果を使い回す。
    """
    key = str(network)
    if key in _SCAN_CACHE:
        return _SCAN_CACHE[key]
    hosts = [str(h) for h in network.hosts()]
    found = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for ip, method in ex.map(discover_host, hosts):
            if method:
                found[ip] = method
    _SCAN_CACHE[key] = found
    return found


def known_hosts(network):
    """応答ホスト + 近隣テーブル上のアドレス（ICMP 不応答機器の取りこぼし対策）。"""
    found = scan_hosts(network)
    for ip in read_neigh():
        try:
            addr = ipaddress.ip_address(ip)
        except ValueError:
            continue
        if addr.version == 4 and addr in network:
            found.setdefault(ip, "neigh")
    return found


# ---------------------------------------------------------------- mDNS / SSDP


def mdns_lookup(timeout=6):
    """avahi-browse で mDNS のホスト名を引く。=> {ip: 名前}"""
    try:
        proc = subprocess.Popen(
            ["avahi-browse", "-artp"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return {}
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, _ = proc.communicate()

    names = {}
    for line in out.splitlines():
        if not line.startswith("="):
            continue
        fields = line.split(";")
        if len(fields) < 9:
            continue
        name, ftype, host, address = fields[3], fields[4], fields[6], fields[7]
        if ":" in address:
            continue
        # _device-info 等より、サービス名の付いたレコードを優先
        label = host.rstrip(".") if host else name
        if address not in names or ftype in ("_http._tcp", "_smb._tcp", "_airplay._tcp"):
            names[address] = label
    return names


def ssdp_discover(st="ssdp:all", timeout=3):
    """SSDP で応答する機器を集める。=> [{ip, server, location, st, usn}]"""
    msg = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        "ST: %s\r\n\r\n" % st
    ).encode()
    results = []
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    except OSError:
        return results
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(0.5)
        sock.sendto(msg, ("239.255.255.250", 1900))
        deadline = time.time() + timeout
        seen = set()
        while time.time() < deadline:
            try:
                data, addr = sock.recvfrom(65507)
            except socket.timeout:
                continue
            except OSError:
                break
            text = data.decode("utf-8", "replace")
            key = (addr[0], text[:200])
            if key in seen:
                continue
            seen.add(key)
            headers = {}
            for line in text.split("\r\n")[1:]:
                if ":" in line:
                    k, _, v = line.partition(":")
                    headers[k.strip().upper()] = v.strip()
            results.append(
                {
                    "ip": addr[0],
                    "server": headers.get("SERVER", ""),
                    "location": headers.get("LOCATION", ""),
                    "st": headers.get("ST", ""),
                    "usn": headers.get("USN", ""),
                }
            )
    finally:
        sock.close()
    return results


# ---------------------------------------------------------------- OUI（ベンダー）


def load_local_oui():
    table = {}
    for path in OUI_FILES:
        p = Path(path)
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            m = re.match(r"^([0-9A-Fa-f]{2}-[0-9A-Fa-f]{2}-[0-9A-Fa-f]{2})\s+\(hex\)\s+(.+)$", line)
            if m:
                table[m.group(1).replace("-", "").upper()] = m.group(2).strip()
                continue
            m = re.match(r"^([0-9A-Fa-f]{6})\s+(.+)$", line)
            if m:
                table[m.group(1).upper()] = m.group(2).strip()
    return table


class VendorResolver:
    """MAC からベンダー名を引く（ローカルDB → オンラインAPI → キャッシュ）。"""

    API = "https://api.macvendors.com/"
    MAX_ONLINE = 15

    def __init__(self, online=True):
        self.local = load_local_oui()
        self.cache = load_json(OUI_CACHE_PATH, {})
        self.online = online
        self.online_used = 0
        self.dirty = False

    def resolve(self, mac):
        if not mac:
            return ""
        oui = mac.replace(":", "").replace("-", "").upper()[:6]
        if len(oui) < 6:
            return ""
        if oui in self.local:
            return self.local[oui]
        if oui in self.cache:
            return self.cache[oui]
        if self.online and self.online_used < self.MAX_ONLINE:
            self.online_used += 1
            name = self._fetch(oui)
            if name:
                self.cache[oui] = name
                self.dirty = True
            else:
                self.cache[oui] = ""
                self.dirty = True
            return name
        return ""

    def _fetch(self, oui):
        mac = ":".join(oui[i : i + 2] for i in range(0, 6, 2))
        try:
            req = urllib.request.Request(self.API + mac, headers={"User-Agent": "netsec/" + VERSION})
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.read().decode("utf-8", "replace").strip()
        except Exception:
            return ""
        finally:
            time.sleep(1.1)  # macvendors.com のレート制限対策

    def save(self):
        if self.dirty:
            save_json(OUI_CACHE_PATH, self.cache)


# ---------------------------------------------------------------- baseline


def load_baseline():
    return load_json(BASELINE_PATH, {"version": 1, "devices": {}, "gateway": {}})


def save_baseline(data):
    data["updated"] = now_iso()
    save_json(BASELINE_PATH, data)


# ---------------------------------------------------------------- ss 解析


def split_addr(value):
    """'192.168.10.1:443' / '[::1]:80' / '192.168.10.114%eth1:68' を (host, port) に。"""
    value = value.split("%")[0]
    if value.startswith("["):
        host, _, port = value.rpartition("]:")
        host = host[1:]
    else:
        host, _, port = value.rpartition(":")
    return host, int(port) if port.isdigit() else 0


def read_ss(listen=False):
    """ss の結果を [{netid, state, local, peer, process}] で返す。"""
    cmd = ["ss", "-lntup" if listen else "-tunap"]
    rows = []
    for line in sh(cmd, timeout=15).splitlines()[1:]:
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            local = split_addr(parts[4])
            peer = split_addr(parts[5]) if len(parts) > 5 else ("", 0)
        except (IndexError, ValueError):
            continue
        rows.append(
            {
                "netid": parts[0],
                "state": parts[1],
                "local": local,
                "peer": peer,
                "process": " ".join(parts[6:]) if len(parts) > 6 else "",
            }
        )
    return rows


# ---------------------------------------------------------------- 評判判定


def ptr_name(ip):
    out = dig(["-x", ip])
    return out.splitlines()[0].rstrip(".") if out else ""


def asn_info(ip):
    """Team Cymru の DNS で ASN と国コードを引く。=> (asn, cc)"""
    if ":" in ip:
        return "", ""
    rev = ".".join(reversed(ip.split(".")))
    out = dig(["TXT", rev + ".origin.asn.cymru.com"])
    if not out:
        return "", ""
    fields = [f.strip() for f in out.strip('"').split("|")]
    asn = fields[0].split()[0] if fields and fields[0] else ""
    cc = fields[2] if len(fields) > 2 else ""
    return asn, cc


def dnsbl_check(ip):
    """Spamhaus DNSBL で既知の悪性IPか判定する。"""
    if ":" in ip:
        return []
    rev = ".".join(reversed(ip.split(".")))
    out = dig(["A", rev + ".zen.spamhaus.org"])
    codes = [line for line in out.splitlines() if line.startswith("127.")]
    if any(c.startswith("127.255.255") for c in codes):
        return ["判定不可(DNSリゾルバ制限)"]
    return codes


def enrich_ip(ip):
    asn, cc = asn_info(ip)
    return {
        "ip": ip,
        "ptr": ptr_name(ip),
        "asn": asn,
        "cc": cc,
        "dnsbl": dnsbl_check(ip),
    }


# ---------------------------------------------------------------- devices


# 端末種別の推定に使うポート（開いていれば手掛かりになる）
DEVICE_HINT_PORTS = (22, 88, 135, 445, 548, 3389, 5000, 5900, 7000, 3283, 62078, 9100)
# macOS の共有系（iPhone/iPad は開けない）。1つでも開いていれば Mac と判断できる
MAC_SHARING_PORTS = (88, 445, 548, 5900, 3283)


def probe_hint_ports(ips, timeout=0.3, workers=16, retry_timeout=1.0):
    """各 IP で開いているヒントポートの集合を返す（並列）。

    iOS はアイドル時に SYN を落とすことがあるため、未検出の組だけ長めの
    タイムアウトで 2 巡目を行う。これを省くと iPhone/iPad の判定が不安定になる。
    """
    ips = list(ips)
    result = {ip: set() for ip in ips}

    def sweep(wait, label):
        jobs = [
            (ip, port) for ip in ips for port in DEVICE_HINT_PORTS if port not in result[ip]
        ]
        if not jobs:
            return
        info("  %s（%d 組）" % (label, len(jobs)))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(tcp_open, ip, port, wait): (ip, port) for ip, port in jobs}
            for fut in concurrent.futures.as_completed(futs):
                ip, port = futs[fut]
                if fut.result():
                    result[ip].add(port)

    sweep(timeout, "1巡目")
    sweep(retry_timeout, "2巡目（未検出分の再試行）")
    return result


def guess_device_type(mac, vendor, host, ports, notes):
    """OUI・ホスト名・開いているポートから端末種別を推測する（断定ではない）。"""
    v = (vendor or "").lower()
    h = (host or "").lower()
    if not mac and not host:
        return ""
    # iOS のペアリングポート。macOS は開けないので最も確実な判別材料
    if 62078 in ports:
        return "iPhone/iPad"
    if 3389 in ports or (135 in ports and 445 in ports):
        return "Windows"
    if 9100 in ports:
        return "プリンタ"
    if "nintendo" in v:
        return "ゲーム機(Nintendo)"
    if "espressif" in v:
        return "IoT(ESP32)"
    if "firestick" in h:
        return "Fire TV"
    if "amazon" in v:
        return "Amazon機器(Echo等)"
    if "tp-link" in v:
        return "ルーター/AP(TP-Link)"
    if "nec platforms" in v:
        return "ルーター(NEC/Aterm)"
    if "toshiba" in v:
        return "TV/家電(Toshiba)"
    if "apple" in v:
        return "Mac" if any(p in ports for p in MAC_SHARING_PORTS) else "Mac候補(62078閉)"
    if 22 in ports or 5900 in ports:
        return "Linux/サーバ"
    if "ルーター(IGD)" in notes:
        return "ルーター"
    if is_local_mac(mac):
        return "種類不明(ランダムMAC)"
    return ""


def poll_ios_port(ips, seconds=30, interval=2.0, port=62078):
    """62078 を一定時間ポーリングし、開いた瞬間を捉えた IP を返す。

    iOS はスリープ中に 62078 を閉じるため、1 回のスキャンでは Mac と区別できない。
    起床を待つことで iPhone/iPad を確定させる。
    """
    found = set()
    deadline = time.time() + seconds
    while time.time() < deadline:
        todo = [ip for ip in ips if ip not in found]
        if not todo:
            break
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(todo)) as ex:
            futs = {ex.submit(tcp_open, ip, port, 1.0): ip for ip in todo}
            for fut in concurrent.futures.as_completed(futs):
                if fut.result():
                    found.add(futs[fut])
        if len(found) == len(ips):
            break
        time.sleep(interval)
    return found


def cmd_devices(args):
    iface, network = resolve_network(args.cidr)
    info("対象ネットワーク: %s (iface=%s)" % (network, iface or "-"))
    info("ホスト探索中... (約10〜20秒)")
    alive = known_hosts(network)
    info("  %d 台が応答" % len(alive))

    neigh = read_neigh()
    info("mDNS 探索中...")
    mdns = {} if args.no_mdns else mdns_lookup()
    info("SSDP 探索中...")
    ssdp = {} if args.no_ssdp else ssdp_discover()
    ssdp_by_ip = defaultdict(list)
    for entry in ssdp:
        ssdp_by_ip[entry["ip"]].append(entry)

    vendor = VendorResolver(online=not args.no_vendor)
    baseline = load_baseline()
    known = baseline.get("devices", {})
    own_ips = own_ipv4_addresses()

    ips = set(alive) | set(neigh) | set(mdns) | set(ssdp_by_ip)
    if args.no_probe:
        hint_ports = {}
    else:
        info("端末種別を推定中...（ポート 8 個 × %d 台）" % len(ips))
        hint_ports = probe_hint_ports(sorted(ips))
    entries = []
    new_devices = []
    seen_keys = set()
    key_of = {}

    for ip in sorted(ips, key=ip_sort_key):
        if ipaddress.ip_address(ip) not in network:
            continue
        mac = (neigh.get(ip) or {}).get("mac") or ""
        random_mac = bool(mac) and is_local_mac(mac)
        # ランダムMACは接続のたびに変わるため、同一性は IP で追う
        key = "ip:" + ip if (not mac or random_mac) else mac
        host = mdns.get(ip, "")
        vendor_name = vendor.resolve(mac) if mac else ""
        if not vendor_name and is_local_mac(mac):
            vendor_name = "ランダムMAC(仮想)"

        notes = []
        is_new = key not in known
        if is_new:
            notes.append("新規")
            new_devices.append(ip)
        elif known[key].get("ip") and known[key]["ip"] != ip:
            notes.append("IP変更(旧%s)" % known[key]["ip"])
        for entry in ssdp_by_ip.get(ip, []):
            if "InternetGatewayDevice" in entry.get("st", ""):
                notes.append("ルーター(IGD)")
                break
        if ip in own_ips:
            notes.append("自ホスト")
        seen_keys.add(key)

        if ip in own_ips:
            kind = "このPC(WSL)"
        else:
            kind = guess_device_type(
                mac, vendor_name, host, hint_ports.get(ip, set()), notes
            )

        # 62078 は iOS がスリープで閉じるため、過去に開いていた実績を基準に残す
        ios_now = 62078 in hint_ports.get(ip, set())
        ios_mem = bool(known.get(key, {}).get("ios_seen"))
        if ios_now:
            kind = "iPhone/iPad"
        elif ios_mem and (kind.startswith("Mac候補") or kind.startswith("種類不明")):
            kind = "iPhone/iPad(過去検出)"

        entries.append(
            {
                "ip": ip,
                "mac": mac,
                "host": host,
                "vendor": vendor_name,
                "type": kind,
                "notes": notes,
                "method": alive.get(ip, ""),
            }
        )
        known[key] = {
            "ip": ip,
            "mac": mac,
            "host": host or known.get(key, {}).get("host", ""),
            "first_seen": known.get(key, {}).get("first_seen", now_iso()),
            "last_seen": now_iso(),
            "ios_seen": ios_now or ios_mem,
        }
        key_of[ip] = key

    if args.deep:
        candidates = [
            e
            for e in entries
            if e["type"].startswith("Mac候補") or e["type"].startswith("種類不明")
        ]
        if candidates:
            secs = int(args.deep) if args.deep else 30
            info(
                "iOS の起床待ち: %d 台の 62078 を %d 秒ポーリング" % (len(candidates), secs)
            )
            found = poll_ios_port([e["ip"] for e in candidates], seconds=secs)
            for e in candidates:
                if e["ip"] in found:
                    e["type"] = "iPhone/iPad"
                    e["notes"].append("62078検出")
                    key = key_of.get(e["ip"])
                    if key in known:
                        known[key]["ios_seen"] = True
        else:
            info("--deep: Mac/iOS 判定が曖昧な機器は無い")

    vendor.save()

    missing = [
        (k, v)
        for k, v in known.items()
        if k not in seen_keys
        and v.get("mac")
        and not is_local_mac(v.get("mac", ""))
        and v.get("last_seen", "") >= _days_ago(30)
    ]

    if args.json:
        print(json.dumps({"network": str(network), "devices": entries,
                          "new": new_devices,
                          "missing": [v for _, v in missing]}, ensure_ascii=False, indent=2))
        if not args.no_save:
            baseline["devices"] = known
            save_baseline(baseline)
        return

    print()
    # 端末幅 80 桁でも折り返さないよう 4 列（77 桁）に収め、
    # ホスト名と注記は値がある行だけ次行に出す
    head = " ".join([pad_disp("IP", 15), pad_disp("MAC", 17),
                     pad_disp("VENDOR", 20), "TYPE"])
    print(head)
    print("-" * disp_width(head))
    for e in entries:
        print(" ".join([
            pad_disp(e["ip"], 15),
            pad_disp(e["mac"] or "-", 17),
            pad_disp(e["vendor"] or "-", 20),
            clip_disp(e["type"] or "-", 22),
        ]).rstrip())
        extra = []
        if e["host"]:
            extra.append("host=" + e["host"])
        if e["notes"]:
            extra.append(" ".join(e["notes"]))
        if extra:
            print("    " + " / ".join(extra))
    print()
    print("TYPE は MACベンダー・ホスト名・開いているポートからの推定（断定ではない）。")
    print("Apple機が 62078 を開けていれば iPhone/iPad、閉なら Mac 候補。")
    print("　スリープ中の iOS も 62078 を閉じるため、閉＝Mac とは限らない。")
    print("過去に 62078 を検出した機器は「iPhone/iPad(過去検出)」と表示する。")
    print("合計 %d 台 / 新規 %d 台" % (len(entries), len(new_devices)))
    if new_devices:
        print("  !! 新規デバイス: " + ", ".join(new_devices))
        print("     見覚えの無い機器なら、ルーターの管理画面で接続端末を確認すること。")
    if missing:
        print("  -- 30日以内に観測したが今回は未検出: %d 台" % len(missing))
        for _, v in missing:
            print("     %s %s (最終観測 %s)" % (v.get("ip", "?"), v.get("mac", ""), v.get("last_seen", "")[:10]))

    if not args.no_save:
        baseline["devices"] = known
        save_baseline(baseline)
        info("ベースライン更新: %s" % BASELINE_PATH)


def _days_ago(days):
    return (datetime.now().astimezone() - timedelta(days=days)).isoformat(timespec="seconds")


# ---------------------------------------------------------------- ports


def cmd_ports(args):
    iface, network = resolve_network(args.cidr)
    info("対象ネットワーク: %s (iface=%s)" % (network, iface or "-"))
    info("応答ホストを探索中...")
    alive = known_hosts(network)
    info("  %d 台を検査します" % len(alive))

    own_ips = own_ipv4_addresses()

    findings = []
    hosts = sorted(alive, key=lambda x: ipaddress.ip_address(x))
    total = len(hosts)
    for idx, ip in enumerate(hosts, 1):
        info("  [%d/%d] %s" % (idx, total, ip))

        def probe(port):
            return port, tcp_open(ip, port, timeout=args.timeout)

        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as ex:
            for port, opened in ex.map(probe, RISKY_PORTS):
                if not opened:
                    continue
                name, sev = RISKY_PORTS[port]
                findings.append(
                    {
                        "ip": ip,
                        "port": port,
                        "service": name,
                        "severity": sev,
                        "self": ip in own_ips,
                    }
                )

    findings.sort(key=lambda f: (SEVERITY_ORDER[f["severity"]], f["ip"], f["port"]))
    if args.json:
        print(json.dumps(findings, ensure_ascii=False, indent=2))
        return

    print()
    if not findings:
        print("危険ポートの露出は検出されませんでした。")
        return
    print("%-6s %-15s %-6s %-16s %s" % ("重要度", "IP", "PORT", "SERVICE", "備考"))
    print("-" * 80)
    for f in findings:
        print(
            "%-6s %-15s %-6d %-16s %s"
            % (
                SEVERITY_LABEL[f["severity"]],
                f["ip"],
                f["port"],
                f["service"],
                "自ホスト" if f["self"] else "",
            )
        )
    print()
    crit = [f for f in findings if f["severity"] in ("critical", "high")]
    if crit:
        print("!! 重要度 高以上が %d 件。LAN 内の他端末（乗っ取られた端末・来客の端末）から到達できる。" % len(crit))
        print("   不要なら各機器の設定で無効化すること。")


# ---------------------------------------------------------------- conns


def cmd_conns(args):
    info("接続一覧を取得中...")
    rows = [r for r in read_ss() if r["state"] not in ("LISTEN", "UNCONN")]
    remotes = {}
    for r in rows:
        ip = r["peer"][0]
        if not ip or ip in ("0.0.0.0", "::", "*"):
            continue
        if is_private(ip):
            continue
        remotes.setdefault(ip, None)

    info("宛先 %d 件を評価中... (ASN / PTR / DNSBL)" % len(remotes))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for res in ex.map(enrich_ip, remotes):
            remotes[res["ip"]] = res

    flagged = []
    normal = []
    shown = set()
    shown_peers = set()
    for r in rows:
        ip = r["peer"][0]
        e = remotes.get(ip)
        if not e:
            normal.append((r, None))
            continue
        shown_peers.add(ip)
        bad = bool([d for d in e["dnsbl"] if d.startswith("127.") and not d.startswith("127.255.255")])
        (flagged if bad else normal).append((r, e))

    listen_rows = read_ss(listen=True)
    exposed = [r for r in listen_rows if r["local"][0] in ("0.0.0.0", "::", "*")]

    if args.json:
        print(json.dumps(
            {
                "flagged": [{"peer": r["peer"][0], "port": r["peer"][1], "state": r["state"],
                             "process": r["process"], "rep": e} for r, e in flagged],
                "connections": [{"peer": r["peer"][0], "port": r["peer"][1], "state": r["state"],
                                 "process": r["process"],
                                 "asn": (e or {}).get("asn", ""), "cc": (e or {}).get("cc", "")}
                                for r, e in normal if e],
                "exposed_listeners": [{"local": r["local"][0], "port": r["local"][1],
                                       "process": r["process"]} for r in exposed],
            },
            ensure_ascii=False, indent=2,
        ))
        return

    print()
    if flagged:
        print("!! 既知の悪性IPとの通信: %d 件" % len(flagged))
        print("-" * 80)
        for r, e in flagged:
            print("  %s:%d  %s" % (r["peer"][0], r["peer"][1], "DNSBL=" + ",".join(e["dnsbl"])))
            print("    AS%s %s / %s" % (e["asn"] or "?", e["cc"] or "?", e["ptr"] or ""))
            print("    %s" % (r["process"] or "(プロセス不明)"))
        print()
    else:
        print("既知の悪性IPとの通信は検出されませんでした。")
        print()

    print("外向き接続（LAN 外）: %d 件" % len(shown_peers))
    print("%-15s %-6s %-10s %-8s %-18s %s" % ("PEER", "PORT", "ASN", "COUNTRY", "PTR", "PROCESS"))
    print("-" * 80)
    for r, e in normal:
        if not e:
            continue
        key = (r["peer"][0], r["peer"][1], proc_name(r["process"]))
        if key in shown:
            continue
        shown.add(key)
        print(
            "%-15s %-6d %-10s %-8s %-18s %s"
            % (r["peer"][0], r["peer"][1], e["asn"] or "-", e["cc"] or "-",
               (e["ptr"] or "-")[:18], proc_name(r["process"]) or "?")
        )

    print()
    unique_exposed = {}
    for r in exposed:
        unique_exposed.setdefault((r["netid"], r["local"][1]), r)
    print("全インターフェースで待ち受けているポート: %d 件" % len(unique_exposed))
    if unique_exposed:
        for (netid, port), r in sorted(unique_exposed.items(), key=lambda x: (x[0][0], x[0][1])):
            host = r["local"][0]
            addr = "[%s]:%d" % (host, port) if ":" in host else "%s:%d" % (host, port)
            print(
                "  %-5s %-24s %s"
                % (netid, addr, proc_name(r["process"]) or "(プロセス不明)")
            )
        print("  → 同一 LAN の他端末から到達可能。必要なものだけに絞ること。")


# ---------------------------------------------------------------- arp


def cmd_arp(args):
    neigh = read_neigh()
    ignored = ignored_networks()
    neigh = {
        ip: v
        for ip, v in neigh.items()
        if ":" in ip or not any(ipaddress.ip_address(ip) in n for n in ignored)
    }
    gw_ip, gw_dev = default_gateway()
    baseline = load_baseline()
    issues = []

    mac_to_ips = defaultdict(list)
    for ip, v in neigh.items():
        if v["mac"] and ":" not in ip:
            mac_to_ips[v["mac"]].append(ip)

    for mac, ips in mac_to_ips.items():
        if len(ips) > 1:
            sev = "critical" if gw_ip in ips else "high"
            issues.append((sev, "同一 MAC が複数 IP に出現: %s -> %s" % (mac, ", ".join(ips))))
            if gw_ip in ips:
                issues.append(("critical", "ゲートウェイ(%s)の MAC を他 IP が共有。ARP スプーフィングの疑い。" % gw_ip))

    gw_mac = (neigh.get(gw_ip) or {}).get("mac") if gw_ip else None
    prev_gw = baseline.get("gateway", {}).get("mac")
    if gw_ip and gw_mac:
        gw_changed = bool(prev_gw and prev_gw != gw_mac)
        if gw_changed:
            issues.append(
                ("critical", "ゲートウェイの MAC が変化: %s -> %s（機器入れ替えでなければ ARP スプーフィング）。"
                 "ベースラインは更新していない。正当な機器入れ替えならベースラインを削除して再取得"
                 % (prev_gw, gw_mac))
            )
        if is_local_mac(gw_mac):
            issues.append(("high", "ゲートウェイの MAC がローカル管理アドレス: %s" % gw_mac))
        # MAC 変化時はベースラインを上書き保存しない（保存すると次回以降 異常を検知できなくなる）
        if not gw_changed:
            baseline.setdefault("gateway", {})
            baseline["gateway"].update({"ip": gw_ip, "mac": gw_mac, "updated": now_iso()})
            if not args.no_save:
                save_baseline(baseline)

    rows = []
    for ip in sorted(neigh, key=ip_sort_key):
        if ":" in ip:
            continue
        v = neigh[ip]
        rows.append((ip, v["mac"] or "-", v["state"], "GW" if ip == gw_ip else ""))

    if args.json:
        print(json.dumps({"gateway": {"ip": gw_ip, "mac": gw_mac}, "issues":
                          [{"severity": s, "message": m} for s, m in issues],
                          "neighbors": [{"ip": i, "mac": m, "state": st, "role": r} for i, m, st, r in rows]},
                         ensure_ascii=False, indent=2))
        return

    print()
    print("近隣テーブル: %d 件（ゲートウェイ %s / %s）" % (len(rows), gw_ip or "?", gw_mac or "?"))
    print("%-15s %-17s %-12s %s" % ("IP", "MAC", "STATE", "ROLE"))
    print("-" * 70)
    for ip, mac, state, role in rows:
        print("%-15s %-17s %-12s %s" % (ip, mac, state, role))

    print()
    if issues:
        print("!! ARP 異常: %d 件" % len(issues))
        for sev, msg in sorted(issues, key=lambda x: SEVERITY_ORDER[x[0]]):
            print("  [%s] %s" % (SEVERITY_LABEL[sev], msg))
    else:
        print("ARP テーブルに異常は見つかりませんでした。")
        print("  （ARP スプーフィングは通信の瞬間にしか観測できないため、これは現在値の検査のみ）")


# ---------------------------------------------------------------- upnp

SOAP_ENVELOPE = """<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><u:%(action)s xmlns:u="%(service)s">%(args)s</u:%(action)s></s:Body>
</s:Envelope>"""


def localname(el):
    return el.tag.split("}")[-1]


def xml_first(root, tag):
    for el in root.iter():
        if localname(el) == tag:
            return el.text
    return None


def urljoin(base, path):
    if not base:
        return path
    if not path:
        return base
    m = re.match(r"^(https?://[^/]+)", base)
    root = m.group(1) if m else ""
    if path.startswith("http"):
        return path
    if path.startswith("/"):
        return root + path
    return base.rsplit("/", 1)[0] + "/" + path


def soap_call(control_url, service, action, args_xml, timeout=4):
    body = (SOAP_ENVELOPE % {"action": action, "service": service, "args": args_xml}).encode()
    req = urllib.request.Request(
        control_url,
        data=body,
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPACTION": '"%s#%s"' % (service, action),
            "User-Agent": "netsec/" + VERSION,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return ET.fromstring(r.read())


def upnp_probe(timeout=3):
    responses = ssdp_discover("urn:schemas-upnp-org:device:InternetGatewayDevice:1", timeout=timeout)
    gateways = []
    seen = set()
    for entry in responses:
        loc = entry.get("location")
        if not loc or loc in seen:
            continue
        seen.add(loc)
        gw = {"location": loc, "ip": entry["ip"], "server": entry.get("server", ""),
              "model": "", "control_url": None, "service": None,
              "external_ip": None, "mappings": []}
        try:
            req = urllib.request.Request(loc, headers={"User-Agent": "netsec/" + VERSION})
            with urllib.request.urlopen(req, timeout=4) as r:
                root = ET.fromstring(r.read())
        except Exception:
            gateways.append(gw)
            continue
        gw["model"] = "%s %s" % (xml_first(root, "manufacturer") or "",
                                 xml_first(root, "modelName") or "")
        gw["model"] = gw["model"].strip()
        for svc in root.iter():
            if localname(svc) != "service":
                continue
            stype = xml_first(svc, "serviceType") or ""
            if "WANIPConnection" in stype or "WANPPPConnection" in stype:
                gw["service"] = stype
                gw["control_url"] = urljoin(loc, xml_first(svc, "controlURL") or "")
                break
        if not gw["control_url"]:
            gateways.append(gw)
            continue
        try:
            resp = soap_call(gw["control_url"], gw["service"], "GetExternalIPAddress", "")
            gw["external_ip"] = xml_first(resp, "NewExternalIPAddress")
        except Exception:
            pass
        for idx in range(30):
            args = "<NewPortMappingIndex>%d</NewPortMappingIndex>" % idx
            try:
                resp = soap_call(gw["control_url"], gw["service"], "GetGenericPortMappingEntry", args)
            except Exception:
                break
            mapping = {
                "external_port": xml_first(resp, "NewExternalPort"),
                "protocol": xml_first(resp, "NewProtocol"),
                "internal_client": xml_first(resp, "NewInternalClient"),
                "internal_port": xml_first(resp, "NewInternalPort"),
                "description": xml_first(resp, "NewPortMappingDescription"),
                "enabled": xml_first(resp, "NewEnabled"),
            }
            if not mapping["external_port"]:
                break
            gw["mappings"].append(mapping)
        gateways.append(gw)
    return gateways


def cmd_upnp(args):
    info("SSDP で IGD（ルーター）を探索中...")
    gateways = upnp_probe(timeout=args.timeout)
    if args.json:
        print(json.dumps(gateways, ensure_ascii=False, indent=2))
        return
    print()
    if not gateways:
        gw_ip, _ = default_gateway()
        print("SSDP の応答なし（UPnP 対応ルーターを検出できず）。")
        print("  → UPnP が無効なのか、WSL からマルチキャストが届いていないのかは判別できない。")
        print("     確実に確認するには %s の管理画面で UPnP 設定を見ること。" % (gw_ip or "ルーター"))
        return
    for gw in gateways:
        print("IGD 検出: %s" % gw["ip"])
        print("  LOCATION: %s" % gw["location"])
        if gw["model"]:
            print("  機種: %s" % gw["model"])
        if gw["external_ip"]:
            print("  外部IP: %s" % gw["external_ip"])
        if not gw["control_url"]:
            print("  ポートマッピング: 取得不可（サービス未検出）")
            continue
        print("  ポートマッピング: %d 件" % len(gw["mappings"]))
        if gw["mappings"]:
            print("  %-8s %-5s %-18s %-8s %s" % ("EXT", "PROTO", "INTERNAL", "INT", "DESC"))
            print("  " + "-" * 76)
            for m in gw["mappings"]:
                print(
                    "  %-8s %-5s %-18s %-8s %s"
                    % (m["external_port"] or "-", m["protocol"] or "-",
                       m["internal_client"] or "-", m["internal_port"] or "-",
                       (m["description"] or "")[:30])
                )
            print()
            print("  !! 覚えの無いマッピングは外部への穴。ルーター管理画面で削除すること。")
        else:
            print("  （マッピング無し、または取得を拒否された）")
    print()
    print("補足: UPnP は LAN 内の任意のソフトが無認証でポートを開けられる仕組み。")
    print("      使っていないならルーター設定で UPnP を無効化するのが最も安全。")


# ---------------------------------------------------------------- audit


def cmd_audit(args):
    out = []
    out.append("# 自宅ネットワーク セキュリティ検査レポート")
    out.append("")
    out.append("- 実行日時: %s" % now_iso())
    try:
        iface, network = resolve_network(args.cidr)
        out.append("- 対象ネットワーク: %s (iface=%s)" % (network, iface or "-"))
    except SystemExit:
        pass
    out.append("- 実行ホスト: %s" % socket.gethostname())
    out.append("")
    out.append("注意: 本レポートはコマンド実行時点のスナップショット。常時監視は行っていない。")
    out.append("")

    for title, func, ns in (
        ("1. 接続デバイス一覧", cmd_devices, {}),
        ("2. 危険ポート露出", cmd_ports, {"timeout": getattr(args, "timeout", 0.4)}),
        ("3. 外向き通信", cmd_conns, {}),
        ("4. ARP 異常", cmd_arp, {}),
        ("5. UPnP 外部公開", cmd_upnp, {"timeout": 3.0}),
    ):
        out.append("## " + title)
        out.append("")
        buf = _capture(func, getattr(args, "cidr", None), ns)
        out.append("```")
        out.append(buf.strip() or "(出力なし)")
        out.append("```")
        out.append("")

    text = "\n".join(out)
    if args.out:
        path = Path(args.out).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        info("レポート出力: %s" % path)
    else:
        print(text)


def _capture(func, cidr, overrides):
    """サブコマンドを既定値付きで実行し、標準出力を文字列で返す。"""
    import contextlib
    import io

    base = {"cidr": cidr, "json": False, "no_save": True, "no_vendor": False,
            "no_mdns": False, "no_ssdp": False, "timeout": 0.4,
            "no_probe": False, "deep": None}
    base.update(overrides)
    ns = argparse.Namespace(**base)
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            func(ns)
    except SystemExit:
        pass
    return buf.getvalue()


# ---------------------------------------------------------------- HTTP


def http_get_text(url, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": "netsec/" + VERSION})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace").strip()


def http_get_json(url, timeout=8):
    return json.loads(http_get_text(url, timeout))


SUSPICIOUS_TLDS = (
    ".xyz", ".top", ".tk", ".ml", ".ga", ".cf", ".gq", ".cc", ".icu",
    ".click", ".work", ".support", ".zip", ".mov", ".rest", ".buzz",
)


def dga_suspicion(name):
    """ランダム生成ドメイン（DGA）っぽさの簡易判定。"""
    label = name.split(".")[0]
    if len(label) < 16:
        return ""
    digits = sum(c.isdigit() for c in label)
    if digits and digits / len(label) >= 0.25:
        return "DGA疑い(数字比率高)"
    if len(label) >= 24 and len(set(label)) >= 12 and "-" not in label:
        return "DGA疑い(長いランダム列)"
    return ""


DNS_QUERY_RE = re.compile(
    r"(\d+\.\d+\.\d+\.\d+)\.\d+ > [\d.]+\.53: .*?\? (\S+)"
)
IGNORED_DOMAIN_SUFFIXES = (".local", ".arpa", ".internal")


def dns_query_of(line):
    """tcpdump の 1 行から (送信元IP, クエリ名) を取り出す。クエリ以外は None。"""
    m = DNS_QUERY_RE.search(line)
    if not m:
        return None
    name = m.group(2).rstrip(".").lower()
    if name.endswith(IGNORED_DOMAIN_SUFFIXES) or name == "localhost":
        return None
    return m.group(1), name


def collect_dns_lines(lines, counts, sources):
    """行の並びから DNS クエリを集計し、観測パケット数を返す。"""
    packets = 0
    for line in lines:
        packets += 1
        hit = dns_query_of(line)
        if not hit:
            continue
        src, name = hit
        counts[name] += 1
        sources.setdefault(name, src)
    return packets


def report_dns(counts, sources, seconds, packets, no_save, hints=None):
    seen = load_json(DNS_SEEN_PATH, {})
    # 基準が空の初回は全件が「新規」になり警告が無意味なので、差分判定をしない
    first_run = not seen
    new_names = [] if first_run else [n for n in counts if n not in seen]
    for name in counts:
        seen[name] = {
            "first_seen": seen.get(name, {}).get("first_seen", now_iso()),
            "last_seen": now_iso(),
            "count": counts[name],
        }
    if not no_save:
        save_json(DNS_SEEN_PATH, seen)

    rows = []
    for name, cnt in sorted(counts.items(), key=lambda x: (-x[1], x[0])):
        notes = []
        if name in new_names:
            notes.append("新規")
        if name.endswith(SUSPICIOUS_TLDS):
            notes.append("要注意TLD")
        dga = dga_suspicion(name)
        if dga:
            notes.append(dga)
        rows.append((cnt, sources.get(name, ""), name, " ".join(notes)))

    print()
    print("観測ドメイン: %d 件（%.0f 秒間 / パケット %d）" % (len(rows), seconds, packets))
    if not rows:
        print("  DNS クエリを観測できなかった。")
        for hint in hints or ():
            print("  → %s" % hint)
        print("  確認: 傍受中にブラウザで未訪問サイトを開くと確実にクエリが出る。")
        return 0

    print("%-5s %-15s %-45s %s" % ("COUNT", "SOURCE", "DOMAIN", "NOTE"))
    print("-" * 80)
    for cnt, src, name, note in rows:
        print("%-5d %-15s %-45s %s" % (cnt, src, name[:45], note))
    flagged = [r for r in rows if r[3]]
    print()
    if first_run:
        print("初回実行: %d 件を基準として記録した（次回以降は追加分のみ「新規」表示）。" % len(rows))
    if flagged:
        label = "要注意TLD/DGA疑い" if first_run else "新規/要注意TLD/DGA疑い"
        print("!! 要注意: %d 件（%s）" % (len(flagged), label))
        print("   新規でも一般的なクラウド・CDNなら正常。心当たりのない長いランダム名が繰り返すなら確認。")
    print("注意: 暗号化DNS（DoH/DoT）や LAN 外の通信は見えない。手動実行した時間内のみ観測。")
    return 0


# ---------------------------------------------------------------- dnswin（pktmon）


def win_path(cmd_list):
    out = subprocess.run(cmd_list, capture_output=True, timeout=30)
    return out.stdout.decode("utf-8", "replace").strip()


def win_to_wsl(path):
    out = subprocess.run(["wslpath", "-u", path], capture_output=True, timeout=15)
    return out.stdout.decode("utf-8", "replace").strip()


PKTMON_SCRIPT = r"""$ErrorActionPreference = 'Stop'
$tmp = '%(tmp)s'
$out = '%(out)s'
$etl = Join-Path $tmp 'capture.etl'
$status = Join-Path $tmp 'status.txt'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
Remove-Item $etl, $out, $status -ErrorAction SilentlyContinue
try {
    pktmon filter remove | Out-Null
%(filters)s
    pktmon start --capture --pkt-size %(pkt_size)d --file-name $etl | Out-Null
    Start-Sleep -Seconds %(seconds)d
    pktmon stop | Out-Null
    pktmon etl2pcap $etl --out $out | Out-Null
    'OK' | Set-Content -Path $status -Encoding ascii
} catch {
    $_.Exception.Message | Set-Content -Path $status -Encoding utf8
} finally {
    pktmon filter remove | Out-Null
}
"""


def win_temp():
    """Windows の %TEMP% を Windows 形式で返す。"""
    return win_path(["powershell.exe", "-NoProfile", "-Command", "$env:TEMP"])


def pktmon_capture(tag, seconds, filters, out_win, pkt_size=1500):
    """Windows 側 pktmon を昇格実行して pcapng を作る。

    filters: `pktmon filter add` に渡す引数（例 "-p 53" / "-i 192.168.10.116 -p 443"）。
             空文字なら全パケット。
    戻り値: (pcapng の WSL Path か None, エラーメッセージ)
    """
    if not shutil.which("powershell.exe"):
        return None, "powershell.exe が見つからない（WSL 以外では未対応）。"

    temp = win_temp()
    if not temp:
        return None, "Windows の TEMP ディレクトリを取得できない。"
    tmp_win = temp.rstrip("\\") + "\\netsec-" + tag
    tmp_wsl = win_to_wsl(tmp_win)
    out_wsl = win_to_wsl(out_win)
    if not tmp_wsl.startswith("/mnt/") or not out_wsl.startswith("/mnt/"):
        return None, "Windows パスの変換に失敗: %s" % out_win
    Path(tmp_wsl).mkdir(parents=True, exist_ok=True)
    Path(out_wsl).parent.mkdir(parents=True, exist_ok=True)

    ps1_win = tmp_win + "\\capture.ps1"
    filter_line = "    pktmon filter add %s | Out-Null\n" % filters if filters else ""
    Path(win_to_wsl(ps1_win)).write_text(
        PKTMON_SCRIPT % {
            "tmp": tmp_win,
            "out": out_win,
            "seconds": int(seconds),
            "pkt_size": int(pkt_size),
            "filters": filter_line,
        },
        encoding="ascii",
    )
    status_wsl = Path(tmp_wsl) / "status.txt"

    info("Windows 側で pktmon を %d 秒実行します（UAC の承認が必要）。" % seconds)
    info("  承認しない場合は何も取得できない。")
    launcher = (
        "Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden "
        "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%s')" % ps1_win
    )
    try:
        subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", launcher],
            timeout=seconds + 120,
            capture_output=True,
        )
    except subprocess.TimeoutExpired:
        return None, "pktmon の実行がタイムアウトした。"

    if not status_wsl.is_file():
        return None, ("結果ファイルが無い。UAC を承認しなかった可能性が高い。"
                      "管理者 PowerShell で手動実行もできる: %s" % ps1_win)
    status = status_wsl.read_text(encoding="utf-8", errors="replace").strip()
    if status != "OK":
        return None, "pktmon が失敗した: %s" % status
    pcap = Path(out_wsl)
    if not pcap.is_file():
        return None, "pcapng が作成されていない（フィルタに該当するパケットが無かった可能性）。"
    try:
        status_wsl.unlink()
    except OSError:
        pass
    return pcap, ""


def cmd_dnswin(args):
    if not shutil.which("tcpdump"):
        print("tcpdump が見つからない（pcapng の解析に必要）: sudo apt install tcpdump")
        return 1

    temp = win_temp()
    if not temp:
        print("Windows の TEMP ディレクトリを取得できない。")
        return 1
    out_win = temp.rstrip("\\") + "\\netsec-dnswin\\dns.pcapng"
    pcap_wsl, err = pktmon_capture("dnswin", args.seconds, "-p 53", out_win, pkt_size=512)
    if err:
        print(err)
        return 1

    lines = sh(["tcpdump", "-r", str(pcap_wsl), "-n", "udp port 53"], timeout=90).splitlines()
    counts = defaultdict(int)
    sources = {}
    packets = collect_dns_lines(lines, counts, sources)
    if not args.keep:
        try:
            pcap_wsl.unlink()
        except OSError:
            pass
    hints = [
        "pktmon の記録に DNS クエリが無い。傍受中に未訪問サイトを開くと出る。",
        "DNS over HTTPS（DoH）を使うブラウザは UDP/53 を出さない。",
    ]
    return report_dns(counts, sources, args.seconds, packets, args.no_save, hints)


# ---------------------------------------------------------------- capture

CAPTURE_DIR = "netsec-captures"


def split_endpoint(token):
    """`1.2.3.4.443` 形式を (ip, port) に分ける。port が無ければ (token, None)。

    ICMP のようにポート表記が無い行（`192.168.10.1`）を IP と誤分割しないよう、
    ポートがある場合だけ host 側の形を検証する。
    """
    host, _, port = token.rpartition(".")
    if port.isdigit() and ":" not in port and not host.endswith(":"):
        if host.count(".") == 3 or ":" in host:
            return host, int(port)
    return token, None


def capture_peer_stats(lines, own, target=None):
    """tcpdump の 1 行から (proto 内訳, 通信相手ごとの集計, 解釈不能件数) を作る。

    target を渡すと、方向（→/←）をその端末から見た向きで判定する。
    """
    proto = defaultdict(int)
    peers = defaultdict(int)
    undecoded = 0
    for line in lines:
        if line.startswith("ARP,"):
            proto["arp"] += 1
            continue
        m = re.match(r"^IP6? (\S+) > (\S+): ?(.*)$", line)
        if not m:
            undecoded += 1
            continue
        src, dst, rest = m.group(1), m.group(2), m.group(3)
        if rest.startswith("tcp") or "Flags [" in rest:
            kind = "tcp"
        elif rest.startswith("UDP"):
            kind = "udp"
        elif rest.startswith("ICMP") or rest.startswith("ICMP6"):
            kind = "icmp"
        elif rest.startswith("igmp") or rest.startswith("IGMP"):
            kind = "igmp"
        else:
            kind = "other"
        proto[kind] += 1

        sip, sport = split_endpoint(src)
        dip, dport = split_endpoint(dst)
        if target and sip == target:
            peer, pport, mark = dip, dport, "→"
        elif target and dip == target:
            peer, pport, mark = sip, sport, "←"
        elif sip in own:
            peer, pport, mark = dip, dport, "→"
        elif dip in own:
            peer, pport, mark = sip, sport, "←"
        else:
            peer, pport, mark = dip, dport, "⇄"
        peers[(peer, pport, kind, mark)] += 1
    return proto, peers, undecoded


def find_tshark():
    """Windows 同梱の tshark.exe を探す。

    実行は WSL 側から行うため `/mnt/c/...` のパスを返す（Windows 形式の
    `C:\\Program Files\\...` をそのまま subprocess に渡すと FileNotFoundError）。
    """
    cands = []
    base = win_path(["powershell.exe", "-NoProfile", "-Command", "$env:ProgramFiles"])
    if base:
        cands.append(base.rstrip("\\") + "\\Wireshark\\tshark.exe")
    cands.append("C:\\Program Files\\Wireshark\\tshark.exe")
    cands.append("C:\\Program Files (x86)\\Wireshark\\tshark.exe")
    for exe in cands:
        wsl = win_to_wsl(exe)
        if wsl and Path(wsl).is_file():
            return wsl
    return None


def tshark_fields(exe, win_pcap, display, fields):
    """tshark で表示フィルタを適用し、指定フィールドをタブ区切りで取り出す。"""
    cmd = [exe, "-r", win_pcap, "-Y", display, "-T", "fields"]
    for name in fields:
        cmd += ["-e", name]
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if out.returncode not in (0, 1, 2):
        return []
    text = out.stdout.decode("utf-8", "replace")
    return [line for line in text.splitlines() if line.strip()]


def print_sites(tshark_exe, win_pcap, peers):
    """DNS 応答と TLS の SNI から、接続したサイト（ドメイン）の一覧を作る。"""
    name_ips = defaultdict(set)
    for line in tshark_fields(
        tshark_exe, win_pcap, "dns.flags.response==1 && dns.a", ["dns.qry.name", "dns.a"]
    ):
        parts = line.split("\t")
        if len(parts) < 2 or not parts[0].strip():
            continue
        for ip in parts[1].split(","):
            ip = ip.strip()
            if ip:
                name_ips[parts[0].strip().rstrip(".")].add(ip)

    sni_ips = defaultdict(set)
    for line in tshark_fields(
        tshark_exe, win_pcap, "tls.handshake.type==1",
        ["ip.dst", "tls.handshake.extensions_server_name"],
    ):
        parts = line.split("\t")
        if len(parts) < 2 or not parts[1].strip():
            continue
        sni_ips[parts[1].strip().rstrip(".")].add(parts[0].strip())

    ip_count = defaultdict(int)
    for (peer, _port, _kind, _mark), n in peers.items():
        if peer and (peer[0].isdigit() or ":" in peer):
            ip_count[peer] += n

    rows = []
    for name in set(name_ips) | set(sni_ips):
        ips = name_ips.get(name) or sni_ips.get(name) or set()
        src = "dns+sni" if name in name_ips and name in sni_ips else (
            "dns" if name in name_ips else "sni"
        )
        rows.append((sum(ip_count.get(ip, 0) for ip in ips), name, src,
                     ",".join(sorted(ips))))
    if not rows:
        print()
        print("サイト一覧: 取得できず（DNS 応答も SNI も無い。DoH/ECH の可能性）")
        return
    rows.sort(key=lambda r: (-r[0], r[1]))
    print()
    print("接続したサイト（ドメイン単位）")
    head = " ".join([
        pad_disp("COUNT", 7),
        pad_disp("SITE", 30),
        pad_disp("SRC", 8),
        "IP",
    ])
    print(head)
    print("-" * disp_width(head))
    for n, name, src, ips in rows[:20]:
        print(" ".join([
            pad_disp(str(n) if n else "-", 7),
            pad_disp(clip_disp(name, 30), 30),
            pad_disp(src, 8),
            clip_disp(ips, 26),
        ]).rstrip())
    if len(rows) > 20:
        print("  … 他 %d 件" % (len(rows) - 20))
    print("SRC: dns=DNS応答 / sni=TLSのサーバー名 / dns+sni=両方")
    print("COUNT は相手 IP の記録数（重複含む）。- は名前解決のみで接続は未観測。")
    print("URL のパス・検索語は暗号化のため不明。DoH/DoT 利用時は dns に出ない。")


def print_capture_summary(pcap_wsl, seconds=None, target_ip=None, sites=False):
    """pcapng を tcpdump で要約して表示する。

    pktmon は同一パケットを複数のコンポーネントで記録する（実測 約5〜8 倍）ため、
    件数は実数より多い。順位・内訳の比率は有効。
    また一部レコードは L2 ヘッダが欠けており、tcpdump は非 IP フレームとして
    解釈する（16 進ダンプになるので除外して数える）。
    """
    lines = sh(["tcpdump", "-r", str(pcap_wsl), "-nn", "-q", "-t"], timeout=300).splitlines()
    total = len(lines)
    print()
    if not total:
        print("観測パケット: 0%s" % ("（%d 秒間）" % seconds if seconds else ""))
        print("  該当パケット無し。フィルタが厳しすぎるか、対象が通信していない。")
        print("保存: %s" % pcap_wsl)
        return 0
    proto, peers, undecoded = capture_peer_stats(lines, own_ipv4_addresses(), target_ip)
    span = "（%d 秒間・重複含む）" % seconds if seconds else "（重複含む）"
    print("観測: 記録 %d 件%s" % (total, span))
    kinds = [k for k in ("tcp", "udp", "icmp", "igmp", "arp", "other") if proto[k]]
    if kinds:
        print("内訳: " + " / ".join("%s %d" % (k, proto[k]) for k in kinds))
    if undecoded:
        print("L2 ヘッダ欠落フレーム: %d 件（集計から除外）" % undecoded)
    print("  pktmon は同一パケットを複数コンポーネントで記録する（実測 約5〜8 倍）。")
    if target_ip:
        hits = sum(1 for line in lines if target_ip in line)
        if not hits:
            print()
            print("注意: %s の通信は 1 件も観測されていない。" % target_ip)
            print("  端末がスリープ／電源OFF、IP が変わった、または別セグメントの可能性。")
            print("  `run netsec devices` で現在の IP を確認する。")

    rows = sorted(peers.items(), key=lambda kv: -kv[1])[:15]
    if rows:
        print()
        head = " ".join([
            pad_disp("COUNT", 6),
            pad_disp("PEER", 16),
            pad_disp("PORT", 6),
            pad_disp("PROTO", 6),
            "DIR",
        ])
        print(head)
        print("-" * disp_width(head))
        for (peer, port, kind, mark), n in rows:
            print(" ".join([
                pad_disp(str(n), 6),
                pad_disp(peer, 16),
                pad_disp(str(port) if port is not None else "-", 6),
                pad_disp(kind, 6),
                mark,
            ]).rstrip())

    dns_lines = sh(["tcpdump", "-r", str(pcap_wsl), "-n", "udp port 53"], timeout=120).splitlines()
    counts = defaultdict(int)
    collect_dns_lines(dns_lines, counts, {})
    if counts:
        print()
        print("DNS クエリ TOP")
        for name, n in sorted(counts.items(), key=lambda kv: -kv[1])[:10]:
            print("  %3d  %s" % (n, clip_disp(name, 60)))

    if sites:
        exe = find_tshark()
        win_pcap = win_path(["wslpath", "-w", str(pcap_wsl)])
        if not exe:
            print()
            print("サイト一覧: tshark.exe が見つからない（Wireshark を導入すると使える）")
        elif not win_pcap:
            print()
            print("サイト一覧: パスの Windows 変換に失敗")
        else:
            print_sites(exe, win_pcap, peers)

    size_mb = pcap_wsl.stat().st_size / 1024 / 1024
    print()
    if size_mb >= 100:
        print("ヒント: 全パケット 1500 バイトは重い（%d MB）。" % size_mb)
        print("  --pkt-size 128（ヘッダのみ）か --ip / --port で絞る。")
    print("保存: %s" % pcap_wsl)
    print("サイズ: %.1f MB" % size_mb)
    print("DIR: → 送信 / ← 受信 / ⇄ どちらでもない（ブロードキャスト等）")
    print("この PC から見える範囲のみ。他端末同士の通信（スイッチ内）は含まれない。")
    return 0


def open_in_wireshark(win_pcap):
    """Windows の Wireshark に pcapng を渡す。見つからなければ False。"""
    base = win_path(["powershell.exe", "-NoProfile", "-Command", "$env:ProgramFiles"])
    cands = []
    if base:
        cands.append(base.rstrip("\\") + "\\Wireshark\\Wireshark.exe")
    cands.append("C:\\Program Files (x86)\\Wireshark\\Wireshark.exe")
    for exe in cands:
        if not Path(win_to_wsl(exe)).is_file():
            continue
        subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command",
             "Start-Process -FilePath '%s' -ArgumentList '%s'" % (exe, win_pcap)],
            capture_output=True,
            timeout=60,
        )
        return True
    return False


def cmd_capture(args):
    if not shutil.which("tcpdump"):
        print("tcpdump が見つからない（要約に必要）: sudo apt install tcpdump")
        return 1

    if args.read:
        pcap = Path(args.read).expanduser()
        if not pcap.is_file():
            print("ファイルが無い: %s" % pcap)
            return 1
        return print_capture_summary(pcap, target_ip=args.ip, sites=args.sites)

    crit = []
    if args.ip:
        # PowerShell スクリプト / pktmon へ渡す前に形式を検証する
        try:
            ipaddress.ip_address(args.ip)
        except ValueError:
            print("IP アドレスの形式が不正: %s" % args.ip)
            return 1
        crit += ["-i", args.ip]
    if args.port:
        crit += ["-p", str(args.port)]
    filters = " ".join(crit)

    if args.out:
        out_wsl = Path(args.out).expanduser()
        out_win = win_path(["wslpath", "-w", str(out_wsl)])
        if not out_win:
            print("出力先の Windows パス変換に失敗: %s" % out_wsl)
            return 1
    else:
        profile = win_path(["powershell.exe", "-NoProfile", "-Command", "$env:USERPROFILE"])
        if not profile:
            print("Windows のユーザープロファイルを取得できない。")
            return 1
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        out_win = "%s\\%s\\capture-%s.pcapng" % (profile.rstrip("\\"), CAPTURE_DIR, stamp)

    if filters:
        info("対象: %s" % filters.replace("-i", "IP ").replace("-p", "port "))
    else:
        info("対象: 全パケット（この PC が見える範囲）")
    pcap_wsl, err = pktmon_capture("capture", args.seconds, filters, out_win,
                                   pkt_size=args.pkt_size)
    if err:
        print(err)
        return 1

    rc = print_capture_summary(pcap_wsl, args.seconds, args.ip, args.sites)
    if args.open and not open_in_wireshark(out_win):
        print()
        print("Wireshark が見つからない。Windows 側で次を実行すると導入できる:")
        print("  winget install WiresharkFoundation.Wireshark")
        print("  （ID が変わっていたら winget search wireshark で確認）")
    return rc


# ---------------------------------------------------------------- external


def cmd_external(args):
    info("公開IPを取得中...")
    try:
        public_ip = http_get_text("https://api.ipify.org")
    except Exception as e:
        print("公開IPを取得できない（外部通信の失敗）: %s" % e)
        return 1
    info("  公開IP: %s" % public_ip)

    asn, cc = asn_info(public_ip)
    record = {}
    try:
        record = http_get_json("https://internetdb.shodan.io/%s" % public_ip)
    except Exception:
        record = {}

    ports = record.get("ports", []) or []
    vulns = record.get("vulns", []) or []
    hostnames = record.get("hostnames", []) or []
    tags = record.get("tags", []) or []

    local_listen = {}
    for r in read_ss(listen=True):
        if r["local"][0] in ("0.0.0.0", "::", "*"):
            local_listen[r["local"][1]] = r

    print()
    print("公開IP: %s  AS%s %s" % (public_ip, asn or "?", cc or "?"))
    if hostnames:
        print("逆引き/登録名: %s" % ", ".join(hostnames[:5]))
    if tags:
        print("タグ: %s" % ", ".join(tags))
    print()
    if not record:
        print("第三者スキャンDB（Shodan InternetDB）にこのIPの記録なし。")
        print("  → 直近に外部スキャンされていない、または記録が無い状態。")
    else:
        print("外部から見えているポート（第三者スキャンの記録）: %d 件" % len(ports))
        if ports:
            print("  %s" % ", ".join(str(p) for p in sorted(ports)))
            overlap = sorted(set(ports) & set(local_listen))
            if overlap:
                print()
                print("  !! 自ホストが 0.0.0.0 で待ち受けているポートと一致: %s" % overlap)
                print("     ルーターでポート開放していなければ NAT で守られているが、UPnP 設定を確認すること。")
        if vulns:
            print()
            print("!! 既知脆弱性（CVE）: %d 件" % len(vulns))
            for cve in sorted(vulns)[:20]:
                print("  %s" % cve)
            print("   → 該当機器のファームウェア更新を検討。")
    print()
    print("注意: Shodan の観測は過去の記録で、現在の状態と一致しない場合がある。")
    print("      このコマンドは自前の外部スキャンを行わない（第三者DBの参照のみ）。")
    return 0


# ---------------------------------------------------------------- CLI


def build_parser():
    parser = argparse.ArgumentParser(
        prog="netsec",
        description="自宅ネットワークの簡易セキュリティ検査（root 不要・手動実行）",
        epilog=(
            "例: netsec devices / netsec ports / netsec conns / netsec arp / netsec upnp\n"
            "    netsec audit --out ~/net-audit.md\n"
            "    netsec external\n"
            "    netsec dnswin --seconds 30     (DNS 名の取得・UAC 承認要)\n"
            "    netsec capture --seconds 30 --ip 192.168.10.116 --open\n"
            "                                   (pcapng 保存・Wireshark で開く・UAC 承認要)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version="netsec " + VERSION)
    parser.add_argument("--cidr", help="対象 CIDR（既定: デフォルトルートの NIC から自動判定）")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("devices", help="LAN 接続デバイス一覧と新規デバイス差分")
    p.add_argument("--json", action="store_true", help="JSON で出力")
    p.add_argument("--no-save", action="store_true", help="ベースラインを更新しない")
    p.add_argument("--no-vendor", action="store_true", help="MAC ベンダーのオンライン照会をしない")
    p.add_argument("--no-mdns", action="store_true", help="mDNS 探索をしない")
    p.add_argument("--no-ssdp", action="store_true", help="SSDP 探索をしない")
    p.add_argument("--no-probe", action="store_true", help="端末種別の推定（ポート探索）をしない")
    p.add_argument(
        "--deep",
        nargs="?",
        const=30,
        type=int,
        metavar="SEC",
        help="Mac/iOS 判定が曖昧な機器の 62078 をポーリング（省略時 30 秒・iOS の起床待ち）",
    )
    p.set_defaults(func=cmd_devices)

    p = sub.add_parser("ports", help="LAN 内機器の危険ポート露出検査")
    p.add_argument("--json", action="store_true")
    p.add_argument("--timeout", type=float, default=0.4, help="1 ポートあたりの待ち時間(秒)")
    p.set_defaults(func=cmd_ports)

    p = sub.add_parser("conns", help="外向き通信の一覧と宛先の評判判定")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_conns)

    p = sub.add_parser("arp", help="ARP テーブル異常（スプーフィング兆候）検知")
    p.add_argument("--json", action="store_true")
    p.add_argument("--no-save", action="store_true", help="ゲートウェイ MAC を保存しない")
    p.set_defaults(func=cmd_arp)

    p = sub.add_parser("upnp", help="UPnP(IGD) の検出と外部公開ポート確認")
    p.add_argument("--json", action="store_true")
    p.add_argument("--timeout", type=float, default=3.0, help="SSDP の待ち時間(秒)")
    p.set_defaults(func=cmd_upnp)

    p = sub.add_parser("audit", help="全項目を実行して Markdown レポートを出力")
    p.add_argument("--out", help="出力ファイル（省略時は標準出力）")
    p.add_argument("--timeout", type=float, default=0.4, help="ポート走査の待ち時間(秒)")
    p.set_defaults(func=cmd_audit)

    p = sub.add_parser("dnswin", help="Windows 側 pktmon で DNS を取得")
    p.add_argument("--seconds", type=int, default=30, help="傍受時間(秒)")
    p.add_argument("--keep", action="store_true", help="取得した pcapng/etl を残す")
    p.add_argument("--no-save", action="store_true", help="観測履歴を保存しない")
    p.set_defaults(func=cmd_dnswin)

    p = sub.add_parser("capture", help="パケットを取得して pcapng 保存＋要約（Wireshark 相当）")
    p.add_argument("--seconds", type=int, default=30, help="取得時間(秒)")
    p.add_argument("--ip", help="対象 IP で絞る（例: 192.168.10.116）")
    p.add_argument("--port", type=int, help="対象ポートで絞る（例: 443）")
    p.add_argument("--pkt-size", type=int, default=1500, help="1 パケットの取得バイト数")
    p.add_argument("--out", help="出力 pcapng（省略時: Windows ユーザーフォルダ\\netsec-captures\\）")
    p.add_argument("--open", action="store_true", help="保存後に Windows の Wireshark で開く")
    p.add_argument("--read", metavar="PCAPNG", help="既存の pcapng を要約するだけ（取得しない）")
    p.add_argument("--sites", action="store_true", help="接続したサイト（DNS/SNI）の一覧も出す")
    p.set_defaults(func=cmd_capture)

    p = sub.add_parser("external", help="第三者スキャンDBから外から見えるポートを確認")
    p.set_defaults(func=cmd_external)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if not getattr(args, "command", None):
        parser.print_help()
        return 1
    rc = args.func(args)
    return rc or 0


if __name__ == "__main__":
    sys.exit(main())
