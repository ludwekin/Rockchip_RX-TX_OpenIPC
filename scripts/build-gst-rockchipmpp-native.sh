#!/bin/bash
set -e
mkdir -p /root/gstdeps/usr/lib
cd /root/gstdeps/usr/lib
for l in gstreamer-1.0 gstvideo-1.0 gstbase-1.0 gstallocators-1.0 gstpbutils-1.0 gstaudio-1.0 glib-2.0 gobject-2.0 gmodule-2.0 gio-2.0; do
  if [ -e /usr/lib/aarch64-linux-gnu/lib$l.so.0 ]; then ln -sf /usr/lib/aarch64-linux-gnu/lib$l.so.0 lib$l.so; fi
done
export PKG_CONFIG_PATH=/root/gstdeps/usr/lib/pkgconfig
export PKG_CONFIG_LIBDIR=/root/gstdeps/usr/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/root/gstdeps
sed -i 's/define GST_VERSION_MINOR (24)/define GST_VERSION_MINOR (20)/' /root/gstdeps/usr/include/gstreamer-1.0/gst/gstversion.h
sed -i 's/define GST_VERSION_MICRO (13)/define GST_VERSION_MICRO (3)/' /root/gstdeps/usr/include/gstreamer-1.0/gst/gstversion.h
cd /root/gstplug
CF=$(pkg-config --cflags gstreamer-1.0 gstreamer-video-1.0 gstreamer-base-1.0 gstreamer-allocators-1.0 gstreamer-pbutils-1.0)
LB=$(pkg-config --libs gstreamer-1.0 gstreamer-video-1.0 gstreamer-base-1.0 gstreamer-allocators-1.0 gstreamer-pbutils-1.0)
echo "CF=$CF"
echo "LB=$LB"
gcc -shared -fPIC -O2 -DHAVE_CONFIG_H '-DUNUSED=__attribute__((unused))' -I/root/gstplug -I/root/mppbuild/usr/include $CF \
  -o /root/libgstrockchipmpp_new.so \
  gstmpp.c gstmppallocator.c gstmppdec.c gstmppjpegdec.c gstmppvideodec.c \
  gstmppenc.c gstmppjpegenc.c gstmpph264enc.c gstmpph265enc.c gstmppvp8enc.c \
  -L/root/gstdeps/usr/lib $LB -lrockchip_mpp
ls -l /root/libgstrockchipmpp_new.so
