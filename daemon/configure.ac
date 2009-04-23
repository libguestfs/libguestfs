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
AM_INIT_AUTOMAKE

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

dnl Check for basic C environment.
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AC_PROG_CC_C_O

dnl Check for Augeas.
AC_CHECK_LIB([augeas],[aug_match],,[
	AC_MSG_ERROR([Augeas library not found])
	])

dnl Check for functions not available in earlier versions of Augeas.
AC_CHECK_FUNC([aug_load aug_defvar aug_defnode])

dnl Check for XDR library.
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
	AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
	])

dnl Produce output files.
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
