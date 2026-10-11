#!/bin/bash
QEMU="${QEMU:-qemu-system-arm}"
"$QEMU" \
  -M vexpress-a9 \
  -cpu cortex-a9 \
  -m 512M \
  -nographic \
  -kernel output/u-boot
