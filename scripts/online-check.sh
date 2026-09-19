#!/bin/bash
# ===============================================
#  ShowOn Online Checker (EkromSSH - ปรับตาม TspKchn/showon)
#  - ใช้ค่าจาก /etc/showon.conf
#  - Outputs: $WWW_DIR/online_app.json
# ===============================================

set -u -o pipefail

# -------- Default config --------
CONF="/etc/showon.conf"

WWW_DIR_DEFAULT="/home/vps/public_html/server"
DEBUG_LOG_DEFAULT="/var/log/showon-debug.log"
LIMIT_DEFAULT=200
NET_IFACE_DEFAULT="eth0"
STATE_DEFAULT="/tmp/agnudp_state"
KEEP=30   # เก็บสถานะ IP UDP ที่เห็นไว้ 30 วินาที (เลิกต่อแล้วหายหลัง 30 วิ)

WWW_DIR="$WWW_DIR_DEFAULT"
DEBUG_LOG="$DEBUG_LOG_DEFAULT"
LIMIT="$LIMIT_DEFAULT"
NET_IFACE="$NET_IFACE_DEFAULT"
PANEL_URL=""
XUI_USER=""
XUI_PASS=""
AGN_PRESENT=0
AGN_PORT=""

# โหลด config ถ้ามี
if [[ -f "$CONF" ]]; then
  . "$CONF"
fi

# กันค่าที่ว่าง / null
WWW_DIR=${WWW_DIR:-$WWW_DIR_DEFAULT}
DEBUG_LOG=${DEBUG_LOG:-$DEBUG_LOG_DEFAULT}
LIMIT=${LIMIT:-$LIMIT_DEFAULT}
NET_IFACE=${NET_IFACE:-$NET_IFACE_DEFAULT}
PANEL_URL=${PANEL_URL:-""}
XUI_USER=${XUI_USER:-""}
XUI_PASS=${XUI_PASS:-""}
AGN_PRESENT=${AGN_PRESENT:-0}
AGN_PORT=${AGN_PORT:-""}

# -------- เตรียมโฟลเดอร์ / log --------
mkdir -p "$WWW_DIR"
mkdir -p "$(dirname "$DEBUG_LOG")"
touch "$DEBUG_LOG"

ONLINE_JSON="$WWW_DIR/online_app.json"
NOW="$(date +%s%3N)"

# cookie ชั่วคราวสำหรับ 3X-UI
TMP_COOKIE="$(mktemp /tmp/showon_cookie_XXXXXX || echo /tmp/showon_cookie_cookie)"

# -------- Logging helpers --------
log() {
  echo "[$(date '+%F %T')] $*" >> "$DEBUG_LOG"
}
log_debug() {
  echo "[$(date '+%F %T')] $*" >> "$DEBUG_LOG"
}

# -------- Log rotation (1MB) --------
rotate_log() {
  local max=1000000 size=0
  if [[ -f "$DEBUG_LOG" ]]; then
    size=$(stat -c%s "$DEBUG_LOG" 2>/dev/null || echo 0)
    if (( size > max )); then
      : > "$DEBUG_LOG"
    fi
  fi
}
rotate_log

log "=== ONLINE CHECK START ==="

# -------- Regex IP ภายใน / Local --------
INTERNAL_REGEX='^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|169\.254\.)'

local_ipv4_regex() {
  ip -o -4 addr show up scope global 2>/dev/null \
    | awk '{print $4}' \
    | cut -d/ -f1 \
    | paste -sd '|' - 2>/dev/null || true
}
LOCAL_IPS_REGEX="$(local_ipv4_regex || true)"

# ===============================================
#  1) SSH Online (Universal, Accurate)
# ===============================================
count_ssh() {
  SSH_ON=$(ps -eo comm,args \
    | grep "[s]shd:" \
    | grep -v "sshd: .*priv" \
    | grep -v "sshd: .*notty" \
    | wc -l)

  # หากขึ้นค้าง 0 แต่ ss -tn ยังเห็น connection → fallback
  if [[ "$SSH_ON" -eq 0 ]]; then
    SSH_ON=$(ss -tn state established 2>/dev/null \
      | grep -E ":22\s" \
      | wc -l)
  fi
}
count_ssh
log_debug "SSH sessions: $SSH_ON"

# ===============================================
#  2) Dropbear Online (Accurate via ps)
# ===============================================
DB_ON=0

count_dropbear() {
  local n
  n=$(ps aux | grep '[d]ropbear' | wc -l)
  DB_ON=$(( n - 1 ))
  [[ $DB_ON -lt 0 ]] && DB_ON=0
  log_debug "Dropbear accurate count: $DB_ON"
}
count_dropbear

# ===============================================
#  3) OpenVPN Online (จาก openvpn-status.log)
# ===============================================
OVPN_ON=0

count_openvpn() {
  local status="/etc/openvpn/server/openvpn-status.log"
  if [[ -f "$status" ]]; then
    if ! OVPN_ON=$(grep -c '^CLIENT_LIST' "$status" 2>/dev/null); then
      OVPN_ON=0
    fi
  else
    OVPN_ON=0
  fi
}
count_openvpn
log_debug "OpenVPN count: $OVPN_ON"

# ===============================================
#  4) V2Ray / Xray — รองรับ 3X-UI + XrayCore
# ===============================================
V2_ON=0

if [[ -n "${PANEL_URL:-}" ]]; then
  LOGIN_OK=false
  RESP=""

  if curl -sk -c "$TMP_COOKIE" -X POST "$PANEL_URL/login" \
       -H "Content-Type: application/x-www-form-urlencoded" \
       --data "username=$XUI_USER&password=$XUI_PASS" 2>/dev/null \
       | grep -q '"success":true'; then
    LOGIN_OK=true
  fi

  if ! $LOGIN_OK; then
    if curl -sk -c "$TMP_COOKIE" -X POST "$PANEL_URL/login" \
         -H "Content-Type: application/json" \
         -d "{\"username\":\"$XUI_USER\",\"password\":\"$XUI_PASS\"}" 2>/dev/null \
         | grep -q '"success":true'; then
      LOGIN_OK=true
    fi
  fi

  if $LOGIN_OK; then
    RESP="$(curl -sk -b "$TMP_COOKIE" "$PANEL_URL/panel/api/inbounds/onlines" 2>/dev/null || true)"
    if echo "$RESP" | grep -q '"success":true'; then
      V2_ON=$(echo "$RESP" | jq '[.obj[]?] | length' 2>/dev/null || echo 0)
    else
      RESP="$(curl -sk -b "$TMP_COOKIE" "$PANEL_URL/panel/api/inbounds/list" 2>/dev/null || true)"
      if echo "$RESP" | grep -q '"success":true'; then
        V2_ON=$(echo "$RESP" | jq --argjson now "$NOW" '
          [ .obj[]?.clientStats[]?
            | select(.lastOnline != null and ($now - .lastOnline) < 5000)
          ] | length' 2>/dev/null || echo 0)
      fi
    fi
    log_debug "3x-ui V2 counted: $V2_ON"
  else
    log "3x-ui login failed (PANEL_URL set but auth not success)"
  fi
else
  if [[ -f /usr/local/etc/xray/config.json || -f /etc/xray/config.json ]]; then
    if [[ -f /var/log/xray/vless_ntls.log ]]; then
      V2_ON=$(
        grep -F 'accepted' /var/log/xray/vless_ntls.log 2>/dev/null \
          | grep -F 'email:' 2>/dev/null \
          | awk '{print $3}' \
          | cut -d: -f1 \
          | sort -u | wc -l
      )
    elif [[ -f /var/log/xray/access.log ]]; then
      V2_ON=$(
        grep -F 'accepted' /var/log/xray/access.log 2>/dev/null \
          | grep -F 'email:' 2>/dev/null \
          | awk '{print $3}' \
          | cut -d: -f1 \
          | sort -u | wc -l
      )
    fi
  fi
fi
log_debug "V2/Xray count: $V2_ON"

# ===============================================
#  5) AGN-UDP / Hysteria Online (via conntrack)
# ===============================================
AGNUDP_ON=0

# ดึง IP เครื่องเรา (ใช้ตัด outbound ที่ sport=AGN_PORT แต่ dst คือเราเอง)
MY_IP=$(ip -o -4 route get 8.8.8.8 2>/dev/null | awk '{print $7}')

count_agnudp() {
  if [[ "${AGN_PRESENT}" != "1" ]]; then
    AGNUDP_ON=0
    return
  fi
  if [[ -z "${AGN_PORT}" ]]; then
    AGNUDP_ON=0
    return
  fi
  if ! command -v conntrack >/dev/null 2>&1; then
    AGNUDP_ON=0
    return
  fi

  local raw filtered now now_s
  now=$(date +%s%3N); now_s=$((now/1000))
  STATE="${STATE:-$STATE_DEFAULT}"
  touch "$STATE" 2>/dev/null

  # ลบรายการที่หมดอายุ (เกิน KEEP วินาที)
  if [[ -f "$STATE" ]]; then
    while IFS='|' read -r ip ts; do
      [ -z "$ip" ] && continue
      if [ $((now_s - ${ts:-0})) -gt $KEEP ]; then
        sed -i "/^${ip}|/d" "$STATE" 2>/dev/null
      fi
    done < "$STATE"
  fi

  raw="$(
    # ตรวจจับแค่ IP ที่เชื่อมต่อเข้ามา (src = ฝั่งเริ่ม connection, ไม่ใช่เครื่องเราเอง)
    journalctl -u hysteria --since "${KEEP}s ago" --no-pager 2>/dev/null \
      | grep -oE 'src:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      | sed 's/^src://' \
      | grep -E '^[0-9]' \
      | grep -v "^${MY_IP}$" \
      | grep -Ev '^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|169\.254\.)' \
      | sort -u
  )"

  if [[ -z "$raw" ]]; then
    AGNUDP_ON=0
    # ถ้ายังมีใน state (คนเลิกต่อไม่นาน) ให้นับจาก state
    if [[ -f "$STATE" ]]; then
      AGNUDP_ON=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\|[0-9]+$' "$STATE" 2>/dev/null)
      AGNUDP_ON=${AGNUDP_ON:-0}
    fi
    return
  fi

  filtered="$(
    echo "$raw" \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' 2>/dev/null \
      | grep -Ev "$INTERNAL_REGEX" 2>/dev/null
  )"

  if [[ -n "$LOCAL_IPS_REGEX" ]]; then
    filtered="$(echo "$filtered" | grep -Ev "$LOCAL_IPS_REGEX" 2>/dev/null || true)"
  fi

  # เขียน IP ที่เห็นรอบนี้ลง state (อัปเดต timestamp) - เฉพาะ IP ถูกต้อง
  for ip in $filtered; do
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    sed -i "/^${ip}|/d" "$STATE" 2>/dev/null
    echo "${ip}|${now_s}" >> "$STATE"
  done

  # ล้างบรรทัดผิดรูปใน state (ที่ไม่ใช่ IP|ts)
  sed -i '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+|[0-9]\+$/!d' "$STATE" 2>/dev/null

  if [[ -f "$STATE" ]]; then
    AGNUDP_ON=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\|[0-9]+$' "$STATE" 2>/dev/null)
    AGNUDP_ON=${AGNUDP_ON:-0}
  else
    AGNUDP_ON=0
  fi
}
count_agnudp
log_debug "AGN-UDP count: $AGNUDP_ON"

# กันค่าผิดรูป (มี newline/ตัวอักษร) ให้เหลือแค่ตัวเลข
clean_num() { local v="$1"; v=$(printf '%s' "$v" | tr -d '\n' | grep -oE '[0-9]+' | head -n1); printf '%s' "${v:-0}"; }
SSH_ON=$(clean_num "$SSH_ON")
DB_ON=$(clean_num "$DB_ON")
OVPN_ON=$(clean_num "$OVPN_ON")
V2_ON=$(clean_num "$V2_ON")
AGNUDP_ON=$(clean_num "$AGNUDP_ON")
DB_ON=${DB_ON:-0}
OVPN_ON=${OVPN_ON:-0}
V2_ON=${V2_ON:-0}
AGNUDP_ON=${AGNUDP_ON:-0}
LIMIT=${LIMIT:-200}

TOTAL=$(( SSH_ON + DB_ON + OVPN_ON + V2_ON + AGNUDP_ON ))

JSON_DATA=$(
  cat <<EOF
[{"onlines":"$TOTAL","limite":"$LIMIT","ssh":"$SSH_ON","openvpn":"$OVPN_ON","dropbear":"$DB_ON","v2ray":"$V2_ON","agnudp":"$AGNUDP_ON","timestamp":"$NOW"}]
EOF
)

echo -n "$JSON_DATA" > "$ONLINE_JSON"

# ===============================================
#  7) แก้ permission กัน 403
# ===============================================
chmod 755 "$WWW_DIR" 2>/dev/null || true
find "$WWW_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true

log "ONLINE: total=$TOTAL ssh=$SSH_ON ovpn=$OVPN_ON dropbear=$DB_ON v2=$V2_ON agnudp=$AGNUDP_ON"
log "=== ONLINE CHECK END ==="

rm -f "$TMP_COOKIE" 2>/dev/null || true

exit 0
