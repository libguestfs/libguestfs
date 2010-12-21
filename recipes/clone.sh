#!/bin/sh -

preimage="$1"    ;# original guest
newimage="$2"    ;# new guest
root="$3"        ;# root filesystem
nameserver="$4"  ;# new nameserver
hostname="$5"    ;# new hostname

dd if="$preimage" of="$newimage" bs=1M

guestfish -a "$newimage" -m "$root" <<EOF
  write /etc/resolv.conf "nameserver $nameserver"
  write /etc/HOSTNAME "$hostname"
EOF
