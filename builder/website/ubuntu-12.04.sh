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
# https://help.ubuntu.com/10.04/installation-guide/i386/preseed-using.html

set -e
set -x

# Some configuration.
#export http_proxy=http://squid.corp.redhat.com:3128
#export https_proxy=$http_proxy
#export ftp_proxy=$http_proxy
location=http://archive.ubuntu.net/ubuntu/dists/precise/main/installer-amd64

# Currently you have to run this script as root.
if [ `id -u` -ne 0 ]; then
    echo "You have to run this script as root."
    exit 1
fi

# Make sure it's being run from the correct directory.
if [ ! -f ubuntu-12.04.preseed ]; then
    echo "You are running this script from the wrong directory."
    exit 1
fi

pwd=`pwd`

# Note that the injected file must be called "/preseed.cfg" in order
# for d-i to pick it up.
sed -e "s,@CACHE@,$http_proxy,g" < ubuntu-12.04.preseed > preseed.cfg

name=tmpprecise

virsh undefine $name ||:
rm -f ubuntu-12.04 ubuntu-12.04.old

virt-install \
    --name $name \
    --ram=1024 \
    --os-type=linux --os-variant=ubuntuprecise \
    --initrd-inject=$pwd/preseed.cfg \
    --extra-args="auto console=tty0 console=ttyS0,115200" \
    --disk=$pwd/ubuntu-12.04,size=4 \
    --location=$location \
    --nographics \
    --noreboot
# The virt-install command should exit after complete installation.
# Remove the guest, we don't want it to be defined in libvirt.
virsh undefine $name

rm preseed.cfg

# Sysprep (removes logfiles and so on).
virt-sysprep -a ubuntu-12.04

# Sparsify.
mv ubuntu-12.04 ubuntu-12.04.old
virt-sparsify ubuntu-12.04.old ubuntu-12.04
rm ubuntu-12.04.old

# Compress.
rm -f ubuntu-12.04.xz
xz --best --block-size=16777216 ubuntu-12.04

# Result:
ls -lh ubuntu-12.04.xz
