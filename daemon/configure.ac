# libguestfs-daemon
# Copyright (C) 2009 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

AC_INIT([libguestfs-daemon],[1.0.0])
AM_INIT_AUTOMAKE([foreign])

AC_CONFIG_MACRO_DIR([m4])

dnl If the user specified --enable-32bit, then force the C compiler
dnl to build 32 bit binaries (gcc -m32).
AC_ARG_ENABLE([32bit],
  [AS_HELP_STRING([--enable-32bit], [build 32 bit binaries (gcc -m32)])],
  [export CC="gcc -m32"],
  [enable_32bit=no])

dnl Enable 'debug' command.
AC_ARG_ENABLE([debug-command],
  [AS_HELP_STRING([--enable-debug-command], [enable the 'debug' command])],
  [AC_DEFINE_UNQUOTED([ENABLE_DEBUG_COMMAND],[1],[Enable the 'debug' command])],
  [])

dnl For strchrnul(3), asprintf(3), futimens(2) and getline(3).
AC_GNU_SOURCE

dnl Check for basic C environment.
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

dnl Check for Augeas (now optional).
AC_CHECK_LIB([augeas],[aug_match],[
        LIBS="-laugeas $LIBS"
        have_augeas=yes
        dnl Check for functions not available in earlier versions of Augeas.
        AC_CHECK_FUNCS([aug_load aug_defvar aug_defnode])
        ],[have_augeas=no])
if test "x$have_augeas" = "xyes"; then
        AC_DEFINE([HAVE_AUGEAS],[1],[Define to 1 if you have Augeas])
fi

dnl Check for XDR library.
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
        AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
        ])

dnl Functions which may not be available in older distributions.
AC_CHECK_FUNCS([futimens listxattr llistxattr getxattr lgetxattr setxattr lsetxattr removexattr lremovexattr])

dnl For modified printf, we need glibc either (old-style)
dnl register_printf_function or (new-style) register_printf_specifier.
AC_CHECK_FUNC([register_printf_specifier],[
        AC_DEFINE([HAVE_REGISTER_PRINTF_SPECIFIER],[1],
                [Define to 1 if you have new-style register_printf_specifier])
        ],[
        AC_CHECK_FUNC([register_printf_function],[
                AC_DEFINE([HAVE_REGISTER_PRINTF_FUNCTION],[1],
                        [Define to 1 if you have old-style register_printf_function])
                ],[
                AC_MSG_FAILURE(
[No support for glibc-style extended printf formatters.

This means you either have a very old glibc (pre-2.0) or you
are using some other libc where this is not supported.])])])

dnl Headers.
AC_CHECK_HEADERS([attr/xattr.h sys/xattr.h])

dnl Produce output files.
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
