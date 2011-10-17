#!/bin/bash -
# libguestfs
# Copyright (C) 2009-2011 Red Hat Inc.
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

unset CDPATH
set -e
#set -v

if [ ! -w /dev/fuse ]; then
    echo "SKIPPING guestmount test, because there is no /dev/fuse."
    exit 0
fi

if [ -z "$top_builddir" ]; then
    echo "$0: error: environment variable \$top_builddir must be set"
    exit 1
fi

nr_stages=$(grep "^stage " $0 | wc -l)

# Allow top_builddir to be a relative path, but also make it absolute,
# and move to that directory for the initial phase of the script.
top_builddir=$(cd "$top_builddir" > /dev/null; pwd)

# Set TMPDIR so the appliance doesn't conflict with globally
# installed libguestfs.
export TMPDIR=$top_builddir

# Set libguestfs up for running locally.
export LIBGUESTFS_PATH="$top_builddir/appliance"

# Paths to the other programs and files.  NB: Must be absolute paths.
guestfish="$top_builddir/fish/guestfish"
guestmount="$top_builddir/fuse/guestmount"
image="$top_builddir/fuse/test.img"
mp="$top_builddir/fuse/test-mp"

if [ ! -x "$guestfish" -o ! -x "$guestmount" ]; then
    echo "$0: error: guestfish or guestmount are not available"
    exit 1
fi

# Ensure everything is cleaned up on exit.
rm -f "$image"
mkdir -p "$mp"
fusermount -u "$mp" >/dev/null 2>&1 ||:
function cleanup ()
{
    status=$?
    set +e
    [ $status = 0 ] || echo "*** FAILED ***"
    echo "Unmounting filesystem and cleaning up."

    # Move out of the mountpoint (otherwise our cwd will prevent the
    # mountpoint from being unmounted).
    cd "$top_builddir"

    # Who's using this?  Should be no one, but see below.
    if [ -x /sbin/fuser ]; then /sbin/fuser "$mp"; fi

    # If you run this and you have GNOME running at the same time,
    # then randomly /usr/libexec/gvfs-gdu-volume-monitor will decide
    # to do whatever it does in the mountpoint directory, preventing
    # you from unmounting it!  Hence the need for this loop.
    count=10
    while ! fusermount -u "$mp" && [ $count -gt 0 ]; do
        sleep 1
        ((count--))
    done

    rm -f "$image"
    rm -rf "$mp"
    exit $status
}
trap cleanup INT TERM QUIT EXIT

s=1
function stage ()
{
    echo "test-fuse: $s/$nr_stages:" "$@" "..."
    ((s++))
}

stage Create filesystem with some initial content
$guestfish <<EOF
  sparse "$image" 10M
  run
  part-disk /dev/sda mbr
  mkfs ext2 /dev/sda1
  mount_options acl,user_xattr /dev/sda1 /
  write /hello.txt hello
  write /world.txt "hello world"
  touch /empty
  touch /user_xattr
  setxattr user.test hello123 8 /user_xattr
  touch /acl
  # XXX hack until libguestfs gets ACL support
  debug sh "setfacl -m u:500:r /sysroot/acl" | cat > /dev/null
EOF

stage Mounting the filesystem
$guestmount \
    -a "$image" -m /dev/sda1:/:acl,user_xattr \
    -o uid="$(id -u)" -o gid="$(id -g)" "$mp"
# To debug guestmount, add this to the end of the preceding command:
# -v -x & sleep 60

stage Changing into mounted directory
cd "$mp"

stage Checking initial files exist
[ -n "$(echo *)" ]
[ "$(ls empty hello.txt world.txt)" = "empty
hello.txt
world.txt" ]

stage Checking initial files contain expected content
[ "$(cat hello.txt)" = "hello" ]
[ "$(cat world.txt)" = "hello world" ]
cat empty ;# should print nothing
[ -z "$(cat empty)" ]

stage Checking file modes of initial content
[ "$(stat -c %a empty)" = "644" ]
[ "$(stat -c %a hello.txt)" = "644" ]
[ "$(stat -c %a world.txt)" = "644" ]

stage Checking sizes of initial content
[ "$(stat -c %s empty)" -eq 0 ]
[ "$(stat -c %s hello.txt)" -eq 5 ]
[ "$(stat -c %s world.txt)" -eq 11 ]

stage Checking unlink
touch new
rm -f new ;# force because file is "owned" by root

stage Checking symbolic link
ln -s hello.txt symlink
[ -L symlink ]

stage Checking readlink
[ "$(readlink symlink)" = "hello.txt" ]

stage Checking hard link
[ "$(stat -c %h hello.txt)" -eq 1 ]
ln hello.txt link
[ "$(stat -c %h link)" -eq 2 ]
[ "$(stat -c %h hello.txt)" -eq 2 ]
rm -f link
[ ! -e link ]

# This fails because of caching.  The problem is that the linked file
# ("hello.txt") is cached with a link count of 2.  unlink("link")
# invalidates the cache for "link", but _not_ for "hello.txt" which
# still has the now-incorrect cached value.  However there's not much
# we can do about this since searching for all linked inodes of a file
# is an O(n) operation.
#[ "$(stat -c %h hello.txt)" -eq 1 ]

stage Checking mkdir
mkdir newdir
[ -d newdir ]

stage Checking rmdir
rmdir newdir
[ ! -e newdir ]

stage Checking rename
touch old
mv old new
[ -f new ]
[ ! -e old ]
rm -f new

stage Checking chmod
touch new
chmod a+x new
[ -x new ]
chmod a-x new
[ ! -x new ]
chmod a-w new
[ ! -w new ]
chmod a+w new
[ -w new ]
chmod a-r new
[ ! -r new ]
chmod a+r new
[ -r new ]
rm -f new

stage Checking truncate
truncate -s 10000 truncated
[ "$(stat -c %s truncated)" -eq 10000 ]
truncate -c -s 1000 truncated
[ "$(stat -c %s truncated)" -eq 1000 ]
truncate -c -s 10 truncated
[ "$(stat -c %s truncated)" -eq 10 ]
truncate -c -s 0 truncated
[ "$(stat -c %s truncated)" -eq 0 ]
rm -f truncated

# Disabled because of RHBZ#660687 on Debian.
# stage Checking utimens and timestamps
# for ts in 12345 1234567 987654321; do
#     # NB: It's not possible to set the ctime with touch.
#     touch -a -d @$ts timestamp
#     [ "$(stat -c %X timestamp)" -eq $ts ]
#     touch -m -d @$ts timestamp
#     [ "$(stat -c %Y timestamp)" -eq $ts ]
#     touch    -d @$ts timestamp
#     [ "$(stat -c %X timestamp)" -eq $ts ]
#     [ "$(stat -c %Y timestamp)" -eq $ts ]
# done

stage Checking writes
cp hello.txt copy.txt
echo >> copy.txt
echo world >> copy.txt
echo bigger >> copy.txt
echo biggest >> copy.txt
[ "$(cat copy.txt)" = "hello
world
bigger
biggest" ]

stage 'Checking extended attribute (xattr) read operation'
if getfattr --help > /dev/null 2>&1 ; then
  [ "$(getfattr -d user_xattr | grep -v ^#)" = 'user.test="hello123"' ]
fi

stage Checking POSIX ACL read operation
if getfacl --help > /dev/null 2>&1 ; then
  [ "$(getfacl -n acl | grep -v ^#)" = "user::rw-
user:500:r--
group::r--
mask::r--
other::r--" ]
fi

# These ones are not yet tested by the current script:
#stage XXX statfs/statvfs

# These ones cannot easily be tested by the current script, eg because
# this script doesn't run as root:
#stage XXX fsync
#stage XXX chown
#stage XXX mknod
