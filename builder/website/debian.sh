#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
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

# The basic plan comes from:
# http://honk.sigxcpu.org/con/Preseeding_Debian_virtual_machines_with_virt_install.html
# https://wiki.debian.org/DebianInstaller/Preseed

unset CDPATH
export LANG=C
set -e
set -x

if [ $# -ne 2 ]; then
    echo "$0 VERSION DIST"
    exit 1
fi

# Some configuration.
version=$1
dist=$2
location=http://ftp.uk.debian.org/debian/dists/$dist/main/installer-amd64
output=debian-$version
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

rm -f $output $output.old $output.xz

# Make sure it's being run from the correct directory.
if [ ! -f debian.preseed ]; then
    echo "You are running this script from the wrong directory."
    exit 1
fi

# Note that the injected file must be called "/preseed.cfg" in order
# for d-i to pick it up.
sed -e "s,@CACHE@,$http_proxy,g" < debian.preseed > preseed.cfg

# Clean up function.
cleanup ()
{
    rm -f preseed.cfg
    virsh undefine $tmpname ||:
}
trap cleanup INT QUIT TERM EXIT ERR

virt-install \
    --name=$tmpname \
    --ram=1024 \
    --os-type=linux --os-variant=debian$dist \
    --initrd-inject=$(pwd)/preseed.cfg \
    --extra-args="auto console=tty0 console=ttyS0,115200" \
    --disk=$(pwd)/$output,size=4,format=raw \
    --serial pty \
    --location=$location \
    --nographics \
    --noreboot

# Remove apt proxy configuration (thanks: Daniel Miranda).
guestfish -a $output -i <<EOF
  rm /etc/apt/apt.conf
  touch /etc/apt/apt.conf
EOF

source $(dirname "$0")/compress.sh $output
