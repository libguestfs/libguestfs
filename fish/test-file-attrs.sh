#!/bin/bash -
# libguestfs
# Copyright (C) 2014 Red Hat Inc.
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

# Test guestfish file attributes commands (chmod, copy-attributes, etc).

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f test-file-attrs.out

$VG guestfish > test-file-attrs.out <<EOF
scratch 50MB
run
part-disk /dev/sda mbr
mkfs ext2 /dev/sda1
mount /dev/sda1 /

touch /foo
touch /bar
chmod 0712 /foo
stat /foo | grep mode:
copy-attributes /foo /bar mode:true
stat /bar | grep mode:

echo -----

stat /foo | grep uid:
stat /foo | grep gid:
chown 10 11 /foo
stat /foo | grep uid:
stat /foo | grep gid:
stat /bar | grep uid:
stat /bar | grep gid:
copy-attributes /foo /bar ownership:true
stat /bar | grep uid:
stat /bar | grep gid:

echo -----

setxattr user.test foo 3 /foo
setxattr user.test2 secondtest 10 /foo
setxattr user.foo another 7 /bar
lxattrlist / "foo bar"
copy-attributes /foo /bar xattributes:true
lxattrlist / "foo bar"

echo -----

touch /new
chmod 0111 /new
copy-attributes /foo /new all:true mode:false
stat /new | grep mode:
stat /new | grep uid:
stat /new | grep gid:
lxattrlist / new
copy-attributes /foo /new mode:true
stat /new | grep mode:
EOF

if [ "$(cat test-file-attrs.out)" != "mode: 33226
mode: 33226
-----
uid: 0
gid: 0
uid: 10
gid: 11
uid: 0
gid: 0
uid: 10
gid: 11
-----
[0] = {
  attrname: 
  attrval: 2\x00
}
[1] = {
  attrname: user.test
  attrval: foo
}
[2] = {
  attrname: user.test2
  attrval: secondtest
}
[3] = {
  attrname: 
  attrval: 1\x00
}
[4] = {
  attrname: user.foo
  attrval: another
}
[0] = {
  attrname: 
  attrval: 2\x00
}
[1] = {
  attrname: user.test
  attrval: foo
}
[2] = {
  attrname: user.test2
  attrval: secondtest
}
[3] = {
  attrname: 
  attrval: 3\x00
}
[4] = {
  attrname: user.foo
  attrval: another
}
[5] = {
  attrname: user.test
  attrval: foo
}
[6] = {
  attrname: user.test2
  attrval: secondtest
}
-----
mode: 32841
uid: 10
gid: 11
[0] = {
  attrname: 
  attrval: 2\x00
}
[1] = {
  attrname: user.test
  attrval: foo
}
[2] = {
  attrname: user.test2
  attrval: secondtest
}
mode: 33226" ]; then
    echo "$0: unexpected output:"
    cat test-file-attrs.out
    exit 1
fi

rm test-file-attrs.out
