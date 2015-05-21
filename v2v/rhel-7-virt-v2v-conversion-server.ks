# Kickstart file for creating the RHEL 7 virt-v2v conversion server appliance.
# (C) Copyright 2014-2015 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# NB: Use rhel-7-virt-v2v-conversion-server.config to build the appliance.
# Read the instructions at the top of that file.

lang en_US.UTF-8
keyboard us
timezone --utc GMT

rootpw --plaintext v2v

selinux --enforcing
firewall --enabled

network --bootproto=dhcp

bootloader --location=mbr --append="console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
zerombr
clearpart --all --initlabel
autopart --type=plain

reboot

# Repository lines.
# Note that brew ignores these and overrides them with the ones
# specified in the config file.

repo --name=rhel --baseurl=http://cdn.stage.redhat.com/content/dist/rhel/server/7/7.1/x86_64/os/
repo --name=v2v --baseurl=http://cdn.stage.redhat.com/content/dist/rhel/server/7/7Server/x86_64/openstack/6.0/os/
repo --name=v2vwin --baseurl=http://cdn.stage.redhat.com/content/dist/rhel/server/7/7Server/x86_64/v2vwin/os/

%packages

@core

# rpm must be installed, else you'll hit RHBZ#1089566.
rpm

# Note you must have a kernel, else the boot menu won't work:
kernel

# This is required in order for RHEL to set the root password.
passwd

# RHEL needs this in order to get networking.
NetworkManager

# Required to run firewall --enabled kickstart command:
firewalld

# The packages to install.
virt-v2v
libvirt-client
libguestfs-tools-c
libguestfs-xfs
libguestfs-winsupport
virtio-win

# Allow users to subscribe the appliance to RHN, if they wish.
subscription-manager

# Packages to make the bare system more usable.
emacs
#libguestfs-rescue
mlocate
net-tools
nfs-utils
ntp
sed
telnet

%end

# Post-install configuration.
%post

# /etc/issue

cat > /etc/issue << 'EOF'
Welcome to the Red Hat Enterprise Linux 7 virt-v2v conversion server.

Tips:

 * Login: root Password: v2v

 * Read the manual page before trying to use virt-v2v:   man virt-v2v

 * Find out which version of virt-v2v is installed:      rpm -q virt-v2v

 * To switch between virtual consoles, use ALT+F1, ALT+F2, etc.

 * If you need more disk space, mount NFS directories on /mnt.

 * virt-v2v is constrained by the speed and latency of the network.
   Use virtio-net and fast, local network connections where possible.

EOF

cp /etc/issue /etc/issue.net

# Remove HWADDR from ifcfg-*, else NetworkMangler will ignore
# it when it has a random MAC address on next boot.
for f in /etc/sysconfig/network-scripts/ifcfg-*; do
  sed -i '/^HWADDR.*/d' $f
done

# A little trick to speed up the first run of libguestfs.
LIBGUESTFS_BACKEND=direct guestfish -a /dev/null run >/dev/null 2>&1 ||:

%end
