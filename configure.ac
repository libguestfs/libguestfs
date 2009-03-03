# libguestfs
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

AC_INIT([libguestfs],[0.1])
AM_INIT_AUTOMAKE

dnl Make sure the user has created the link to nfs-utils source.
if ! test -e $srcdir/daemon/nfs-utils \
    -o -f $srcdir/daemon/nfs-utils/utils/nfsd/nfsd.c; then
  AC_MSG_ERROR([$srcdir/daemon/nfs-utils must be a symlink to the unpacked nfs-utils sources.
See the README file for more information.])
fi

dnl Check for basic C environment.
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AC_PROG_CC_C_O

dnl Check for rpcgen and XDR library.  rpcgen is optional.
AC_CHECK_PROG([RPCGEN],[rpcgen],[rpcgen],[no])
AM_CONDITIONAL([RPCGEN],[test "x$RPCGEN" != "xno"])
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
	AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
	])

dnl Check for QEMU.  We only check for the basic 'qemu' program here
dnl (ie. the i386 full system qemu).  But at runtime we might choose
dnl a different qemu to run, eg. qemu-system-ppc.  What we run depends
dnl on several factors explained in the README.
AC_PATH_PROG([QEMU],[qemu],[no],
	[$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$QEMU" = "xno" && AC_MSG_ERROR([No 'qemu' program found])

dnl Check for mkinitrd, cpio.
AC_PATH_PROG([MKINITRD],[mkinitrd],[no],
	[$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$MKINITRD" = "xno" && AC_MSG_ERROR([No 'mkinitrd' program found])
AC_CHECK_PROG([CPIO],[cpio],[cpio],[no])
test "x$CPIO" = "xno" && AC_MSG_ERROR([No 'cpio' program found])

dnl Produce output files.
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
