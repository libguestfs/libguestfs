#!/bin/bash -
# libguestfs virt-builder test script
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

export LANG=C
set -e

abs_builddir=$(pwd)

export XDG_CONFIG_HOME=
export XDG_CONFIG_DIRS="$abs_builddir/test-config"

if [ -n "$SKIP_TEST_VIRT_BUILDER_SH" ]; then
    echo "$0: skipping test because environment variable is set."
    exit 77
fi

if [ ! -f fedora.xz ]; then
    echo "$0: test skipped because there is no fedora.xz in the build directory"
    exit 77
fi

output=phony-fedora.img

format=qcow2
if [ "$(../fish/guestfish get-backend)" = "uml" ]; then
    format=raw

    # XXX We specifically want virt-builder to work with the UML
    # backend.  However currently it fails with:
    #   error: uml backend does not support networking
    # We should be able to make uml have a network backend, but in
    # the meantime add this:
    no_network=--no-network
fi

rm -f $output

# Test as many options as we can!
#
# Note we cannot test --install, --run since the phony Fedora doesn't
# have a real OS inside just some configuration files.  Just about
# every other option is fair game.
$VG ./virt-builder phony-fedora \
    -v --no-cache --no-check-signature $no_network \
    -o $output --size 2G --format $format \
    --arch x86_64 \
    --hostname test.example.com \
    --timezone Europe/London \
    --root-password password:123456 \
    --mkdir /etc/foo/bar/baz \
    --write '/etc/foo/bar/baz/foo:Hello World' \
    --upload Makefile:/Makefile \
    --edit '/Makefile: s{^#.*}{}' \
    --upload Makefile:/etc/foo/bar/baz \
    --delete /Makefile \
    --link /etc/foo/bar/baz/foo:/foo \
    --link /etc/foo/bar/baz/foo:/foo1:/foo2:/foo3 \
    --firstboot Makefile --firstboot-command 'echo "hello"' \
    --firstboot-install "minicom,inkscape"

# Check that some modifications were made.
$VG ../fish/guestfish --ro -i -a $output > test.out <<EOF
# Uploaded files
is-file /etc/foo/bar/baz/Makefile
cat /etc/foo/bar/baz/foo
is-symlink /foo
is-symlink /foo1
is-symlink /foo2
is-symlink /foo3

echo -----
# Hostname
cat /etc/sysconfig/network | grep HOSTNAME=

echo -----
# Timezone
is-file /usr/share/zoneinfo/Europe/London
is-symlink /etc/localtime
readlink /etc/localtime

echo -----
# Password
is-file /etc/shadow
cat /etc/shadow | sed -r '/^root:/!d;s,^(root:\\\$6\\\$).*,\\1,g'
EOF

if [ "$(cat test.out)" != "true
Hello World
true
true
true
true
-----
HOSTNAME=test.example.com
-----
true
true
/usr/share/zoneinfo/Europe/London
-----
true
root:\$6\$" ]; then
    echo "$0: unexpected output:"
    cat test.out
    exit 1
fi

rm $output
rm test.out
