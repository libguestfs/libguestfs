#!/bin/bash -
# libguestfs
# Copyright (C) 2014-2023 Red Hat Inc.
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

# Most of the tests written in shell script source this file for
# useful functions.
#
# To include this file, the test must do:
#
#   $TEST_FUNCTIONS
#
# (this macro is defined in subdir-rules.mk).

# Clean up the environment in every test script.
unset CDPATH
export LANG=C

# When test-functions.sh is invoked, a list of variables is passed as
# parameters, so we eval those to define the variables.
while [ $# -ge 1 ]; do eval "$1"; shift; done

# Configure check results.
source $abs_top_builddir/config.sh

# Skip if $SKIP_<script_name> environment variable is set.
# Every test should call this function first.
skip_if_skipped ()
{
    local v
    if [ -n "$1" ]; then
        v="SKIP_$(basename $1 | tr a-z.- A-Z__)"
    else
        v="SKIP_$(basename $0 | tr a-z.- A-Z__)"
    fi
    if [ -n "${!v}" ]; then
        echo "$(basename $0): test skipped because \$$v is set"
        exit 77
    fi
    echo "$(basename $0): info: you can skip this test by setting $v=1"
}

# Skip if the current libguestfs backend is $1.
# eg. skip_if_backend libvirt
skip_if_backend ()
{
    local b="$(guestfish get-backend)"
    case "$1" in
        # Some magic happens for $1 == libvirt.
        libvirt)
            if [ "$b" = "libvirt" ] || [[ "$b" =~ ^libvirt: ]]; then
                echo "$(basename $0): test skipped because the current backend is $b"
                exit 77
            fi
            ;;
        *)
            if [ "$b" = "$1" ]; then
                echo "$(basename $0): test skipped because the current backend is $b"
                exit 77
            fi
            ;;
    esac
}

# Skip if the current libguestfs backend is NOT $1.
skip_unless_backend ()
{
    local b="$(guestfish get-backend)"
    case "$1" in
        # Some magic happens for $1 == libvirt.
        libvirt)
            if [ "$b" != "libvirt" ] && [[ ! "$b" =~ ^libvirt: ]]; then
                echo "$(basename $0): this test only runs if the backend is libvirt, but the current backend is $b"
                exit 77
            fi
            ;;
        *)
            if [ "$b" != "$1" ]; then
                echo "$(basename $0): this test only runs if the backend is $1, but the current backend is $b"
                exit 77
            fi
            ;;
    esac
}

# Skip if the named ($1) disk image in test-data/phony-guests was not
# created.
skip_unless_phony_guest ()
{
    local f="$abs_top_builddir/test-data/phony-guests/$1"
    if ! test -f $f || ! test -s $f; then
        echo "$(basename $0): test skipped because disk image '$1' was not created"
        echo "$(basename $0): try running: make -C test-data check"
        exit 77
    fi
}

# Skip if test.iso was not created.
skip_unless_test_iso ()
{
    local f="$abs_top_builddir/test-data/test.iso"
    if ! test -f $f || ! test -s $f; then
        echo "$(basename $0): test skipped because test-data/test.iso was not created"
        echo "$(basename $0): try running: make -C test-data check"
        exit 77
    fi
}

# Skip if the current arch = $1.
skip_if_arch ()
{
    local m="$(uname -m)"
    case "$1" in
        # Some magic happens for some architectures.
        arm)
            if [[ "$m" =~ ^arm ]]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is arm (32 bit)"
                exit 77
            fi
            ;;
        i?86)
            if [[ "$m" =~ ^i?86 ]]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is $1"
                exit 77
            fi
            ;;
        *)
            if [ "$m" = "$1" ]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is $1"
                exit 77
            fi
            ;;
    esac
}

# Skip if the current arch != $1.
skip_unless_arch ()
{
    local m="$(uname -m)"
    case "$1" in
        # Some magic happens for some architectures.
        arm)
            if [[ ! "$m" =~ ^arm ]]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is not arm (32 bit)"
                exit 77
            fi
            ;;
        i?86)
            if [[ ! "$m" =~ ^i?86 ]]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is not $1"
                exit 77
            fi
            ;;
        *)
            if [ "$m" != "$1" ]; then
                echo "$(basename $0): test skipped because the current architecture ($m) is not $1"
                exit 77
            fi
            ;;
    esac
}

# Skip if $1 is not known to virt-builder.
skip_unless_virt_builder_guest ()
{
    if ! virt-builder -l "$1" >/dev/null 2>&1; then
        echo "$(basename $0): test skipped because $1 is not known to virt-builder"
        exit 77
    fi
}

# Skip if FUSE is not available in the host kernel.
skip_unless_fuse ()
{
    if ! test -w /dev/fuse; then
        echo "$(basename $0): test skipped because the host kernel does not support FUSE"
        echo "$(basename $0): /dev/fuse is missing or not writable by the current user"
        exit 77
    fi
}

# Skip if a feature is not available in the daemon.
skip_unless_feature_available ()
{
    if ! guestfish -a /dev/null run : available "$1"; then
        echo "$(basename $0): test skipped because feature $1 is not available"
        exit 77
    fi
}

# Skip if a filesystem is unavailable in the daemon.
skip_unless_filesystem_available ()
{
    r="$(guestfish -a /dev/null run : filesystem_available "$1")"
    if [ "$r" != "true" ] ; then
        echo "$(basename $0): test skipped because $1 filesystem is not available"
        exit 77
    fi
}

# Skip unless the libvirt minimum version is met.
skip_unless_libvirt_minimum_version ()
{
    if ! test -x $abs_top_builddir/lib/libvirt-is-version; then
        echo "$(basename $0): test skipped because lib/libvirt-is-version is not built yet"
        exit 77
    fi
    if ! $abs_top_builddir/lib/libvirt-is-version "$@"; then
        echo "$(basename $0): test skipped because libvirt is too old, <" "$@"
        exit 77
    fi
}

# Skip unless the environment variable named is set to a non-empty value.
skip_unless_environment_variable_set ()
{
    if [ -z "${!1}" ]; then
        echo "$(basename $0): test skipped because \$$1 is not set"
        exit 77
    fi
}

# Run an external command and skip if the command fails.  This can be
# used to test if a command exists.  Normally you should use
# `cmd --help' or `cmd --version' or similar.
skip_unless ()
{
    if ! "$@"; then
        echo "$(basename $0): test skipped because $1 is not available"
        exit 77
    fi
}

# Use this if a test is broken.  "$1" should contain the reason.
skip_because ()
{
    echo "$(basename $0): test skipped because: $1"
    exit 77
}

# Skip if the user is trying to run a test as root.
# Tests shouldn't be run as root, but a few are especially dangerous.
skip_if_root ()
{
    if [ "$(id -u)" -eq 0 ]; then
        echo "$(basename $0): test skipped because you're running tests as root."
        echo "$(basename $0): it is NEVER a good idea to run libguestfs tests as root."
    exit 77
fi
}

# Slow tests should always call this function.  (See guestfs-hacking(1)).
slow_test ()
{
    if [ -z "$SLOW" ]; then
        echo "$(basename $0): use 'make check-slow' to run this test"
        exit 77
    fi
}

# Root tests should always call this function.  (See guestfs-hacking(1)).
root_test ()
{
    if test "$(id -u)" -ne 0; then
        echo "$(basename $0): use 'sudo make check-root' to run this test"
        exit 77
    fi
}

do_md5 ()
{
  case "$(uname)" in
    Linux)
      md5sum "$1" | awk '{print $1}'
      ;;
    *)
      echo "$(basename $0): unknown method to calculate MD5 of file on $(uname)"
      exit 1
      ;;
  esac
}

do_sha1 ()
{
  case "$(uname)" in
    Linux)
      sha1sum "$1" | awk '{print $1}'
      ;;
    *)
      echo "$(basename $0): unknown method to calculate SHA1 of file on $(uname)"
      exit 1
      ;;
  esac
}

do_sha256 ()
{
  case "$(uname)" in
    Linux)
      sha256sum "$1" | awk '{print $1}'
      ;;
    *)
      echo "$(basename $0): unknown method to calculate SHA256 of file on $(uname)"
      exit 1
      ;;
  esac
}
