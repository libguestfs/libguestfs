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
output=rhel-$version
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)
guestroot=/dev/sda3

case $version in
    3.*)
        major=3
        minor=`echo $version | awk -F. '{print $2}'`
        topurl=http://download.devel.redhat.com/released/RHEL-$major/U$minor/AS
        tree=$topurl/x86_64/tree
        srpms=$topurl/x86_64/tree/SRPMS
        bootfs=ext2
        rootfs=ext3
        guestroot=/dev/sda2
        ;;
    4.*)
        major=4
        minor=`echo $version | awk -F. '{print $2}'`
        topurl=http://download.devel.redhat.com/released/RHEL-$major/U$minor/AS
        tree=$topurl/x86_64/tree
        srpms=$topurl/x86_64/tree/SRPMS
        bootfs=ext2
        rootfs=ext3
        guestroot=/dev/sda2
        ;;
    5.*)
        major=5
        minor=`echo $version | awk -F. '{print $2}'`
        topurl=http://download.devel.redhat.com/released/RHEL-$major-Server/U$minor
        tree=$topurl/x86_64/os/Server
        srpms=$topurl/source/SRPMS
        bootfs=ext2
        rootfs=ext4
        guestroot=/dev/sda2
        ;;
    6.*)
        major=6
        topurl=http://download.devel.redhat.com/released/RHEL-$major/$version
        tree=$topurl/Server/x86_64/os
        srpms=$topurl/source/SRPMS
        optional=$topurl/Server/optional/x86_64/os
        optionalsrpms=$topurl/Server/optional/source/SRPMS
        bootfs=ext4
        rootfs=ext4
        ;;
    7.*)
        major=7
        topurl=http://download.devel.redhat.com/released/RHEL-$major/$version
        tree=$topurl/Server/x86_64/os
        srpms=$topurl/Server/source/tree
        optional=$topurl/Server-optional/x86_64/os
        optionalsrpms=$topurl/Server-optional/source/tree
        bootfs=ext4
        rootfs=xfs
        ;;
    *)
        echo "$0: version $version not supported by this script yet"
        exit 1
esac

rm -f $output $output.old $output.xz

# Generate the kickstart to a temporary file.
ks=$(mktemp)
cat > $ks <<'EOF'
install
text
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
rootpw builder
firewall --enabled --ssh
timezone --utc America/New_York
EOF

if [ $major -le 4 ]; then
cat >> $ks <<EOF
langsupport en_US
mouse generic
EOF
fi

if [ $major -ge 4 ]; then
cat >> $ks <<EOF
selinux --enforcing
EOF
fi

if [ $major -eq 5 ]; then
cat >> $ks <<EOF
key --skip
EOF
fi

cat >> $ks <<EOF
bootloader --location=mbr --append="console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
part /boot --fstype=$bootfs --size=512         --asprimary
part swap                   --size=1024        --asprimary
part /     --fstype=$rootfs --size=1024 --grow --asprimary

EOF

if [ $major -ge 4 ]; then
cat >> $ks <<EOF
# Halt the system once configuration has finished.
poweroff

EOF
fi

cat >> $ks <<EOF
%packages
@core
EOF

# RHEL 5 didn't understand the %end directive, but RHEL >= 6
# requires it.
if [ $major -ge 6 ]; then
cat >> $ks <<EOF
%end
EOF
fi

# Yum configuration.
yum=$(mktemp)
cat > $yum <<EOF
[rhel$major]
name=RHEL $major Server
baseurl=$tree
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
    --ram=2048 \
    --cpu=host --vcpus=2 \
    --os-type=linux --os-variant=rhel$major \
    --initrd-inject=$ks \
    --extra-args="ks=file:/`basename $ks` console=tty0 console=ttyS0,115200" \
    --disk $(pwd)/$output,size=6 \
    --serial pty \
    --location=$tree \
    --nographics \
    --noreboot

if [ $major -ge 5 ]; then
# We have to replace yum config so it doesn't try to use RHN (it
# won't be registered).
guestfish --rw -a $output -m $guestroot \
  upload $yum /etc/yum.repos.d/download.devel.redhat.com.repo
fi

source $(dirname "$0")/compress.sh $output
