#!/bin/bash -
# virt-builder
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

set -e
set -x

# Some configuration.
export http_proxy=http://cache.home.annexia.org:3128
export https_proxy=$http_proxy
export ftp_proxy=$http_proxy

# We rebuild this every time there is a new 6.x release, and bump
# the revision in the index.
tree=http://mirror.bytemark.co.uk/centos/6.4/os/x86_64/

# Currently you have to run this script as root.
if [ `id -u` -ne 0 ]; then
    echo "You have to run this script as root."
    exit 1
fi

# Make sure it's being run from the correct directory.
if [ ! -f centos-6.ks ]; then
    echo "You are running this script from the wrong directory."
    exit 1
fi

pwd=`pwd`

virsh undefine tmpc6 ||:
rm -f centos-6 centos-6.old

virt-install \
    --name=tmpc6 \
    --ram 2048 \
    --cpu=host --vcpus=2 \
    --os-type=linux --os-variant=fedora18 \
    --initrd-inject=$pwd/centos-6.ks \
    --extra-args="ks=file:/centos-6.ks console=tty0 console=ttyS0,115200 proxy=$http_proxy" \
    --disk $pwd/centos-6,size=6 \
    --location=$tree \
    --nographics \
    --noreboot
# The virt-install command should exit after complete installation.
# Remove the guest, we don't want it to be defined in libvirt.
virsh undefine tmpc6

# Sysprep (removes logfiles and so on).
# Note this also touches /.autorelabel so the further installation
# changes that we make will be labelled properly at first boot.
virt-sysprep -a centos-6

# Sparsify.
mv centos-6 centos-6.old
virt-sparsify centos-6.old centos-6
rm centos-6.old

# Compress.
rm -f centos-6.xz
xz --best --block-size=16777216 centos-6

# Result:
ls -lh centos-6.xz
