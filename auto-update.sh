fetch_raw() {
  local repo="EkromSSH/UDP-HYSTERIA"
  local path="$1"
  local out="$2"
  if curl -sL -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/${repo}/contents/${path}" -o "$out" 2>/dev/null && [ -s "$out" ]; then
    return 0
  fi
  curl -sL -H "Cache-Control: no-cache" -H "Pragma: no-cache" "https://raw.githubusercontent.com/${repo}/main/${path}?nocache=$(date +%s%N)" -o "$out" 2>/dev/null || true
}

fetch_raw "scripts/menu.py" "/opt/hysteria/menu.py"
fetch_raw "scripts/online-check.sh" "/usr/local/bin/online-check.sh"
fetch_raw "scripts/sysinfo.sh" "/usr/local/bin/sysinfo.sh"
fetch_raw "scripts/vnstat-traffic.sh" "/usr/local/bin/vnstat-traffic.sh"
fetch_raw "web/index.html" "/home/vps/public_html/server/index.html"
fetch_raw "auto-update.sh" "/opt/hysteria/auto-update.sh"
fetch_raw "version.txt" "/opt/hysteria/version"
fetch_raw "install.sh" "/tmp/ida-update.sh"

chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /opt/hysteria/auto-update.sh /tmp/ida-update.sh 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null

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
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 1000 --max-connections-for-client 500
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
echo "v2.3.2" > /etc/ida-version 2>/dev/null || true

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

