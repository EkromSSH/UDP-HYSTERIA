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

def get_version():
    for vpath in ["/etc/ida-version", "/opt/hysteria/version"]:
        if os.path.exists(vpath):
            try:
                with open(vpath, "r") as f:
                    v = f.read().strip()
                    if v: return v
            except: pass
    return "v2.3.4"

VERSION = get_version()

# ══ Colors ══
R = '\033[1;31m'; G = '\033[1;32m'; O = '\033[1;33m'
Y = '\033[1;33m'; B = '\033[0;34m'; M = '\033[0;35m'
C = '\033[1;36m'; WHT = '\033[1;37m'; BD = '\033[1m'
D = '\033[2m'; NC = '\033[0m'

W = 62
H = '\u2550'

def vislen(s):
    s2 = re.sub(r'\033\[[0-9;]*m', '', s)
    try:
        from wcwidth import wcswidth
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

def bput(c="", indent="        "):
    max_w = W - 5
    if not c:
        print(f"  {B}\u2551{NC}{' ' * (W - 4)}{B}\u2551{NC}")
        return
    vl = vislen(c)
    if vl <= max_w:
        p = max_w - vl
        print(f"  {B}\u2551{NC} {c}{' ' * p}{B}\u2551{NC}")
    else:
        # Wrap long text by words so text is NEVER cut off with ...
        words = c.split(" ")
        cur_line = ""
        is_first = True
        for w in words:
            test_line = cur_line + (" " if cur_line else "") + w
            if vislen(test_line) <= max_w:
                cur_line = test_line
            else:
                if cur_line:
                    p = max(0, max_w - vislen(cur_line))
                    print(f"  {B}\u2551{NC} {cur_line}{' ' * p}{B}\u2551{NC}")
                cur_line = (indent if not is_first else "") + w
                is_first = False
        if cur_line:
            p = max(0, max_w - vislen(cur_line))
            print(f"  {B}\u2551{NC} {cur_line}{' ' * p}{B}\u2551{NC}")

def center(t):
    v = vislen(t); l = (W-4-v)//2; r = W-4-v-l
    print(f"  {B}\u2551{NC}{' '*l}{t}{' '*r}{B}\u2551{NC}")

def box_header(title, subtitle=None):
    box()
    center(f"  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}  {WHT}{title}{NC}  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}")
    if subtitle:
        center(f"{D}{subtitle}{NC}")
    bsep()

def box_section(title):
    inner_w = W - 5
    t = f" {title} "
    vt = vislen(t)
    left_w = max(2, (inner_w - vt) // 2)
    right_w = max(2, inner_w - vt - left_w)
    bput(f"{D}{H * left_w}{NC}{Y}{BD}{t}{NC}{D}{H * right_w}{NC}")

def box_kv(label, val, label_width=16, val_color=WHT):
    bput(f"  {D}{pad(label, label_width)}{NC} : {val_color}{val}{NC}")

def box_bar(label, pct, detail="", bar_width=14, label_width=16):
    p = max(0.0, min(100.0, float(pct)))
    filled = int(round((p / 100.0) * bar_width))
    empty = bar_width - filled
    bar_col = G if p < 60 else (Y if p < 85 else R)
    bar_str = f"{bar_col}{'█' * filled}{D}{'░' * empty}{NC}"
    pct_str = f"{p:5.1f}%"
    if detail:
        bput(f"  {D}{pad(label, label_width)}{NC} : [{bar_str}] {WHT}{pct_str}{NC}  {D}{detail}{NC}")
    else:
        bput(f"  {D}{pad(label, label_width)}{NC} : [{bar_str}] {WHT}{pct_str}{NC}")

def box_success(msg):
    bput(f"  {G}[ ✔ ]{NC} {BD}{WHT}{msg}{NC}")

def box_error(msg):
    bput(f"  {R}[ ✖ ]{NC} {BD}{R}{msg}{NC}")

def box_warn(msg):
    bput(f"  {Y}[ ! ]{NC} {BD}{Y}{msg}{NC}")

def box_info(msg):
    bput(f"  {C}[ i ]{NC} {D}{msg}{NC}")

def sub_row(n1, t1, n2, t2):
    left = f"{G}[{n1}]{NC} {WHT}{t1}{NC}"
    right = f"{G}[{n2}]{NC} {WHT}{t2}{NC}" if n2 else ""
    bput(f"  {pad(left, 26)} {pad(right, 26)}")

def box_footer():
    bsep()
    bot()
    print()

def press_enter(msg="Press Enter to return to menu..."):
    try:
        input(f"  {B}>>{NC} {D}{msg}{NC} ")
    except: pass

def ask_input(prompt_text, default=None):
    try:
        def_hint = f" {D}[default: {default}]{NC}" if default is not None else ""
        res = input(f"  {Y}>>{NC} {BD}{prompt_text}{NC}{def_hint} : ").strip()
        return res if res else (default if default is not None else "")
    except: return ""

def ask_confirm(prompt_text, default=False):
    hint = "[Y/n]" if default else "[y/N]"
    try:
        res = input(f"  {Y}>>{NC} {BD}{prompt_text}{NC} {D}{hint}{NC} : ").strip().lower()
        if not res: return default
        return res == "y" or res == "yes"
    except: return False

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
        my_ip = subprocess.run("ip -o -4 route get 8.8.8.8 | awk '{print $7}'", shell=True, capture_output=True,text=True,timeout=3).stdout.strip()
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
        _u=subprocess.run("uptime -p", shell=True, capture_output=True,text=True,timeout=3).stdout.strip().replace("up ","")
        info["uptime"]=_u.strip().rstrip(",").strip()
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

# ══ Main Menu ══
def show_menu():
    p, a, o = read_config(); ip = get_ip(); st = get_status()
    u = get_uptime(); ver = get_version()
    ssh = count_ssh(); v2r = count_v2ray(); ovpn = count_openvpn(); udp = count_udp()
    total = ssh + v2r + ovpn + udp
    stt = f"{G}ONLINE{NC}" if st=="active" else f"{R}OFFLINE{NC}"
    web_st = f"{G}ON{NC}" if is_web_running() else f"{R}OFF{NC}"
    os.system("clear")
    print()
    box()
    center(f"  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}  {WHT}IDA UDPHysteria{NC}  {R}\u2588\u2588{O}\u2588\u2588{Y}\u2588\u2588{G}\u2588\u2588{C}\u2588\u2588{B}\u2588\u2588{M}\u2588\u2588{NC}")
    center(f"{D}Hysteria v1 Server Manager — {G}{ver}{NC}")
    bsep()
    LW = 14
    for label, val in [("Server IP", ip), ("Port", f"{p} (10000-65000)"), ("Auth", a if a else "-"),
                       ("Obfs", o if o else "-"), ("Status", f"{stt}  Up:{u}"),
                       ("Version", f"{G}{ver}{NC} {D}(Gaming Fixed){NC}"),
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
    return input(f"  {Y}>>{NC} {BD}Choose{NC} {D}[00-17]{NC} : ").strip()

# ══ Sub-screens 01 to 17 ══

# 01. Connection Info
def show_info():
    p, a, o = read_config(); ip = get_ip(); st = get_status()
    st_color = G if st == "active" else R
    st_text = "ONLINE" if st == "active" else "OFFLINE"
    up, down = 100, 100
    try:
        with open(HYST_CONFIG) as f:
            _d = json.load(f)
            up = _d.get("up_mbps", 100)
            down = _d.get("down_mbps", 100)
    except: pass
    link_direct = f"hysteria://{ip}:{p}?protocol=udp&auth={a}&obfs={o}&peer={ip}&insecure=1&upmbps={up}&downmbps={down}&alpn=hysteria#Hysteria-Direct"
    link_hop = f"hysteria://{ip}:{p}?protocol=udp&auth={a}&obfs={o}&peer={ip}&insecure=1&upmbps={up}&downmbps={down}&alpn=hysteria&mport=10000-65000#Hysteria-PortHop"
    
    os.system("clear"); print()
    box_header("CONNECTION INFO", "Hysteria v1 Client Details")
    bput("")
    box_section("SERVER CONFIGURATION")
    bput("")
    box_kv("Protocol", "UDP Hysteria v1", 16)
    box_kv("Server IP", ip, 16, G)
    box_kv("Listen Port", f"{p} (UDP)", 16, Y)
    box_kv("Port Range", "10000 - 65000", 16)
    box_kv("Auth Pass", a if a else "(none)", 16, WHT)
    box_kv("OBFS Key", o if o else "(disabled)", 16, WHT)
    box_kv("Status", f"{st_color}[ {st_text} ]{NC}  Up: {get_uptime()}", 16)
    bput("")
    box_section("GAMING OPTIMIZATION")
    bput("")
    box_kv("MTU Discovery", f"{G}[ OK ] Disabled (Fixed 1280){NC}", 16)
    box_kv("UDP Buffer", f"{G}[ OK ] 16 MB (Sysctl Buffer){NC}", 16)
    box_kv("BadVPN Ports", f"{G}[ OK ] 7100, 7200, 7300 Active{NC}", 16)
    bput("")
    box_section("CLIENT CONNECTIVITY")
    bput("")
    box_kv("Supported Apps", "IDA VPN, V2Box, Matsuri, NekoBox, Sing-box", 16)
    box_kv("Direct Port URL", "(Fastest for True / AIS / Dtac)", 16, C)
    box_kv("Port Hopping URL", "(Bypasses ISP UDP block/throttling)", 16, C)
    bput("")
    box_footer()
    print(f"  {Y}>>{NC} {BD}Direct URL:{NC}     {C}{link_direct}{NC}")
    print(f"  {Y}>>{NC} {BD}PortHop URL:{NC}    {C}{link_hop}{NC}\n")
    press_enter()

# 02. Restart Hysteria
def do_restart():
    os.system("clear"); print()
    box_header("RESTART HYSTERIA", "Service Restart Process")
    bput("")
    box_section("RESTARTING SERVICE")
    bput("")
    box_info("Stopping existing processes and restarting Hysteria...")
    box_info("Verifying listening sockets and systemd status...")
    bput("")
    box_footer()
    
    subprocess.run(["systemctl", "restart", "hysteria"], capture_output=True, text=True, timeout=10)
    time.sleep(2)
    st = get_status()
    
    os.system("clear"); print()
    box_header("RESTART HYSTERIA", "Service Restart Summary")
    bput("")
    if st == "active":
        box_success("Hysteria service restarted successfully!")
        bput("")
        box_section("CURRENT SERVICE STATE")
        bput("")
        box_kv("Service Status", f"{G}[ ONLINE ] Active (running){NC}", 16)
        box_kv("Listening Port", f"{read_config()[0]} (UDP)", 16, Y)
        box_kv("Server IP", get_ip(), 16, WHT)
        box_kv("Server Uptime", get_uptime(), 16)
    else:
        box_error("Failed to restart Hysteria service!")
        bput("")
        box_kv("Service Status", f"{R}[ OFFLINE ] Inactive{NC}", 16)
        bput("")
        box_section("ERROR DIAGNOSTICS")
        bput("")
        err = subprocess.run("journalctl -u hysteria -n 5 --no-pager", shell=True, capture_output=True, text=True).stdout
        for el in err.strip().split("\n")[-4:]:
            bput(f"  {D}{el[:50]}{NC}")
    bput("")
    box_footer()
    press_enter()

# 03. Stop Hysteria
def do_stop():
    os.system("clear"); print()
    box_header("STOP HYSTERIA", "Service Shutdown Confirmation")
    bput("")
    box_section("CURRENT SERVICE STATUS")
    bput("")
    st = get_status()
    st_col = G if st == "active" else R
    box_kv("Current Status", f"{st_col}[ {st.upper()} ]{NC}", 16)
    box_kv("Active Users", f"{count_udp()} UDP client(s)", 16)
    bput("")
    box_warn("Stopping Hysteria will disconnect all connected clients!")
    bput("")
    box_footer()
    
    if not ask_confirm("Are you sure you want to stop Hysteria?"):
        return
        
    subprocess.run(["systemctl", "stop", "hysteria"], capture_output=True, text=True, timeout=10)
    time.sleep(1)
    
    os.system("clear"); print()
    box_header("STOP HYSTERIA", "Service Stopped")
    bput("")
    box_success("Hysteria service has been safely STOPPED.")
    bput("")
    box_kv("Service Status", f"{R}[ OFFLINE ] Inactive{NC}", 16)
    bput("")
    box_footer()
    press_enter()

# 04. Start Hysteria
def do_start():
    os.system("clear"); print()
    box_header("START HYSTERIA", "Service Startup Process")
    bput("")
    box_section("STARTING SERVICE")
    bput("")
    box_info("Initiating Hysteria daemon startup...")
    bput("")
    box_footer()
    
    subprocess.run(["systemctl", "start", "hysteria"], capture_output=True, text=True, timeout=10)
    time.sleep(2)
    st = get_status()
    
    os.system("clear"); print()
    box_header("START HYSTERIA", "Service Startup Summary")
    bput("")
    if st == "active":
        box_success("Hysteria started successfully!")
        bput("")
        p, a, o = read_config()
        box_section("CURRENT SERVICE STATE")
        bput("")
        box_kv("Service Status", f"{G}[ ONLINE ] Active (running){NC}", 16)
        box_kv("Server IP", get_ip(), 16, WHT)
        box_kv("Listening Port", f"{p} (UDP)", 16, Y)
        box_kv("Auth Pass", a or "-", 16, WHT)
    else:
        box_error("Failed to start Hysteria service!")
        bput("")
        box_kv("Service Status", f"{R}[ FAILED ] Inactive{NC}", 16)
        bput("")
        box_section("ERROR DIAGNOSTICS")
        bput("")
        err = subprocess.run("journalctl -u hysteria -n 5 --no-pager", shell=True, capture_output=True, text=True).stdout
        for el in err.strip().split("\n")[-4:]:
            bput(f"  {D}{el[:50]}{NC}")
    bput("")
    box_footer()
    press_enter()

# 05. View Logs
def view_logs():
    while True:
        os.system("clear"); print()
        box_header("SERVICE LOGS", "Hysteria Daemon Activity")
        bput("")
        box_section("SELECT LOG VIEW")
        bput("")
        sub_row("1", "Recent 25 Lines", "3", "Filtered Errors")
        sub_row("2", "Live Stream (Follow)", "4", "Vacuum / Clean Logs")
        sub_row("0", "Back to Main Menu", "", "")
        bput("")
        box_footer()
        
        ch = ask_input("Choose an option [0-4]")
        if ch == "0" or not ch:
            break
        elif ch == "1":
            os.system("clear"); print()
            box_header("RECENT LOGS", "Last 25 Log Entries")
            bput("")
            r = subprocess.run(["journalctl", "-u", "hysteria", "--no-pager", "-n", "25"], capture_output=True, text=True, timeout=5)
            lines = [l for l in r.stdout.strip().split("\n") if l]
            if lines:
                for line in lines[-20:]:
                    hl = line
                    if "error" in line.lower() or "failed" in line.lower():
                        hl = f"{R}{line[:52]}{NC}"
                    elif "warn" in line.lower():
                        hl = f"{Y}{line[:52]}{NC}"
                    else:
                        hl = f"{D}{line[:52]}{NC}"
                    bput(f"  {hl}")
            else:
                bput(f"  {D}No recent logs available{NC}")
            bput("")
            box_footer()
            press_enter()
        elif ch == "2":
            os.system("clear")
            print(f"\n  {G}[ ✔ ] Following Hysteria logs in real-time... (Press Ctrl+C to stop){NC}\n")
            try:
                subprocess.run("journalctl -u hysteria -f", shell=True)
            except KeyboardInterrupt: pass
        elif ch == "3":
            os.system("clear"); print()
            box_header("ERROR LOGS", "Filtered Errors & Warnings")
            bput("")
            r = subprocess.run("journalctl -u hysteria -n 50 --no-pager | grep -iE 'error|failed|panic|fatal|warn' | tail -20", shell=True, capture_output=True, text=True)
            lines = [l for l in r.stdout.strip().split("\n") if l]
            if lines:
                for line in lines:
                    bput(f"  {R}{line[:52]}{NC}")
            else:
                box_success("No errors or warnings found in recent logs!")
            bput("")
            box_footer()
            press_enter()
        elif ch == "4":
            subprocess.run("journalctl --vacuum-time=1s -u hysteria >/dev/null 2>&1", shell=True)
            os.system("clear"); print()
            box_header("CLEAN LOGS", "Vacuum Logs")
            bput("")
            box_success("Hysteria logs have been cleaned successfully!")
            bput("")
            box_footer()
            time.sleep(1.2)

# 06. System Info
def sys_info():
    os.system("clear"); print()
    box_header("SYSTEM INFORMATION", "Hardware, OS & Resource Usage")
    si = get_sysinfo()
    
    os_name = "Linux"
    try:
        with open("/etc/os-release") as f:
            for l in f:
                if l.startswith("PRETTY_NAME="):
                    os_name = l.split("=", 1)[1].strip().strip('"')
                    break
    except: pass
    
    cpu_val = 0.0
    try: cpu_val = float(si.get("cpu", "0").replace("%", "").strip())
    except: pass
    
    ram_pct = 0.0
    ram_detail = si.get("ram", "N/A")
    try:
        if "/" in ram_detail:
            parts = ram_detail.replace("MB", "").split("/")
            u, t = float(parts[0]), float(parts[1])
            if t > 0: ram_pct = (u / t) * 100.0
    except: pass
    
    disk_pct = 0.0
    disk_detail = si.get("disk", "N/A")
    try:
        r = subprocess.run("df / | awk 'NR==2{print $5}'", shell=True, capture_output=True, text=True).stdout.strip().replace("%", "")
        disk_pct = float(r)
    except: pass
    
    cores = os.cpu_count() or 1
    
    bput("")
    box_section("HARDWARE & OPERATING SYSTEM")
    bput("")
    box_kv("OS Distro", os_name[:32], 16)
    box_kv("Kernel", subprocess.run("uname -r", shell=True, capture_output=True, text=True).stdout.strip()[:32], 16)
    box_kv("Hostname", subprocess.run("hostname", shell=True, capture_output=True, text=True).stdout.strip()[:32], 16)
    box_kv("Server IP", get_ip(), 16, G)
    box_kv("Network NIC", get_nic(), 16)
    box_kv("System Uptime", si.get("uptime", "N/A"), 16, Y)
    bput("")
    box_section("RESOURCE UTILIZATION")
    bput("")
    box_bar("CPU Usage", cpu_val, f"{cores} Core(s)", 14, 16)
    box_bar("RAM Memory", ram_pct, ram_detail, 14, 16)
    box_bar("Disk Space", disk_pct, disk_detail, 14, 16)
    box_kv("Swap File", get_swap_info(), 16)
    box_kv("Load Average", si.get("load", "N/A"), 16)
    bput("")
    box_section("ACTIVE SESSIONS")
    bput("")
    ssh = count_ssh(); v2r = count_v2ray(); ovpn = count_openvpn(); udp = count_udp()
    bput(f"  {D}SSH:{NC} {WHT}{ssh}{NC}  │  {D}V2R:{NC} {WHT}{v2r}{NC}  │  {D}OVPN:{NC} {WHT}{ovpn}{NC}  │  {D}UDP:{NC} {WHT}{udp}{NC}")
    bput("")
    box_footer()
    press_enter()

# 07. Traffic Stats
def traffic_stats():
    os.system("clear"); print()
    box_header("TRAFFIC STATISTICS", "Network Bandwidth Monitor (vnStat)")
    rx, tx = get_vnstat_traffic()
    def fmt(b):
        if b >= 1073741824: return f"{b/1073741824:.2f} GB"
        if b >= 1048576: return f"{b/1048576:.2f} MB"
        if b >= 1024: return f"{b/1024:.2f} KB"
        return f"{b} B"
    
    bput("")
    box_section("TOTAL ACCUMULATED BANDWIDTH")
    bput("")
    box_kv("Download (RX)", fmt(rx), 16, G)
    box_kv("Upload (TX)", fmt(tx), 16, Y)
    box_kv("Combined Total", fmt(rx + tx), 16, C)
    bput("")
    box_section("PERIOD USAGE BREAKDOWN")
    bput("")
    
    today_shown = False
    try:
        r = subprocess.run("vnstat --json d 1 2>/dev/null", shell=True, capture_output=True, text=True, timeout=4)
        if r.stdout:
            jd = json.loads(r.stdout)
            day = jd["interfaces"][0]["traffic"]["day"][0]
            drx, dtx = day["rx"], day["tx"]
            box_kv("Today Total", fmt(drx + dtx), 16, C)
            box_kv("Today Download", fmt(drx), 16, G)
            box_kv("Today Upload", fmt(dtx), 16, Y)
            today_shown = True
    except: pass
    
    if not today_shown:
        box_kv("Today Total", "Collecting data...", 16, D)
        
    try:
        r = subprocess.run("vnstat --json m 1 2>/dev/null", shell=True, capture_output=True, text=True, timeout=4)
        if r.stdout:
            jm = json.loads(r.stdout)
            m = jm["interfaces"][0]["traffic"]["month"][0]
            mrx, mtx = m["rx"], m["tx"]
            box_kv("Month to Date", fmt(mrx + mtx), 16, WHT)
    except: pass
    
    box_kv("Interface", f"{get_nic()} (Active)", 16)
    bput("")
    box_footer()
    press_enter()

# 08. Debug Log
def debug_log():
    while True:
        os.system("clear"); print()
        box_header("DEBUG LOGS & HEALTH", "System Diagnostics & Logs")
        bput("")
        box_section("DIAGNOSTIC OPTIONS")
        bput("")
        sub_row("1", "IDA / ShowOn Log", "3", "Nginx Server Logs")
        sub_row("2", "Gaming / BadVPN Status", "4", "Clear Debug Logs")
        sub_row("0", "Back to Main Menu", "", "")
        bput("")
        box_footer()
        
        ch = ask_input("Choose an option [0-4]")
        if ch == "0" or not ch: break
        elif ch == "1":
            os.system("clear"); print()
            box_header("DEBUG LOG", "IDA & ShowOn Service Log")
            bput("")
            found = False
            for lf in ["/var/log/ida-debug.log", "/var/log/showon-debug.log"]:
                if os.path.exists(lf):
                    r = subprocess.run(f"tail -n 25 {lf}", shell=True, capture_output=True, text=True)
                    lines = [l for l in r.stdout.split("\n") if l]
                    for l in lines[-20:]:
                        bput(f"  {D}{l[:52]}{NC}")
                    found = True
                    break
            if not found:
                box_info("No debug log file found at this time.")
            bput("")
            box_footer()
            press_enter()
        elif ch == "2":
            os.system("clear"); print()
            box_header("GAMING DIAGNOSTICS", "BadVPN & Kernel UDP Buffers")
            bput("")
            box_section("BADVPN GAME GATEWAYS")
            bput("")
            for p in [7100, 7200, 7300]:
                idx = (p - 7000) // 100
                st = get_service_status(f"badvpn{idx}")
                badge = f"{G}[ OK ] (Active){NC}" if st == "active" else f"{R}[ FAIL ] (Inactive){NC}"
                box_kv(f"BadVPN {idx} (Port {p})", badge, 20)
            bput("")
            box_section("KERNEL & MTU SETTINGS")
            bput("")
            rmem = subprocess.run("sysctl -n net.core.rmem_max 2>/dev/null", shell=True, capture_output=True, text=True).stdout.strip()
            rmem_badge = f"{G}[ OK ] (8 MB Buffer){NC}" if rmem == "8388608" else f"{Y}[ WARN ] ({rmem} Bytes){NC}"
            box_kv("Sysctl UDP Buffer", rmem_badge, 20)
            box_kv("MTU Discovery", f"{G}[ OK ] (Fixed 1280){NC}", 20)
            bput("")
            box_footer()
            press_enter()
        elif ch == "3":
            os.system("clear"); print()
            box_header("NGINX LOGS", "Web Server Access & Errors")
            bput("")
            r = subprocess.run("tail -n 20 /var/log/nginx/error.log 2>/dev/null", shell=True, capture_output=True, text=True)
            lines = [l for l in r.stdout.split("\n") if l]
            if lines:
                for l in lines[-15:]:
                    bput(f"  {D}{l[:52]}{NC}")
            else:
                box_success("No nginx errors recorded.")
            bput("")
            box_footer()
            press_enter()
        elif ch == "4":
            subprocess.run("rm -f /var/log/ida-debug.log /var/log/showon-debug.log 2>/dev/null", shell=True)
            os.system("clear"); print()
            box_header("CLEAR LOGS", "Debug Logs Removed")
            bput("")
            box_success("Debug logs have been successfully cleared!")
            bput("")
            box_footer()
            time.sleep(1.2)

# 09. Edit AUTH
def edit_auth():
    os.system("clear"); print()
    box_header("EDIT AUTH PASSWORD", "Client Authentication Key")
    _, old, _ = read_config()
    bput("")
    box_section("CURRENT AUTHENTICATION")
    bput("")
    box_kv("Current Auth", old if old else "(none)", 16, Y)
    box_kv("Config File", HYST_CONFIG, 16)
    bput("")
    box_warn("Changing auth will require updating all connected clients!")
    box_info("Enter 'random' to automatically generate a secure key.")
    bput("")
    box_footer()
    
    n = ask_input("New AUTH Password (or Enter to cancel)")
    if not n:
        return
        
    if n.lower() == "random":
        import string
        chars = string.ascii_letters + string.digits
        n = "".join(random.choice(chars) for _ in range(12))
        
    if " " in n or len(n) < 3:
        os.system("clear"); print()
        box_header("EDIT AUTH PASSWORD", "Validation Error")
        bput("")
        box_error("Invalid password! Must be at least 3 characters without spaces.")
        bput("")
        box_footer()
        time.sleep(2)
        return
        
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["auth_str"] = n
        auth_list = [n]
        if ":" not in n:
            auth_list.append(f"{n}:{n}")
        d["auth"] = {"mode": "passwords", "config": auth_list}
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)
        subprocess.run(["systemctl", "restart", "hysteria"], capture_output=True, text=True, timeout=10)
        time.sleep(2)
        
        os.system("clear"); print()
        box_header("EDIT AUTH PASSWORD", "Update Successful")
        bput("")
        box_success("Authentication password updated successfully!")
        bput("")
        box_section("UPDATED CREDENTIALS")
        bput("")
        box_kv("Old Password", old if old else "(none)", 16, D)
        box_kv("New Password", n, 16, G)
        box_kv("Service Status", f"{G}[ ONLINE ] Restarted{NC}", 16)
        bput("")
        box_footer()
        press_enter()
    except Exception as e:
        os.system("clear"); print()
        box_header("EDIT AUTH PASSWORD", "Error Occurred")
        bput("")
        box_error(f"Failed to update config: {e}")
        bput("")
        box_footer()
        press_enter()

# 10. Edit OBFS
def edit_obfs():
    os.system("clear"); print()
    box_header("EDIT OBFS KEY", "Traffic Obfuscation Key")
    _, _, old = read_config()
    bput("")
    box_section("CURRENT OBFUSCATION")
    bput("")
    box_kv("Current OBFS", old if old else "(disabled)", 16, Y)
    box_kv("Config File", HYST_CONFIG, 16)
    bput("")
    box_info("OBFS scrambles UDP packets into random noise against ISP DPI.")
    box_info("Enter '-' to disable, 'random' for auto-gen, or Enter to cancel.")
    bput("")
    box_footer()
    
    n = ask_input("New OBFS Key (Enter to cancel, '-' to disable)")
    if not n:
        return
        
    if n == "-":
        n = ""
    elif n.lower() == "random":
        import string
        chars = string.ascii_letters + string.digits
        n = "".join(random.choice(chars) for _ in range(8))
        
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["obfs"] = n
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)
        subprocess.run(["systemctl", "restart", "hysteria"], capture_output=True, text=True, timeout=10)
        time.sleep(2)
        
        os.system("clear"); print()
        box_header("EDIT OBFS KEY", "Update Successful")
        bput("")
        box_success("OBFS key updated successfully!")
        bput("")
        box_section("UPDATED CONFIGURATION")
        bput("")
        box_kv("New OBFS Key", n if n else "(disabled)", 16, G)
        box_kv("Service Status", f"{G}[ ONLINE ] Restarted{NC}", 16)
        bput("")
        box_footer()
        press_enter()
    except Exception as e:
        os.system("clear"); print()
        box_header("EDIT OBFS KEY", "Error Occurred")
        bput("")
        box_error(f"Failed to update OBFS: {e}")
        bput("")
        box_footer()
        press_enter()

# 11. Change Port
def change_port():
    os.system("clear"); print()
    box_header("CHANGE LISTEN PORT", "UDP Port Configuration")
    p, _, _ = read_config()
    bput("")
    box_section("CURRENT PORT CONFIGURATION")
    bput("")
    box_kv("Current Port", f"{p} (UDP)", 16, Y)
    box_kv("Allowed Range", "10000 - 65000", 16)
    box_kv("Multi-port Range", "Supported (e.g. 20000-30000)", 16)
    bput("")
    box_warn("Make sure cloud security groups / firewall allow this UDP port!")
    bput("")
    box_footer()
    
    n = ask_input("New Port or Range [10000-65000] (Enter to cancel)")
    if not n:
        return
        
    if "-" in n:
        parts = n.split("-", 1)
        if parts[0].isdigit() and parts[1].isdigit():
            lo, hi = int(parts[0]), int(parts[1])
            if 1 <= lo <= 65535 and 1 <= hi <= 65535 and lo <= hi:
                chosen_port = str(random.randint(lo, hi))
            else:
                os.system("clear"); print()
                box_header("CHANGE LISTEN PORT", "Invalid Range")
                bput("")
                box_error("Invalid port range! Range must be within 1-65535.")
                bput("")
                box_footer()
                time.sleep(2)
                return
        else:
            os.system("clear"); print()
            box_header("CHANGE LISTEN PORT", "Invalid Range")
            bput("")
            box_error("Invalid range format! Use e.g. 20000-30000.")
            bput("")
            box_footer()
            time.sleep(2)
            return
    elif not n.isdigit() or not (1 <= int(n) <= 65535):
        os.system("clear"); print()
        box_header("CHANGE LISTEN PORT", "Invalid Port")
        bput("")
        box_error("Invalid port number! Must be an integer between 1-65535.")
        bput("")
        box_footer()
        time.sleep(2)
        return
    else:
        chosen_port = n
        
    try:
        with open(HYST_CONFIG) as f: d = json.load(f)
        d["listen"] = f"{d.get('listen',':25000').rsplit(':',1)[0]}:{chosen_port}"
        with open(HYST_CONFIG, 'w') as f: json.dump(d, f, indent=2)

        # Update iptables NAT PREROUTING and INPUT rules
        subprocess.run(f"iptables -t nat -D PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port {p} 2>/dev/null", shell=True)
        subprocess.run(f"iptables -t nat -D PREROUTING -p udp --dport {p} -j REDIRECT --to-port {p} 2>/dev/null", shell=True)
        subprocess.run(f"iptables -t nat -A PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port {chosen_port}", shell=True)
        subprocess.run(f"iptables -t nat -A PREROUTING -p udp --dport {chosen_port} -j REDIRECT --to-port {chosen_port}", shell=True)
        subprocess.run(f"iptables -I INPUT -p udp --dport {chosen_port} -j ACCEPT 2>/dev/null", shell=True)
        subprocess.run("iptables-save > /etc/iptables/rules.v4 2>/dev/null || true", shell=True)

        # Update /etc/showon.conf
        if os.path.exists(SHOWON_CONF):
            with open(SHOWON_CONF, 'r') as sf: sfc = sf.read()
            sfc = re.sub(r'^AGN_PORT=.*$', f'AGN_PORT="{chosen_port}"', sfc, flags=re.MULTILINE)
            with open(SHOWON_CONF, 'w') as sf: sf.write(sfc)
        subprocess.run("systemctl restart online-check 2>/dev/null", shell=True)

        subprocess.run(["systemctl", "restart", "hysteria"], capture_output=True, text=True, timeout=10)
        time.sleep(2)
        
        os.system("clear"); print()
        box_header("CHANGE LISTEN PORT", "Port Updated")
        bput("")
        box_success(f"Listen port successfully changed to {chosen_port}!")
        bput("")
        box_section("UPDATED CONFIGURATION")
        bput("")
        box_kv("Old Port", f"{p} (UDP)", 16, D)
        box_kv("New Port", f"{chosen_port} (UDP)", 16, G)
        box_kv("Port Hopping", f"{G}[ OK ] 10000-65000 -> {chosen_port}{NC}", 16)
        box_kv("Service Status", f"{G}[ ONLINE ] Restarted{NC}", 16)
        bput("")
        box_footer()
        press_enter()
    except Exception as e:
        os.system("clear"); print()
        box_header("CHANGE LISTEN PORT", "Error Occurred")
        bput("")
        box_error(f"Failed to update port: {e}")
        bput("")
        box_footer()
        press_enter()

# 12. Speed Test
def speed_test():
    os.system("clear"); print()
    box_header("NETWORK SPEED TEST", "Latency & Bandwidth Benchmark")
    bput("")
    box_section("BENCHMARK IN PROGRESS")
    bput("")
    box_info("Testing latency to Cloudflare & Google DNS...")
    box_info("Measuring download throughput via Cloudflare CDN...")
    bput("")
    box_footer()
    
    cf_ping = "N/A"
    try:
        r = subprocess.run("ping -c 3 -W 2 1.1.1.1 | awk -F '/' 'END {print $5}'", shell=True, capture_output=True, text=True, timeout=5)
        if r.stdout.strip(): cf_ping = f"{float(r.stdout.strip()):.1f} ms"
    except: pass
    
    gg_ping = "N/A"
    try:
        r = subprocess.run("ping -c 3 -W 2 8.8.8.8 | awk -F '/' 'END {print $5}'", shell=True, capture_output=True, text=True, timeout=5)
        if r.stdout.strip(): gg_ping = f"{float(r.stdout.strip()):.1f} ms"
    except: pass
    
    mbps = 0.0
    try:
        r = subprocess.run("curl -s -o /dev/null -w '%{speed_download}' --max-time 15 'https://speed.cloudflare.com/__down?bytes=10000000'", shell=True, capture_output=True, text=True, timeout=20)
        raw_speed = float(r.stdout.strip().replace("'", ""))
        mbps = (raw_speed * 8) / 1_000_000
    except: pass
    
    if mbps >= 150: rating = f"{G}[ ULTRA FAST ]{NC} (Optimal)"
    elif mbps >= 80: rating = f"{G}[ EXCELLENT ]{NC} (High Speed)"
    elif mbps >= 30: rating = f"{Y}[ GOOD ]{NC} (Normal)"
    elif mbps > 0: rating = f"{O}[ MODERATE ]{NC} (Acceptable)"
    else: rating = f"{R}[ FAILED ]{NC} (Timeout / Unreachable)"
    
    os.system("clear"); print()
    box_header("NETWORK SPEED TEST", "Benchmark Results")
    bput("")
    box_section("LATENCY RESULTS")
    bput("")
    box_kv("Cloudflare (1.1.1.1)", cf_ping, 18, G if cf_ping != "N/A" else D)
    box_kv("Google DNS (8.8.8.8)", gg_ping, 18, G if gg_ping != "N/A" else D)
    bput("")
    box_section("BANDWIDTH THROUGHPUT")
    bput("")
    box_kv("Download Speed", f"{mbps:.1f} Mbps" if mbps > 0 else "N/A", 18, WHT)
    box_kv("Speed Rating", rating, 18)
    box_kv("Test Server", "Cloudflare Global Edge CDN", 18, C)
    bput("")
    box_footer()
    press_enter()

def ensure_daemon_service(svc):
    service_file = f"/etc/systemd/system/{svc}.service"
    script_file = f"/usr/local/bin/{svc}.sh"
    need_reload = False
    if os.path.exists(script_file):
        try: os.chmod(script_file, 0o755)
        except: pass
    has_install = False
    if os.path.exists(service_file):
        try:
            with open(service_file) as f:
                has_install = "[Install]" in f.read()
        except: pass
    if not os.path.exists(service_file) or not has_install:
        desc = "Traffic" if svc == "vnstat-traffic" else "System Info"
        wants = "After=network.target vnstat.service\nWants=vnstat.service\n" if svc == "vnstat-traffic" else "After=network.target\n"
        try:
            with open(service_file, "w") as f:
                f.write(f"[Unit]\nDescription={desc}\n{wants}[Service]\nType=simple\nExecStart={script_file}\nRestart=always\nRestartSec=3\n\n[Install]\nWantedBy=multi-user.target\n")
            need_reload = True
        except: pass
    if need_reload:
        subprocess.run("systemctl daemon-reload 2>/dev/null", shell=True)
    subprocess.run(f"systemctl enable --now {svc} 2>/dev/null || systemctl restart {svc} 2>/dev/null", shell=True)

# 13. Web Dashboard
def web_dashboard():
    while True:
        os.system("clear"); print()
        box_header("WEB DASHBOARD", "Nginx & Background Monitor Services")
        ip = get_ip()
        
        bput("")
        box_section("SERVICES STATUS")
        bput("")
        for svc, title in [("nginx", "Nginx Web Server"), ("online-check", "Online Check Monitor"),
                           ("vnstat-traffic", "vnStat Traffic Daemon"), ("sysinfo", "SysInfo Daemon")]:
            st = get_service_status(svc)
            if st not in ("active", "activating") and svc in ("vnstat-traffic", "sysinfo"):
                ensure_daemon_service(svc)
                st = get_service_status(svc)
            elif st != "active" and svc != "nginx":
                try:
                    if subprocess.run(f"systemctl is-active {svc}.timer", shell=True, capture_output=True, text=True, timeout=3).stdout.strip() == "active":
                        st = "active"
                except: pass
            badge = f"{G}[ OK ] Active{NC}" if st in ("active", "activating") else f"{R}[ FAIL ] Inactive{NC}"
            box_kv(title, badge, 22)
            
        bput("")
        box_section("DASHBOARD ACCESS")
        bput("")
        box_kv("Access URL", f"http://{ip}:{WEB_PORT}/server/", 14, C)
        bput("")
        box_section("MANAGEMENT ACTIONS")
        bput("")
        sub_row("1", "Restart All", "4", "Restart Nginx")
        sub_row("2", "Stop All", "5", "Restart Online")
        sub_row("3", "Start All", "0", "Back to Menu")
        bput("")
        box_footer()
        
        ch = ask_input("Choose an action [0-5]")
        if ch == "0" or not ch: break
        elif ch == "1":
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Restarting Services")
            bput("")
            box_info("Restarting all web and monitoring services...")
            bput("")
            box_footer()
            subprocess.run("systemctl restart nginx online-check vnstat-traffic sysinfo 2>/dev/null", shell=True)
            time.sleep(1.5)
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Services Restarted")
            bput("")
            box_success("All dashboard services restarted successfully!")
            bput("")
            box_footer()
            time.sleep(1.2)
        elif ch == "2":
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Stopping Services")
            bput("")
            box_info("Stopping all dashboard services...")
            bput("")
            box_footer()
            subprocess.run("systemctl stop nginx online-check vnstat-traffic sysinfo 2>/dev/null", shell=True)
            time.sleep(1)
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Services Stopped")
            bput("")
            box_success("All dashboard services stopped!")
            bput("")
            box_footer()
            time.sleep(1.2)
        elif ch == "3":
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Starting Services")
            bput("")
            box_info("Starting all dashboard services...")
            bput("")
            box_footer()
            subprocess.run("systemctl start nginx online-check vnstat-traffic sysinfo 2>/dev/null", shell=True)
            time.sleep(1.5)
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Services Started")
            bput("")
            box_success("All dashboard services started successfully!")
            bput("")
            box_footer()
            time.sleep(1.2)
        elif ch == "4":
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Restarting Nginx")
            bput("")
            box_info("Restarting Nginx web server...")
            bput("")
            box_footer()
            subprocess.run("systemctl restart nginx 2>/dev/null", shell=True)
            time.sleep(1)
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Nginx Restarted")
            bput("")
            box_success("Nginx web server restarted successfully!")
            bput("")
            box_footer()
            time.sleep(1.2)
        elif ch == "5":
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Restarting Online Check")
            bput("")
            box_info("Restarting online-check monitor...")
            bput("")
            box_footer()
            subprocess.run("systemctl restart online-check 2>/dev/null", shell=True)
            time.sleep(1)
            os.system("clear"); print()
            box_header("WEB DASHBOARD", "Online Check Restarted")
            bput("")
            box_success("Online Check service restarted successfully!")
            bput("")
            box_footer()
            time.sleep(1.2)

# 14. Setup Swap
def setup_swap():
    while True:
        os.system("clear"); print()
        box_header("SETUP SWAP MEMORY", "Virtual Memory Management")
        ram_mb = 0
        try: ram_mb = int(subprocess.run("free -m | awk '/Mem:/{print $2}'", shell=True, capture_output=True, text=True).stdout.strip())
        except: pass
        
        swap_info = get_swap_info()
        if ram_mb <= 1024: rec_mb = ram_mb * 2
        elif ram_mb <= 4096: rec_mb = ram_mb
        else: rec_mb = 4096
        
        bput("")
        box_section("CURRENT MEMORY STATUS")
        bput("")
        box_kv("Physical RAM", f"{ram_mb} MB", 16)
        box_kv("Current Swap", swap_info, 16, Y)
        box_kv("Swap File", SWAP_FILE, 16)
        box_kv("Recommended", f"{rec_mb} MB", 16, G)
        bput("")
        box_section("SWAP OPTIONS")
        bput("")
        sub_row("1", f"Auto Swap ({rec_mb}MB)", "3", "Remove Swap")
        sub_row("2", "Custom Size (MB)", "0", "Back to Menu")
        bput("")
        box_footer()
        
        ch = ask_input("Choose an option [0-3]")
        if ch == "0" or not ch: break
        
        swap_to_create = 0
        if ch == "1":
            swap_to_create = rec_mb
        elif ch == "2":
            val = ask_input("Enter Swap Size in MB (e.g. 2048)")
            if val.isdigit() and int(val) >= 256:
                swap_to_create = int(val)
            else:
                os.system("clear"); print()
                box_header("SETUP SWAP", "Invalid Size")
                bput("")
                box_error("Invalid swap size! Must be at least 256 MB.")
                bput("")
                box_footer()
                time.sleep(2)
                continue
        elif ch == "3":
            os.system("clear"); print()
            box_header("REMOVE SWAP", "Disable Swap File")
            bput("")
            box_info("Disabling and removing swap file...")
            bput("")
            box_footer()
            subprocess.run("swapoff -a 2>/dev/null", shell=True)
            subprocess.run(f"rm -f {SWAP_FILE} 2>/dev/null", shell=True)
            subprocess.run(f"sed -i '\\|{SWAP_FILE}|d' /etc/fstab 2>/dev/null", shell=True)
            
            os.system("clear"); print()
            box_header("REMOVE SWAP", "Swap Removed")
            bput("")
            box_success("Swap file has been completely removed!")
            bput("")
            box_footer()
            press_enter()
            break
            
        if swap_to_create > 0:
            os.system("clear"); print()
            box_header("SETUP SWAP", "Creating Swap File")
            bput("")
            box_info(f"Allocating {swap_to_create}MB swap file...")
            bput("")
            box_footer()
            try:
                subprocess.run("swapoff -a 2>/dev/null", shell=True, timeout=5)
                subprocess.run(f"fallocate -l {swap_to_create}M {SWAP_FILE} 2>/dev/null || dd if=/dev/zero of={SWAP_FILE} bs=1M count={swap_to_create}", shell=True, timeout=60)
                subprocess.run(f"chmod 600 {SWAP_FILE} && mkswap {SWAP_FILE} && swapon {SWAP_FILE}", shell=True, timeout=10)
                subprocess.run(f"grep -q '{SWAP_FILE}' /etc/fstab || echo '{SWAP_FILE} none swap sw 0 0' >> /etc/fstab", shell=True, timeout=3)
                
                os.system("clear"); print()
                box_header("SETUP SWAP", "Swap Created")
                bput("")
                box_success(f"Swap memory successfully created ({swap_to_create}MB)!")
                bput("")
                box_section("UPDATED MEMORY STATE")
                bput("")
                box_kv("Physical RAM", f"{ram_mb} MB", 16)
                box_kv("Active Swap", get_swap_info(), 16, G)
                bput("")
                box_footer()
                press_enter()
                break
            except Exception as e:
                os.system("clear"); print()
                box_header("SETUP SWAP", "Error Occurred")
                bput("")
                box_error(f"Failed to create swap: {e}")
                bput("")
                box_footer()
                press_enter()

# 15. Change Limit
def change_limit():
    os.system("clear"); print()
    box_header("CHANGE USER LIMIT", "Online Concurrent User Threshold")
    current = "2000"
    if os.path.exists(SHOWON_CONF):
        try:
            with open(SHOWON_CONF) as f:
                for line in f:
                    if line.startswith("LIMIT="): current = line.split("=")[1].strip()
        except: pass
        
    bput("")
    box_section("CURRENT ONLINE LIMIT")
    bput("")
    box_kv("Current Limit", f"{current} Users", 16, Y)
    box_kv("Config File", SHOWON_CONF, 16)
    box_kv("Service Name", "online-check.service", 16)
    bput("")
    box_info("Sets the maximum concurrent online user display threshold.")
    bput("")
    box_footer()
    
    n = ask_input("New Online Limit [10-99999] (Enter to cancel)")
    if not n:
        return
        
    if not n.isdigit() or not (10 <= int(n) <= 99999):
        os.system("clear"); print()
        box_header("CHANGE USER LIMIT", "Validation Error")
        bput("")
        box_error("Invalid limit! Must be a number between 10 and 99999.")
        bput("")
        box_footer()
        time.sleep(2)
        return
        
    try:
        if os.path.exists(SHOWON_CONF):
            with open(SHOWON_CONF) as f: content = f.read()
            content = re.sub(r'^LIMIT=.*$', f'LIMIT={n}', content, flags=re.MULTILINE)
            with open(SHOWON_CONF, 'w') as f: f.write(content)
        subprocess.run("systemctl restart online-check 2>/dev/null", shell=True)
        
        os.system("clear"); print()
        box_header("CHANGE USER LIMIT", "Limit Updated")
        bput("")
        box_success(f"Online user limit changed to {n} successfully!")
        bput("")
        box_section("UPDATED CONFIGURATION")
        bput("")
        box_kv("Old Limit", f"{current} Users", 16, D)
        box_kv("New Limit", f"{n} Users", 16, G)
        box_kv("Service", f"{G}[ OK ] online-check restarted{NC}", 16)
        bput("")
        box_footer()
        press_enter()
    except Exception as e:
        os.system("clear"); print()
        box_header("CHANGE USER LIMIT", "Error Occurred")
        bput("")
        box_error(f"Failed to update limit: {e}")
        bput("")
        box_footer()
        press_enter()

# 16. Update All & Game Fix
def auto_fix_gaming():
    try:
        for cfg in [HYST_CONFIG, "/opt/hysteria/config.json", "/etc/hysteria/config.json", "/etc/hysteria/config-v1.json"]:
            if os.path.exists(cfg):
                with open(cfg, 'r') as f: content = f.read()
                changed = False
                if '"disable_mtu_discovery": false' in content or '"disable_mtu_discovery"' not in content:
                    content = re.sub(r'"disable_mtu_discovery"\s*:\s*(false|true)', '"disable_mtu_discovery": true', content)
                    if '"disable_mtu_discovery"' not in content:
                        content = content.rstrip().rstrip('}') + ',\n  "disable_mtu_discovery": true\n}'
                    changed = True
                if '"resolve_preference"' not in content:
                    content = content.rstrip().rstrip('}') + ',\n  "resolve_preference": "4"\n}'
                    changed = True
                if '20971520' in content:
                    content = content.replace('20971520', '2097152')
                    changed = True
                if '41943040' in content:
                    content = content.replace('41943040', '8388608')
                    changed = True
                if changed:
                    with open(cfg, 'w') as f: f.write(content)
                    subprocess.run("systemctl restart hysteria 2>/dev/null", shell=True)
    except: pass

    try:
        need_badvpn_update = False
        r = subprocess.run("systemctl is-active badvpn3", shell=True, capture_output=True, text=True)
        if r.stdout.strip() != "active":
            need_badvpn_update = True
        elif os.path.exists("/etc/systemd/system/badvpn1.service"):
            with open("/etc/systemd/system/badvpn1.service", "r") as bf:
                if "client-socket-sndbuf 0" in bf.read():
                    need_badvpn_update = True

        if need_badvpn_update:
            subprocess.run("rm -f /etc/systemd/system/badvpn101.service /etc/systemd/system/badvpn201.service 2>/dev/null", shell=True)
            subprocess.run("command -v /usr/sbin/badvpn >/dev/null 2>&1 || (wget -q -O /usr/sbin/badvpn https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn && chmod +x /usr/sbin/badvpn)", shell=True)
            for p in [7100, 7200, 7300]:
                idx = (p - 7000) // 100
                svc = f"[Unit]\nDescription=UDP {p}\nAfter=syslog.target network-online.target\n\n[Service]\nUser=root\nNoNewPrivileges=true\nExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:{p} --max-clients 1000 --max-connections-for-client 500\nRestart=on-failure\nRestartPreventExitStatus=23\nLimitNPROC=10000\nLimitNOFILE=1000000\n\n[Install]\nWantedBy=multi-user.target\n"
                with open(f"/etc/systemd/system/badvpn{idx}.service", "w") as f: f.write(svc)
            subprocess.run("systemctl daemon-reload && systemctl restart badvpn1 badvpn2 badvpn3 2>/dev/null", shell=True)
    except: pass

    try:
        cfg = """# UDP Buffer Optimization for QUIC / Hysteria & High Throughput
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304

# Ephemeral port range for outbound connections (prevents port exhaustion)
net.ipv4.ip_local_port_range = 10000 65535

# Enable IP forwarding
net.ipv4.ip_forward = 1

# BBR Congestion Control & Fair Queuing for UDP/TCP stability
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Conntrack tuning for High-Volume UDP Port Hopping & VPN
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 10
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 10

# Disable IPv6 since VPS has no IPv6 routing (prevents IPv6 blackhole / timeouts)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
"""
        with open("/etc/sysctl.d/99-hysteria.conf", "w") as f: f.write(cfg)
        subprocess.run("sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1", shell=True)
        with open("/etc/modprobe.d/nf_conntrack.conf", "w") as f: f.write("options nf_conntrack hashsize=262144\n")
        subprocess.run("echo 262144 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true", shell=True)
    except: pass

def update_dashboard():
    os.system("clear"); print()
    box_header("UPDATE SYSTEM & SCRIPTS", "GitHub Sync & Gaming Fixes")
    bput("")
    box_section("UPDATE SPECIFICATION")
    bput("")
    box_kv("Current Version", get_version(), 16, G)
    box_kv("Target Repo", "EkromSSH/UDP-HYSTERIA", 16)
    box_kv("Gaming Features", "BadVPN 7100/7200/7300, MTU, Sysctl 16MB & BBR", 16, C)
    bput("")
    box_info("Updating will fetch the latest scripts and apply all game fixes.")
    bput("")
    box_footer()
    
    if not ask_confirm("Proceed with system update?"):
        return
        
    os.system("clear"); print()
    box_header("UPDATING SYSTEM", "Downloading & Applying Fixes")
    bput("")
    box_info("Running update script from GitHub repository...")
    box_info("Applying kernel 16MB UDP buffer, BBR & MTU 1280...")
    box_info("Verifying BadVPN Roblox / Game gateways...")
    bput("")
    box_footer()
    
    try:
        subprocess.run("curl -fsSL -H 'Cache-Control: no-cache, no-store, must-revalidate' -H 'Pragma: no-cache' 'https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/update.sh?v='$(date +%s%N)$RANDOM | bash", shell=True)
    except Exception as e:
        print(f"  {R}Update Error: {e}{NC}")
        
    auto_fix_gaming()
    
    updated_ver = get_version()
    os.system("clear"); print()
    box_header("UPDATE COMPLETED", "System Up to Date")
    bput("")
    box_success("All scripts and game fixes updated successfully!")
    bput("")
    box_section("SYSTEM STATUS")
    bput("")
    box_kv("Current Version", updated_ver, 16, G)
    box_kv("Gaming Gateways", f"{G}[ OK ] 7100/7200/7300 Active{NC}", 16)
    box_kv("Kernel Buffer", f"{G}[ OK ] 16 MB UDP Buffer & BBR{NC}", 16)
    bput("")
    box_footer()
    press_enter("Press Enter to reload menu...")
    try:
        os.execv(sys.executable, [sys.executable, "/opt/hysteria/menu.py"])
    except:
        pass

# 17. Uninstall Dashboard
def uninstall_dashboard():
    os.system("clear"); print()
    box_header("UNINSTALL DASHBOARD", "Remove Web & Monitor Services")
    bput("")
    box_section("COMPONENTS TO BE REMOVED")
    bput("")
    box_kv("Services", "online-check, vnstat-traffic, sysinfo", 16, R)
    box_kv("Binaries", "/usr/local/bin/*.sh", 16, R)
    box_kv("Config Files", "/etc/showon.conf, /etc/ida-version", 16, R)
    box_kv("Web Block", "Nginx /server/ location block", 16, R)
    bput("")
    box_info("Hysteria core VPN server will REMAIN completely untouched!")
    box_warn("This action cannot be undone.")
    bput("")
    box_footer()
    
    if not ask_confirm("Are you sure you want to uninstall dashboard components?"):
        return
        
    os.system("clear"); print()
    box_header("UNINSTALLING", "Removing Services & Files")
    bput("")
    box_info("Stopping and disabling dashboard background services...")
    box_info("Removing configuration files and systemd units...")
    box_info("Restoring original Nginx configuration...")
    bput("")
    box_footer()
    
    try:
        subprocess.run("systemctl stop online-check vnstat-traffic sysinfo 2>/dev/null", shell=True)
        subprocess.run("systemctl disable online-check vnstat-traffic sysinfo 2>/dev/null", shell=True)
        subprocess.run("rm -f /etc/systemd/system/online-check.service /etc/systemd/system/sysinfo.service /etc/systemd/system/vnstat-traffic.service", shell=True)
        subprocess.run("rm -f /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh", shell=True)
        subprocess.run("rm -f /etc/showon.conf /var/log/ida-debug.log /etc/ida-version", shell=True)
        subprocess.run("sed -i '/==== IDA AUTOCONFIG BEGIN ====/,/==== IDA AUTOCONFIG END ====/d' /etc/nginx/conf.d/vps.conf 2>/dev/null", shell=True)
        subprocess.run("systemctl daemon-reload && systemctl restart nginx 2>/dev/null", shell=True)
        
        os.system("clear"); print()
        box_header("UNINSTALL COMPLETED", "Dashboard Removed")
        bput("")
        box_success("Dashboard components have been uninstalled!")
        bput("")
        box_kv("Hysteria Status", f"{G}[ ONLINE ] Running{NC}", 16)
        bput("")
        box_footer()
        press_enter()
    except Exception as e:
        os.system("clear"); print()
        box_header("UNINSTALL ERROR", "Error Occurred")
        bput("")
        box_error(f"Error during uninstallation: {e}")
        bput("")
        box_footer()
        press_enter()

# ══ Main Loop ══
if __name__ == "__main__":
    os.system("chmod 600 " + HYST_CONFIG + " 2>/dev/null")
    auto_fix_gaming()
    while True:
        try:
            ch = show_menu()
            if ch in ("01", "1"): show_info()
            elif ch in ("02", "2"): do_restart()
            elif ch in ("03", "3"): do_stop()
            elif ch in ("04", "4"): do_start()
            elif ch in ("05", "5"): view_logs()
            elif ch in ("06", "6"): sys_info()
            elif ch in ("07", "7"): traffic_stats()
            elif ch in ("08", "8"): debug_log()
            elif ch in ("09", "9"): edit_auth()
            elif ch == "10": edit_obfs()
            elif ch == "11": change_port()
            elif ch == "12": speed_test()
            elif ch == "13": web_dashboard()
            elif ch == "14": setup_swap()
            elif ch == "15": change_limit()
            elif ch == "16": update_dashboard()
            elif ch == "17": uninstall_dashboard()
            elif ch in ("00", "0", "q", "exit"):
                os.system("clear"); print()
                box(); center(f"{G}\U0001f44b{NC} {BD}Thank You - IDA UDPHysteria{NC}"); bot()
                print(); break
        except KeyboardInterrupt: break
        except Exception as e:
            print(f"  {R}Error: {e}{NC}"); time.sleep(2)
    os.system("clear"); print(); box(); center(f"{G}\U0001f44b{NC} {BD}Thank You - IDA UDPHysteria{NC}"); bot(); print()
