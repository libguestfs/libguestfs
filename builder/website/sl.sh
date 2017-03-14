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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
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
output=sl-$version
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

# We rebuild this every time there is a new 6.x release, and bump
# the revision in the index.
tree=http://www.mirrorservice.org/sites/ftp.scientificlinux.org/linux/scientific/$version/x86_64/os

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
part /boot --fstype=ext4 --size=512 --asprimary
part swap --size=1024 --asprimary
part / --fstype=ext4 --size=1024 --grow --asprimary

# Halt the system once configuration has finished.
poweroff

%packages
@core
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
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
output=sl-$version
tmpname=tmp-$(tr -cd 'a-f0-9' < /dev/urandom | head -c 8)

# We rebuild this every time there is a new 6.x release, and bump
# the revision in the index.
tree=http://www.mirrorservice.org/sites/ftp.scientificlinux.org/linux/scientific/$version/x86_64/os

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
part /boot --fstype=ext4 --size=512 --asprimary
part swap --size=1024 --asprimary
part / --fstype=ext4 --size=1024 --grow --asprimary

# Halt the system once configuration has finished.
poweroff

%packages
@core
%end
EOF

# Clean up function.
cleanup ()
{
    rm -f $ks
    virsh undefine $tmpname ||:
}
trap cleanup INT QUIT TERM EXIT ERR

virt-install \
    --name=$tmpname \
    --ram=2048 \
    --cpu=host --vcpus=2 \
    --os-type=linux --os-variant=rhel$version \
    --initrd-inject=$ks \
    --extra-args="ks=file:/`basename $ks` console=tty0 console=ttyS0,115200 proxy=$http_proxy" \
    --disk $(pwd)/$output,size=6 \
    --location=$tree \
    --nographics \
    --noreboot

# Sysprep (removes logfiles and so on).
# Note this also touches /.autorelabel so the further installation
# changes that we make will be labelled properly at first boot.
virt-sysprep -a $output

# Sparsify.
mv $output $output.old
virt-sparsify $output.old $output
rm $output.old

# Compress.
xz --best --block-size=16777216 $output

# Result:
ls -lh $output.xz
