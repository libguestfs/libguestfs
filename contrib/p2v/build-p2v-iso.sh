#!/bin/bash -
# Build virt-p2v ISO for RHEL 5/6/7.
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

# This script is used to build the virt-p2v ISO on RHEL 5/6/7,
# for 32 bit (i686) and 64 bit (x86-64).
#
# This script is *not* used to build the official RHEL 7 virt-p2v ISO
# for Red Hat customers.  However it is used to build alternate ISOs
# which can optionally be used by customers who need older RHEL
# (eg. for proprietary FakeRAID drivers), or have 32 bit physical
# machines that they wish to virtualize.
#
# The virt-p2v ISOs built by this script are hosted at:
# http://oirase.annexia.org/virt-p2v/

set -e

usage ()
{
    echo '      libguestfs and nbdkit tarballs'
    echo '      (http URLs may also be used here)'
    echo '                       |'
    echo './build-p2v-iso.sh file:///path/to/libguestfs-1.XX.YY.tar.gz \'
    echo '                   file:///path/to/nbdkit-1.XX.YY.tar.gz \'
    echo '                   rhel-5.11 i686'
    echo '                      |       |'
    echo '                      |       `--- architecture (i686 or x86_64)'
    echo '                      `---- version of RHEL (5.x or 6.x tested)'
    echo
    echo 'Note this downloads the libguestfs tarball from upstream, it'
    echo 'does not use libguestfs from the current directory.'
    echo
    echo 'Minimum versions of: libguestfs = 1.35.22'
    echo '                     nbdkit = 1.1.13'
    echo
    echo 'You should run the script on a Fedora (or recent Linux) host.'
    echo 'It uses virt-builder to create the RHEL environment'
    exit 0
}

if [ $# -ne 4 ]; then
    usage
fi

tmpdir="$(mktemp -d)"
cleanup ()
{
    rm -rf "$tmpdir"
}
trap cleanup INT QUIT TERM EXIT ERR

libguestfs_tarball=$1
nbdkit_tarball=$2
osversion=$3
arch=$4

# Get the path to the auxiliary script.
d="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ ! -d "$d/aux-scripts" ]; then
    echo "$0: error: cannot locate auxiliary scripts"
    exit 1
fi

# Build the list of packages needed for the build environment.
pkgs=augeas-devel,bison,coreutils,cpio,file-devel,flex,gcc,gperf,gtk2-devel,libxml2-devel,livecd-tools,mkisofs,ncurses-devel,patch,perl-Pod-Man,perl-Pod-Simple,pcre-devel,/usr/bin/pod2text,syslinux,syslinux-extlinux,xz,xz-devel

for f in `cat $d/../../p2v/dependencies.redhat`; do
    pkgs="$pkgs,$f"
done

# Various hacks for different versions of RHEL.
if=virtio
netdev=virtio-net-pci
declare -a epel
case $osversion in
    rhel-5.*|centos-5.*)
        if=ide
        netdev=rtl8139
        # RHEL 5 yum cannot download a package.
        curl -o $tmpdir/epel-release.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-5.noarch.rpm
        epel[0]="--upload"
        epel[1]="$tmpdir/epel-release.rpm:/var/tmp"
        # RHEL 5 i686 template has a broken RPM DB, so rebuild it.
        epel[2]="--run-command"
        epel[3]="rm -f /var/lib/rpm/__db*; rpm -vv --rebuilddb"
        epel[4]="--run-command"
        epel[5]="yum install -y --nogpgcheck /var/tmp/epel-release.rpm"
        ;;
    rhel-6.*|centos-6.*)
        epel[0]="--run-command"
        epel[1]="yum install -y --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
        pkgs="$pkgs,jansson-devel"
        ;;
    rhel-7.*|centos-7.*)
        epel[0]="--run-command"
        epel[1]="yum install -y --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
        pkgs="$pkgs,jansson-devel"
        ;;
esac

# Download libguestfs and nbdkit sources.
curl -o $tmpdir/libguestfs.tar.gz $libguestfs_tarball
curl -o $tmpdir/nbdkit.tar.gz $nbdkit_tarball

# Write a proxy file for the guest environment.
echo "export http_proxy=$http_proxy" >> $tmpdir/proxy
echo "export https_proxy=$https_proxy" >> $tmpdir/proxy
echo "export ftp_proxy=$ftp_proxy" >> $tmpdir/proxy

# Build the temporary guest RHEL environment.
disk=$tmpdir/tmp-$osversion.img
livecd=virt-p2v-livecd-$osversion-$arch-`date +"%Y%m%d%H%M"`.iso
virt-builder $osversion --arch $arch \
             --size 20G --output $disk \
             "${epel[@]}" \
             --install "$pkgs" \
             --upload $tmpdir/libguestfs.tar.gz:/var/tmp \
             --upload $tmpdir/nbdkit.tar.gz:/var/tmp \
             --copy-in $d/patches:/var/tmp \
             --write /var/tmp/osversion:$osversion \
             --write /var/tmp/livecd:$livecd \
             --upload $tmpdir/proxy:/var/tmp/proxy \
             --firstboot $d/aux-scripts/do-build.sh \
             --selinux-relabel

# Run the guest.
qemu-system-x86_64 -no-user-config -nodefaults -nographic \
                   -no-reboot \
                   -machine accel=kvm:tcg \
                   -cpu host \
                   -m 4096 \
                   -drive file=$disk,format=raw,if=$if \
                   -netdev user,id=usernet,net=169.254.0.0/16 \
                   -device $netdev,netdev=usernet \
                   -serial stdio

# Did we get any output from the auxiliary script?
# (This command will fail if not)
guestfish --ro -a $disk -i download /var/tmp/$livecd $livecd
ls -lh $livecd
