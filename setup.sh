#!/bin/bash
set -e
echo -e "\n\033[1;34m==>\033[0m \033[1;37mIDA UDPHysteria Complete Installer\033[0m\n"
read -p "Server IP: " SERVER_IP
read -p "Port [36712]: " PORT
PORT=${PORT:-36712}
read -p "Auth [idavpn]: " AUTH
AUTH=${AUTH:-idavpn}
read -p "OBFS [idavpn]: " OBFS
OBFS=${OBFS:-idavpn}
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive

echo -e "\n\033[1;34m==>\033[0m Installing packages..."
apt-get update -qq 2>/dev/null
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" wget curl openssl nginx vnstat conntrack jq python3 iptables-persistent 2>&1 | tail -2
echo -e "\n\033[1;34m==>\033[0m Downloading Hysteria v1.3.5..."
wget -q https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-amd64 -O /usr/local/bin/hysteria
chmod +x /usr/local/bin/hysteria
mkdir -p /opt/hysteria/certs /home/vps/public_html/server
echo -e "\n\033[1;34m==>\033[0m Generating certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /opt/hysteria/certs/server.key -out /opt/hysteria/certs/server.crt -subj "/C=TH/ST=Bangkok/L=Bangkok/O=IDA VPN/CN=${SERVER_IP}" 2>/dev/null
chmod 600 /opt/hysteria/certs/server.key
cat > /opt/hysteria/config-v1.json << EOF
{
  "listen": ":${PORT}",
  "protocol": "udp",
  "cert": "/opt/hysteria/certs/server.crt",
  "key": "/opt/hysteria/certs/server.key",
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
cat > /etc/showon.conf << E3
VERSION="V.2.3.2"
WWW_DIR="/home/vps/public_html/server"
LIMIT=50
NET_IFACE="eth0"
AGN_PRESENT=1
AGN_PORT="${PORT}"
E3
cat > /usr/local/bin/online-check.sh << 'E4'
#!/bin/bash
WWW="/home/vps/public_html/server"; LIMIT=50; AGN_PORT=36712
[ -f /etc/showon.conf ] && . /etc/showon.conf
mkdir -p "$WWW"; NOW=$(date +%s%3N)
SSH_ON=$(ss -tn state established 2>/dev/null | grep -E ':22\s' | wc -l)
AGNUDP_ON=0
[ -n "$AGN_PORT" ] && command -v conntrack >/dev/null 2>&1 && {
  SIP=$(ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}')
  ips=$(conntrack -L -p udp 2>/dev/null | grep "sport=${AGN_PORT}" | grep -oP 'dst=\K[0-9.]+' | sort -u)
  [ -n "$ips" ] && AGNUDP_ON=$(echo "$ips" | grep -vE "^${SIP}$|^127\." | wc -l)
}
TOTAL=$((SSH_ON + AGNUDP_ON))
echo "[{\"onlines\":\"$TOTAL\",\"limite\":\"$LIMIT\",\"ssh\":\"$SSH_ON\",\"openvpn\":\"0\",\"dropbear\":\"0\",\"v2ray\":\"0\",\"agnudp\":\"$AGNUDP_ON\",\"timestamp\":\"$NOW\"}]" > "$WWW/online_app.json"
E4
chmod +x /usr/local/bin/online-check.sh
printf '[Unit]\nDescription=Online Check\n[Service]\nType=simple\nExecStart=/usr/local/bin/online-check.sh\n' > /etc/systemd/system/online-check.service
printf '[Unit]\nDescription=Online Check Timer\n[Timer]\nOnBootSec=10\nOnUnitActiveSec=10\n[Install]\nWantedBy=timers.target\n' > /etc/systemd/system/online-check.timer
systemctl enable --now online-check.timer 2>/dev/null
wget -q https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/scripts/sysinfo.sh -O /usr/local/bin/sysinfo.sh
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

wget -q https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/scripts/vnstat-traffic.sh -O /usr/local/bin/vnstat-traffic.sh
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
wget -q https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/web/index.html -O /home/vps/public_html/server/index.html
cat > /etc/nginx/conf.d/dashboard.conf << 'E8'
server {listen 82;root /home/vps/public_html;index index.html;location /server/{alias /home/vps/public_html/server/;}}
E8
nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
wget -q https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main/scripts/menu.py -O /opt/hysteria/menu.py 2>/dev/null || true
chmod +x /opt/hysteria/menu.py 2>/dev/null
printf '#!/bin/bash\npython3 /opt/hysteria/menu.py\n' > /usr/local/bin/showon && chmod +x /usr/local/bin/showon
echo ""; echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo -e "\033[1;33m  🚀 Installation Complete!\033[0m"
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo "  Hysteria : $(systemctl is-active hysteria)"
echo "  Auth     : ${AUTH}"
echo "  OBFS     : ${OBFS}"
echo "  Dashboard: http://${SERVER_IP}:82/server/"
echo "  Type: showon → for menu"
