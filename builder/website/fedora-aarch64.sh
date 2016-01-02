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

# Build Fedora images for aarch64 (secondary arch).

unset CDPATH
export LANG=C
set -e
set -x

if [ $# -ne 1 ]; then
    echo "$0 VERSION"
    exit 1
fi

version=$1
tree=https://download.fedoraproject.org/pub/fedora-secondary/releases/$version/Server/aarch64/os/
output=fedora-$version-aarch64
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

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

# Clean up function.
cleanup ()
{
    rm -f $ks
    virsh undefine --nvram $tmpname ||:
}
trap cleanup INT QUIT TERM EXIT ERR

# virt-install nvram_template option is broken for non-root users
# https://bugzilla.redhat.com/show_bug.cgi?id=1189143
# work around it:
vars=$(mktemp)
cp /usr/share/edk2.git/aarch64/vars-template-pflash.raw $vars

virt-install \
    --name=$tmpname \
    --ram=4096 \
    --cpu=host --vcpus=2 \
    --os-type=linux --os-variant=fedora21 \
    --boot loader=/usr/share/edk2.git/aarch64/QEMU_EFI-pflash.raw,loader_ro=yes,loader_type=pflash,nvram=$vars \
    --initrd-inject=$ks \
    --extra-args="ks=file:/`basename $ks` earlyprintk=pl011,0x9000000 ignore_loglevel console=ttyAMA0 no_timer_check printk.time=1 proxy=$http_proxy" \
    --disk $(pwd)/$output,size=6,format=raw \
    --serial pty \
    --location=$tree \
    --nographics \
    --noreboot

# NB: We need to preserve the nvram after installation since
# it contains the EFI boot variables set by grub.
cp $vars $output-nvram
xz --best $output-nvram

source $(dirname "$0")/compress.sh $output
