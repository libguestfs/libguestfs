#!/bin/bash -
# Test firstboot functionality.
# Copyright (C) 2016 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# This slow test checks that firstboot works.
#
# NB. 'test-firstboot.sh' runs the tests, but the various tests are
# run via the 'test-firstboot-GUESTNAME.sh' wrappers.

set -e
set -x

$TEST_FUNCTIONS
slow_test
skip_if_skipped "$script"

guestname="$1"
if [ -z "$guestname" ]; then
    echo "$script: guestname parameter not set, don't run this test directly."
    exit 1
fi

disk="firstboot-$guestname.img"
rm -f "$disk"

# If the guest doesn't exist in virt-builder, skip.  This is because
# we test some RHEL guests which most users won't have access to.
skip_unless_virt_builder_guest "$guestname"

# We can only run the tests on x86_64.
skip_unless_arch x86_64

# Check qemu is installed.
qemu=qemu-system-x86_64
skip_unless $qemu -help

# Some guests need special virt-builder parameters.
# See virt-builder --notes "$guestname"
declare -a extra
case "$guestname" in
    debian-6|debian-7)
        extra[${#extra[*]}]='--edit'
        extra[${#extra[*]}]='/etc/inittab:
                                s,^#([1-9].*respawn.*/sbin/getty.*),$1,'
        ;;
    fedora*|rhel*|centos*)
        extra[${#extra[*]}]='--selinux-relabel'
        ;;
    *)
        ;;
esac

# Build a guest (using virt-builder) with some firstboot commands.
#
# The script currently assumes a Linux guest.  We should test Windows,
# FreeBSD in future (XXX).
virt-builder "$guestname" \
             --quiet \
             -o "$disk" \
             --firstboot-command "mkdir /fb1; sleep 5" \
             --firstboot-command "touch /fb1/fb2; sleep 5" \
             --firstboot-command "poweroff" \
             "${extra[@]}"

# Boot the guest in qemu and wait for the firstboot scripts to run.
#
# Use IDE because some ancient guests don't support anything else.
#
# Adding a network device is not strictly necessary, but makes
# the Debian 7 guest happier.
$qemu \
    -nodefconfig \
    -display none \
    -machine accel=kvm:tcg \
    -m 2048 \
    -boot c \
    -drive file="$disk",format=raw,if=ide \
    -netdev user,id=usernet \
    -device rtl8139,netdev=usernet \
    -serial stdio ||:

# Did the firstboot scripts run?  And in the right order?  We can tell
# because the directory and file are created and so the 'stat'
# commands should not fail in guestfish.
guestfish --ro -a "$disk" -i \
    statns /fb1 : \
    statns /fb1/fb2

rm "$disk"
