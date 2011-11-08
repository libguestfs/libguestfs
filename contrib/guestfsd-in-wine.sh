#!/bin/bash -
# Copyright (C) 2009 Red Hat Inc.
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

# INSTRUCTIONS
#----------------------------------------------------------------------
#
# This is a QEMU wrapper script that allows you to run a
# Windows-compiled guestfsd.exe (daemon) under Wine from a Linux main
# program.  You need to read and understand all the instructions below
# before use.
#
# To understand how to compile the daemon for Windows, please read:
# http://www.redhat.com/archives/libguestfs/2009-November/msg00255.html
#
# Adjust the Wine configuration so it can find the libraries, as
# described here:
# http://fedoraproject.org/wiki/MinGW/Configure_wine
#
# On Fedora 13 there is a serious bug in Wine.  See:
# https://bugzilla.redhat.com/show_bug.cgi?id=533806#c11
#
# If necessary, adjust the line 'guestfsd=...' below so it points to
# the correct location of the guestfsd.exe program.  You can use an
# absolute path here if you want.
guestfsd=daemon/guestfsd.exe
#
# This script is a QEMU wrapper.  It pretends to be qemu as far as
# libguestfs programs are concerned.  Read this to understand the
# purpose of QEMU wrappers:
# http://libguestfs.org/guestfs.3.html#qemu_wrappers
#
# With this script, the qemu program is not actually run.  Instead we
# pretend to be qemu, parse out the necessary parts of the long
# command line that libguestfs passes to qemu, and run the Windows
# daemon, under Wine, with the right command line.  The Windows daemon
# then hopefully connects back to the libguestfs socket, and as far as
# the libguestfs program is concerned, it looks like a full appliance
# is running.
#
# To use this script, you must set the environment variable
# LIBGUESTFS_QEMU=/path/to/contrib/guestfsd-in-wine.sh (ie. the path
# to this script).
#
# You can then run libguestfs test programs, and (hopefully!) they'll
# use the Windows guestfsd.exe, simulating calls using Wine.
#
# For example from the top build directory:
#
# LIBGUESTFS_QEMU=contrib/guestfsd-in-wine.sh ./run ./fish/guestfish
#
# Another suggested environment variable is LIBGUESTFS_DEBUG=1 which
# will give you must more detail about what is going on.  Also look at
# the contents of the log file 'guestfsd-in-wine.log' after each run.
#
#----------------------------------------------------------------------

# Note that stdout & stderr messages will get eaten by libguestfs
# early on in the process.  Therefore write log messages to
# a log file.
exec 5>>guestfsd-in-wine.log
echo "Environment:" >&5
printenv | grep LIBGUESTFS >&5
echo "Command line:" >&5
echo "  $@" >&5

# We're called several times, first with -help and -version, and we
# have to pretend to be qemu!  (At least enough to trick libguestfs).
if [ "$1" = "-help" ]; then
    echo -- "  -net user  "
    echo -- "  -no-hpet  "
    echo -- "  -rtc-td-hack  "
    exit 0
elif [ "$1" = "-version" ]; then
    echo -- "0.0.0"
    exit 0
fi

# The interesting parameter is -append.
append=
while [ $# -gt 0 ]; do
    if [ $1 = "-append" ]; then
        append="$2"
        shift
    fi
    shift
done
echo "Append parameter:" >&5
echo "  $append" >&5

# guestfs_vmchannel parameter.
vmchannel_param=$(echo "$append" | grep -Eo 'guestfs_vmchannel=[^[:space:]]+')
echo "Vmchannel parameter:" >&5
echo "  $vmchannel_param" >&5

# Port number.
port=$(echo "$vmchannel_param" | grep -Eo '[[:digit:]]+$')
echo "Port number:" >&5
echo "  $vmchannel_param" >&5

# Run guestfsd.exe.
echo "Command:" >&5
echo "  $guestfsd -f -v -c tcp:localhost:$port" >&5
$guestfsd -f -v -c tcp:127.0.0.1:$port
