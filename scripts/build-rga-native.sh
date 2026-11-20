#!/bin/bash
# Build librga (Rockchip RGA userspace) natively on the board.
#
# The stock 1.3.2 (2021) librga does not match the 6.1 kernel RGA driver and
# every RgaBlit() fails with "Invalid argument". The SDK has 1.10.5; build it
# with the board gcc (glibc 2.35) so it can load.
#
# Source: <SDK>/external/linux-rga
# Prereq: gcc/g++, make, libdrm-dev, cmake.
#
# Usage: build-rga-native.sh [source_dir] [build_dir]
set -e
SRC=${1:-/root/rgasrc}
OUT=${2:-/root/rgaout}
CMAKE=${CMAKE:-/opt/cmake-3.28.3-linux-aarch64/bin/cmake}

rm -rf "$OUT"; mkdir -p "$OUT"; cd "$OUT"
"$CMAKE" -DCMAKE_BUILD_TYPE=Release -DCMAKE_BUILD_TARGET=buildroot \
         -DCMAKE_INSTALL_PREFIX=/usr/local "$SRC"
# Samples may fail (missing utils.h include path); the library is what we need.
make -j4 || true
if [ ! -f "$OUT/librga.so" ]; then
  echo "ERROR: librga.so was not built" >&2
  exit 1
fi

cp -a /usr/lib/aarch64-linux-gnu/librga.so.2.1.0 /root/librga.so.2.1.0.old 2>/dev/null || true
cp "$OUT/librga.so" /usr/lib/aarch64-linux-gnu/librga.so.2.1.0
ln -sf librga.so.2.1.0 /usr/lib/aarch64-linux-gnu/librga.so.2
ln -sf librga.so.2 /usr/lib/aarch64-linux-gnu/librga.so
ldconfig
echo "librga installed: $(strings "$OUT/librga.so" | grep -m1 'rga_api version')"
