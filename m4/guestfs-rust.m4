# libguestfs
# Copyright (C) 2019 Hiroyuki Katsura <hiroyuki.katsura.0513@gmail.com>
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

dnl Rust
AC_ARG_ENABLE([rust],
    AS_HELP_STRING([--disable-rust], [disable Rust language bindings]),
        [],
        [enable_rust=yes])
AS_IF([test "x$enable_rust" != "xno"],[
    AC_CHECK_PROG([RUSTC],[rustc],[rustc],[no])
    AC_CHECK_PROG([CARGO],[cargo],[cargo],[no])

    AS_IF([test "x$RUSTC" = "xno"], [AC_MSG_WARN([rustc not found])])
    AS_IF([test "x$CARGO" = "xno"], [AC_MSG_WARN([cargo not found])])
],[
    RUSTC=no
    CARGO=no
    ])
AM_CONDITIONAL([HAVE_RUST],[test "x$RUSTC" != "xno" && test "x$CARGO" != "xno"])
