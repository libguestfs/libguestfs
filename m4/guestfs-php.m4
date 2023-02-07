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

dnl PHP
PHP=no
AC_ARG_ENABLE([php],
    AS_HELP_STRING([--disable-php], [disable PHP language bindings]),
    [],
    [enable_php=yes])
AS_IF([test "x$enable_php" != "xno"],[
    PHP=
    AC_CHECK_PROG([PHP],[php],[php],[no])
    AC_CHECK_PROG([PHPIZE],[phpize],[phpize],[no])
])
AM_CONDITIONAL([HAVE_PHP], [test "x$PHP" != "xno" && test "x$PHPIZE" != "xno"])
