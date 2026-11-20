#!/bin/bash
# Build Rockchip MPP (userspace) natively on the RK3566 board.
#
# The SDK prebuilt librockchip_mpp.so.0 needs GLIBC_2.38, but the board rootfs
# is glibc 2.35, so it cannot be copied as-is. Build from the SDK source with
# the board's own gcc instead.
#
# Source: <SDK>/external/mpp  (keep its build/ directory, it holds the CMake
#         modules; do NOT use rockchip-mpp-develop.tar, that is an install tree)
# Prereq: gcc, make, libdrm-dev, and cmake (aarch64 static tarball is fine).
#
# Usage: build-mpp-native.sh [source_dir] [build_dir]
set -e
SRC=${1:-/root/mppsrc}
OUT=${2:-/root/mppout}
CMAKE=${CMAKE:-/opt/cmake-3.28.3-linux-aarch64/bin/cmake}

rm -rf "$OUT"; mkdir -p "$OUT"; cd "$OUT"
"$CMAKE" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TEST=ON \
         -DCMAKE_INSTALL_PREFIX=/usr/local "$SRC"
make -j4

cp -a /usr/lib/aarch64-linux-gnu/librockchip_mpp.so.0 /root/librockchip_mpp.so.0.old 2>/dev/null || true
cp mpp/librockchip_mpp.so.0 /usr/lib/aarch64-linux-gnu/librockchip_mpp.so.0
ln -sf librockchip_mpp.so.0 /usr/lib/aarch64-linux-gnu/librockchip_mpp.so.1
ln -sf librockchip_mpp.so.0 /usr/lib/aarch64-linux-gnu/librockchip_mpp.so
ldconfig
echo "MPP installed. Decode benchmark:"
echo "  LD_LIBRARY_PATH=$OUT/mpp $OUT/test/mpi_dec_test -i cap.h265 -t 16777220 -w 1280 -h 720 -n 251 -o /dev/null"
