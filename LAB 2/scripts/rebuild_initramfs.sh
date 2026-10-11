#!/bin/bash
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LAB2_DIR="$(dirname "$SCRIPT_DIR")"
ROOTFS="$LAB2_DIR/rootfs"
OUTPUT="$LAB2_DIR/output/initramfs_lab2.cpio.gz"

if [ ! -c "$ROOTFS/dev/console" ]; then
    echo "ERROR: rootfs/dev/console does not exist."
    echo "Run: sudo ./scripts/create_dev_nodes.sh"
    exit 1
fi

cd "$ROOTFS"
find . | cpio -H newc -o | gzip > "$OUTPUT"

echo "Created:"
ls -lh "$OUTPUT"
