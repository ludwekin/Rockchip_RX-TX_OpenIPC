#!/bin/bash
# OpenIPC RX: put RTL8812AU into monitor mode
# Usage: openipc-rx-setup.sh [channel] [bandwidth] [interface]
IFACE=${3:-wlxbcec23d80c81}
CHANNEL=${1:-161}
BW=${2:-HT20}

ip link set "$IFACE" down
iw dev "$IFACE" set type monitor
iw dev "$IFACE" set monitor otherbss fcsfail
ip link set "$IFACE" up
iw reg set US >/dev/null 2>&1
iw dev "$IFACE" set channel "$CHANNEL" "$BW"
iw dev "$IFACE" info
