#!/bin/bash
# Host (x86 Ubuntu) wfb-ng RX with RTL8812AU (aircrack 88XXau driver)
set -e
IF="${IF:-wlxbcec23d80c81}"
KEY="${KEY:-/etc/gs.key}"
CH="${CH:-161}"
STREAM_ID="${STREAM_ID:-7669206}"
sudo ip link set "$IF" down
sudo iw dev "$IF" set type monitor
sudo iw dev "$IF" set monitor otherbss fcsfail
sudo ip link set "$IF" up
sudo iw reg set US
sudo iw dev "$IF" set channel "$CH" HT20
iw dev "$IF" info | grep -E 'type|channel'
sudo pkill -x wfb_rx 2>/dev/null || true
sleep 1
sudo nohup wfb_rx -K "$KEY" -i "$STREAM_ID" -p 0 -u 5600 "$IF" >/root/wfb_rx.log 2>&1 &
sleep 5
sudo grep -E 'SESSION|PKT' /root/wfb_rx.log | tail -4 || true
