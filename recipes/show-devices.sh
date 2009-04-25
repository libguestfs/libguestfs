#!/bin/sh -

guestfish -a "$1" <<EOF
run
list-devices
list-partitions
pvs
vgs
lvs
EOF
