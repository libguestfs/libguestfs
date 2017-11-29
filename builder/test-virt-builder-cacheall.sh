#!/bin/bash -
# libguestfs virt-builder test script
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

tmpdir="$(mktemp -d)"
echo "tmpdir= $tmpdir"
reposdir="$tmpdir/virt-builder/repos.d"
repodir="$tmpdir/repo"
indexfile="$repodir/index"
cachedir="$tmpdir/cache"

mkdir -p "$reposdir"
mkdir -p "$repodir"

# Create some fake images.
img1_path="$repodir/img1.raw"
img1_size=10485760  # 10G
qemu-img create -f raw "$img1_path" $img1_size
img1_csum=`do_sha256 "$img1_path"`

img2_path="$repodir/img2.qcow2"
img2_size=5242880  # 5G
qemu-img create -f qcow2 "$img2_path" $img2_size
img2_csum=`do_sha256 "$img2_path"`

# Create an index for the images.
cat > "$indexfile" <<EOF
[img1]
name=img1
file=$(basename "$img1_path")
arch=x86_64
size=$img1_size
checksum[sha512]=$img1_csum
revision=1

[img2]
name=img2
file=$(basename "$img2_path")
arch=aarch64
size=$img2_size
checksum[sha512]=$img2_csum
revision=3
EOF

# Create the repository.
cat > "$reposdir/repo1.conf" <<EOF
[repo1]
uri=$indexfile
EOF

export XDG_CONFIG_HOME=
export XDG_CONFIG_DIRS="$tmpdir"
export XDG_CACHE_HOME="$cachedir"

short_list=$($VG virt-builder --no-check-signature --no-cache --list)

if [ "$short_list" != "img1                     x86_64     img1
img2                     aarch64    img2" ]; then
    echo "$0: unexpected --list output:"
    echo "$short_list"
    exit 1
fi

$VG virt-builder --no-check-signature --cache-all-templates
ls -lh "$cachedir/virt-builder"
test -f "$cachedir/virt-builder/img1.x86_64.1"
test -f "$cachedir/virt-builder/img2.aarch64.3"

rm -rf "$tmpdir"
