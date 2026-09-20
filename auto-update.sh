#!/bin/bash
BASE="https://raw.githubusercontent.com/EkromSSH/UDP-HYSTERIA/main"
curl -sL "$BASE/scripts/menu.py" -o /opt/hysteria/menu.py 2>/dev/null
curl -sL "$BASE/scripts/online-check.sh" -o /usr/local/bin/online-check.sh 2>/dev/null
curl -sL "$BASE/scripts/sysinfo.sh" -o /usr/local/bin/sysinfo.sh 2>/dev/null
curl -sL "$BASE/scripts/vnstat-traffic.sh" -o /usr/local/bin/vnstat-traffic.sh 2>/dev/null
curl -sL "$BASE/web/index.html" -o /home/vps/public_html/server/index.html 2>/dev/null
curl -sL "$BASE/install.sh" -o /tmp/ida-update.sh 2>/dev/null
chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /tmp/ida-update.sh 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null

# Update config: ensure disable_mtu_discovery=true for gaming/UDP stability & resolve_preference=4 to prevent IPv6 timeout
for cfg in /opt/hysteria/config-v1.json /opt/hysteria/config.json /etc/hysteria/config.json /etc/hysteria/config-v1.json; do
  if [ -f "$cfg" ]; then
    sed -i -E 's/"disable_mtu_discovery"[[:space:]]*:[[:space:]]*(false|true)/"disable_mtu_discovery":  true/' "$cfg" 2>/dev/null || true
    if ! grep -q "disable_mtu_discovery" "$cfg" 2>/dev/null; then
      sed -i 's/}$/,\n  "disable_mtu_discovery":  true\n}/' "$cfg" 2>/dev/null || true
    fi
    if ! grep -q "resolve_preference" "$cfg" 2>/dev/null; then
      sed -i 's/}$/,\n  "resolve_preference": "4"\n}/' "$cfg" 2>/dev/null || true
    fi
  fi
done
systemctl restart hysteria 2>/dev/null || true

# Apply sysctl UDP buffer, conntrack & ephemeral port optimization
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
echo "v2.3.1" > /etc/ida-version 2>/dev/null || true

# Ensure sysinfo & vnstat-traffic service definitions with [Install] section
if [ ! -f /etc/systemd/system/sysinfo.service ] || ! grep -q "\[Install\]" /etc/systemd/system/sysinfo.service 2>/dev/null; then
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
fi

if [ ! -f /etc/systemd/system/vnstat-traffic.service ] || ! grep -q "\[Install\]" /etc/systemd/system/vnstat-traffic.service 2>/dev/null; then
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
fi

systemctl daemon-reload 2>/dev/null || true
systemctl enable --now sysinfo vnstat-traffic 2>/dev/null || true
systemctl restart online-check sysinfo vnstat-traffic 2>/dev/null || true

