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

dnl Lua
AC_ARG_ENABLE([lua],
    AS_HELP_STRING([--disable-lua], [disable Lua language bindings]),
        [],
        [enable_lua=yes])
AS_IF([test "x$enable_lua" != "xno"],[
    AC_CHECK_PROG([LUA],[lua],[lua],[no])
    AS_IF([test "x$LUA" != "xno"],[
        AC_MSG_CHECKING([for Lua version])
        LUA_VERSION=`$LUA -e 'print(_VERSION)' | $AWK '{print $2}'`
        AC_MSG_RESULT([$LUA_VERSION])
        dnl On Debian it's 'lua5.1', 'lua5.2' etc.  On Fedora, just 'lua'.
        PKG_CHECK_MODULES([LUA], [lua$LUA_VERSION],[
            AC_SUBST([LUA_CFLAGS])
            AC_SUBST([LUA_LIBS])
            AC_SUBST([LUA_VERSION])
            AC_DEFINE([HAVE_LUA],[1],[Lua library found at compile time])
        ],[
            PKG_CHECK_MODULES([LUA], [lua],[
                AC_SUBST([LUA_CFLAGS])
                AC_SUBST([LUA_LIBS])
                AC_SUBST([LUA_VERSION])
                AC_DEFINE([HAVE_LUA],[1],[Lua library found at compile time])
            ],[
                AC_MSG_WARN([lua $LUA_VERSION not found])
            ])
        ])
    ])
])
AM_CONDITIONAL([HAVE_LUA],[test "x$LUA_LIBS" != "x"])
