#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LAB2_DIR="$(dirname "$SCRIPT_DIR")"
DEV="$LAB2_DIR/rootfs/dev"

mkdir -p "$DEV"

[ -e "$DEV/console" ] || sudo mknod -m 600 "$DEV/console" c 5 1
[ -e "$DEV/null"    ] || sudo mknod -m 666 "$DEV/null" c 1 3
[ -e "$DEV/zero"    ] || sudo mknod -m 666 "$DEV/zero" c 1 5
[ -e "$DEV/random"  ] || sudo mknod -m 444 "$DEV/random" c 1 8

echo "Device nodes created successfully."
