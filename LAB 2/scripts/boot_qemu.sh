#!/bin/bash
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LAB2_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$LAB2_DIR")"
QEMU="${QEMU:-qemu-system-arm}"

"$QEMU" \
  -M vexpress-a9 \
  -cpu cortex-a9 \
  -m 512M \
  -smp 2 \
  -nographic \
  -kernel "$REPO_DIR/LAB 1/output/zImage" \
  -dtb "$REPO_DIR/LAB 1/output/vexpress-v2p-ca9.dtb" \
  -initrd "$LAB2_DIR/output/initramfs_lab2.cpio.gz" \
  -append 'console=ttyAMA0,115200 rdinit=/sbin/init mem=512M'
