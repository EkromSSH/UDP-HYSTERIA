#!/bin/bash
WWW="/home/vps/public_html/server"
mkdir -p "$WWW"

while true; do
  # Delta-based CPU (1s sample)
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
