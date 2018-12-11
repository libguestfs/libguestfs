#!/bin/bash -
# Test serial console is present in templates.
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

# This slow test checks that the serial console works.
#
# NB. 'test-console.sh' runs the tests, but the various tests are
# run via the 'test-console-GUESTNAME.sh' wrappers.
#
# The script currently assumes a Linux guest.  We should test Windows,
# FreeBSD in future (XXX).

set -e

$TEST_FUNCTIONS
slow_test
skip_if_skipped "$script"

guestname="$1"
if [ -z "$guestname" ]; then
    echo "$script: guestname parameter not set, don't run this test directly."
    exit 1
fi

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
    debian-7)
        extra[${#extra[*]}]='--edit'
        extra[${#extra[*]}]='/etc/inittab:
                                s,^#([1-9].*respawn.*/sbin/getty.*),$1,'
        ;;
    debian-8|ubuntu-16.04|ubuntu-18.04)
        # These commands are required to fix the serial console.
        # See https://askubuntu.com/questions/763908/ubuntu-16-04-has-no-vmware-console-access-once-booted-on-vmware-vsphere-5-5-clus/764476#764476
        extra[${#extra[*]}]='--edit'
        extra[${#extra[*]}]='/etc/default/grub:
            s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"/'
        extra[${#extra[*]}]='--run-command'
        extra[${#extra[*]}]='update-grub'
        ;;
    *)
        ;;
esac

disk="console-$guestname.img"
rm -f "$disk"

# Build a guest (using virt-builder).
virt-builder "$guestname" \
             --quiet \
             -o "$disk" \
             "${extra[@]}"

out="console-$guestname.out"
rm -f "$out"

# Boot the guest in qemu with a serial console.  Allow it to run
# for a set amount of time, and then kill it.
$qemu \
    -no-user-config \
    -display none \
    -machine accel=kvm:tcg \
    -m 1024 \
    -boot c \
    -drive file="$disk",format=raw,if=ide \
    -serial stdio > "$out" &
pid=$!
sleep 180
kill -9 $pid

# Did we see console output?
err ()
{
    set +e
    echo "$script: didn't see $1 in serial console output"
    echo "$script: full output from the serial console below"
    echo
    cat "$out"
    exit 1
}

grub_rex="(highlighted|selected) entry will be (started|executed) automatically"

case "$guestname" in
    centos-7.*|rhel-7.*)
        grep -Esq "$grub_rex" "$out" ||
            err "GRUB messages"
        grep -Esq "Linux version [0-9]" "$out" || err "Linux kernel messages"
        grep -sq "Reached target Basic System" "$out" || err "systemd messages"
        grep -sq "^Kernel [0-9]" "$out" || err "login banner"
        grep -sq "login:" "$out" || err "login prompt"
        ;;
    debian-*)
        grep -Esq "$grub_rex" "$out" ||
            err "GRUB messages"
        # Debian boots with 'quiet' so no kernel messages seen.
        grep -sq "^Debian GNU/Linux" "$out" || err "login banner"
        grep -sq "login:" "$out" || err "login prompt"
        ;;
    fedora-*)
        grep -Esq "$grub_rex" "$out" ||
            err "GRUB messages"
        grep -Esq "Linux version [0-9]" "$out" || err "Linux kernel messages"
        grep -sq "Reached target Basic System" "$out" || err "systemd messages"
        grep -sq "^Kernel.*(ttyS0)" "$out" || err "login banner"
        grep -sq "login:" "$out" || err "login prompt"
        ;;
    ubuntu-*)
        # Ubuntu boot is very quiet, but we should see a banner and
        # a login prompt at the end.
        grep -sq "^Ubuntu" "$out" || err "login banner"
        grep -sq "login:" "$out" || err "login prompt"
        ;;
    *)
        # Fall back to only checking we see a login prompt.
        grep -sq "login:" "$out" || err "login prompt"
        ;;
esac

rm "$disk" "$out"
