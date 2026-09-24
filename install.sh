#!/bin/bash
echo -e "\n\033[1;34m==>\033[0m \033[1;37mIDA UDPHysteria Complete Installer v2.2\033[0m\n"

# ══ Auto-detect IP ══
echo -e "\033[1;34m==>\033[0m Detecting server IP..."
AUTO_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
          curl -s --connect-timeout 5 icanhazip.com 2>/dev/null || \
          ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}' || \
          hostname -I | awk '{print $1}')
AUTO_IP=$(echo "$AUTO_IP" | tr -d "\n\r" | xargs)
[ -z "$AUTO_IP" ] && AUTO_IP="0.0.0.0"
echo -e "  \033[1;32mAuto-detect:\033[0m $AUTO_IP"
echo -e "  \033[2m(Press Enter to accept auto-detect, or type custom IP)\033[0m"
if [ -z "$SERVER_IP" ]; then
  read -p "Server IP [$AUTO_IP]: " SERVER_IP < /dev/null
fi
SERVER_IP=$(echo "${SERVER_IP:-$AUTO_IP}" | tr -d "\n\r" | xargs)

# ══ Port / Auth / OBFS ══
if [ -z "$PORT" ]; then
  read -p "Port [36712]: " PORT < /dev/null
fi
PORT=${PORT:-36712}
if [ -z "$AUTH" ]; then
  read -p "Auth [idavpn]: " AUTH < /dev/null
fi
AUTH=${AUTH:-idavpn}
if [ -z "$OBFS" ]; then
  read -p "OBFS [idavpn]: " OBFS < /dev/null
fi
OBFS=${OBFS:-idavpn}

# ══ Handle apt lock gracefully ══
# ย้าย sources.list.d ออกชั่วคราว (กันค้างตอน update) แล้วคืนค่าหลังติดตั้ง
mkdir -p /etc/apt/backup-sources 2>/dev/null
if ls /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
  mv /etc/apt/sources.list.d/*.list /etc/apt/backup-sources/ 2>/dev/null
fi

restore_sources() {
  if ls /etc/apt/backup-sources/*.list >/dev/null 2>&1; then
    mv /etc/apt/backup-sources/*.list /etc/apt/sources.list.d/ 2>/dev/null || true
  fi
}
trap restore_sources EXIT

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive

echo -e "\n\033[1;34m==>\033[0m Installing packages..."
for i in 1 2 3 4 5; do
  echo "  apt-get update attempt $i/5 ..."
  if timeout 180 apt-get update -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 >/tmp/apt_update.log 2>&1; then
    echo "  apt-get update OK"
    break
  fi
  echo "  attempt $i failed, clearing lock..."
  rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock 2>/dev/null
  dpkg --configure -a 2>/dev/null
  sleep 5
done
apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=60 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wget curl openssl nginx vnstat conntrack jq python3 iptables-persistent 2>&1 | tail -5

# คืนค่า sources.list.d
restore_sources

# ══ Download Hysteria ══
echo -e "\n\033[1;34m==>\033[0m Downloading Hysteria v1.3.5..."
timeout 60 wget -q --timeout=50 https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-amd64 -O /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria
mkdir -p /opt/hysteria /etc/hysteria /home/vps/public_html/server
chmod o+x /home/vps 2>/dev/null

# ══ Generate certificates ══
echo -e "\n\033[1;34m==>\033[0m Generating certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/C=TH/ST=Bangkok/L=Bangkok/O=IDA VPN/CN=${SERVER_IP}" 2>/dev/null
chmod 600 /etc/hysteria/server.key

# ══ Config ══
cat > /opt/hysteria/config-v1.json << EOF
{
  "listen": ":${PORT}",
  "protocol": "udp",
  "cert": "/etc/hysteria/server.crt",
  "key": "/etc/hysteria/server.key",
  "up_mbps": 100,
  "down_mbps": 100,
  "obfs": "${OBFS}",
  "auth_str": "${AUTH}",
  "recv_window_conn": 2097152,
  "recv_window_client": 8388608,
  "max_conn_client": 1024,
  "resolve_preference": "4",
  "disable_mtu_discovery": true
}
EOF

cat > /opt/hysteria/start.sh << 'E1'
#!/bin/bash
exec /usr/local/bin/hysteria server -c /opt/hysteria/config-v1.json
E1
chmod +x /opt/hysteria/start.sh

cat > /etc/systemd/system/hysteria.service << 'E2'
[Unit]
Description=Hysteria VPN Server
After=network.target
[Service]
Type=simple
ExecStart=/bin/bash /opt/hysteria/start.sh
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
E2

# ══ Kernel & UDP Buffer Optimization ══
echo -e "\n\033[1;34m==>\033[0m Optimizing system UDP buffers & network..."
cat > /etc/sysctl.d/99-hysteria.conf << 'EOF'
# UDP Buffer Optimization for QUIC / Hysteria & High Throughput
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
net.netfilter.nf_conntrack_udp_timeout = 10
net.netfilter.nf_conntrack_udp_timeout_stream = 20
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
EOF
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1 || true
echo 'options nf_conntrack hashsize=262144' > /etc/modprobe.d/nf_conntrack.conf
echo 262144 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true

# ══ BadVPN udpgw for Gaming (7100, 7200, 7300) ══
echo -e "\n\033[1;34m==>\033[0m Installing BadVPN udpgw for Gaming..."
wget -q -O /usr/sbin/badvpn "https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn" 2>/dev/null || true
chmod +x /usr/sbin/badvpn 2>/dev/null || true

for p in 7100 7200 7300; do
  idx=$(( (p - 7000) / 100 ))
  cat > /etc/systemd/system/badvpn${idx}.service << EOF
[Unit]
Description=UDP ${p}
After=syslog.target network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 1000 --max-connections-for-client 512 --client-socket-sndbuf 0
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now badvpn${idx} 2>/dev/null || true
done

# ══ Port hopping ══
echo -e "\n\033[1;34m==>\033[0m Setting up port hopping (UDP 10000-65000 -> ${PORT})..."
# ลบเฉพาะกฎเดิมของ Hysteria ก่อนถ้ามี (ป้องกันกฎซ้ำซ้อน) โดยไม่ล้างกฎ PREROUTING ของบริการอื่น (เช่น SSH, SlowDNS)
iptables -t nat -D PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port ${PORT} 2>/dev/null || true
iptables -t nat -D PREROUTING -p udp --dport ${PORT} -j REDIRECT --to-port ${PORT} 2>/dev/null || true

# ตั้งค่า Port Hopping พอร์ตสุ่ม UDP 10000-65000 ชี้เข้า PORT (${PORT})
iptables -t nat -A PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port ${PORT}
iptables -t nat -A PREROUTING -p udp --dport ${PORT} -j REDIRECT --to-port ${PORT}

# เปิด Firewall ตาราง INPUT สำหรับ UDP
iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p udp --dport 10000:65000 -j ACCEPT 2>/dev/null || true

# บันทึกกฎ iptables อย่างปลอดภัย
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

systemctl daemon-reload && systemctl enable hysteria && systemctl restart hysteria
sleep 3
systemctl is-active hysteria && echo "✅ Hysteria: active" || echo "❌ Hysteria: failed"

# ══ showon.conf ══
echo "v2.3.2" > /etc/ida-version 2>/dev/null || true
echo "v2.3.2" > /opt/hysteria/version 2>/dev/null || true
cat > /etc/showon.conf << E3
VERSION="V.2.3.2"
WWW_DIR="/home/vps/public_html/server"
LIMIT=50
NET_IFACE="eth0"
AGN_PRESENT=1
AGN_PORT="${PORT}"
E3

# ══ Scripts ══
cat > /usr/local/bin/online-check.sh << 'E4'
#!/bin/bash
WWW="/home/vps/public_html/server"; LIMIT=50; AGN_PORT=36712
[ -f /etc/showon.conf ] && . /etc/showon.conf
mkdir -p "$WWW"; NOW=$(date +%s%3N)
SSH_ON=$(ps aux | grep 'sshd:' | grep -v 'listener\|grep\|root' | awk '{print $1}' | sort -u | wc -l)
AGNUDP_ON=0
[ -n "$AGN_PORT" ] && command -v conntrack >/dev/null 2>&1 && {
  SIP=$(ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}')
  SNET=$(echo "$SIP" | cut -d. -f1-3)
  ips=$(conntrack -L -p udp 2>/dev/null | grep "sport=${AGN_PORT}" | grep -v "sport=443 " | sed "s/.* dst=\([0-9.]*\) sport=${AGN_PORT}.*/\1/" | sort -u)
  [ -n "$ips" ] && AGNUDP_ON=$(echo "$ips" | grep -vE "^${SIP}$|^127\.|^${SNET}\." | wc -l)
}
TOTAL=$((SSH_ON + AGNUDP_ON))
echo "[{\"onlines\":\"$TOTAL\",\"limite\":\"$LIMIT\",\"ssh\":\"$SSH_ON\",\"openvpn\":\"0\",\"dropbear\":\"0\",\"v2ray\":\"0\",\"agnudp\":\"$AGNUDP_ON\",\"timestamp\":\"$NOW\"}]" > "$WWW/online_app.json"
E4
chmod +x /usr/local/bin/online-check.sh
printf '[Unit]\nDescription=Online Check\n[Service]\nType=simple\nExecStart=/usr/local/bin/online-check.sh\nRestart=always\nRestartSec=5\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/online-check.service
printf '[Unit]\nDescription=Online Check Timer\n[Timer]\nOnBootSec=10\nOnUnitActiveSec=60\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/online-check.timer
systemctl daemon-reload 2>/dev/null; systemctl enable --now online-check.service online-check.timer 2>/dev/null

cat > /usr/local/bin/sysinfo.sh << 'E5'
#!/bin/bash
WWW="/home/vps/public_html/server"
mkdir -p "$WWW"
while true; do
  C1=$(awk 'NR==1{print $2+$4+$5}' /proc/stat 2>/dev/null || echo 0)
  I1=$(awk 'NR==1{print $2+$4}' /proc/stat 2>/dev/null || echo 0)
  sleep 1
  C2=$(awk 'NR==1{print $2+$4+$5}' /proc/stat 2>/dev/null || echo 0)
  I2=$(awk 'NR==1{print $2+$4}' /proc/stat 2>/dev/null || echo 0)
  u=$(( ${I2:-0} - ${I1:-0} ))
  c=$(( ${C2:-0} - ${C1:-0} ))
  CPU=$(awk -v u="$u" -v c="$c" 'BEGIN{if(c>0)printf "%d",u*100/c;else print 0}' 2>/dev/null || echo 0)
  RAW=$(uptime -p 2>/dev/null | sed 's/up //')
  WK=$(echo "$RAW" | grep -oE '[0-9]+ week' | grep -oE '[0-9]+' 2>/dev/null); WK=${WK:-0}
  REST=$(echo "$RAW" | sed -E 's/[0-9]+ week[s]?,? ?//' 2>/dev/null)
  DAYS=$(echo "$REST" | grep -oE '[0-9]+ day' | grep -oE '[0-9]+' 2>/dev/null); DAYS=${DAYS:-0}
  TOTALD=$(( ${DAYS:-0} + ${WK:-0} * 7 ))
  if [ "$TOTALD" -gt 0 ]; then
    REST="$(echo "$REST" | sed -E "s/[0-9]+ day[s]?//g; s/^,//; s/,//g" 2>/dev/null)"
    UPTIME="${TOTALD}D $(echo "$REST" | sed -E 's/([0-9]+) hour[s]?/\1H/g; s/([0-9]+) minute[s]?/\1M/g; s/^ //; s/ $//' | sed 's/^, //; s/,//g' 2>/dev/null)"
  else
    UPTIME=$(echo "$REST" | sed -E "s/([0-9]+) hour[s]?/\1H/g; s/([0-9]+) minute[s]?/\1M/g; s/,//g; s/ +/ /g; s/^ //; s/ $//" 2>/dev/null)
  fi
  UPTIME=$(echo "$UPTIME" | sed 's/^ //; s/ $//; s/  / /g' 2>/dev/null)
  RAM_U=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
  RAM_T=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
  DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2}')
  echo "[{\"uptime\":\"${UPTIME:-0M}\",\"cpu_usage\":\"${CPU:-0}%\",\"ram_usage\":\"${RAM_U:-0}/${RAM_T:-0}MB\",\"disk_usage\":\"${DISK:-0/0}\"}]" > "$WWW/sysinfo.json.tmp" 2>/dev/null && mv -f "$WWW/sysinfo.json.tmp" "$WWW/sysinfo.json" 2>/dev/null
  sleep 29
done
E5
chmod +x /usr/local/bin/sysinfo.sh
cat > /etc/systemd/system/sysinfo.service << 'EOF'
[Unit]
Description=System Info
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sysinfo.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null
systemctl enable --now sysinfo 2>/dev/null

cat > /usr/local/bin/vnstat-traffic.sh << 'E6'
#!/bin/bash
WWW="/home/vps/public_html/server"
mkdir -p "$WWW"
if ! systemctl is-active --quiet vnstat 2>/dev/null; then
  systemctl start vnstat 2>/dev/null || true
fi
while true; do
  RX=$(vnstat --json d 2>/dev/null|python3 -c "import json,sys;d=json.load(sys.stdin);traffic=d.get('interfaces',[{}])[0].get('traffic',{});days=traffic.get('day') or traffic.get('days') or [{}];latest=days[-1] if days else {};print(latest.get('rx',0))" 2>/dev/null||echo 0)
  TX=$(vnstat --json d 2>/dev/null|python3 -c "import json,sys;d=json.load(sys.stdin);traffic=d.get('interfaces',[{}])[0].get('traffic',{});days=traffic.get('day') or traffic.get('days') or [{}];latest=days[-1] if days else {};print(latest.get('tx',0))" 2>/dev/null||echo 0)
  echo "{\"vnstat_rx\":\"${RX:-0}\",\"vnstat_tx\":\"${TX:-0}\",\"v2ray_up\":\"0\",\"v2ray_down\":\"0\"}" > "$WWW/netinfo.json.tmp" 2>/dev/null && mv -f "$WWW/netinfo.json.tmp" "$WWW/netinfo.json" 2>/dev/null
  sleep 30
done
E6
chmod +x /usr/local/bin/vnstat-traffic.sh
cat > /etc/systemd/system/vnstat-traffic.service << 'EOF'
[Unit]
Description=Traffic
After=network.target vnstat.service
Wants=vnstat.service

[Service]
Type=simple
ExecStart=/usr/local/bin/vnstat-traffic.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null
systemctl enable --now vnstat-traffic 2>/dev/null

# ══ Dashboard HTML ══
cat > /home/vps/public_html/server/index.html << 'E7'
<!doctype html><html lang="en"><head><meta charset="utf-8"/><title>IDA UDPHysteria Dashboard V.1.0.7</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d1117;color:#e6edf3;font-family:sans-serif;max-width:1200px;margin:0 auto;padding:20px}
h1{font-size:1.6rem;margin-bottom:16px}h2{font-size:1.2rem;margin-bottom:10px}
.grid{display:grid;gap:20px}@media(min-width:900px){.grid{grid-template-columns:1fr 1fr}}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:16px}
table{width:100%;border-collapse:collapse;margin-top:10px}
th,td{padding:10px;text-align:center}th{background:#1f242c;color:#c9d1d9}
td{border-top:1px solid #2d333b}.ok{color:#3fb950;font-weight:600}
@media(max-width:600px){body{padding:10px}h1{font-size:1.2rem}table{font-size:.7rem}th,td{padding:6px 3px}.table-wrap{overflow-x:auto}}
</style></head><body>
<h1>IDA UDPHysteria Dashboard V.1.0.7</h1><div class="grid">
<div class="card"><h2>Online Summary</h2><div class="table-wrap"><table><thead><tr><th>✅ Total</th><th>🎯 Limit</th><th>🔒 SSH</th><th>🌐 OpenVPN</th><th>⚫ Dropbear</th><th>⚡ V2Ray</th><th>📡 AGN-UDP</th></tr></thead>
<tbody><tr id="row-online"><td colspan="7">Loading...</td></tr></tbody></table></div></div>
<div class="card"><h2>System</h2><div class="mono" id="sys">Loading...</div></div>
<div class="card"><h2>Traffic</h2><table><thead id="traffic-head"></thead><tbody><tr id="row-net"><td>Loading...</td></tr></tbody></table></div></div>
<script>
const j=async u=>{const r=await fetch(u+"?_="+Date.now(),{cache:"no-store"});if(!r.ok)throw new Error(r.status);return r.json()};
let lo=null,ls=null,lt=null;
async function refresh(){
try{const a=await j('./online_app.json');lo=Array.isArray(a)?a[0]:a}catch(e){}
try{const s=await j('./sysinfo.json');ls=Array.isArray(s)?s[0]:s}catch(e){}
try{const n=await j('./netinfo.json');lt=Array.isArray(n)?n[0]:n}catch(e){}
if(lo)document.getElementById('row-online').innerHTML='<td class="ok">'+lo.onlines+'</td><td>'+lo.limite+'</td><td>'+lo.ssh+'</td><td>'+lo.openvpn+'</td><td>'+lo.dropbear+'</td><td>'+lo.v2ray+'</td><td>'+lo.agnudp+'</td>'
if(ls)document.getElementById('sys').innerHTML='<b>Uptime:</b> '+ls.uptime+' · <b>CPU:</b> '+ls.cpu_usage+' · <b>RAM:</b> '+ls.ram_usage+' · <b>Disk:</b> '+ls.disk_usage
if(lt)document.getElementById('row-net').innerHTML='<td>'+lt.vnstat_rx+' B</td><td>'+lt.vnstat_tx+' B</td>'
}
setInterval(refresh,5000);refresh()
</script></body></html>
E7

# ══ Nginx ══
cat > /etc/nginx/conf.d/dashboard.conf << 'E8'
server {listen 82;root /home/vps/public_html;index index.html;location /server/{alias /home/vps/public_html/server/;}}
E8
nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null

# ══ Download menu ══
if wget -q https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/menu.py -O /opt/hysteria/menu.py 2>/dev/null; then
  chmod +x /opt/hysteria/menu.py
  printf '#!/bin/bash\npython3 /opt/hysteria/menu.py\n' > /usr/local/bin/showon && chmod +x /usr/local/bin/showon
else
  echo "⚠️  Menu download failed. Run after internet is available:"
  echo "   wget -q https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/menu.py -O /opt/hysteria/menu.py"
  echo "   printf '#!/bin/bash\\npython3 /opt/hysteria/menu.py\\n' > /usr/local/bin/showon && chmod +x /usr/local/bin/showon"
fi

# ══ Fresh update: download latest scripts from GitHub ══
echo -e "\n\033[1;34m==>\033[0m Updating to latest scripts..."
timeout 30 curl -sL --max-time 25 https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/web/index.html -o /home/vps/public_html/server/index.html 2>/dev/null
timeout 30 curl -sL --max-time 25 https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/online-check.sh -o /usr/local/bin/online-check.sh 2>/dev/null
timeout 30 curl -sL --max-time 25 https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/sysinfo.sh -o /usr/local/bin/sysinfo.sh 2>/dev/null
timeout 30 curl -sL --max-time 25 https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/vnstat-traffic.sh -o /usr/local/bin/vnstat-traffic.sh 2>/dev/null
timeout 30 curl -sL --max-time 25 https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/menu.py -o /opt/hysteria/menu.py 2>/dev/null
chmod +x /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /opt/hysteria/menu.py 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null
systemctl restart online-check sysinfo vnstat-traffic 2>/dev/null || true

# ══ Auto-update menu (every 6 hours) ══
cat > /opt/hysteria/auto-update.sh << 'AU'
#!/bin/bash
BASE="https://raw.githubusercontent.com/EkromSSH/hysteria-install/main"
curl -sL "$BASE/scripts/menu.py" -o /opt/hysteria/menu.py 2>/dev/null
curl -sL "$BASE/scripts/online-check.sh" -o /usr/local/bin/online-check.sh 2>/dev/null
curl -sL "$BASE/scripts/sysinfo.sh" -o /usr/local/bin/sysinfo.sh 2>/dev/null
curl -sL "$BASE/scripts/vnstat-traffic.sh" -o /usr/local/bin/vnstat-traffic.sh 2>/dev/null
curl -sL "$BASE/web/index.html" -o /home/vps/public_html/server/index.html 2>/dev/null
curl -sL "$BASE/install.sh" -o /tmp/ida-update.sh 2>/dev/null
chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /tmp/ida-update.sh 2>/dev/null
# Update config: ensure disable_mtu_discovery=true for gaming/UDP stability, low-RAM mobile buffer & resolve_preference=4
for cfg in /opt/hysteria/config-v1.json /opt/hysteria/config.json /etc/hysteria/config.json /etc/hysteria/config-v1.json; do
  if [ -f "$cfg" ]; then
    sed -i -E 's/"disable_mtu_discovery"[[:space:]]*:[[:space:]]*(false|true)/"disable_mtu_discovery": true/' "$cfg" 2>/dev/null || true
    if ! grep -q "disable_mtu_discovery" "$cfg" 2>/dev/null; then
      sed -i 's/}$/,\n  "disable_mtu_discovery": true\n}/' "$cfg" 2>/dev/null || true
    fi
    if ! grep -q "resolve_preference" "$cfg" 2>/dev/null; then
      sed -i 's/}$/,\n  "resolve_preference": "4"\n}/' "$cfg" 2>/dev/null || true
    fi
    sed -i 's/20971520/2097152/g' "$cfg" 2>/dev/null || true
    sed -i 's/41943040/8388608/g' "$cfg" 2>/dev/null || true
  fi
done
systemctl restart hysteria 2>/dev/null || true

# Apply sysctl UDP buffer, conntrack, BBR & ephemeral port optimization
cat > /etc/sysctl.d/99-hysteria.conf << 'EOF'
# UDP Buffer Optimization for QUIC / Hysteria & High Throughput
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
net.netfilter.nf_conntrack_udp_timeout = 10
net.netfilter.nf_conntrack_udp_timeout_stream = 20
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
EOF
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1 || true
echo 'options nf_conntrack hashsize=262144' > /etc/modprobe.d/nf_conntrack.conf
echo 262144 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true

# Ensure BadVPN udpgw (7100, 7200, 7300) is installed and running
if [ ! -f /usr/sbin/badvpn ]; then
  wget -q -O /usr/sbin/badvpn "https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn" 2>/dev/null || true
  chmod +x /usr/sbin/badvpn 2>/dev/null || true
fi

for p in 7100 7200 7300; do
  idx=$(( (p - 7000) / 100 ))
  cat > /etc/systemd/system/badvpn${idx}.service << EOF
[Unit]
Description=UDP ${p}
After=syslog.target network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 1000 --max-connections-for-client 512 --client-socket-sndbuf 0
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
done
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now badvpn1 badvpn2 badvpn3 2>/dev/null || true

systemctl restart online-check sysinfo vnstat-traffic 2>/dev/null || true
AU
chmod +x /opt/hysteria/auto-update.sh
echo "0 */6 * * * root /opt/hysteria/auto-update.sh" > /etc/cron.d/ida-auto-update

# ══ Done ══
echo ""
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo -e "\033[1;33m  🚀 Installation Complete!\033[0m"
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo "  Hysteria : $(systemctl is-active hysteria)"
echo "  Auth     : ${AUTH}"
echo "  OBFS     : ${OBFS}"
echo "  Dashboard: http://${SERVER_IP}:82/server/"
echo "  Type: showon → for menu"
echo ""
echo -e "\033[1;32m  ✅ Menu auto-updates every 6 hours\033[0m"
