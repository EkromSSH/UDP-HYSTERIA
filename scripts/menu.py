#!/usr/bin/env python3
"""IDA UDPHysteria Manager v4.0 — All-in-One (ShowOn features merged)"""
import os, subprocess, re, unicodedata, json, socket, time, sys, random
from http.server import HTTPServer, SimpleHTTPRequestHandler
from threading import Thread

# ══ Config ══
HYST_CONFIG = "/opt/hysteria/config-v1.json"
WEB_DIR = "/home/vps/public_html/server"
WEB_PORT = 82
SWAP_FILE = "/swapfile"
SHOWON_CONF = "/etc/showon.conf"
VERSION = "v2.3.0"

# ══ Colors ══
R = '\033[0;31m'; G = '\033[0;32m'; O = '\033[0;33m'
Y = '\033[1;33m'; B = '\033[0;34m'; M = '\033[0;35m'
C = '\033[0;36m'; WHT = '\033[1;37m'; BD = '\033[1m'
D = '\033[2m'; NC = '\033[0m'

W = 62
H = '\u2550'
def vislen(s):
    s2 = re.sub(r'\033\[[0-9;]*m', '', s)
    try:
        from wcwidth import wcswidth
        # Use wcswidth on full string — handles Variation Selectors correctly
        return max(0, wcswidth(s2))
    except:
        w = 0
        for c in s2:
            if unicodedata.category(c) == 'Mn': continue
            cp = ord(c)
            if (0x0E00 <= cp <= 0x0E7F or cp <= 0x00FF): w += 1
            elif (0x1100 <= cp <= 0x11FF or 0x2E80 <= cp <= 0x2FFF or
                  0x3000 <= cp <= 0x33FF or 0x3400 <= cp <= 0x4DBF or
                  0x4E00 <= cp <= 0x9FFF or 0xAC00 <= cp <= 0xD7AF or
                  0xF900 <= cp <= 0xFAFF or 0xFE10 <= cp <= 0xFE19 or
                  0xFE30 <= cp <= 0xFE6F or 0xFF01 <= cp <= 0xFF60 or
                  0xFFE0 <= cp <= 0xFFE6 or 0x1F000 <= cp <= 0x1FFFF or
                  0x20000 <= cp <= 0x2FFFF or 0x30000 <= cp <= 0x3FFFF):
                w += 2
            else: w += 1
        return w
def pad(s, w): return s + ' ' * max(0, w - vislen(s))
def box(): print(f"  {B}\u2554{H*(W-4)}\u2557{NC}")
def bot(): print(f"  {B}\u255a{H*(W-4)}\u255d{NC}")
def bsep(): print(f"  {B}\u2560{H*(W-4)}\u2563{NC}")
def bput(c):
    # Simple bput: pad content to fixed width inside the box
    # Content width = W - 5 (2 margin + ║ + space + space + ║ = 5)
    p = max(0, W-5-vislen(c))
    print(f"  {B}\u2551{NC} {c}{' '*p}{B}\u2551{NC}")
def center(t):
    v = vislen(t); l = (W-4-v)//2; r = W-4-v-l
    print(f"  {B}\u2551{NC}{' '*l}{t}{' '*r}{B}\u2551{NC}")
def menu_row(n1, i1, l1, n2, i2, l2):
    left = f"{G}[{n1}]{NC}  {i1}  {l1}"
    right = f"{G}[{n2}]{NC}  {i2}  {l2}" if n2 else ""
    bput(f"  {pad(left, 25)}  {pad(right, 25)}")

# ══ Data ══
def get_ip():
    try: return subprocess.check_output("curl -s --connect-timeout 3 ifconfig.me", shell=True, timeout=5).decode().strip()
    except: return "N/A"
def get_nic():
    try:
        r = subprocess.run("ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\") print $(i+1)}' | head -1",
                          shell=True, capture_output=True,text=True,timeout=3)
        return r.stdout.strip() or "eth0"
    except: return "eth0"
def read_config():
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        port = d.get("listen", ":25000").split(":")[-1]
        auth = d.get("auth_str", "") or (d.get("auth", {}).get("config", [""])[0] if d.get("auth", {}).get("config") else "")
        return port, auth, d.get("obfs", "")
    except: return "25000", "", ""
def get_status():
    try: return subprocess.run(["systemctl","is-active","hysteria"], capture_output=True,text=True,timeout=3).stdout.strip()
    except: return "inactive"
def get_uptime():
    try:
        raw=subprocess.run("uptime -p", shell=True, capture_output=True,text=True,timeout=3).stdout.strip().replace("up ","")
        import re
        wk=re.search(r'([0-9]+) week', raw); wk=int(wk.group(1)) if wk else 0
        rest=re.sub(r'[0-9]+ week[s]?,? ?','',raw)
        dy=re.search(r'([0-9]+) day', rest); dy=int(dy.group(1)) if dy else 0
        totald=dy + wk*7
        if totald>0:
            rest=re.sub(r'[0-9]+ day[s]?,? ?','',rest).replace(',','').strip()
            x=f"{totald}D " + re.sub(r'([0-9]+) hour[s]?',r'\1H',re.sub(r'([0-9]+) minute[s]?',r'\1M',rest)).strip()
        else:
            x=re.sub(r'([0-9]+) hour[s]?',r'\1H',re.sub(r'([0-9]+) minute[s]?',r'\1M',rest)).strip()
        return x
    except: return ""
def count_ssh():
    try:
        # นับเฉพาะคนล็อกอินสำเร็จแล้วจริงๆ (มี @pts/ หรือ @tty/) ไม่นับ bot/priv/notty/net
        r = subprocess.run("ps -eo args | grep -E '[s]shd: [^ ]+@(pts|tty)/' | wc -l", shell=True, capture_output=True,text=True,timeout=3)
        return int(r.stdout.strip() or 0)
    except: return 0
def count_dropbear():
    try:
        r = subprocess.run("ps aux | grep '[d]ropbear' | wc -l", shell=True, capture_output=True,text=True,timeout=3)
        return max(0, int(r.stdout.strip() or 0) - 1)
    except: return 0
def count_v2ray():
    return 0
def count_openvpn():
    try:
        if os.path.exists("/etc/openvpn/server/openvpn-status.log"):
            r = subprocess.run("grep -c '^CLIENT_LIST' /etc/openvpn/server/openvpn-status.log", shell=True, capture_output=True,text=True,timeout=3)
            return int(r.stdout.strip() or 0)
    except: pass
    return 0
def count_udp():
    p, _, _ = read_config()
    try:
        r = subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'sport={p}'", shell=True, capture_output=True,text=True,timeout=5)
        ips = set()
        my_ip = subprocess.run("ip -o -4 route get 8.8.8.8 | awk '{print }'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
        for m in re.finditer(r'dst=(\d+\.\d+\.\d+\.\d+)', r.stdout):
            ip = m.group(1)
            if ip != my_ip and not ip.startswith("127."):
                ips.add(ip)
        return len(ips)
    except: return 0
def get_hysteria_ips():
    p, _, _ = read_config()
    ips = {}
    try:
        r = subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep -F 'dport={p}'", shell=True, capture_output=True,text=True,timeout=5)
        for m in re.finditer(r'src=(\d+\.\d+\.\d+\.\d+)', r.stdout):
            ip = m.group(1)
            if not ip.startswith("127.") and not ip.startswith("10.") and not ip.startswith("192.168."):
                ips[ip] = ips.get(ip, 0) + 1
    except: pass
    return ips
def get_vnstat_traffic():
    try:
        r = subprocess.run("vnstat --json a 2>/dev/null", shell=True, capture_output=True,text=True,timeout=5)
        if r.stdout:
            d = json.loads(r.stdout)
            return d["interfaces"][0]["traffic"]["total"]["rx"], d["interfaces"][0]["traffic"]["total"]["tx"]
    except: pass
    return 0, 0
def get_sysinfo():
    info = {}
    try:
            import re as _re
            _u=subprocess.run("uptime -p", shell=True, capture_output=True,text=True,timeout=3).stdout.strip().replace("up ","")
            _u=_u.strip().rstrip(",").strip()
            info["uptime"]=_u
    except: info["uptime"] = "N/A"
    try:
        r = subprocess.run("top -bn1 | awk '/Cpu\\(s\\)/ {print $8}'", shell=True, capture_output=True,text=True,timeout=3)
        info["cpu"] = f"{100 - float(r.stdout.strip() or 0):.1f}%"
    except: info["cpu"] = "N/A"
    try: info["ram"] = subprocess.run("free -m | awk 'NR==2{printf \"%s/%sMB\",$3,$2}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
    except: info["ram"] = "N/A"
    try: info["disk"] = subprocess.run("df -h / | awk 'NR==2{printf \"%s/%s\",$3,$2}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
    except: info["disk"] = "N/A"
    try: info["load"] = subprocess.run("cat /proc/loadavg | awk '{print $1}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
    except: info["load"] = "N/A"
    return info
def get_swap_info():
    try: return subprocess.run("free -h | awk '/Swap:/{print $2}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
    except: return "N/A"
def get_service_status(svc):
    try: return subprocess.run(f"systemctl is-active {svc}", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
    except: return "inactive"

# ══ Web ══
def is_web_running():
    try:
        r = subprocess.run(f"curl -s --connect-timeout 2 http://127.0.0.1:{WEB_PORT}/server/", shell=True, capture_output=True,text=True,timeout=3)
        return "IDA" in r.stdout or "ShowOn" in r.stdout
    except: return False

# ══ Menu ══
def show_menu():
    p, a, o = read_config(); ip = get_ip(); st = get_status()
    u = get_uptime()
    ssh = count_ssh(); v2r = count_v2ray(); ovpn = count_openvpn(); udp = count_udp()
    total = ssh + v2r + ovpn + udp
    stt = f"{G}ONLINE{NC}" if st=="active" else f"{R}OFFLINE{NC}"
    web_st = f"{G}ON{NC}" if is_web_running() else f"{R}OFF{NC}"
    os.system("clear")
    print()
    box()
    center(f"  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}  {WHT}IDA UDPHysteria{NC}  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}")
    center(f"{D}Hysteria v1 Server Manager — {G}{VERSION}{NC}")
    bsep()
    LW = 14
    for label, val in [("Server IP", ip), ("Port", f"{p} (10000-65000)"), ("Auth", a if a else "-"),
                       ("Obfs", o if o else "-"), ("Status", f"{stt}  Up:{u}"),
                       ("Version", f"{G}{VERSION}{NC} {D}(Gaming Fixed){NC}"),
                       ("Online", f"Total:{WHT}{total}{NC}  SSH:{WHT}{ssh}{NC}  V2R:{WHT}{v2r}{NC}  OVPN:{WHT}{ovpn}{NC}  UDP:{WHT}{udp}{NC}")]:
        bput(f"{D}{pad(label, LW)}{NC} : {val}")
    bput(f"  {R}\u258c{NC}{O}\u258c{NC}{Y}\u258c{NC}{G}\u258c{NC}{C}\u258c{NC}{B}\u258c{NC}{M}\u258c{NC}")
    bput(f"  {D}{'='*14}  {NC}SELECT OPTION{D}  {'='*14}{NC}")
    bput("")
    menu_row("01","📊","Connection Info","09","🔑","Edit AUTH")
    menu_row("02","🔄","Restart","10","🔏","Edit OBFS")
    menu_row("03","⛔","Stop","11","🔧","Change Port")
    menu_row("04","\U0001f680","Start","12","📶","Speed Test")
    menu_row("05","📜","View Logs","13","📺","Web Dashboard")
    menu_row("06","🔍","System Info","14","💾","Setup Swap")
    menu_row("07","📈","Traffic Stats","15","🎯","Change Limit")
    menu_row("08","🐛","Debug Log","16","📡","Update All")
    menu_row("00","🚪","Exit","17","🗑","Uninstall")
    bput("")
    bsep()
    bot()
    print()
    return input(f"  {Y}>>{NC} {BD}Choose{NC} {D}[00-18]{NC} : ").strip()

# ══ Screens ══
def show_info():
    p,a,o = read_config(); ip = get_ip()
    os.system("clear"); print(); box(); center(f"{G}\u2591{NC} {BD}Connection Info{NC}"); bsep()
    for l,v in [("Protocol","UDP Hysteria v1"),("Server",ip),("Port",f"{p} (10000-65000)"),
                ("Auth",a or "-"),("Obfs",o or "-"),("Config",HYST_CONFIG)]:
        bput(f"{D}{pad(l,12)}{NC} : {WHT}{v}{NC}")
    bput(""); bput(f"{D}Use this info in Creeb / v2 Box client{NC}")
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")
def do_restart():
    os.system("clear"); print(); box(); center(f"{Y}\u21bb{NC} {BD}Restart Hysteria{NC}"); bsep()
    subprocess.run(["systemctl","restart","hysteria"], capture_output=True,text=True,timeout=10)
    time.sleep(2)
    bput(f"{G}\u2705{NC} Restarted" if get_status()=="active" else f"{R}\u274C{NC} Failed")
    bsep(); bot(); print(); time.sleep(1.5)
def do_stop():
    os.system("clear"); print(); box(); center(f"{R}\u25a0{NC} {BD}Stop Hysteria{NC}"); bsep()
    subprocess.run(["systemctl","stop","hysteria"], capture_output=True,text=True,timeout=10)
    time.sleep(1); bput(f"{G}\u2705{NC} Stopped"); bsep(); bot(); print(); time.sleep(1.5)
def do_start():
    os.system("clear"); print(); box(); center(f"{G}\u25b6{NC} {BD}Start Hysteria{NC}"); bsep()
    subprocess.run(["systemctl","start","hysteria"], capture_output=True,text=True,timeout=10)
    time.sleep(2)
    bput(f"{G}\u2705{NC} Started" if get_status()=="active" else f"{R}\u274C{NC} Failed")
    bsep(); bot(); print(); time.sleep(1.5)
def view_logs():
    os.system("clear"); print(); box(); center(f"{C}\u2591{NC} {BD}Logs (Last 10 min){NC}"); bsep()
    r = subprocess.run(["journalctl","-u","hysteria","--no-pager","-n","30","--since","10 min ago"], capture_output=True,text=True,timeout=5)
    for line in r.stdout.strip().split("\n")[-20:]: bput(f"{D}{line[:54]}{NC}")
    if not r.stdout.strip(): bput(f"{D}  No recent logs{NC}")
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")
def sys_info():
    os.system("clear"); print(); box(); center(f"{M}\u25c8{NC} {BD}System Info{NC}"); bsep()
    si = get_sysinfo()
    for l,v in [("Hostname",subprocess.run("hostname -f",shell=True,capture_output=True,text=True,timeout=3).stdout.strip()),
                ("Kernel",subprocess.run("uname -r",shell=True,capture_output=True,text=True,timeout=3).stdout.strip()),
                ("Uptime",si["uptime"]),("CPU",si["cpu"]),("RAM",si["ram"]),("Disk",si["disk"]),
                ("Load",si["load"]),("NIC",get_nic()),("Swap",get_swap_info())]:
        bput(f"{D}{pad(l,12)}{NC} : {WHT}{v[:35]}{NC}")
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")
def traffic_stats():
    os.system("clear"); print(); box(); center(f"{G}\u2191{NC} {BD}Traffic Stats (vnStat){NC}"); bsep()
    rx, tx = get_vnstat_traffic()
    def fmt(b):
        if b >= 1073741824: return f"{b/1073741824:.1f} GB"
        if b >= 1048576: return f"{b/1048576:.1f} MB"
        if b >= 1024: return f"{b/1024:.1f} KB"
        return f"{b} B"
    bput(f"  {D}Download (Total){NC} : {WHT}{fmt(rx)}{NC}")
    bput(f"  {D}Upload (Total){NC}   : {WHT}{fmt(tx)}{NC}"); bput("")
    try:
        r = subprocess.run("vnstat -d 2>/dev/null | head -15", shell=True, capture_output=True,text=True,timeout=5)
        for line in r.stdout.strip().split("\n")[:12]: bput(f"  {D}{line[:54]}{NC}")
    except: pass
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")
def edit_auth():
    os.system("clear"); print(); box(); center(f"{M}\u25c0{NC} {BD}Edit AUTH{NC}"); bsep()
    _,old,_ = read_config()
    bput(f"Current AUTH : {WHT}{old}{NC}"); bput("")
    n = input(f"  {Y}>>{NC} New AUTH (empty=cancel) : ").strip()
    if not n: bput(f"{D}  Cancelled{NC}"); bsep(); bot(); print(); time.sleep(1); return
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["auth_str"] = n
        d["auth"] = {"mode": "passwords", "config": [n]}
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)
        subprocess.run(["systemctl","restart","hysteria"], capture_output=True,text=True,timeout=10)
        time.sleep(2); bput(f"{G}\u2705{NC} Updated"); bsep(); bot(); print(); time.sleep(2)
    except Exception as e: bput(f"{R}\u274C{NC} {e}"); bsep(); bot(); print(); time.sleep(2)
def edit_obfs():
    os.system("clear"); print(); box(); center(f"{M}\u25c0{NC} {BD}Edit OBFS{NC}"); bsep()
    _,_,old = read_config()
    bput(f"Current OBFS : {WHT}{old}{NC}"); bput("")
    n = input(f"  {Y}>>{NC} New OBFS (empty=cancel) : ").strip()
    if not n: bput(f"{D}  Cancelled{NC}"); bsep(); bot(); print(); time.sleep(1); return
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["obfs"] = n
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)
        subprocess.run(["systemctl","restart","hysteria"], capture_output=True,text=True,timeout=10)
        time.sleep(2); bput(f"{G}\u2705{NC} Updated"); bsep(); bot(); print(); time.sleep(2)
    except Exception as e: bput(f"{R}\u274C{NC} {e}"); bsep(); bot(); print(); time.sleep(2)
def change_port():
    os.system("clear"); print(); box(); center(f"{M}\u25c6{NC} {BD}Change Port{NC}"); bsep()
    p,_,_ = read_config()
    bput(f"Current Port : {WHT}{p}{NC}"); bput("")
    n = input(f"  {Y}>>{NC} New Port/Range (empty=cancel) : ").strip()
    if not n: bput(f"{D}  Cancelled{NC}"); bsep(); bot(); print(); time.sleep(1); return
    if "-" in n:
        parts = n.split("-", 1)
        if parts[0].isdigit() and parts[1].isdigit():
            lo, hi = int(parts[0]), int(parts[1])
            if 1 <= lo <= 65535 and 1 <= hi <= 65535 and lo <= hi:
                n = str(random.randint(lo, hi))
            else:
                bput(f"{R}\u274C{NC} Invalid range"); bsep(); bot(); print(); time.sleep(2); return
        else:
            bput(f"{R}\u274C{NC} Invalid range"); bsep(); bot(); print(); time.sleep(2); return
    elif not n.isdigit() or not (1 <= int(n) <= 65535):
        bput(f"{R}\u274C{NC} Invalid"); bsep(); bot(); print(); time.sleep(2); return
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["listen"] = f"{d.get('listen',':25000').rsplit(':',1)[0]}:{n}"
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)
        subprocess.run(["systemctl","restart","hysteria"], capture_output=True,text=True,timeout=10)
        time.sleep(2); bput(f"{G}\u2705{NC} Port changed to {n}"); bsep(); bot(); print(); time.sleep(2)
    except Exception as e: bput(f"{R}\u274C{NC} {e}"); bsep(); bot(); print(); time.sleep(2)
def speed_test():
    os.system("clear"); print(); box(); center(f"{G}\u25cb{NC} {BD}Speed Test{NC}"); bsep()
    bput(f"{D}  Testing download speed...{NC}")
    try:
        r = subprocess.run("curl -s -o /dev/null -w '%{speed_download}' https://speed.cloudflare.com/__down?bytes=10000000", shell=True, capture_output=True,text=True,timeout=30)
        mbps = float(r.stdout.strip().replace("'","")) * 8 / 1_000_000
        bput(f"  {WHT}{mbps:.1f} Mbps{NC} download")
    except: bput(f"  {R}Test failed{NC}")
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")

def web_dashboard():
    os.system("clear"); print(); box(); center(f"{C}\u25a3{NC} {BD}Web Dashboard{NC}"); bsep()
    ip = get_ip()
    for svc in ["nginx","online-check","vnstat-traffic","sysinfo"]:
        st = get_service_status(svc)
        # Check timer status for oneshot services
        if st != "active" and svc != "nginx":
            timer_st = "inactive"
            try: timer_st = subprocess.run(f"systemctl is-active {svc}.timer", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
            except: pass
            if timer_st == "active": st = "active"
        color = G if st=="active" else R
        bput(f"  {D}{svc}:{NC} {color}{st}{NC}")
    bput(f"  {D}Open:{NC} {WHT}http://{ip}:{WEB_PORT}/server/{NC}")
    bput(f"")
    menu_row("1","","Restart All","4","","Restart Nginx")
    menu_row("2","","Stop All","5","","Restart Online")
    menu_row("3","","Start All","0","","Back")
    bsep(); bot(); print()
    ch = input(f"  {Y}>>{NC} Choose: ").strip()
    if ch == "1":
        subprocess.run("systemctl restart nginx online-check vnstat-traffic sysinfo", shell=True, capture_output=True,timeout=10)
        time.sleep(2); bput(f"  {G}\u2705{NC} All restarted"); time.sleep(1.5)
    elif ch == "2":
        subprocess.run("systemctl stop nginx online-check vnstat-traffic sysinfo", shell=True, capture_output=True,timeout=10)
        time.sleep(1); bput(f"  {G}\u2705{NC} All stopped"); time.sleep(1.5)
    elif ch == "3":
        subprocess.run("systemctl start nginx online-check vnstat-traffic sysinfo", shell=True, capture_output=True,timeout=10)
        time.sleep(2); bput(f"  {G}\u2705{NC} All started"); time.sleep(1.5)
    elif ch == "4":
        subprocess.run("systemctl restart nginx", shell=True, capture_output=True,timeout=10)
        time.sleep(1); bput(f"  {G}\u2705{NC} Nginx restarted"); time.sleep(1.5)
    elif ch == "5":
        subprocess.run("systemctl restart online-check", shell=True, capture_output=True,timeout=10)
        time.sleep(1); bput(f"  {G}\u2705{NC} Online Check restarted"); time.sleep(1.5)

def setup_swap():
    os.system("clear"); print(); box(); center(f"{M}\u25a1{NC} {BD}Setup Swap{NC}"); bsep()
    ram_mb = 0
    try: ram_mb = int(subprocess.run("free -m | awk '/Mem:/{print $2}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip())
    except: pass
    if ram_mb <= 1024: swap_mb = ram_mb * 2
    elif ram_mb <= 4096: swap_mb = ram_mb
    else: swap_mb = 4096
    bput(f"  {D}RAM:{NC} {WHT}{ram_mb}MB{NC}  {D}Swap:{NC} {WHT}{swap_mb}MB{NC}"); bput("")
    ch = input(f"  {Y}>>{NC} Create swap {swap_mb}MB? (Y/n): ").strip()
    if ch and ch.lower() != "y": return
    try:
        subprocess.run("swapoff -a 2>/dev/null", shell=True, capture_output=True,timeout=5)
        subprocess.run(f"fallocate -l {swap_mb}M {SWAP_FILE} 2>/dev/null || dd if=/dev/zero of={SWAP_FILE} bs=1M count={swap_mb}", shell=True, capture_output=True,timeout=60)
        subprocess.run(f"chmod 600 {SWAP_FILE} && mkswap {SWAP_FILE} && swapon {SWAP_FILE}", shell=True, capture_output=True,timeout=10)
        subprocess.run(f"grep -q '{SWAP_FILE}' /etc/fstab || echo '{SWAP_FILE} none swap sw 0 0' >> /etc/fstab", shell=True, capture_output=True,timeout=3)
        bput(f"  {G}\u2705{NC} Swap created: {swap_mb}MB")
    except Exception as e: bput(f"  {R}\u274C{NC} {e}")
    bsep(); bot(); print()

def debug_log():
    os.system("clear"); print(); box(); center(f"{M}\u2022{NC} {BD}Debug Log{NC}"); bsep()
    for lf in ["/var/log/ida-debug.log", "/var/log/showon-debug.log"]:
        if os.path.exists(lf):
            r = subprocess.run(f"tail -n 30 {lf}", shell=True, capture_output=True,text=True,timeout=5)
            for line in r.stdout.strip().split("\n")[:25]: bput(f"{D}{line[:54]}{NC}")
            break
    else: bput(f"  {D}No debug log found{NC}")
    bsep(); bot(); print(); input(f"  {B}Press Enter{NC} ")

def change_limit():
    os.system("clear"); print(); box(); center(f"{M}●{NC} {BD}Change Limit User Online{NC}"); bsep()
    current = "2000"
    if os.path.exists(SHOWON_CONF):
        try:
            with open(SHOWON_CONF) as f:
                for line in f:
                    if line.startswith("LIMIT="): current = line.split("=")[1].strip()
        except: pass
    bput(f"  {D}Current:{NC} {WHT}{current}{NC}")
    bput(f"  {Y}>>{NC} New Limit (empty=cancel) :  ")
    bsep(); bot(); print()
    n = input(f"  {Y}>>{NC} ").strip()
    print()
    if not n: bput(f"{D}  Cancelled{NC}"); bsep(); bot(); print(); return
    if not n.isdigit(): print(); box(); center(f"{M}\u25cf{NC} {BD}Change Limit User Online{NC}"); bsep(); bput(f"{R}\u274C{NC} Invalid"); bsep(); bot(); print(); time.sleep(2); return
    try:
        if os.path.exists(SHOWON_CONF):
            with open(SHOWON_CONF) as f: content = f.read()
            content = re.sub(r'^LIMIT=.*$', f'LIMIT={n}', content, flags=re.MULTILINE)
            with open(SHOWON_CONF, 'w') as f: f.write(content)
        subprocess.run("systemctl restart online-check", shell=True, capture_output=True,timeout=5)
        print(); box(); center(f"{M}\u25cf{NC} {BD}Change Limit User Online{NC}"); bsep(); bput(f"  {D}Current:{NC} {WHT}{current}{NC}"); bput(f"  {G}\u2705{NC} Limit changed to {n}")
    except Exception as e: print(); box(); center(f"{M}\u25cf{NC} {BD}Change Limit User Online{NC}"); bsep(); bput(f"  {D}Current:{NC} {WHT}{current}{NC}"); bput(f"{R}\u274C{NC} {e}")
    bsep(); bot(); print(); time.sleep(2)

def auto_fix_gaming():
    # 1. Ensure disable_mtu_discovery=true for gaming/UDP stability (2 spaces prevent old sed revert)
    try:
        for cfg in [HYST_CONFIG, "/opt/hysteria/config.json", "/etc/hysteria/config.json", "/etc/hysteria/config-v1.json"]:
            if os.path.exists(cfg):
                with open(cfg, 'r') as f: content = f.read()
                if '"disable_mtu_discovery": false' in content or '"disable_mtu_discovery": true' in content or '"disable_mtu_discovery"' not in content:
                    content = re.sub(r'"disable_mtu_discovery"\s*:\s*(false|true)', '"disable_mtu_discovery":  true', content)
                    if '"disable_mtu_discovery"' not in content:
                        content = content.rstrip().rstrip('}') + ',\n  "disable_mtu_discovery":  true\n}'
                    with open(cfg, 'w') as f: f.write(content)
                    subprocess.run("systemctl restart hysteria 2>/dev/null", shell=True)
    except: pass

    # 2. Ensure BadVPN (7100, 7200, 7300) is running for Roblox / game UDP gateway
    try:
        r = subprocess.run("systemctl is-active badvpn3", shell=True, capture_output=True, text=True)
        if r.stdout.strip() != "active":
            subprocess.run("rm -f /etc/systemd/system/badvpn101.service /etc/systemd/system/badvpn201.service 2>/dev/null", shell=True)
            subprocess.run("command -v /usr/sbin/badvpn >/dev/null 2>&1 || (wget -q -O /usr/sbin/badvpn https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn && chmod +x /usr/sbin/badvpn)", shell=True)
            for p in [7100, 7200, 7300]:
                idx = (p - 7000) // 100
                svc = f"[Unit]\nDescription=UDP {p}\nAfter=syslog.target network-online.target\n\n[Service]\nUser=root\nNoNewPrivileges=true\nExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:{p} --max-clients 500\nRestart=on-failure\nRestartPreventExitStatus=23\nLimitNPROC=10000\nLimitNOFILE=1000000\n\n[Install]\nWantedBy=multi-user.target\n"
                with open(f"/etc/systemd/system/badvpn{idx}.service", "w") as f: f.write(svc)
            subprocess.run("systemctl daemon-reload && systemctl enable --now badvpn1 badvpn2 badvpn3 2>/dev/null", shell=True)
    except: pass

    # 3. Ensure Sysctl UDP Buffer (8MB) & Ephemeral Port Range
    try:
        if not os.path.exists("/etc/sysctl.d/99-hysteria.conf"):
            cfg = "net.core.rmem_max = 8388608\nnet.core.wmem_max = 8388608\nnet.core.rmem_default = 8388608\nnet.core.wmem_default = 8388608\nnet.ipv4.ip_local_port_range = 1024 9999\nnet.ipv4.ip_forward = 1\n"
            with open("/etc/sysctl.d/99-hysteria.conf", "w") as f: f.write(cfg)
            subprocess.run("sysctl -p /etc/sysctl.d/99-hysteria.conf 2>/dev/null", shell=True)
    except: pass

def update_dashboard():
    os.system("clear"); print(); box(); center(f"{G}\u21bb{NC} {BD}Update Scripts & Game Fix{NC}"); bsep()
    bput(f"  {D}Running update script & applying game fixes...{NC}")
    bsep()
    try:
        subprocess.run("curl -sL 'https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/update.sh?t='$(date +%s) | bash", shell=True)
    except Exception as e:
        print(f"  {R}Error: {e}{NC}")
    bsep(); bot(); print()
    print(f"  {G}✅ Update completed! Reloading menu...{NC}")
    time.sleep(2)
    try:
        os.execv(sys.executable, [sys.executable, "/opt/hysteria/menu.py"])
    except:
        input(f"  {B}Press Enter to return to menu...{NC} ")

def uninstall_dashboard():
    os.system("clear"); print(); box(); center(f"{R}\u2716{NC} {BD}Uninstall Dashboard{NC}"); bsep()
    bput(f"  {D}Remove all dashboard services?{NC}"); bput("")
    ch = input(f"  {Y}>>{NC} Confirm (y/N) : ").strip()
    if ch.lower() != "y": bput(f"{D}  Cancelled{NC}"); bsep(); bot(); print(); return
    try:
        subprocess.run("systemctl stop online-check vnstat-traffic sysinfo 2>/dev/null", shell=True, capture_output=True,timeout=5)
        subprocess.run("systemctl disable online-check vnstat-traffic sysinfo 2>/dev/null", shell=True, capture_output=True,timeout=5)
        subprocess.run("rm -f /etc/systemd/system/online-check.service /etc/systemd/system/sysinfo.service /etc/systemd/system/vnstat-traffic.service", shell=True, capture_output=True,timeout=5)
        subprocess.run("rm -f /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh", shell=True, capture_output=True,timeout=5)
        subprocess.run("rm -f /etc/showon.conf /var/log/ida-debug.log /etc/ida-version", shell=True, capture_output=True,timeout=5)
        subprocess.run("sed -i '/==== IDA AUTOCONFIG BEGIN ====/,/==== IDA AUTOCONFIG END ====/d' /etc/nginx/conf.d/vps.conf 2>/dev/null", shell=True, capture_output=True,timeout=5)
        subprocess.run("systemctl daemon-reload && systemctl restart nginx 2>/dev/null", shell=True, capture_output=True,timeout=5)
        bput(f"  {G}\u2705{NC} Uninstalled!")
    except Exception as e: bput(f"{R}\u274C{NC} {e}")
    bsep(); bot(); print(); time.sleep(2)

# ══ Main ══
if __name__ == "__main__":
    os.system("chmod 600 " + HYST_CONFIG + " 2>/dev/null")
    auto_fix_gaming()
    while True:
        try:
            ch = show_menu()
            if ch == "01": show_info()
            elif ch == "02": do_restart()
            elif ch == "03": do_stop()
            elif ch == "04": do_start()
            elif ch == "05": view_logs()
            elif ch == "06": sys_info()
            elif ch == "07": traffic_stats()
            elif ch == "08": debug_log()
            elif ch == "09": edit_auth()
            elif ch == "10": edit_obfs()
            elif ch == "11": change_port()

            elif ch == "12": speed_test()
            elif ch == "13": web_dashboard()
            elif ch == "14": setup_swap()
            elif ch == "15": change_limit()
            elif ch == "16": update_dashboard()
            elif ch == "17": uninstall_dashboard()
            elif ch == "00":

                os.system("clear"); print()
                box(); center(f"{G}\U0001f44b{NC} {BD}Thank You - IDA UDPHysteria{NC}"); bot()
                print(); break
        except KeyboardInterrupt: break
        except Exception as e:
            print(f"  {R}Error: {e}{NC}"); time.sleep(2)
    os.system("clear"); print(); box(); center(f"{G}\U0001f44b{NC} {BD}Thank You - IDA UDPHysteria{NC}"); bot(); print()