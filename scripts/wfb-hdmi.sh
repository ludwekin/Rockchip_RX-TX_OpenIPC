#!/bin/bash
IF=wlxbcec23d80c81
systemctl stop NetworkManager.service wpa_supplicant.service 2>/dev/null
pkill -x wpa_supplicant 2>/dev/null
pkill -x hostapd 2>/dev/null
ip link set wlan0 down 2>/dev/null
modprobe -r bcmdhd 2>/dev/null
sleep 1
modprobe -r 88XXau 2>/dev/null
sleep 2
modprobe 88XXau rtw_usb_rxagg_mode=0 2>/dev/null

for i in $(seq 1 600); do
    [ -e /sys/class/net/$IF ] && break
    sleep 1
done
[ -e /sys/class/net/$IF ] || { echo "no iface" > /tmp/wfb-hdmi.log; exit 1; }

ip link set "$IF" down
iw dev "$IF" set type monitor
iw dev "$IF" set monitor otherbss fcsfail
ip link set "$IF" up
iw reg set US 2>/dev/null
iw dev "$IF" set channel 161 HT20
iw dev "$IF" info > /tmp/wfb-iface.txt 2>&1

pkill -x wfb_rx 2>/dev/null
nohup wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 "$IF" >/tmp/wfb_rx.log 2>&1 &

for i in $(seq 1 600); do
    [ "$(cat /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null)" = "connected" ] && break
    sleep 1
done

pkill -x gst-launch-1.0 2>/dev/null
nohup gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
  caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
  ! rtpjitterbuffer latency=0 mode=none ! rtph265depay ! h265parse \
  ! video/x-h265,stream-format=byte-stream,alignment=au \
  ! mppvideodec \
  ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 \
  ! videoconvert \
  ! kmssink force-modesetting=true sync=false >/tmp/play.log 2>&1 &
