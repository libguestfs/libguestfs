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

dnl Check for Haskell (GHC).
GHC=no
AC_ARG_ENABLE([haskell],
    AS_HELP_STRING([--disable-haskell], [disable Haskell language bindings]),
    [],
    [enable_haskell=yes])
AS_IF([test "x$enable_haskell" != "xno"],[
    GHC=
    AC_CHECK_PROG([GHC],[ghc],[ghc],[no])
])
AM_CONDITIONAL([HAVE_HASKELL],[test "x$GHC" != "xno"])
