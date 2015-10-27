# libguestfs
# Copyright (C) 2009-2015 Red Hat Inc.
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

dnl Check for Perl (optional, for Perl bindings and Perl tools).
AC_ARG_ENABLE([perl],
    AS_HELP_STRING([--disable-perl], [disable Perl language bindings]),
    [],
    [enable_perl=yes])
AS_IF([test "x$enable_perl" != "xno"],[
    dnl Check for Perl modules that must be present to compile and
    dnl test the Perl bindings.
    missing_perl_modules=no
    for pm in Test::More Module::Build; do
        AC_MSG_CHECKING([for $pm])
        if ! $PERL -M$pm -e1 >&AS_MESSAGE_LOG_FD 2>&1; then
            AC_MSG_RESULT([no])
            missing_perl_modules=yes
        else
            AC_MSG_RESULT([yes])
        fi
    done
    if test "x$missing_perl_modules" = "xyes"; then
        AC_MSG_WARN([some Perl modules required to compile or test the Perl bindings are missing])
    fi
])
AM_CONDITIONAL([HAVE_PERL],
    [test "x$enable_perl" != "xno" && test "x$PERL" != "xno" && test "x$missing_perl_modules" != "xyes"])
