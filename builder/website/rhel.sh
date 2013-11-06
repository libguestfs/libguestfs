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

if [ $# -ne 1 ]; then
    echo "$0 VERSION"
    exit 1
fi

version=$1
output=rhel-$version
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

case $version in
    6.*)
        major=6
        baseurl=http://download.devel.redhat.com/released/RHEL-$major/$version
        tree=$baseurl/Server/x86_64/os
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
bootloader --location=mbr --append="console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
part /boot --fstype=ext4 --size=512         --asprimary
part swap                --size=1024        --asprimary
part /     --fstype=ext4 --size=1024 --grow --asprimary

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
baseurl=$baseurl/Server/x86_64/os/
enabled=1
gpgcheck=0
keepcache=0

[rhel$major-source]
name=RHEL $major Server Source
baseurl=$baseurl/source/SRPMS/
enabled=0
gpgcheck=0
keepcache=0

[rhel$major-optional]
name=RHEL $major Server Optional
baseurl=$baseurl/Server/optional/x86_64/os/
enabled=1
gpgcheck=0
keepcache=0

[rhel$major-optional-source]
name=RHEL $major Server Optional
baseurl=$baseurl/Server/optional/source/SRPMS/
enabled=0
gpgcheck=0
keepcache=0
EOF

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
    --location=$tree \
    --nographics \
    --noreboot

# We have to replace yum config so it doesn't try to use RHN (it
# won't be registered).
guestfish --rw -a $output -m /dev/sda3 \
  upload $yum /etc/yum.repos.d/download.devel.redhat.com.repo

source $(dirname "$0")/compress.sh $output
