#!/bin/sh
mkdir -p dev
[ -e dev/null ] || sudo mknod -m 666 dev/null c 1 3
[ -e dev/console ] || sudo mknod -m 600 dev/console c 5 1
[ -e dev/zero ] || sudo mknod -m 666 dev/zero c 1 5
[ -e dev/random ] || sudo mknod -m 444 dev/random c 1 8
