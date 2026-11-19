#!/bin/bash
# Backup RX using RTL8852BU (rtw89) in monitor mode
set -e
IF="${IF:-wlx6c1ff7475509}"
KEY="${KEY:-/etc/gs.key}"
sudo nmcli device set "$IF" managed no 2>/dev/null || true
sudo ip link set "$IF" down
sudo iw dev "$IF" set type monitor
sudo ip link set "$IF" up
sudo iw reg set US
sudo iw dev "$IF" set channel 161 HT20
iw dev "$IF" info | grep -E 'type|channel'
sudo pkill -x wfb_rx 2>/dev/null || true
sleep 1
sudo nohup wfb_rx -K "$KEY" -i 7669206 -p 0 -u 5600 "$IF" >/root/wfb_rx.log 2>&1 &
