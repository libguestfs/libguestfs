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

# Check for external programs required to either build or run
# libguestfs.
#
# AC_CHECK_PROG(S) or AC_PATH_PROG(S)?
#
# Use AC_CHECK_PROG(S) for programs which are only used during build.
#
# Use AC_PATH_PROG(S) for program names which are compiled into the
# binary and used at run time.  The reason is so that we know which
# programs the binary actually uses.

# Define $(SED).
m4_ifdef([AC_PROG_SED],[
    AC_PROG_SED
],[
    dnl ... else hope for the best
    AC_SUBST([SED], "sed")
])

# Define $(AWK).
AC_PROG_AWK

AC_PROG_LN_S

dnl Check for cpio which isn't in the default Pardus install amazingly.
AC_CHECK_PROG([CPIO],[cpio],[cpio],[no])
test "x$CPIO" = "xno" &&
    AC_MSG_ERROR([cpio must be installed])

dnl Check for gperf.
AC_CHECK_PROG([GPERF],[gperf],[gperf],[no])
test "x$GPERF" = "xno" &&
    AC_MSG_ERROR([gperf must be installed])

dnl Check for realpath (used by ocaml-dep.sh for basic builds).
AC_CHECK_PROGS([REALPATH],[grealpath realpath],[no])
test "x$REALPATH" = "xno" &&
    AC_MSG_ERROR([GNU realpath program must be installed])

dnl Check for xorriso/genisoimage/mkisofs.
AC_PATH_PROGS([MKISOFS],[xorrisofs genisoimage mkisofs],[no],
    [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$MKISOFS" = "xno" && AC_MSG_ERROR([xorriso or genisoimage or mkisofs must be installed])

dnl Check for optional xmllint.
AC_CHECK_PROG([XMLLINT],[xmllint],[xmllint],[no])
AM_CONDITIONAL([HAVE_XMLLINT],[test "x$XMLLINT" != "xno"])

dnl po4a for translating man pages and POD files (optional).
AC_CHECK_PROG([PO4A_GETTEXTIZE],[po4a-gettextize],[po4a-gettextize],[no])
AC_CHECK_PROG([PO4A_TRANSLATE],[po4a-translate],[po4a-translate],[no])
AM_CONDITIONAL([HAVE_PO4A], [test "x$PO4A_GETTEXTIZE" != "xno" && test "x$PO4A_TRANSLATE" != "xno"])

dnl Check for sqlite3 (optional).
AC_CHECK_PROG([SQLITE3],[sqlite3],[sqlite3],[no])

dnl Check for netpbm programs (optional).
AC_PATH_PROGS([PBMTEXT],[pbmtext],[no])
AC_PATH_PROGS([PNMTOPNG],[pnmtopng],[no])
AC_PATH_PROGS([BMPTOPNM],[bmptopnm],[no])
AC_PATH_PROGS([PAMCUT],[pamcut],[no])
if test "x$PBMTEXT" != "xno"; then
    AC_DEFINE_UNQUOTED([PBMTEXT],["$PBMTEXT"],[Name of pbmtext program.])
fi
if test "x$PNMTOPNG" != "xno"; then
    AC_DEFINE_UNQUOTED([PNMTOPNG],["$PNMTOPNG"],[Name of pnmtopng program.])
fi
if test "x$BMPTOPNM" != "xno"; then
    AC_DEFINE_UNQUOTED([BMPTOPNM],["$BMPTOPNM"],[Name of bmptopnm program.])
fi
if test "x$PAMCUT" != "xno"; then
    AC_DEFINE_UNQUOTED([PAMCUT],["$PAMCUT"],[Name of pamcut program.])
fi

dnl Check for icoutils (optional).
AC_PATH_PROGS([WRESTOOL],[wrestool],[no])
if test "x$WRESTOOL" != "xno"; then
    AC_DEFINE_UNQUOTED([WRESTOOL],["$WRESTOOL"],[Name of wrestool program.])
fi

dnl Check for xzcat (required).
AC_PATH_PROGS([XZCAT],[xzcat],[no])
test "x$XZCAT" = "xno" && AC_MSG_ERROR([xzcat must be installed])
AC_DEFINE_UNQUOTED([XZCAT],["$XZCAT"],[Name of xzcat program.])

dnl Check for zstdcat (required).
AC_PATH_PROGS([ZSTDCAT],[zstdcat],[no])
test "x$ZSTDCAT" = "xno" && AC_MSG_ERROR([zstdcat must be installed])

dnl (f)lex and bison for virt-builder (required).
dnl XXX Could be optional with some work.
AC_PROG_LEX
AC_PROG_YACC
dnl These macros don't fail, instead they set some useless defaults.
if test "x$LEX" = "x:"; then
    AC_MSG_FAILURE([GNU 'flex' is required.])
fi
if test "x$YACC" = "xyacc"; then
    AC_MSG_FAILURE([GNU 'bison' is required (yacc won't work).])
fi

dnl Check for valgrind
AC_CHECK_PROG([VALGRIND],[valgrind],[valgrind],[no])
AS_IF([test "x$VALGRIND" != "xno"],[
    # Substitute the whole valgrind command.
    # --read-inline-info=no is a temporary workaround for RHBZ#1662656.
    # Note we run libtool, not $(LIBTOOL) since the latter expands to
    # libtool-kill-dependency-libs.sh
    VG='libtool --mode=execute $(VALGRIND) --vgdb=no --log-file=$(abs_top_builddir)/tmp/valgrind-%q{T}-%p.log --leak-check=full --error-exitcode=119 --suppressions=$(abs_top_srcdir)/valgrind-suppressions --trace-children=no --child-silent-after-fork=yes --run-libc-freeres=no --read-inline-info=no'
    ],[
    # No valgrind, so substitute VG with something that will break.
    VG=VALGRIND_IS_NOT_INSTALLED
])
AC_SUBST([VG])
AM_SUBST_NOTMAKE([VG])

dnl Check for fuser (used in FUSE stuff).
AC_PATH_PROGS([FUSER],[fuser],[/sbin/fuser])
AC_DEFINE_UNQUOTED([FUSER],["$FUSER"],[Name of fuser program.])

dnl Check for true (used in tests).
AC_PATH_PROGS([TOOL_TRUE],[true],[/bin/true])
AC_DEFINE_UNQUOTED([TOOL_TRUE],["$TOOL_TRUE"],[Name of 'true' program.])
