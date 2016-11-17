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
output=rhel-$version-aarch64
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)
guestroot=/dev/sda4

case $version in
    7.*)
        major=7
        topurl=http://download.eng.bos.redhat.com/released/RHEL-7/$version/
        tree=$topurl/Server/aarch64/os
        baseurl=$tree
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
reboot
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
rootpw builder
firewall --enabled --ssh
selinux --enforcing
timezone --utc America/New_York
bootloader --location=mbr --append="console=ttyAMA0 earlyprintk=pl011,0x9000000 ignore_loglevel no_timer_check printk.time=1 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
autopart --type=plain

# Halt the system once configuration has finished.
poweroff

%packages
@core
%end

%post
# Rerun dracut for the installed kernel (not the running kernel):
KERNEL_VERSION=$(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n')
dracut -f /boot/initramfs-$KERNEL_VERSION.img $KERNEL_VERSION
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
    virsh undefine --nvram $tmpname ||:
}
trap cleanup INT QUIT TERM EXIT ERR

# virt-install nvram_template option is broken for non-root users
# https://bugzilla.redhat.com/show_bug.cgi?id=1189143
# work around it:
vars=$(mktemp)
cp /usr/share/edk2/aarch64/vars-template-pflash.raw $vars

virt-install \
    --name=$tmpname \
    --ram=2048 \
    --vcpus=1 \
    --os-type=linux --os-variant=rhel$major \
    --arch aarch64 \
    --boot loader=/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw,loader_ro=yes,loader_type=pflash,nvram=$vars \
    --initrd-inject=$ks \
    --extra-args="ks=file:/`basename $ks` earlyprintk=pl011,0x9000000 ignore_loglevel console=ttyAMA0 no_timer_check printk.time=1" \
    --disk $(pwd)/$output,size=6,format=raw \
    --serial pty \
    --location=$tree \
    --nographics \
    --noreboot

# NB: We need to preserve the nvram after installation since
# it contains the EFI boot variables set by grub.
cp $vars $output-nvram

# We have to replace yum config so it doesn't try to use RHN (it
# won't be registered).
guestfish --rw -a $output -m $guestroot \
  upload $yum /etc/yum.repos.d/download.devel.redhat.com.repo

DO_RELABEL=1

source $(dirname "$0")/compress.sh $output
