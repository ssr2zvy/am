#!/bin/sh
cd ~
if [ -x "/container_upa/container_mount/am/build-output/am" ]; then
    exec /container_upa/container_mount/am/build-output/am
fi
exec /container_upa/container_mount/am/upa/am
