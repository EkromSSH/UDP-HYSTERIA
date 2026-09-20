#!/bin/bash
WWW="/home/vps/public_html/server"
mkdir -p "$WWW"

# Ensure vnstat daemon is running
if ! systemctl is-active --quiet vnstat 2>/dev/null; then
  systemctl start vnstat 2>/dev/null || true
fi

while true; do
  RX=$(vnstat --json d 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); traffic=d.get('interfaces',[{}])[0].get('traffic',{}); days=traffic.get('day') or traffic.get('days') or [{}]; latest=days[-1] if days else {}; print(latest.get('rx',0))" 2>/dev/null || echo 0)
  TX=$(vnstat --json d 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); traffic=d.get('interfaces',[{}])[0].get('traffic',{}); days=traffic.get('day') or traffic.get('days') or [{}]; latest=days[-1] if days else {}; print(latest.get('tx',0))" 2>/dev/null || echo 0)
  echo "{\"vnstat_rx\":\"${RX:-0}\",\"vnstat_tx\":\"${TX:-0}\",\"v2ray_up\":\"0\",\"v2ray_down\":\"0\"}" > "$WWW/netinfo.json.tmp" 2>/dev/null && mv -f "$WWW/netinfo.json.tmp" "$WWW/netinfo.json" 2>/dev/null
  sleep 30
done
