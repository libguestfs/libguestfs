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

do_md5 ()
{
  case "$(uname)" in
    Linux)
      md5sum "$1" | awk '{print $1}'
      ;;
    *)
      echo "$0: unknown method to calculate MD5 of file on $(uname)"
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
      echo "$0: unknown method to calculate SHA1 of file on $(uname)"
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
      echo "$0: unknown method to calculate SHA256 of file on $(uname)"
      exit 1
      ;;
  esac
}

# Returns 0 if QEMU version is greater or equal to the arguments
qemu_is_version() {
    if [ $# -ne 2 ] ; then
        echo "Usage: $0 <major_version> <minor_version>" >&2
        return 3
    fi


    [[ "$(qemu-img --version)" =~ 'qemu-img version '([0-9]+)\.([0-9]+) ]] || return 2
    QMAJ=${BASH_REMATCH[1]}
    QMIN=${BASH_REMATCH[2]}

    if [ \( $QMAJ -gt $1 \) -o \( $QMAJ -eq $1 -a $QMIN -ge $2 \) ] ; then
        return 0
    fi

    return 1
}
