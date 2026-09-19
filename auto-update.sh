#!/bin/bash
BASE="https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main"
curl -sL "$BASE/scripts/online-check.sh" -o /usr/local/bin/online-check.sh 2>/dev/null
curl -sL "$BASE/scripts/sysinfo.sh" -o /usr/local/bin/sysinfo.sh 2>/dev/null
curl -sL "$BASE/scripts/vnstat-traffic.sh" -o /usr/local/bin/vnstat-traffic.sh 2>/dev/null
curl -sL "$BASE/web/index.html" -o /home/vps/public_html/server/index.html 2>/dev/null
curl -sL "$BASE/install.sh" -o /tmp/ida-update.sh 2>/dev/null
chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /tmp/ida-update.sh 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null
# Update config: ensure disable_mtu_discovery=true for gaming/UDP stability
if [ -f /opt/hysteria/config-v1.json ]; then
  sed -i 's/"disable_mtu_discovery": false/"disable_mtu_discovery": true/' /opt/hysteria/config-v1.json
  systemctl restart hysteria 2>/dev/null || true
fi

# Apply sysctl UDP buffer & ephemeral port optimization
cat > /etc/sysctl.d/99-hysteria.conf << 'EOF'
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.ipv4.ip_local_port_range = 1024 9999
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-hysteria.conf >/dev/null 2>&1 || true

# Ensure BadVPN udpgw (7100, 7200, 7300) is installed and running
if [ ! -f /usr/sbin/badvpn ]; then
  wget -q -O /usr/sbin/badvpn "https://raw.githubusercontent.com/EkromSSH/VPN/main/badvpn/badvpn" 2>/dev/null || true
  chmod +x /usr/sbin/badvpn 2>/dev/null || true
fi

for p in 7100 7200 7300; do
  idx=$((p - 7099))
  if [ ! -f /etc/systemd/system/badvpn${idx}.service ]; then
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
  fi
done
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now badvpn1 badvpn2 badvpn3 2>/dev/null || true

systemctl restart online-check sysinfo vnstat-traffic 2>/dev/null || true
