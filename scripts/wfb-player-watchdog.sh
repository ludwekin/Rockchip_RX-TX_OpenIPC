#!/bin/bash
HB=/tmp/osd-metrics.log
APP=/usr/local/sbin/openipc-kms-osd.py
LOG=/tmp/player-watchdog.log
while true; do
    sleep 2
    if ! pgrep -x python3 >/dev/null; then
        echo "$(date '+%F %T') player not running, starting" >>"$LOG"
        nohup python3 "$APP" >/tmp/osd.log 2>&1 &
        sleep 5
        continue
    fi
    now=$(date +%s)
    m=$(stat -c %Y "$HB" 2>/dev/null || echo 0)
    if [ $((now - m)) -gt 5 ]; then
        echo "$(date '+%F %T') player stalled $((now - m))s, restarting" >>"$LOG"
        pkill -9 -x python3
        sleep 1
        nohup python3 "$APP" >/tmp/osd.log 2>&1 &
        sleep 5
    fi
done
