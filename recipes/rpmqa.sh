#!/bin/sh -

guestfish <<EOF
add "$1"
run
mount-ro "$2" /
command "rpm -qa"
EOF
