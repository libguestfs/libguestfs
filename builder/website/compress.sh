#!/bin/bash -
# virt-builder
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

# Common code which syspreps, sparsifies and compresses the templates.

output=$1

relabel_args=()

if [ -n "$DO_RELABEL" ]; then
    os_arch=$(uname -m)
    guest_arch=$(virt-inspector -a "$output" | virt-inspector --xpath "string(/operatingsystems/operatingsystem/arch)")

    if [ "$os_arch" = "$guest_arch" ] || [ "$os_arch" = "x86_64" -a "$guest_arch" = "i386" ]; then
        # this is what --selinux-relabel should really do, but do it ourselves
        # in the meanwhile -- see RHBZ#1089100.
        relabel_args+=(--run-command "setfiles /etc/selinux/targeted/contexts/files/file_contexts /")
    else
        relabel_args+=(--selinux-relabel)
    fi
fi

# Sysprep (removes logfiles and so on).
# Note this also touches /.autorelabel so the further installation
# changes that we make will be labelled properly at first boot.
virt-sysprep -a $output "${relabel_args[@]}"

# Sparsify.
mv $output $output.old
virt-sparsify $output.old $output
rm $output.old

# Compress.
xz --best --block-size=16777216 $output

# Result.  These can be copied into the index file directly.
echo -n compressed_size= ; stat -c %s $output.xz
echo -n checksum= ; sha512sum $output.xz | awk '{print $1}'
