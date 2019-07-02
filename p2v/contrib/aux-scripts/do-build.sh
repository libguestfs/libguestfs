#!/bin/bash -
# Auxiliary script for building virt-p2v ISO.
# Copyright (C) 2017 Red Hat Inc.
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

# See build-p2v-iso.sh

set -e
set -x

# Make sure we're in the virtual environment, and refuse to run otherwise.
if [ ! -f /var/tmp/livecd ]; then
    echo "$0: do not run this script directly"
    exit 1
fi

# If the script exits for any reason (including success) reboot.  This
# in fact powers off the virtual machine because we are using
# qemu -no-reboot.
trap reboot INT QUIT TERM EXIT ERR

cd /var/tmp

osversion=`cat osversion`
livecd=`cat livecd`
source ./proxy
prefix=`rpm --eval '%_prefix'`
libdir=`rpm --eval '%_libdir'`
sysconfdir=`rpm --eval '%_sysconfdir'`

# Build virt-p2v from libguestfs sources.
# We have to start from a tarball because at least RHEL 5 autotools
# isn't sufficiently new to run autoreconf.
zcat libguestfs.tar.gz | tar xf -
pushd libguestfs-*

# Various hacks for different versions of RHEL.
case $osversion in
    rhel-5.*|centos-5.*)
        # This just forces configure to ignore these missing dependencies.
        export LIBTINFO_CFLAGS=-D_GNU_SOURCE
        export LIBTINFO_LIBS=-lncurses
        export JANSSON_CFLAGS=-D_GNU_SOURCE
        export JANSSON_LIBS=-ljansson
        # Remove some unsupported flags that the configure script hard codes.
        sed -i -e 's/-fno-strict-overflow//' configure
        sed -i -e 's/-Wno-strict-overflow//' configure
        # Apply some RHEL 5 only patches.
        patch -p1 < ../patches/0001-RHEL-5-ONLY-DISABLE-AUTOMATIC-REMOTE-PORT-ALLOCATION.patch
        patch -p1 < ../patches/0002-RHEL-5-ONLY-QEMU-NBD-1.4-HAS-NO-f-OPTION.patch
        ;;
    rhel-6.*|centos-6.*)
        # This just forces configure to ignore these missing dependencies.
        export LIBTINFO_CFLAGS=-D_GNU_SOURCE
        export LIBTINFO_LIBS=-lncurses
        export JANSSON_CFLAGS=-D_GNU_SOURCE
        export JANSSON_LIBS=-ljansson
        ;;
esac

export vmchannel_test=no
./configure \
    --prefix $prefix \
    --libdir $libdir \
    --sysconfdir $sysconfdir \
    --disable-static \
    --disable-appliance \
    --disable-daemon \
    --disable-lua \
    --disable-ocaml \
    --disable-perl \
    --disable-php \
    --disable-python \
    --disable-ruby \
    --with-qemu=no
# We only need to build a handful of directories to get virt-p2v.
make -C generator
make -C gnulib/lib
make -C common/utils
make -C common/miniexpect
make -C p2v virt-p2v virt-p2v.xz dependencies.redhat
make run

# Check virt-p2v was built and runs.
./run ./p2v/virt-p2v --version
./run ./p2v/virt-p2v-make-kickstart --version

# Create the kickstart file.
if [ "x$http_proxy" != "x" ]; then proxy="--proxy=$http_proxy"; fi
./run ./p2v/virt-p2v-make-kickstart -o /var/tmp/p2v.ks $osversion $proxy

popd

# More hacks for different versions of RHEL.
case $osversion in
    rhel-5.*|centos-5.*)
        # RHEL 5 livecd-tools is broken with syslinux, this fixes it:
        sed -i -e 's,/usr/lib/syslinux/,/usr/share/syslinux/,g'\
            /usr/lib/python2.4/site-packages/imgcreate/live.py
        # livecd-tools cannot parse certain aspects of the kickstart:
        sed -i \
            -e 's/--plaintext//g' \
            -e 's/^firewall.*//g' \
            -e 's/^%end.*//g' \
            p2v.ks
        # Remove some packages which don't exist on RHEL 5:
        sed -i \
            -e 's,^dracut-live.*,,g' \
            -e 's,^dejavu-.*,,g' \
            -e 's,^mesa-dri-drivers.*,,g' \
            -e 's,^network-manager-applet.*,,g' \
            -e 's,^nm-connection-editor.*,,g' \
            -e 's,^/usr/bin/qemu-nbd.*,,g' \
            -e '/^net-tools/a syslinux' \
            p2v.ks
        # Remove systemctl lines, doesn't exist on RHEL 5.
        sed -i \
            -e 's/^\(systemctl.*\)/#\1/g' \
            p2v.ks
        ;;
    rhel-6.*|centos-6.*)
        # Remove some packages which don't exist on RHEL 6:
        sed -i \
            -e 's,^dracut-live.*,,g' \
            -e 's,^firewalld.*,,g' \
            -e 's,^network-manager-applet.*,,g' \
            -e 's,^nm-connection-editor.*,,g' \
            -e 's,^/usr/bin/qemu-nbd.*,,g' \
            p2v.ks
        # Remove systemctl lines, doesn't exist on RHEL 5.
        sed -i \
            -e 's/^\(systemctl.*\)/#\1/g' \
            p2v.ks
        ;;
esac

# Build nbdkit
zcat nbdkit.tar.gz | tar xf -
pushd nbdkit-*
./configure \
    CFLAGS="-D_GNU_SOURCE" \
    --prefix $prefix \
    --libdir $libdir \
    --sysconfdir $sysconfdir \
    --without-liblzma
make
cp src/nbdkit ..
cp plugins/file/.libs/nbdkit-file-plugin.so ..
popd
gzip -c nbdkit > nbdkit.gz
gzip -c nbdkit-file-plugin.so > nbdkit-file-plugin.so.gz
base64 nbdkit.gz > nbdkit.gz.b64
base64 nbdkit-file-plugin.so.gz > nbdkit-file-plugin.so.gz.b64

# Add nbdkit binaries to the kickstart.
echo > fragment.ks
echo '#' `md5sum nbdkit` >> fragment.ks
echo 'base64 -d -i <<EOF | gzip -cd > /usr/bin/nbdkit' >> fragment.ks
cat nbdkit.gz.b64 >> fragment.ks
echo >> fragment.ks
echo EOF >> fragment.ks
echo 'chmod 0755 /usr/bin/nbdkit' >> fragment.ks
echo >> fragment.ks

echo '#' `md5sum nbdkit-file-plugin.so` >> fragment.ks
echo 'mkdir -p' $libdir/nbdkit/plugins >> fragment.ks
echo 'base64 -d -i <<EOF | gzip -cd >' $libdir/nbdkit/plugins/nbdkit-file-plugin.so >> fragment.ks
cat nbdkit-file-plugin.so.gz.b64 >> fragment.ks
echo >> fragment.ks
echo EOF >> fragment.ks
echo 'chmod 0755' $libdir/nbdkit/plugins/nbdkit-file-plugin.so >> fragment.ks
echo >> fragment.ks

sed -i -e '/^chmod.*\/usr\/bin\/virt-p2v$/ r fragment.ks' p2v.ks

# Run livecd-creator to make the live CD.  The strange redirect works
# around a bug in RHEL 5's livecd-tools: "/sbin/mksquashfs: invalid
# option" is printed if the output is redirected to a file
# (https://bugs.centos.org/bug_view_page.php?bug_id=3738)
livecd-creator -c p2v.ks > `tty` 2>&1

# Move the live CD to the final filename.
mv livecd-*.iso $livecd
