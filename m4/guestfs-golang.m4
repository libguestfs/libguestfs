# libguestfs
# Copyright (C) 2009-2023 Red Hat Inc.
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

dnl Golang
AC_ARG_ENABLE([golang],
    AS_HELP_STRING([--disable-golang], [disable Go language bindings]),
        [],
        [enable_golang=yes])
AS_IF([test "x$enable_golang" != "xno"],[
    AC_CHECK_PROG([GOLANG],[go],[go],[no])
    AS_IF([test "x$GOLANG" != "xno"],[
        AC_MSG_CHECKING([if $GOLANG is usable])
        AS_IF([$GOLANG run $srcdir/golang/config-test.go 2>&AS_MESSAGE_LOG_FD],[
            AC_MSG_RESULT([yes])
        ],[
            AC_MSG_RESULT([no])
            AC_MSG_WARN([golang ($GOLANG) is installed but not usable])
            GOLANG=no
        ])
    ])
],[GOLANG=no])
AM_CONDITIONAL([HAVE_GOLANG],[test "x$GOLANG" != "xno"])
