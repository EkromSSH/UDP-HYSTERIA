#!/bin/bash
# ═══════════════════════════════════════════════════════
# IDA UDPHysteria — Quick Update & Game Fix
# ═══════════════════════════════════════════════════════
echo -e "\n\033[1;34m==>\033[0m \033[1;37mUpdating IDA UDPHysteria & Applying Game Fixes...\033[0m\n"

BASE="https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main"
CACHE_BUST="?t=$(date +%s)"

# 1. Update MTU for gaming (disable_mtu_discovery:  true with 2 spaces)
echo -e "\033[1;34m==>\033[0m Fixing MTU for Mobile & Gaming..."
for cfg in /opt/hysteria/config-v1.json /opt/hysteria/config.json /etc/hysteria/config.json /etc/hysteria/config-v1.json; do
  if [ -f "$cfg" ]; then
    sed -i -E 's/"disable_mtu_discovery"[[:space:]]*:[[:space:]]*(false|true)/"disable_mtu_discovery":  true/' "$cfg" 2>/dev/null || true
    if ! grep -q "disable_mtu_discovery" "$cfg" 2>/dev/null; then
      sed -i 's/}$/,\n  "disable_mtu_discovery":  true\n}/' "$cfg" 2>/dev/null || true
    fi
  fi
done
systemctl restart hysteria 2>/dev/null || true
echo -e "  \033[1;32m✅ MTU set to 1280 (disable_mtu_discovery: true)\033[0m"

# 2. Kernel & UDP Buffer Optimization
echo -e "\033[1;34m==>\033[0m Applying Kernel UDP buffer & port range optimizations..."
cat > /etc/sysctl.d/99-hysteria.conf << 'EOF'
# UDP Buffer Optimization for Gaming & High Throughput
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608

# Ephemeral port range to prevent collision with Hysteria port hopping (10000-65000)
net.ipv4.ip_local_port_range = 1024 9999

# Enable IP forwarding
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1 || true
echo -e "  \033[1;32m✅ Sysctl UDP Buffer 8MB applied\033[0m"

# 3. Install & Start BadVPN udpgw (7100, 7200, 7300) for games (Roblox Error 279, etc.)
echo -e "\033[1;34m==>\033[0m Checking & Installing BadVPN-udpgw (7100, 7200, 7300)..."
if [ ! -f /usr/sbin/badvpn ] || [ ! -s /usr/sbin/badvpn ]; then
  wget -q -O /usr/sbin/badvpn "https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn" 2>/dev/null || \
  curl -sL "https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn" -o /usr/sbin/badvpn 2>/dev/null || true
  chmod +x /usr/sbin/badvpn 2>/dev/null || true
fi

rm -f /etc/systemd/system/badvpn101.service /etc/systemd/system/badvpn201.service 2>/dev/null || true

for p in 7100 7200 7300; do
  idx=$(( (p - 7000) / 100 ))
  cat > /etc/systemd/system/badvpn${idx}.service << EOF
[Unit]
Description=UDP ${p}
After=syslog.target network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 500
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
echo -e "  \033[1;32m✅ BadVPN udpgw 7100, 7200, 7300 active\033[0m"

# 4. Download latest scripts from GitHub
echo -e "\033[1;34m==>\033[0m Downloading latest scripts & menu..."
curl -sL "${BASE}/scripts/menu.py${CACHE_BUST}" -o /opt/hysteria/menu.py 2>/dev/null
curl -sL "${BASE}/scripts/online-check.sh${CACHE_BUST}" -o /usr/local/bin/online-check.sh 2>/dev/null
curl -sL "${BASE}/scripts/sysinfo.sh${CACHE_BUST}" -o /usr/local/bin/sysinfo.sh 2>/dev/null
curl -sL "${BASE}/scripts/vnstat-traffic.sh${CACHE_BUST}" -o /usr/local/bin/vnstat-traffic.sh 2>/dev/null
curl -sL "${BASE}/web/index.html${CACHE_BUST}" -o /home/vps/public_html/server/index.html 2>/dev/null
curl -sL "${BASE}/auto-update.sh${CACHE_BUST}" -o /opt/hysteria/auto-update.sh 2>/dev/null

chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /opt/hysteria/auto-update.sh 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null

# 5. Restart services
systemctl restart online-check sysinfo vnstat-traffic hysteria badvpn1 badvpn2 badvpn3 2>/dev/null || true

echo ""
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo -e "\033[1;32m  🎉 Update Completed Successfully!\033[0m"
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo "  Hysteria : $(systemctl is-active hysteria)"
echo "  BadVPN 1 : $(systemctl is-active badvpn1) (port 7100)"
echo "  BadVPN 2 : $(systemctl is-active badvpn2) (port 7200)"
echo "  BadVPN 3 : $(systemctl is-active badvpn3) (port 7300)"
echo "  MTU Fix  : disable_mtu_discovery=true"
echo ""
