#!/bin/bash
set -euo pipefail

KSRC="${KSRC:-/lib/modules/$(uname -r)/build}"
KVER="${KVER:-6.1.141}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

echo "KSRC=$KSRC"
echo "KVER=$KVER"
echo "CROSS_COMPILE=$CROSS_COMPILE"

make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
     KSRC="$KSRC" KVER="$KVER" modules
