# libguestfs
# Copyright (C) 2009-2016 Red Hat Inc.
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

AC_PROG_LIBTOOL
AC_PROG_LN_S

dnl Check for cpio which isn't in the default Pardus install amazingly.
AC_CHECK_PROG([CPIO],[cpio],[cpio],[no])
test "x$CPIO" = "xno" &&
    AC_MSG_ERROR([cpio must be installed])

dnl Check for gperf.
AC_CHECK_PROG([GPERF],[gperf],[gperf],[no])
test "x$GPERF" = "xno" &&
    AC_MSG_ERROR([gperf must be installed])

dnl Check for genisoimage/mkisofs
AC_PATH_PROGS([GENISOIMAGE],[genisoimage mkisofs],[no],
    [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$GENISOIMAGE" = "xno" && AC_MSG_ERROR([genisoimage must be installed])

dnl Check for optional xmllint.
AC_CHECK_PROG([XMLLINT],[xmllint],[xmllint],[no])
AM_CONDITIONAL([HAVE_XMLLINT],[test "x$XMLLINT" != "xno"])

dnl po4a for translating man pages and POD files (optional).
AC_CHECK_PROG([PO4A],[po4a],[po4a],[no])
AM_CONDITIONAL([HAVE_PO4A], [test "x$PO4A" != "xno"])

dnl Check for db_dump, db_load (optional).
GUESTFS_FIND_DB_TOOL([DB_DUMP], [dump])
GUESTFS_FIND_DB_TOOL([DB_LOAD], [load])
if test "x$DB_DUMP" != "xno"; then
    AC_DEFINE_UNQUOTED([DB_DUMP],["$DB_DUMP"],[Name of db_dump program.])
fi
if test "x$DB_LOAD" != "xno"; then
    AC_DEFINE_UNQUOTED([DB_LOAD],["$DB_LOAD"],[Name of db_load program.])
fi

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

dnl zip/unzip, used by virt-v2v
AC_PATH_PROGS([ZIP],[zip],[no])
AC_DEFINE_UNQUOTED([ZIP],["$ZIP"],[Name of zip program.])
AM_CONDITIONAL([HAVE_ZIP],[test "x$ZIP" != "xno"])
AC_PATH_PROGS([UNZIP],[unzip],[no])
AC_DEFINE_UNQUOTED([UNZIP],["$UNZIP"],[Name of unzip program.])

dnl Check for valgrind
AC_CHECK_PROG([VALGRIND],[valgrind],[valgrind],[no])
AS_IF([test "x$VALGRIND" != "xno"],[
    # Substitute the whole valgrind command.
    VG='$(VALGRIND) --vgdb=no --log-file=$(abs_top_builddir)/tmp/valgrind-%q{T}-%p.log --leak-check=full --error-exitcode=119 --suppressions=$(abs_top_srcdir)/valgrind-suppressions'
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
