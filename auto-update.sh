fetch_raw() {
  local path="$1"
  local out="$2"
  local tmp
  tmp=$(mktemp)

  for repo in "EkromSSH/UDP-HYSTERIA" "EkromSSH/hysteria-install"; do
    if curl -fsSL -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" \
         "https://raw.githubusercontent.com/${repo}/main/${path}?v=$(date +%s%N)${RANDOM}" \
         -o "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      
      # If python script, ensure valid syntax before deploying
      if [[ "$path" == *.py ]]; then
        if ! python3 -m py_compile "$tmp" >/dev/null 2>&1; then
          continue
        fi
      fi
      
      mkdir -p "$(dirname "$out")"
      mv -f "$tmp" "$out"
      return 0
    fi
  done
  
  rm -f "$tmp"
  return 1
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

# Update config: ensure disable_mtu_discovery=true for 4G+/5G stability, IPv4-only resolver & low-RAM buffer
_hyst_changed=0
for cfg in /opt/hysteria/config-v1.json /opt/hysteria/config.json /etc/hysteria/config.json /etc/hysteria/config-v1.json; do
  if [ -f "$cfg" ]; then
    if grep -q '"disable_mtu_discovery"[[:space:]]*:[[:space:]]*false' "$cfg" 2>/dev/null || \
       ! grep -q 'disable_mtu_discovery' "$cfg" 2>/dev/null; then
      sed -i -E 's/"disable_mtu_discovery"[[:space:]]*:[[:space:]]*(false|true)/"disable_mtu_discovery": true/' "$cfg" 2>/dev/null || true
      if ! grep -q 'disable_mtu_discovery' "$cfg" 2>/dev/null; then
        sed -i -E 's/}$/,\n  "disable_mtu_discovery": true\n}/' "$cfg" 2>/dev/null || true
      fi
      _hyst_changed=1
    fi
    if ! grep -q 'resolve_preference' "$cfg" 2>/dev/null; then
      sed -i -E 's/}$/,\n  "resolve_preference": "4"\n}/' "$cfg" 2>/dev/null || true
      _hyst_changed=1
    fi
    if ! grep -q 'resolver' "$cfg" 2>/dev/null; then
      sed -i -E 's/}$/,\n  "resolver": "udp:\/\/8.8.8.8:53"\n}/' "$cfg" 2>/dev/null || true
      _hyst_changed=1
    fi
    if grep -q '20971520' "$cfg" 2>/dev/null; then
      sed -i 's/20971520/2097152/g' "$cfg" 2>/dev/null || true
      _hyst_changed=1
    fi
    if grep -q '41943040' "$cfg" 2>/dev/null; then
      sed -i 's/41943040/8388608/g' "$cfg" 2>/dev/null || true
      _hyst_changed=1
    fi
  fi
done
if [ "$_hyst_changed" -eq 1 ]; then
  systemctl restart hysteria 2>/dev/null || true
fi

# Apply sysctl UDP buffer, conntrack, BBR & ephemeral port optimization
cat > /etc/sysctl.d/99-hysteria.conf << 'EOF'
# UDP Buffer Optimization for QUIC / Hysteria & High Throughput
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Ephemeral port range for outbound connections (prevents port exhaustion)
net.ipv4.ip_local_port_range = 10000 65535

# Enable IP forwarding
net.ipv4.ip_forward = 1

# BBR Congestion Control & Fair Queuing for UDP/TCP stability
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Conntrack tuning for High-Volume UDP Port Hopping & 4G/5G mobile CGNAT
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 10
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 10

# Disable IPv6 since VPS has no IPv6 routing (prevents IPv6 blackhole / timeouts on 5G)
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
ExecStart=/usr/sbin/badvpn --listen-addr 127.0.0.1:${p} --max-clients 1000 --max-connections-for-client 500 --client-socket-sndbuf 0
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

# Apply TCP MSS Clamping (1280) to prevent packet fragmentation & drops on 4G+/5G networks
iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280 2>/dev/null || true
iptables -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280 2>/dev/null || true
iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280 2>/dev/null || true
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280
iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1280
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

[ -f /opt/hysteria/version ] && cp -f /opt/hysteria/version /etc/ida-version 2>/dev/null || true

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
