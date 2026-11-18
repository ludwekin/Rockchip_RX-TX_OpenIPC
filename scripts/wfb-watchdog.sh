#!/bin/bash
IF=wlxbcec23d80c81
LOG=/tmp/wfb_rx.log
PLAYLOG=/tmp/play.log
STALL=6

log() { echo "$(date '+%F %T') $*" >>/tmp/wfb-watchdog.log; }

start_rx() {
    pkill -9 -x wfb_rx 2>/dev/null
    sleep 1
    nohup wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 "$IF" >"$LOG" 2>&1 &
}

start_player() {
    pkill -9 -x gst-launch-1.0 2>/dev/null
    sleep 1
    if [ "$(cat /sys/class/drm/card0-DSI-1/status 2>/dev/null)" = "connected" ]; then
        # 3.1" MIPI DSI 480x800: rotate landscape -> portrait, fit with borders
        nohup gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
            caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
            ! rtpjitterbuffer latency=0 mode=none \
            ! rtph265depay ! h265parse \
            ! video/x-h265,stream-format=byte-stream,alignment=au \
            ! mppvideodec \
            ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 \
            ! videoconvert \
            ! videoflip method=counterclockwise \
            ! videoscale add-borders=true \
            ! video/x-raw,width=480,height=800 \
            ! kmssink sync=false >"$PLAYLOG" 2>&1 &
    else
        # HDMI
        nohup gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
            caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
            ! rtpjitterbuffer latency=0 mode=none \
            ! rtph265depay ! h265parse \
            ! video/x-h265,stream-format=byte-stream,alignment=au \
            ! mppvideodec \
            ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 \
            ! videoconvert \
            ! kmssink force-modesetting=true sync=false >"$PLAYLOG" 2>&1 &
    fi
}

ensure_monitor() {
    if [ ! -e "/sys/class/net/$IF" ]; then
        modprobe 88XXau rtw_usb_rxagg_mode=0 2>/dev/null
        for _ in $(seq 1 20); do
            [ -e "/sys/class/net/$IF" ] && break
            sleep 1
        done
    fi
    [ -e "/sys/class/net/$IF" ] || return 1

    local ch type
    type=$(cat "/sys/class/net/$IF/type" 2>/dev/null)
    ch=$(iw dev "$IF" info 2>/dev/null | sed -n 's/.*channel \([0-9][0-9]*\).*/\1/p')
    if [ "$type" = "803" ] && [ "$ch" = "161" ]; then
        return 0
    fi

    log "monitor/channel lost (type=$type ch=$ch), restoring"
    ip link set "$IF" down 2>/dev/null
    iw dev "$IF" set type monitor 2>/dev/null
    iw dev "$IF" set monitor otherbss fcsfail 2>/dev/null
    ip link set "$IF" up 2>/dev/null
    iw reg set US 2>/dev/null
    iw dev "$IF" set channel 161 HT20 2>/dev/null
    type=$(cat "/sys/class/net/$IF/type" 2>/dev/null)
    ch=$(iw dev "$IF" info 2>/dev/null | sed -n 's/.*channel \([0-9][0-9]*\).*/\1/p')
    if [ "$type" = "803" ] && [ "$ch" = "161" ]; then
        return 0
    fi

    log "channel still $ch, reloading 88XXau"
    modprobe -r bcmdhd 2>/dev/null
    modprobe -r 88XXau 2>/dev/null
    sleep 2
    modprobe 88XXau rtw_usb_rxagg_mode=0 2>/dev/null
    sleep 4
    ip link set "$IF" down 2>/dev/null
    iw dev "$IF" set type monitor 2>/dev/null
    iw dev "$IF" set monitor otherbss fcsfail 2>/dev/null
    ip link set "$IF" up 2>/dev/null
    iw reg set US 2>/dev/null
    iw dev "$IF" set channel 161 HT20 2>/dev/null
}

# one-time environment setup
systemctl stop NetworkManager.service wpa_supplicant.service 2>/dev/null
pkill -x wpa_supplicant 2>/dev/null
pkill -x hostapd 2>/dev/null
ip link set wlan0 down 2>/dev/null
modprobe -r bcmdhd 2>/dev/null
modprobe 88XXau rtw_usb_rxagg_mode=0 2>/dev/null

ensure_monitor
pgrep -x wfb_rx >/dev/null || start_rx
sleep 2
pgrep -x gst-launch-1.0 >/dev/null || start_player

while true; do
    now=$(date +%s)
    if ! pgrep -x wfb_rx >/dev/null; then
        log "wfb_rx not running, starting"
        ensure_monitor
        start_rx
        sleep 2
        start_player
        sleep 6
    else
        m=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
        if [ $((now - m)) -gt "$STALL" ]; then
            log "no packets for $((now - m))s, restarting pipeline"
            ensure_monitor
            start_rx
            sleep 2
            start_player
            sleep 8
        fi
    fi
    if pgrep -x wfb_rx >/dev/null && ! pgrep -x gst-launch-1.0 >/dev/null; then
        log "player not running, starting"
        start_player
        sleep 4
    fi
    sleep 2
done
