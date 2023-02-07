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

dnl gobject library
AC_ARG_ENABLE([gobject],
    AS_HELP_STRING([--disable-gobject], [disable GObject bindings]),
    [],
    [enable_gobject=yes])
AS_IF([test "x$enable_gobject" != "xno"],[
    PKG_CHECK_MODULES([GOBJECT], [gobject-2.0 >= 2.26.0],[
        AC_SUBST([GOBJECT_CFLAGS])
        AC_SUBST([GOBJECT_LIBS])
        AC_DEFINE([HAVE_GOBJECT],[1],
                  [GObject library found at compile time.])
    ],
    [AC_MSG_WARN([gobject library not found, gobject binding will be disabled])])

    PKG_CHECK_MODULES([GIO], [gio-2.0 >= 2.26.0],[
        AC_SUBST([GIO_CFLAGS])
        AC_SUBST([GIO_LIBS])
        AC_DEFINE([HAVE_GIO],[1],
                  [gio library found at compile time.])
    ],
    [AC_MSG_WARN([gio library not found, gobject binding will be disabled])])
])
AM_CONDITIONAL([HAVE_GOBJECT],
               [test "x$GOBJECT_LIBS" != "x" -a "x$GIO_LIBS" != "x"])

AC_CHECK_PROG([GJS],[gjs],[gjs])
AS_IF([test "x$GJS" = "x"],
      [AC_MSG_WARN([gjs not found, gobject bindtests will not run])])

dnl gobject introspection
m4_ifdef([GOBJECT_INTROSPECTION_CHECK], [
    GOBJECT_INTROSPECTION_CHECK([1.30.0])

    dnl The above check automatically sets HAVE_INTROSPECTION, but we
    dnl want this to be conditional on gobject also being
    dnl available. We can't move the above check inside the gobject if
    dnl block above or HAVE_INTROSPECTION ends up undefined, so we
    dnl recheck it here.
    AM_CONDITIONAL([HAVE_INTROSPECTION],
                   [test "x$HAVE_INTROSPECTION_TRUE" = "x" &&
                    test "x$HAVE_GOBJECT_TRUE" = "x"])
],[
    AM_CONDITIONAL([HAVE_INTROSPECTION], [false])
])
