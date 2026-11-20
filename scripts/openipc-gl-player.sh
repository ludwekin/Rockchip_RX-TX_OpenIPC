#!/bin/bash
# OpenIPC H.265 RX player for the DSI panel (hardware MPP decode + Mali GL).
[ -f /etc/openipc-rx.conf ] && . /etc/openipc-rx.conf
PORT=${RX_PORT:-5600}
CAPS="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265"
export GST_GL_WINDOW=gbm
export GST_GL_PLATFORM=egl
export GST_GL_API=gles2
export COGL_DRIVER=gles2
export DISPLAY=:0
exec gst-launch-1.0 -e \
  udpsrc port="$PORT" buffer-size=33554432 caps="$CAPS" \
  ! rtpjitterbuffer latency=100 mode=none \
  ! rtph265depay ! h265parse \
  ! video/x-h265,stream-format=byte-stream,alignment=au \
  ! mppvideodec fast-mode=true \
  ! queue leaky=downstream max-size-buffers=3 max-size-time=0 max-size-bytes=0 \
  ! glupload ! glcolorconvert ! glvideoflip method=counterclockwise \
  ! glimagesink sync=false
