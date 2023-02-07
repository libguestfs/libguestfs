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

dnl FUSE is optional to build the FUSE module.
AC_ARG_ENABLE([fuse],
    AS_HELP_STRING([--disable-fuse], [disable FUSE (guestmount) support]),
    [],
    [enable_fuse=yes])
AS_IF([test "x$enable_fuse" != "xno"],[
    PKG_CHECK_MODULES([FUSE],[fuse],[
        AC_SUBST([FUSE_CFLAGS])
        AC_SUBST([FUSE_LIBS])
        AC_DEFINE([HAVE_FUSE],[1],[Define to 1 if you have FUSE.])
        old_LIBS="$LIBS"
        LIBS="$FUSE_LIBS $LIBS"
        AC_CHECK_FUNCS([fuse_opt_add_opt_escaped])
        LIBS="$old_LIBS"
    ],[
        enable_fuse=no
        AC_MSG_WARN([FUSE library and headers are missing, so optional FUSE module won't be built])
    ])
])
AM_CONDITIONAL([HAVE_FUSE],[test "x$enable_fuse" != "xno"])
