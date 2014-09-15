#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

rm -f prep*.img

# It would be nice if we could keep this automatically in sync
# with the prepared disk types.  XXX
$VG guestfish \
    -N prep1.img=disk \
    -N prep2.img=part \
    -N prep3.img=fs \
    -N prep4.img=lv:/dev/VG1/LV \
    -N prep5.img=lvfs:/dev/VG2/LV \
    -N prep6.img=bootroot \
    -N prep7.img=bootrootlv:/dev/VG3/LV \
    exit

rm prep*.img
