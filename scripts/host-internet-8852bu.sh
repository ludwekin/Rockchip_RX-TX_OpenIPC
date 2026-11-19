#!/bin/bash
# Restore RTL8852BU to managed and reconnect to the normal WiFi
IF="${IF:-wlx6c1ff7475509}"
CONN="${CONN:-JUSHI_12}"
sudo ip link set "$IF" down
sudo iw dev "$IF" set type managed
sudo ip link set "$IF" up
sudo nmcli device set "$IF" managed yes
sleep 2
sudo nmcli connection up "$CONN"
iw dev "$IF" info | grep -E 'ssid|channel'
