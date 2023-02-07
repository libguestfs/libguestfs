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

dnl Miscellaneous libraries used by other programs.

dnl glibc 2.27 removes crypt(3) and suggests using libxcrypt.
PKG_CHECK_MODULES([LIBCRYPT], [libxcrypt], [
    AC_SUBST([LIBCRYPT_CFLAGS])
    AC_SUBST([LIBCRYPT_LIBS])
],[
    dnl Check if crypt() is provided by another library.
    old_LIBS="$LIBS"
    AC_SEARCH_LIBS([crypt],[crypt])
    LIBS="$old_LIBS"
    if test "$ac_cv_search_crypt" = "-lcrypt" ; then
        LIBCRYPT_LIBS="-lcrypt"
    fi
    AC_SUBST([LIBCRYPT_LIBS])
])

dnl Do we need to include <crypt.h>?
old_CFLAGS="$CFLAGS"
CFLAGS="$CFLAGS $LIBCRYPT_CFLAGS"
AC_CHECK_HEADERS([crypt.h])
CFLAGS="$old_CFLAGS"

dnl liblzma can be used by virt-builder (optional).
PKG_CHECK_MODULES([LIBLZMA], [liblzma], [
    AC_SUBST([LIBLZMA_CFLAGS])
    AC_SUBST([LIBLZMA_LIBS])
    AC_DEFINE([HAVE_LIBLZMA],[1],[liblzma found at compile time.])

    dnl Old lzma in RHEL 6 didn't have some APIs we need.
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBLZMA_LIBS"
    AC_CHECK_FUNCS([lzma_index_stream_flags lzma_index_stream_padding])
    LIBS="$old_LIBS"
],
[AC_MSG_WARN([liblzma not found, virt-builder will be slower])])

dnl Readline (used by guestfish).
AC_ARG_WITH([readline],[
    AS_HELP_STRING([--with-readline],
        [support fancy command line editing @<:@default=check@:>@])],
    [],
    [with_readline=check])

LIBREADLINE=
AS_IF([test "x$with_readline" != xno],[
    AC_CHECK_LIB([readline], [main],
        [AC_SUBST([LIBREADLINE], ["-lreadline -lncurses"])
         AC_DEFINE([HAVE_LIBREADLINE], [1],
                   [Define if you have libreadline.])
        ],
        [if test "x$with_readline" != xcheck; then
         AC_MSG_FAILURE(
             [--with-readline was given, but test for readline failed])
         fi
        ], -lncurses)
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBREADLINE"
    AC_CHECK_FUNCS([append_history completion_matches rl_completion_matches])
    LIBS="$old_LIBS"
    ])

dnl libconfig (highly recommended) used by guestfish and others.
PKG_CHECK_MODULES([LIBCONFIG], [libconfig],[
    AC_SUBST([LIBCONFIG_CFLAGS])
    AC_SUBST([LIBCONFIG_LIBS])
    AC_DEFINE([HAVE_LIBCONFIG],[1],[libconfig found at compile time.])
],
    [AC_MSG_WARN([libconfig not found, some features will be disabled])])
AM_CONDITIONAL([HAVE_LIBCONFIG],[test "x$LIBCONFIG_LIBS" != "x"])
