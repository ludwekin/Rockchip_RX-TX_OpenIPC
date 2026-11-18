#!/bin/bash
# OpenIPC RX pipeline (config driven, see /etc/openipc-rx.conf)
CONF=/etc/openipc-rx.conf
[ -f "$CONF" ] && . "$CONF"

IFACE=${IFACE:-wlxbcec23d80c81}
CH=${CH:-161}
BW=${BW:-HT20}
LOCAL_PORT=${LOCAL_PORT:-5602}
FORWARD_ENABLE=${FORWARD_ENABLE:-0}
FORWARD_IP=${FORWARD_IP:-}
FORWARD_PORT=${FORWARD_PORT:-5600}
CAPS="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265"

/usr/local/sbin/openipc-rx-setup.sh "$CH" "$BW" "$IFACE" || exit 1

pkill -f "wfb_rx" 2>/dev/null
pkill -f "gst-launch-1.0" 2>/dev/null
sleep 1

wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 "$IFACE" >/tmp/wfb_rx.log 2>&1 &
echo $! > /tmp/wfb_rx.pid
sleep 1

if [ "$FORWARD_ENABLE" = "1" ] && [ -n "$FORWARD_IP" ]; then
  gst-launch-1.0 -e udpsrc port=5600 caps="$CAPS" \
    ! tee name=t allow-not-linked=true \
    t. ! queue max-size-time=100000000 max-size-buffers=100 leaky=downstream \
       ! udpsink host="$FORWARD_IP" port="$FORWARD_PORT" sync=false \
    t. ! queue max-size-time=100000000 max-size-buffers=100 leaky=downstream \
       ! udpsink host=127.0.0.1 port="$LOCAL_PORT" sync=false \
    >/tmp/gst-rx.log 2>&1 &
  echo "forwarding to $FORWARD_IP:$FORWARD_PORT + local $LOCAL_PORT"
else
  echo "forwarding disabled, player reads wfb_rx port ${RX_PORT:-5600} directly"
fi
