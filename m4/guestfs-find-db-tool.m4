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

AC_DEFUN([GUESTFS_FIND_DB_TOOL],[
    pushdef([VARIABLE],$1)
    TOOL=$2

    db_tool_name="db_$TOOL"
    db_versions="53 5.3 5.2 5.1 4.8 4.7 4.6"
    db_tool_patterns="dbX_$TOOL dbX.Y_$TOOL"
    db_tool_patterns="dbX_$TOOL db_$TOOL-X dbX.Y_$TOOL db_$TOOL-X.Y"

    AC_ARG_VAR(VARIABLE, [Absolute path to $db_tool_name executable])

    AS_IF(test -z "$VARIABLE", [
        exe_list="db_$TOOL"
        for ver in $db_versions ; do
            ver_maj=`echo $ver | cut -d. -f1`
            ver_min=`echo $ver | cut -d. -f2`
            for pattern in $db_tool_patterns ; do
                exe=`echo "$pattern" | sed -e "s/X/$ver_maj/g;s/Y/$ver_min/g"`
                exe_list="$exe_list $exe"
            done
        done
        AC_PATH_PROGS([]VARIABLE[], [$exe_list], [no])
    ])

    popdef([VARIABLE])
])
