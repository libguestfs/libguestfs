#!/bin/sh -

preimage="$1"
newimage="$2"
root="$3"
nameserver="$4"
hostname="$5"

dd if="$preimage" of="$newimage"

guestfish -a "$newimage" -m "$root" <<EOF
write /etc/resolv.conf "nameserver $nameserver"
write /etc/HOSTNAME "$hostname"
sync
EOF
