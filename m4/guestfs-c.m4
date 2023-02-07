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

dnl The C compiler environment.
dnl Define the host CPU architecture (defines 'host_cpu')
AC_CANONICAL_HOST

dnl Check for basic C environment.
AC_PROG_CC_STDC
AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

AC_ARG_ENABLE([werror],
    [AS_HELP_STRING([--enable-werror],
                    [turn on lots of GCC warnings (for developers)])],
     [case $enableval in
      yes|no) ;;
      *)      AC_MSG_ERROR([bad value $enableval for werror option]) ;;
      esac
      gcc_warnings=$enableval],
      [gcc_warnings=no]
)
WARN_CFLAGS="-Wall"
AC_SUBST([WARN_CFLAGS])
if test "x$gcc_warnings" = "xyes"; then
    WERROR_CFLAGS="-Werror"
fi
AC_SUBST([WERROR_CFLAGS])

# Provide a global place to set CFLAGS.  (Note that setting AM_CFLAGS
# is no use because it doesn't override target_CFLAGS).
#---
# Kill -fstrict-overflow which is a license for the C compiler to make
# dubious and often unsafe optimizations, in a time-wasting attempt to
# deal with CPU architectures that do not exist.
CFLAGS="$CFLAGS -fno-strict-overflow -Wno-strict-overflow"

dnl Work out how to specify the linker script to the linker.
VERSION_SCRIPT_FLAGS=-Wl,--version-script=
`/usr/bin/ld --help 2>&1 | grep -- --version-script >/dev/null` || \
    VERSION_SCRIPT_FLAGS="-Wl,-M -Wl,"
AC_SUBST(VERSION_SCRIPT_FLAGS)

dnl Use -fvisibility=hidden by default in the library.
dnl http://gcc.gnu.org/wiki/Visibility
AS_IF([test -n "$GCC"],
    [AC_SUBST([GCC_VISIBILITY_HIDDEN], [-fvisibility=hidden])],
    [AC_SUBST([GCC_VISIBILITY_HIDDEN], [:])])

dnl Check support for 64 bit file offsets.
AC_SYS_LARGEFILE

dnl Check sizeof long.
AC_CHECK_SIZEOF([long])

dnl Check if __attribute__((cleanup(...))) works.
dnl Set -Werror, otherwise gcc will only emit a warning for attributes
dnl that it doesn't understand.
acx_nbdkit_save_CFLAGS="${CFLAGS}"
CFLAGS="${CFLAGS} -Werror"
AC_MSG_CHECKING([if __attribute__((cleanup(...))) works with this compiler])
AC_COMPILE_IFELSE([
AC_LANG_SOURCE([[
#include <stdio.h>
#include <stdlib.h>

void
freep (void *ptr)
{
  exit (EXIT_SUCCESS);
}

void
test (void)
{
  __attribute__((cleanup(freep))) char *ptr = malloc (100);
}

int
main (int argc, char *argv[])
{
  test ();
  exit (EXIT_FAILURE);
}
]])
    ],[
    AC_MSG_RESULT([yes])
    AC_DEFINE([HAVE_ATTRIBUTE_CLEANUP],[1],[Define to 1 if '__attribute__((cleanup(...)))' works with this compiler.])
    ],[
    AC_MSG_WARN(
['__attribute__((cleanup(...)))' does not work.

You may not be using a sufficiently recent version of GCC or CLANG, or
you may be using a C compiler which does not support this attribute,
or the configure test may be wrong.

The code will still compile, but is likely to leak memory and other
resources when it runs.])])
dnl restore CFLAGS
CFLAGS="${acx_nbdkit_save_CFLAGS}"

dnl Define this so that include/guestfs.h is included
dnl instead of the possibly installed <guestfs.h>.  This is
dnl only needed when compiling libguestfs itself.  It is
dnl expanded in common/ submodule.  For other packages like
dnl virt-v2v which also use common/ it is empty.
AC_SUBST([INCLUDE_DIRECTORY], [-I\$\(top_srcdir\)/include])
