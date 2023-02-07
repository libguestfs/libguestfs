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

dnl Check for Ruby and rake (optional, for Ruby bindings).
AC_ARG_ENABLE([ruby],
    AS_HELP_STRING([--disable-ruby], [disable Ruby language bindings]),
    [],
    [enable_ruby=yes])
AS_IF([test "x$enable_ruby" != "xno"],[
    AC_CHECK_PROG([RUBY],[ruby],[ruby],[no])
    AC_CHECK_PROG([RAKE],[rake],[rake],[no])

    AS_IF([test -n "$RUBY" && test -n "$RAKE"],[
        dnl Find the library.  Note on Debian it's not -lruby.
        AC_MSG_CHECKING([for C library for Ruby extensions])
        ruby_cmd='puts RbConfig::CONFIG@<:@"RUBY_SO_NAME"@:>@'
        echo running: $RUBY -rrbconfig -e \'$ruby_cmd\' >&AS_MESSAGE_LOG_FD
        $RUBY -rrbconfig -e "$ruby_cmd" >conftest 2>&AS_MESSAGE_LOG_FD
        libruby="$(cat conftest)"
        rm conftest
        AS_IF([test -n "$libruby"],[
            ruby_cmd='puts RbConfig::CONFIG@<:@"libdir"@:>@'
            echo running: $RUBY -rrbconfig -e \'$ruby_cmd\' >&AS_MESSAGE_LOG_FD
            $RUBY -rrbconfig -e "$ruby_cmd" >conftest 2>&AS_MESSAGE_LOG_FD
            libruby_libdir="$(cat conftest)"
            rm conftest
            test -n "$libruby_libdir" && libruby_libdir="-L$libruby_libdir"
            AC_MSG_RESULT([-l$libruby])
            AC_CHECK_LIB([$libruby],[ruby_init],
                         [have_libruby=1],[have_libruby=],[$libruby_libdir])
        ],[
            AC_MSG_RESULT([not found])
        ])
    ])
])
AM_CONDITIONAL([HAVE_RUBY],
    [test -n "$RUBY" && test -n "$RAKE" && test -n "$have_libruby"])
