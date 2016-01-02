#!/bin/bash -
# virt-builder
# Copyright (C) 2013-2016 Red Hat Inc.
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

unset CDPATH
export LANG=C
set -e
set -x

# Hack for RWMJ
unset http_proxy

if [ $# -ne 1 ]; then
    echo "$0 VERSION"
    exit 1
fi

version=$1
output=rhel-$version-ppc64
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)
guestroot=/dev/rhel/root

case $version in
    7.*)
        major=7
        topurl=http://download.devel.redhat.com/released/RHEL-$major/$version
        tree=$topurl/Server/ppc64/os
        baseurl=$tree
        srpms=$topurl/Server/source/tree
        optional=$topurl/Server-optional/ppc64/os
        optionalsrpms=$topurl/Server-optional/source/tree
        ;;
    *)
        echo "$0: version $version not supported by this script yet"
        exit 1
esac

rm -f $output $output.old $output.xz

# Generate the kickstart to a temporary file.
ks=$(mktemp)
cat > $ks <<EOF
install
text
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
rootpw builder
firewall --enabled --ssh
timezone --utc America/New_York
selinux --enforcing
bootloader --location=mbr --append="console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
autopart --type=lvm

# Halt the system once configuration has finished.
poweroff

%packages
@core
%end
EOF

# Yum configuration.
yum=$(mktemp)
cat > $yum <<EOF
[rhel$major]
name=RHEL $major Server
baseurl=$baseurl
enabled=1
gpgcheck=0
keepcache=0

[rhel$major-source]
name=RHEL $major Server Source
baseurl=$srpms
enabled=0
gpgcheck=0
keepcache=0
EOF

if [ -n "$optional" ]; then
cat >> $yum <<EOF
[rhel$major-optional]
name=RHEL $major Server Optional
baseurl=$optional
enabled=1
gpgcheck=0
keepcache=0

[rhel$major-optional-source]
name=RHEL $major Server Optional
baseurl=$optionalsrpms
enabled=0
gpgcheck=0
keepcache=0
EOF
fi

# Clean up function.
cleanup ()
{
    rm -f $ks
    rm -f $yum
    virsh undefine $tmpname ||:
}
trap cleanup INT QUIT TERM EXIT ERR

virt-install \
    --name=$tmpname \
    --ram=4096 \
    --vcpus=1 \
    --os-type=linux --os-variant=rhel$major \
    --arch ppc64 --machine pseries \
    --initrd-inject=$ks \
    --extra-args="ks=file:/`basename $ks` console=tty0 console=ttyS0,115200" \
    --disk $(pwd)/$output,size=6,format=raw \
    --serial pty \
    --location=$tree \
    --nographics \
    --noreboot

# We have to replace yum config so it doesn't try to use RHN (it
# won't be registered).
guestfish --rw -a $output -m $guestroot \
  upload $yum /etc/yum.repos.d/download.devel.redhat.com.repo

source $(dirname "$0")/compress.sh $output
