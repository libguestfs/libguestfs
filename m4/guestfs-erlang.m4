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

dnl Erlang
ERLANG=no
AC_ARG_ENABLE([erlang],
    AS_HELP_STRING([--disable-erlang], [disable Erlang language bindings]),
         [],
         [enable_erlang=yes])
# NB: Don't use AS_IF here: it doesn't work.
if test "x$enable_erlang" != "xno"; then
        ERLANG=
        AC_ERLANG_PATH_ERLC([no])

        if test "x$ERLC" != "xno"; then
            AC_ERLANG_CHECK_LIB([erl_interface], [],
                                [AC_MSG_FAILURE([Erlang erl_interface library not installed.  Use --disable-erlang to disable.])])
            AC_ERLANG_SUBST_LIB_DIR
        fi
fi
AM_CONDITIONAL([HAVE_ERLANG], [test "x$ERLANG" != "xno" && test "x$ERLC" != "xno"])
