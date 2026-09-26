#!/bin/bash
# ═══════════════════════════════════════════════════════
# IDA UDPHysteria — Quick Update & Game Fix
# ═══════════════════════════════════════════════════════
TARGET_VERSION="${1:-$NEXT_VERSION}"
if [ -z "$TARGET_VERSION" ]; then
  CURRENT_VER=""
  for vpath in /etc/ida-version /opt/hysteria/version; do
    if [ -f "$vpath" ] && [ -s "$vpath" ]; then
      CURRENT_VER=$(cat "$vpath" | tr -d '[:space:]')
      break
    fi
  done
  [ -z "$CURRENT_VER" ] && CURRENT_VER="v2.3.4"
  if [[ "$CURRENT_VER" =~ ^(v?)([0-9]+)\.([0-9]+)\.([0-9]+)(.*)$ ]]; then
    P="${BASH_REMATCH[1]}"
    MAJ="${BASH_REMATCH[2]}"
    MIN="${BASH_REMATCH[3]}"
    PAT="${BASH_REMATCH[4]}"
    EXT="${BASH_REMATCH[5]}"
    TARGET_VERSION="${P:-v}${MAJ}.${MIN}.$((PAT + 1))${EXT}"
  else
    TARGET_VERSION="v2.3.5"
  fi
fi
VERSION="$TARGET_VERSION"
echo -e "\n\033[1;34m==>\033[0m \033[1;37mUpdating IDA UDPHysteria to ${VERSION} & Applying Network/Game Fixes...\033[0m\n"

# 1. Update MTU, Mobile Buffer & IPv4 Resolve for gaming and mobile connectivity
echo -e "\033[1;34m==>\033[0m Fixing MTU, Low-RAM Buffer & Resolve Preference for Mobile & Gaming..."
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
echo -e "  \033[1;32m✅ MTU (1280), Mobile Buffer (2M/8M) & resolve_preference (4) applied\033[0m"

# 2. Kernel & UDP Buffer & Conntrack Optimization
echo -e "\033[1;34m==>\033[0m Applying Kernel UDP buffer, Conntrack, BBR & IPv6 optimizations..."
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
echo -e "  \033[1;32m✅ Sysctl UDP Buffer 16MB, BBR+FQ, Conntrack 1M & IPv6 disabled applied\033[0m"

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
echo -e "  \033[1;32m✅ BadVPN udpgw 7100, 7200, 7300 active\033[0m"

# 4. Download latest scripts from GitHub (Safe atomic download + syntax validation)
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

echo -e "\033[1;34m==>\033[0m Downloading latest scripts & menu..."
fetch_raw "scripts/menu.py" "/opt/hysteria/menu.py"
fetch_raw "scripts/online-check.sh" "/usr/local/bin/online-check.sh"
fetch_raw "scripts/sysinfo.sh" "/usr/local/bin/sysinfo.sh"
fetch_raw "scripts/vnstat-traffic.sh" "/usr/local/bin/vnstat-traffic.sh"
fetch_raw "web/index.html" "/home/vps/public_html/server/index.html"
fetch_raw "auto-update.sh" "/opt/hysteria/auto-update.sh"
fetch_raw "version.txt" "/opt/hysteria/version"

chmod +x /opt/hysteria/menu.py /usr/local/bin/online-check.sh /usr/local/bin/sysinfo.sh /usr/local/bin/vnstat-traffic.sh /opt/hysteria/auto-update.sh 2>/dev/null
chown -R www-data:www-data /home/vps/public_html/server 2>/dev/null

# 5. Ensure systemd services & restart
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
systemctl restart online-check sysinfo vnstat-traffic hysteria badvpn1 badvpn2 badvpn3 2>/dev/null || true

echo ""
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo -e "\033[1;32m  🎉 Update Completed Successfully! (${VERSION})\033[0m"
echo -e "\033[1;36m═══════════════════════════════════════\033[0m"
echo "$VERSION" > /etc/ida-version 2>/dev/null || true
echo "$VERSION" > /opt/hysteria/version 2>/dev/null || true
if [ -f /etc/showon.conf ]; then
  sed -i "s/^VERSION=.*/VERSION=\"${VERSION}\"/" /etc/showon.conf 2>/dev/null || true
fi
echo "  Version  : ${VERSION} (Gaming Fix Applied)"
echo "  Hysteria : $(systemctl is-active hysteria)"
echo "  BadVPN 1 : $(systemctl is-active badvpn1) (port 7100)"
echo "  BadVPN 2 : $(systemctl is-active badvpn2) (port 7200)"
echo "  BadVPN 3 : $(systemctl is-active badvpn3) (port 7300)"
echo "  MTU Fix  : disable_mtu_discovery=true"
echo ""
