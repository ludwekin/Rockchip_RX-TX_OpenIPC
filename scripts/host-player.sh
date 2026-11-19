#!/bin/bash
# Play wfb-ng RTP H265 on the host desktop
gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
  caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
  ! rtpjitterbuffer latency=50 mode=none \
  ! rtph265depay ! h265parse \
  ! avdec_h265 ! autovideosink sync=false
