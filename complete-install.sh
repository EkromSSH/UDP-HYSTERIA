#!/bin/bash
# ═══════════════════════════════════════════════════════
# IDA UDPHysteria — Complete Installer v3.0
# ═══════════════════════════════════════════════════════
set -e
echo -e "\n\033[1;34m==>\033[0m \033[1;37mIDA UDPHysteria Complete Installer\033[0m\n"
read -p "Server IP: " SERVER_IP
read -p "Port [36712]: " PORT
PORT=${PORT:-36712}
read -p "Auth (empty=none): " AUTH
read -p "OBFS (empty=none): " OBFS

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive

echo -e "\n\033[1;34m==>\033[0m Installing packages..."
apt-get update -qq 2>/dev/null
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wget curl openssl nginx vnstat conntrack jq python3 iptables-persistent 2>&1 | tail -2

echo -e "\n\033[1;34m==>\033[0m Downloading Hysteria v1.3.5..."
wget -q https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-amd64 -O /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria
mkdir -p /etc/hysteria /home/vps/public_html/server

echo -e "\n\033[1;34m==>\033[0m Generating certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
  -subj "/C=TH/ST=Bangkok/L=Bangkok/O=IDA VPN/CN=${SERVER_IP}" 2>/dev/null
chmod 600 /etc/hysteria/server.key

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
  "auth": {
    "mode": "passwords",
    "config": [
      "${AUTH}",
      "${AUTH}:${AUTH}"
    ]
  },
  "recv_window_conn": 2097152,
  "recv_window_client": 8388608,
  "max_conn_client": 1024,
  "resolve_preference": "4",
  "disable_mtu_discovery": true
}
EOF

cat > /opt/hysteria/start.sh << 'EOF'
#!/bin/bash
exec /usr/local/bin/hysteria server -c /opt/hysteria/config-v1.json
EOF
chmod +x /opt/hysteria/start.sh

cat > /etc/systemd/system/hysteria.service << 'EOF'
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
EOF

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
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 1000 --max-connections-for-client 500 --client-socket-sndbuf 524288 --udp-mtu 1400
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

echo -e "\n\033[1;34m==>\033[0m Setting up port hopping (UDP 10000-65000 -> ${PORT})..."
iptables -t nat -D PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port ${PORT} 2>/dev/null || true
iptables -t nat -D PREROUTING -p udp --dport ${PORT} -j REDIRECT --to-port ${PORT} 2>/dev/null || true
iptables -t nat -A PREROUTING -p udp --dport 10000:65000 -j REDIRECT --to-port ${PORT}
iptables -t nat -A PREROUTING -p udp --dport ${PORT} -j REDIRECT --to-port ${PORT}
iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || true
iptables -I INPUT -p udp --dport 10000:65000 -j ACCEPT 2>/dev/null || true
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

systemctl daemon-reload && systemctl enable hysteria && systemctl restart hysteria
sleep 3
systemctl is-active hysteria && echo "✅ Hysteria: active" || echo "❌ Hysteria: failed"

echo "v2.3.2" > /etc/ida-version 2>/dev/null || true
echo "v2.3.2" > /opt/hysteria/version 2>/dev/null || true
cat > /etc/showon.conf << EOF
VERSION="V.2.3.2"
WWW_DIR="/home/vps/public_html/server"
LIMIT=50
DEBUG_LOG="/var/log/showon-debug.log"
NET_IFACE="eth0"
AGN_PRESENT=1
AGN_PORT="${PORT}"
EOF

# online-check
cat > /usr/local/bin/online-check.sh << 'SCRIPT'
#!/bin/bash
CONF="/etc/showon.conf"; WWW_DIR="/home/vps/public_html/server"; LIMIT=50; AGN_PORT=36712
[ -f "$CONF" ] && . "$CONF"
mkdir -p "$WWW_DIR"; NOW=$(date +%s%3N)
SSH_ON=$(ss -tn state established 2>/dev/null | grep -E ':22\s' | wc -l)
AGNUDP_ON=0
if [ -n "$AGN_PORT" ] && command -v conntrack >/dev/null 2>&1; then
  SERVER_IP=$(ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}')
  ips=$(conntrack -L -p udp 2>/dev/null | grep "sport=${AGN_PORT}" | grep -oP 'dst=\K[0-9.]+' | sort -u)
  [ -n "$ips" ] && AGNUDP_ON=$(echo "$ips" | grep -vE "^${SERVER_IP}$|^127\." | wc -l)
fi
TOTAL=$((SSH_ON + AGNUDP_ON))
echo "[{\"onlines\":\"$TOTAL\",\"limite\":\"$LIMIT\",\"ssh\":\"$SSH_ON\",\"openvpn\":\"0\",\"dropbear\":\"0\",\"v2ray\":\"0\",\"agnudp\":\"$AGNUDP_ON\",\"timestamp\":\"$NOW\"}]" > "$WWW_DIR/online_app.json"
SCRIPT
chmod +x /usr/local/bin/online-check.sh
printf '[Unit]\nDescription=Online Check\n[Service]\nType=simple\nExecStart=/usr/local/bin/online-check.sh\n' > /etc/systemd/system/online-check.service
printf '[Unit]\nDescription=Online Check Timer\n[Timer]\nOnBootSec=10\nOnUnitActiveSec=10\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/online-check.timer
systemctl enable --now online-check.timer 2>/dev/null

# sysinfo
cat > /usr/local/bin/sysinfo.sh << 'SCRIPT3'
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
SCRIPT3
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

# vnstat
cat > /usr/local/bin/vnstat-traffic.sh << 'SCRIPT2'
#!/bin/bash
WWW="/home/vps/public_html/server"
mkdir -p "$WWW"
if ! systemctl is-active --quiet vnstat 2>/dev/null; then
  systemctl start vnstat 2>/dev/null || true
fi
while true; do
  RX=$(vnstat --json d 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); traffic=d.get('interfaces',[{}])[0].get('traffic',{}); days=traffic.get('day') or traffic.get('days') or [{}]; latest=days[-1] if days else {}; print(latest.get('rx',0))" 2>/dev/null||echo 0)
  TX=$(vnstat --json d 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); traffic=d.get('interfaces',[{}])[0].get('traffic',{}); days=traffic.get('day') or traffic.get('days') or [{}]; latest=days[-1] if days else {}; print(latest.get('tx',0))" 2>/dev/null||echo 0)
  echo "{\"vnstat_rx\":\"${RX:-0}\",\"vnstat_tx\":\"${TX:-0}\",\"v2ray_up\":\"0\",\"v2ray_down\":\"0\"}" > "$WWW/netinfo.json.tmp" 2>/dev/null && mv -f "$WWW/netinfo.json.tmp" "$WWW/netinfo.json" 2>/dev/null
  sleep 30
done
SCRIPT2
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

# Dashboard HTML
cat > /home/vps/public_html/server/index.html << 'HTMLEND'
<!doctype html><html lang="en"><head><meta charset="utf-8"/><title>ShowOn Dashboard V.1.0.7</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d1117;color:#e6edf3;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;max-width:1200px;margin:0 auto;padding:20px}
h1{font-size:1.6rem;margin-bottom:16px}h2{font-size:1.2rem;margin-bottom:10px}.muted{color:#8b949e}
.grid{display:grid;gap:20px}@media(min-width:900px){.grid{grid-template-columns:1fr 1fr}}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:16px}
table{width:100%;border-collapse:collapse;margin-top:10px}
th,td{padding:10px;text-align:center}th{background:#1f242c;color:#c9d1d9}
td{border-top:1px solid #2d333b}.mono{font-family:monospace}.ok{color:#3fb950;font-weight:600}
@media(max-width:600px){body{padding:10px}h1{font-size:1.2rem}table{font-size:.7rem}th,td{padding:6px 3px}.table-wrap{overflow-x:auto}}
</style></head><body>
<h1>ShowOn Dashboard V.1.0.7</h1>
<div class="grid"><div class="card"><h2>Online Summary</h2>
<div class="table-wrap"><table><thead><tr><th>✅ Total</th><th>🎯 Limit</th><th>🔒 SSH</th><th>🌐 OpenVPN</th><th>🟤 Dropbear</th><th>⚡ V2Ray</th><th>📡 AGN-UDP</th></tr></thead>
<tbody><tr id="row-online"><td colspan="7">Loading...</td></tr></tbody></table></div></div>
<div class="card"><h2>System</h2><div class="mono" id="sys">Loading...</div></div>
<div class="card"><h2>Traffic</h2><table><thead id="traffic-head"></thead><tbody><tr id="row-net"><td>Loading...</td></tr></tbody></table>
<div class="muted" style="margin-top:6px;font-size:.85rem">* vnstat แสดงเสมอ</div></div></div>
<script>
const j=async u=>{const r=await fetch(u+"?_="+Date.now(),{cache:"no-store"});if(!r.ok)throw new Error(r.status);return r.json()};
let lo=null,ls=null,lt=null;
async function refresh(){
try{const a=await j('./online_app.json');lo=Array.isArray(a)?a[0]:a}catch(e){}
try{const s=await j('./sysinfo.json');ls=Array.isArray(s)?s[0]:s}catch(e){}
try{const n=await j('./netinfo.json');lt=Array.isArray(n)?n[0]:n}catch(e){}
if(lo)document.getElementById('row-online').innerHTML='<td class="ok">'+lo.onlines+'</td><td>'+lo.limite+'</td><td>'+lo.ssh+'</td><td>'+lo.openvpn+'</td><td>'+lo.dropbear+'</td><td>'+lo.v2ray+'</td><td>'+lo.agnudp+'</td>'
if(ls)document.getElementById('sys').innerHTML='<b>Uptime:</b> '+ls.uptime+' · <b>CPU:</b> '+ls.cpu_usage+' · <b>RAM:</b> '+ls.ram_usage+' · <b>Disk:</b> '+ls.disk_usage
if(lt)document.getElementById('row-net').innerHTML='<td>'+(lt.vnstat_rx||'0')+' B</td><td>'+(lt.vnstat_tx||'0')+' B</td>'
}
setInterval(refresh,5000);refresh()
</script></body></html>
HTMLEND

cat > /etc/nginx/conf.d/dashboard.conf << 'NGX'
server {listen 82;root /home/vps/public_html;index index.html;location /server/{alias /home/vps/public_html/server/;}}
NGX
nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null

# Menu
wget -q https://raw.githubusercontent.com/EkromSSH/hysteria-install/main/scripts/menu.py -O /opt/hysteria/menu.py 2>/dev/null || true
chmod +x /opt/hysteria/menu.py 2>/dev/null
printf '#!/bin/bash\npython3 /opt/hysteria/menu.py\n' > /usr/local/bin/showon && chmod +x /usr/local/bin/showon

echo ""; echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo -e "\033[1;33m  🚀 Installation Complete!\033[0m"
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo "  Hysteria : $(systemctl is-active hysteria)"
echo "  Auth     : ${AUTH:-none}"
echo "  OBFS     : ${OBFS:-none}"
echo "  Dashboard: http://${SERVER_IP}:82/server/"
echo "  Type: showon → for menu"
