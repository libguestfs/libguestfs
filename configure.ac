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

AC_INIT([libguestfs],[0.5])
AM_INIT_AUTOMAKE

AC_CONFIG_MACRO_DIR([m4])

AC_PROG_LIBTOOL

dnl Check for basic C environment.
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

dnl Check support for 64 bit file offsets.
AC_SYS_LARGEFILE

dnl Headers.
AC_CHECK_HEADERS([errno.h sys/types.h sys/un.h sys/wait.h sys/socket.h])

dnl Check for rpcgen and XDR library.  rpcgen is optional.
AC_CHECK_PROG([RPCGEN],[rpcgen],[rpcgen],[no])
AM_CONDITIONAL([HAVE_RPCGEN],[test "x$RPCGEN" != "xno"])
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
	AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
	])

dnl Check for pod2man and pod2text.
AC_CHECK_PROG([POD2MAN],[pod2man],[pod2man],[no])
test "x$POD2MAN" = "xno" &&
     AC_MSG_ERROR([pod2man must be installed])
AC_CHECK_PROG([POD2TEXT],[pod2text],[pod2text],[no])
test "x$POD2TEXT" = "xno" &&
     AC_MSG_ERROR([pod2text must be installed])

dnl Check for QEMU for running binaries on this $host_cpu, fall
dnl back to basic 'qemu'.
AC_PATH_PROGS([QEMU],[qemu-system-$host_cpu qemu],[no],
	[$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$QEMU" = "xno" && AC_MSG_ERROR([qemu must be installed])
AC_DEFINE_UNQUOTED([QEMU],["$QEMU"],[Location of qemu binary.])

dnl Check for febootstrap etc.
AC_CHECK_PROG([FEBOOTSTRAP],
	[febootstrap],[febootstrap],[no])
test "x$FEBOOTSTRAP" = "xno" && \
     AC_MSG_ERROR([febootstrap must be installed])
AC_CHECK_PROG([FEBOOTSTRAP_RUN],
	[febootstrap-run],[febootstrap-run],[no])
test "x$FEBOOTSTRAP_RUN" = "xno" && \
     AC_MSG_ERROR([febootstrap-run must be installed])
AC_CHECK_PROG([FEBOOTSTRAP_MINIMIZE],
	[febootstrap-minimize],[febootstrap-minimize],[no])
test "x$FEBOOTSTRAP_MINIMIZE" = "xno" && \
     AC_MSG_ERROR([febootstrap-minimize must be installed])
AC_CHECK_PROG([FEBOOTSTRAP_TO_INITRAMFS],
	[febootstrap-to-initramfs],[febootstrap-to-initramfs],[no])
test "x$FEBOOTSTRAP_TO_INITRAMFS" = "xno" && \
     AC_MSG_ERROR([febootstrap-to-initramfs must be installed])

dnl --with-repo to specify a Fedora repository.
AC_ARG_WITH([repo],
	[AS_HELP_STRING([--with-repo],
	  [set name of Fedora repository @<:@default=fedora-10@:>@])],
	[],
	[with_repo=fedora-10])
REPO="$with_repo"
AC_SUBST(REPO)
AC_DEFINE_UNQUOTED([REPO],["$REPO"],[Name of Fedora repository.])

AC_DEFINE_UNQUOTED([host_cpu],["$host_cpu"],[Host architecture.])

dnl --with-mirror to specify a local Fedora mirror.
AC_ARG_WITH([mirror],
	[AS_HELP_STRING([--with-mirror],
	  [set URI of a local Fedora mirror])],
	[],
	[with_mirror=])
MIRROR="$with_mirror"
AC_SUBST(MIRROR)

dnl Check for OCaml (optional, for OCaml bindings).
AC_PROG_OCAML
AC_PROG_FINDLIB
AM_CONDITIONAL([HAVE_OCAML],[test "x$OCAMLC" != "xno" -a "x$OCAMLFIND" != "xno"])

dnl Check for Perl (optional, for Perl bindings).
dnl XXX This isn't quite right, we should check for devel libraries.
AC_CHECK_PROG([PERL],[perl],[perl],[no])
AM_CONDITIONAL([HAVE_PERL],[test "x$PERL" != "xno"])

dnl Check for Python (optional, for Python bindings).
dnl XXX This isn't quite right, we should check for devel libraries.
AC_CHECK_PROG([PYTHON],[python],[python],[no])
AM_CONDITIONAL([HAVE_PYTHON],[test "x$PYTHON" != "xno"])

dnl Run in subdirs.
AC_CONFIG_SUBDIRS([daemon])

dnl Produce output files.
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile src/Makefile fish/Makefile examples/Makefile
		 images/Makefile
		 ocaml/Makefile ocaml/examples/Makefile
		 perl/Makefile
		 python/Makefile
	         make-initramfs.sh update-initramfs.sh
		 libguestfs.spec
		 ocaml/META perl/Makefile.PL])
AC_OUTPUT

dnl WTF?
chmod +x make-initramfs.sh update-initramfs.sh
