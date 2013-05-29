# libguestfs
# Copyright (C) 2009-2013 Red Hat Inc.
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

# The major, minor, and release fields MUST be numbers.  Packagers can
# add extra information using --with-extra="..." which may be any
# freeform string.
m4_define([libguestfs_major],   [1])
m4_define([libguestfs_minor],   [20])
m4_define([libguestfs_release], [11])

AC_INIT([libguestfs],libguestfs_major.libguestfs_minor.libguestfs_release)
AC_CONFIG_AUX_DIR([build-aux])

dnl Initialize automake.  automake < 1.12 didn't have serial-tests and
dnl gives an error if it sees this, but for automake >= 1.13
dnl serial-tests is required so we have to include it.  Solution is to
dnl test for the version of automake (by running an external command)
dnl and provide it if necessary.  Note we have to do this entirely using
dnl m4 macros since automake queries this macro by running
dnl 'autoconf --trace'.
m4_define([serial_tests], [
    m4_esyscmd([automake --version | head -1 | awk '
                     {
                       split ($NF, version, ".");
                       if (version[1] == 1 && version[2] >= 12)
                         print "serial-tests";
                     }'
    ])
])
AM_INIT_AUTOMAKE(foreign serial_tests) dnl NB: Do not [quote] this parameter.

m4_ifndef([AM_SILENT_RULES], [m4_define([AM_SILENT_RULES],[])])
AM_SILENT_RULES([yes]) # make --enable-silent-rules the default.

AC_CONFIG_MACRO_DIR([m4])

dnl Stable or development version?
BRANCH_NUMBER=libguestfs_major.libguestfs_minor
AC_SUBST([BRANCH_NUMBER])
AC_MSG_CHECKING([if $BRANCH_NUMBER is a stable or development branch of libguestfs])
AS_IF([test "$((libguestfs_minor % 2))" -eq 0 ],[
    BRANCH_TYPE=stable
    AC_MSG_RESULT([$BRANCH_TYPE])
],[
    BRANCH_TYPE=development
    AC_MSG_RESULT([$BRANCH_TYPE])
    AC_MSG_NOTICE([
***
This is a development version of libguestfs. Some APIs may be unstable
until they appear in a stable release of libguestfs (at which point
the C API and ABI is guaranteed to remain stable forever).  For
more information about stable and development branches of libguestfs
please see the section "LIBGUESTFS VERSION NUMBERS" in guestfs(3).
***])
])
AC_SUBST([BRANCH_TYPE])

dnl Extra string, a freeform string defined by packagers.
AC_ARG_WITH([extra],
    [AS_HELP_STRING([--with-extra],
                    [extra version string (for use by packagers)])],
    [libguestfs_extra="$withval"],
    [libguestfs_extra=]
)

AC_MSG_NOTICE([libguestfs version libguestfs_major.libguestfs_minor.libguestfs_release$libguestfs_extra])

dnl Split up the version string.
AC_DEFINE([PACKAGE_VERSION_MAJOR],[libguestfs_major],[Major version number.])
AC_DEFINE([PACKAGE_VERSION_MINOR],[libguestfs_minor],[Minor version number.])
AC_DEFINE([PACKAGE_VERSION_RELEASE],[libguestfs_release],[Release number.])
AC_DEFINE_UNQUOTED([PACKAGE_VERSION_EXTRA],["$libguestfs_extra"],[Extra version string.])

dnl Default attach method.
AC_MSG_CHECKING([if the user specified a default attach method])
AC_ARG_WITH([default-attach-method],
    [AS_HELP_STRING([--with-default-attach-method="appliance|libvirt|..."],
        [set default attach method @<:@default=appliance@:>@])],
    [DEFAULT_ATTACH_METHOD="$withval"],
    [DEFAULT_ATTACH_METHOD=appliance])
AC_MSG_RESULT([$DEFAULT_ATTACH_METHOD])
AC_DEFINE_UNQUOTED([DEFAULT_ATTACH_METHOD],["$DEFAULT_ATTACH_METHOD"],
                   [Default attach method.])

dnl Early gnulib initialization.
gl_EARLY
gl_INIT

AC_PROG_LIBTOOL

# Define $(SED).
m4_ifdef([AC_PROG_SED],[
    AC_PROG_SED
],[
    dnl ... else hope for the best
    AC_SUBST([SED], "sed")
])

dnl Check for basic C environment.
AC_PROG_CC_STDC
AC_PROG_INSTALL
AC_PROG_CPP

AC_ARG_ENABLE([gcc-warnings],
    [AS_HELP_STRING([--enable-gcc-warnings],
                    [turn on lots of GCC warnings (for developers)])],
    [case $enableval in
     yes|no) ;;
     *)      AC_MSG_ERROR([bad value $enableval for gcc-warnings option]) ;;
     esac
     gl_gcc_warnings=$enableval],
    [gl_gcc_warnings=no]
)

if test "$gl_gcc_warnings" = yes; then
    gl_WARN_ADD([-Werror], [WERROR_CFLAGS])
    AC_SUBST([WERROR_CFLAGS])

    nw=
    # This, $nw, is the list of warnings we disable.
    nw="$nw -Wdeclaration-after-statement" # too useful to forbid
    nw="$nw -Waggregate-return"      # anachronistic
    nw="$nw -Wc++-compat"            # We don't care about C++ compilers
    nw="$nw -Wundef"                 # Warns on '#if GNULIB_FOO' etc in gnulib
    nw="$nw -Wtraditional"           # Warns on #elif which we use often
    nw="$nw -Wcast-qual"             # Too many warnings for now
    nw="$nw -Wconversion"            # Too many warnings for now
    nw="$nw -Wsystem-headers"        # Don't let system headers trigger warnings
    nw="$nw -Wsign-conversion"       # Not an error
    nw="$nw -Wtraditional-conversion" # Don't care about pre-ANSI compilers
    nw="$nw -Wpadded"                # Our structs are not padded
    nw="$nw -Wredundant-decls"       # openat.h declares e.g., mkdirat
    nw="$nw -Wlogical-op"            # any use of fwrite provokes this
    nw="$nw -Wvla"                   # two warnings in mount.c
    # things I might fix soon:
    nw="$nw -Wmissing-format-attribute" # daemon.h's asprintf_nowarn
    nw="$nw -Winline"                # daemon.h's asprintf_nowarn
    nw="$nw -Wshadow"                # numerous, plus we're not unanimous
    nw="$nw -Wunsafe-loop-optimizations" # just a warning that an optimization
                                     # was not possible, safe to ignore
    nw="$nw -Wpacked"                # Allow attribute((packed)) on structs
    nw="$nw -Wlong-long"             # Allow long long since it's required
                                     # by Python, Ruby and xstrtoll.
    nw="$nw -Wsuggest-attribute=pure" # Don't suggest pure functions.
    nw="$nw -Wsuggest-attribute=const" # Don't suggest const functions.
    nw="$nw -Wunsuffixed-float-constants" # Don't care about these.
    nw="$nw -Wswitch-default"        # This warning is actively dangerous.
    nw="$nw -Woverlength-strings"    # Who cares about stupid ISO C99 limit.

    gl_MANYWARN_ALL_GCC([ws])
    gl_MANYWARN_COMPLEMENT([ws], [$ws], [$nw])
    for w in $ws; do
        gl_WARN_ADD([$w])
    done

    # Normally we disable warnings in $nw above.  However $nw only
    # filters out exact matching warning strings from a list inside
    # gnulib (see m4/manywarnings.m4).  So we need to explicitly list a
    # few disabled warnings below.

    # Unused parameters are not a bug.
    gl_WARN_ADD([-Wno-unused-parameter])

    # Missing field initializers is not a bug in C.
    gl_WARN_ADD([-Wno-missing-field-initializers])

    # Display the name of the warning option with the warning.
    gl_WARN_ADD([-fdiagnostics-show-option])

    AC_SUBST([WARN_CFLAGS])

    AC_DEFINE([lint], [1], [Define to 1 if the compiler is checking for lint.])
    AC_DEFINE([GNULIB_PORTCHECK], [1], [Enable some gnulib portability checks.])
    AH_VERBATIM([FORTIFY_SOURCE],[
/* Enable compile-time and run-time bounds-checking, and some warnings. */
#if __OPTIMIZE__
# define _FORTIFY_SOURCE 2
#endif])
fi

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

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
dnl XXX It would be nice to use AC_COMPILE_IFELSE here, but gcc just
dnl emits a warning for attributes that it doesn't understand.
AC_MSG_CHECKING([if __attribute__((cleanup(...))) works with this compiler])
AC_RUN_IFELSE([
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

dnl Check if dirent (readdir) supports d_type member.
AC_STRUCT_DIRENT_D_TYPE

dnl Check if stat has the required fields.
AC_STRUCT_ST_BLOCKS
AC_CHECK_MEMBER([struct stat.st_blksize],[
    AC_DEFINE([HAVE_STRUCT_STAT_ST_BLKSIZE],[1],[Define to 1 if 'st_blksize' is a member of 'struct stat'.])])

dnl Define a C symbol for the host CPU architecture.
AC_DEFINE_UNQUOTED([host_cpu],["$host_cpu"],[Host architecture.])

dnl Headers.
AC_CHECK_HEADERS([\
    attr/xattr.h \
    byteswap.h \
    endian.h \
    errno.h \
    printf.h \
    sys/inotify.h \
    sys/socket.h \
    sys/statvfs.h \
    sys/types.h \
    sys/un.h \
    sys/wait.h \
    windows.h \
    sys/xattr.h])

dnl Functions.
AC_CHECK_FUNCS([\
    be32toh \
    fsync \
    futimens \
    getxattr \
    htonl \
    htons \
    inotify_init1 \
    lgetxattr \
    listxattr \
    llistxattr \
    lsetxattr \
    lremovexattr \
    mknod \
    ntohl \
    ntohs \
    posix_fallocate \
    posix_fadvise \
    realpath \
    removexattr \
    setitimer \
    setxattr \
    sigaction \
    statvfs \
    sync])

dnl tgetent, tputs and UP [sic] are all required.  They come from libtinfo
dnl which is pulled in as a dependency of libncurses.
old_LIBS="$LIBS"
AC_CHECK_LIB([ncurses], [tgetent], [], [
    AC_MSG_ERROR(['ncurses' library not found, or it doesn't contain 'tgetent'])
])
AC_CHECK_LIB([ncurses], [tputs], [], [
    AC_MSG_ERROR(['ncurses' library not found, or it doesn't contain 'tputs'])
])
AC_CHECK_LIB([ncurses], [UP], [], [
    AC_MSG_ERROR(['ncurses' library not found, or it doesn't contain 'UP'])
])
LIBS="$old_LIBS"

dnl GNU gettext tools (optional).
AC_CHECK_PROG([XGETTEXT],[xgettext],[xgettext],[no])
AC_CHECK_PROG([MSGCAT],[msgcat],[msgcat],[no])
AC_CHECK_PROG([MSGFMT],[msgfmt],[msgfmt],[no])
AC_CHECK_PROG([MSGMERGE],[msgmerge],[msgmerge],[no])

dnl Check they are the GNU gettext tools.
AC_MSG_CHECKING([msgfmt is GNU tool])
if $MSGFMT --version >/dev/null 2>&1 && $MSGFMT --version | grep -q 'GNU gettext'; then
    msgfmt_is_gnu=yes
else
    msgfmt_is_gnu=no
fi
AC_MSG_RESULT([$msgfmt_is_gnu])
AM_CONDITIONAL([HAVE_GNU_GETTEXT],
    [test "x$XGETTEXT" != "xno" && test "x$MSGCAT" != "xno" && test "x$MSGFMT" != "xno" && test "x$MSGMERGE" != "xno" && test "x$msgfmt_is_gnu" != "xno"])

dnl Build the daemon?
AC_MSG_CHECKING([if we should build the daemon])
AC_ARG_ENABLE([daemon],
    [AS_HELP_STRING([--enable-daemon],
        [enable building the daemon @<:@default=yes@:>@])],
    [],
    [enable_daemon=yes])
AM_CONDITIONAL([ENABLE_DAEMON],[test "x$enable_daemon" = "xyes"])
AC_MSG_RESULT([$enable_daemon])

if test "x$enable_daemon" = "xyes"; then
    dnl Install the daemon (for libguestfs live service)
    AC_MSG_CHECKING([if we should install the daemon])
    AC_ARG_ENABLE([install-daemon],
        [AS_HELP_STRING([--enable-install-daemon],
            [enable installing the daemon under $sbindir @<:@default=no@:>@])],
            [],
            [enable_install_daemon=no])
    AC_MSG_RESULT([$enable_install_daemon])

    dnl Enable valgrind in the daemon.
    AC_MSG_CHECKING([if we should run the daemon under valgrind])
    AC_ARG_ENABLE([valgrind-daemon],
        [AS_HELP_STRING([--enable-valgrind-daemon],
            [run the daemon under valgrind (developers only) @<:@default=no@:>@])],
            [],
            [enable_valgrind_daemon=no])
    AC_MSG_RESULT([$enable_valgrind_daemon])

    if test "x$enable_valgrind_daemon" = "xyes"; then
        AC_DEFINE([VALGRIND_DAEMON],[1],[Define to 1 to run the daemon under valgrind.])
        AC_DEFINE_UNQUOTED([VALGRIND_LOG_PATH],["$(pwd)"],[Path to save valgrind log files.])
    fi

    dnl Which directory should we put the daemon in?  NOTE: This
    dnl is the "virtual" directory inside the appliance, not the
    dnl install directory for libguestfs live.  Since Fedora 17
    dnl /sbin is a symlink to /usr/sbin.  We have to put the
    dnl daemon into a real (non-symlink) directory.
    dirs="/sbin /usr/sbin /bin /usr/bin"
    AC_MSG_CHECKING([which of $dirs is a real directory])
    for dir in $dirs; do
        parent=`dirname $dir`
        if test ! -L $parent && test -d $parent \
            && test ! -L $dir && test -d $dir
        then
            DAEMON_SUPERMIN_DIR=$dir
            break
        fi
    done
    if test "x$DAEMON_SUPERMIN_DIR" = "x"; then
        AC_MSG_ERROR([non-symlink binary directory not found])
    fi
    AC_MSG_RESULT([$DAEMON_SUPERMIN_DIR])
    AC_SUBST([DAEMON_SUPERMIN_DIR])

    dnl For modified printf in the daemon, we need glibc either (old-style)
    dnl register_printf_function or (new-style) register_printf_specifier.
    AC_CHECK_FUNC([register_printf_specifier],[
        AC_DEFINE([HAVE_REGISTER_PRINTF_SPECIFIER],[1],
                  [Define to 1 if you have new-style register_printf_specifier.])
    ],[
        AC_CHECK_FUNC([register_printf_function],[
            AC_DEFINE([HAVE_REGISTER_PRINTF_FUNCTION],[1],
                      [Define to 1 if you have old-style register_printf_function.])
        ],[
            AC_MSG_FAILURE(
[No support for glibc-style extended printf formatters.

This means you either have a very old glibc (pre-2.0) or you
are using some other libc where this is not supported.])])])
fi
AM_CONDITIONAL([INSTALL_DAEMON],[test "x$enable_install_daemon" = "xyes"])
AM_CONDITIONAL([VALGRIND_DAEMON],[test "x$enable_valgrind_daemon" = "xyes"])

dnl Build the appliance?
AC_MSG_CHECKING([if we should build the appliance])
AC_ARG_ENABLE([appliance],
    [AS_HELP_STRING([--enable-appliance],
        [enable building the appliance @<:@default=yes@:>@])],
        [],
        [enable_appliance=yes])
AM_CONDITIONAL([ENABLE_APPLIANCE],[test "x$enable_appliance" = "xyes"])
AC_MSG_RESULT([$enable_appliance])

dnl Check for supermin >= 4.1.0 or febootstrap >= 3.20.
AC_CHECK_PROGS([SUPERMIN],
               [supermin febootstrap],[no])
AC_CHECK_PROGS([SUPERMIN_HELPER],
               [supermin-helper febootstrap-supermin-helper],[no])

dnl Pass supermin --packager-config option.
dnl
dnl Note that in febootstrap >= 3.21 / supermin >= 4.1.0, this option
dnl is now called --packager-config, although --yum-config can still
dnl be used as a deprecated alias.
SUPERMIN_PACKAGER_CONFIG=no

AC_MSG_CHECKING([for --with-supermin-packager-config option])
AC_ARG_WITH([supermin-packager-config],
    [AS_HELP_STRING([--with-supermin-packager-config=FILE],
        [pass supermin --packager-config option @<:@default=no@:>@])],
    [SUPERMIN_PACKAGER_CONFIG="$withval"
     AC_MSG_RESULT([$SUPERMIN_PACKAGER_CONFIG"])],
    [AC_MSG_RESULT([not set])])

AC_MSG_CHECKING([for --with-febootstrap-yum-config option (deprecated)])
AC_ARG_WITH([febootstrap-yum-config],
    [AS_HELP_STRING([--with-febootstrap-yum-config=FILE],
        [pass supermin --packager-config option @<:@default=no@:>@])],
    [SUPERMIN_PACKAGER_CONFIG="$withval"
     AC_MSG_RESULT([$SUPERMIN_PACKAGER_CONFIG"])],
    [AC_MSG_RESULT([not set])])

AC_MSG_CHECKING([for --with-febootstrap-packager-config option (deprecated)])
AC_ARG_WITH([febootstrap-packager-config],
    [AS_HELP_STRING([--with-febootstrap-packager-config=FILE],
        [pass supermin --packager-config option @<:@default=no@:>@])],
    [SUPERMIN_PACKAGER_CONFIG="$withval"
     AC_MSG_RESULT([$SUPERMIN_PACKAGER_CONFIG"])],
    [AC_MSG_RESULT([not set])])

AC_SUBST([SUPERMIN_PACKAGER_CONFIG])

dnl Pass additional supermin options.
dnl
SUPERMIN_EXTRA_OPTIONS=no
AC_MSG_CHECKING([for --with-supermin-extra-options option])
AC_ARG_WITH([supermin-extra-options],
    [AS_HELP_STRING([--with-supermin-extra-options="--opt1 --opt2 ..."],
        [Pass additional supermin options. @<:@default=no@:>@])],
    [SUPERMIN_EXTRA_OPTIONS="$withval"
     AC_MSG_RESULT([$SUPERMIN_EXTRA_OPTIONS"])],
    [AC_MSG_RESULT([not set])])

AC_SUBST([SUPERMIN_EXTRA_OPTIONS])

if test "x$enable_appliance" = "xyes"; then
    test "x$SUPERMIN" = "xno" &&
        AC_MSG_ERROR([supermin (formerly called febootstrap) must be installed])
    dnl febootstrap 2.x did not support the --version parameter
    $SUPERMIN --version >&AS_MESSAGE_LOG_FD 2>&1 ||
        AC_MSG_ERROR([supermin (formerly called febootstrap) >= 3.20 must be installed, your version is too old])
fi

AC_DEFINE_UNQUOTED([SUPERMIN_HELPER],["$SUPERMIN_HELPER"],[Name of supermin-helper program.])

dnl Which distro?
dnl
dnl This used to be Very Important but is now just used to select
dnl which packages to install in the appliance, since the package
dnl names vary slightly across distros.  (See
dnl appliance/packagelist.in and appliance/excludelist.in)
AC_MSG_CHECKING([which Linux distro for package names])
DISTRO=REDHAT
if test -f /etc/debian_version; then
    DISTRO=DEBIAN
    if grep -q 'DISTRIB_ID=Ubuntu' /etc/lsb-release 2>&AS_MESSAGE_LOG_FD; then
        DISTRO=UBUNTU
    fi
fi
if test -f /etc/arch-release; then
    DISTRO=ARCHLINUX
fi
AC_MSG_RESULT([$DISTRO])
AC_SUBST([DISTRO])

dnl Check for rpcgen and XDR library.  rpcgen is optional.
AC_CHECK_PROG([RPCGEN],[rpcgen],[rpcgen],[no])
AM_CONDITIONAL([HAVE_RPCGEN],[test "x$RPCGEN" != "xno"])
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
    AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
])
AC_SEARCH_LIBS([xdr_u_int64_t],[portablexdr rpc xdr nsl],[
    AC_DEFINE([HAVE_XDR_U_INT64_T],[1],[Define to 1 if xdr_u_int64_t() exists.])
])
AC_SEARCH_LIBS([xdr_uint64_t],[portablexdr rpc xdr nsl],[
    AC_DEFINE([HAVE_XDR_UINT64_T],[1],[Define to 1 if xdr_uint64_t() exists.])
])
AM_CONDITIONAL([HAVE_XDR_U_INT64_T],
               [test "x$ac_cv_search_xdr_u_int64_t" != "xno"])
AM_CONDITIONAL([HAVE_XDR_UINT64_T],
               [test "x$ac_cv_search_xdr_uint64_t" != "xno"])

dnl Check for libselinux (optional).
AC_CHECK_HEADERS([selinux/selinux.h])
AC_CHECK_LIB([selinux],[setexeccon],[
    have_libselinux="$ac_cv_header_selinux_selinux_h"
    SELINUX_LIB="-lselinux"

    old_LIBS="$LIBS"
    LIBS="$LIBS $SELINUX_LIB"
    AC_CHECK_FUNCS([setcon getcon])
    LIBS="$old_LIBS"
],[have_libselinux=no])
if test "x$have_libselinux" = "xyes"; then
    AC_DEFINE([HAVE_LIBSELINUX],[1],[Define to 1 if you have libselinux.])
fi
AC_SUBST([SELINUX_LIB])

dnl Check for systemtap/DTrace userspace probes (optional).
dnl Since the probe points break under clang, allow this to be disabled.
AC_ARG_ENABLE([probes],
    AS_HELP_STRING([--disable-probes], [disable systemtap/DTrace userspace probes]),
    [],
    [enable_probes=yes])
AS_IF([test "x$enable_probes" != "xno"],[
    dnl http://sourceware.org/systemtap/wiki/AddingUserSpaceProbingToApps
    AC_CHECK_HEADERS([sys/sdt.h])
    dnl AC_CHECK_PROG([DTRACE],[dtrace],[dtrace],[no])
    AS_IF([test "x$ac_cv_header_sys_sdt_h" = "xyes"],[
        AC_DEFINE([ENABLE_PROBES],[1],[Enable systemtap/DTrace userspace probes.])
    ])
])

dnl Check for cpio which isn't in the default Pardus install amazingly.
AC_CHECK_PROG([CPIO],[cpio],[cpio],[no])
test "x$CPIO" = "xno" &&
    AC_MSG_ERROR([cpio must be installed])

dnl Check for gperf.
AC_CHECK_PROG([GPERF],[gperf],[gperf],[no])
test "x$GPERF" = "xno" &&
    AC_MSG_ERROR([gperf must be installed])

dnl Check for perl.
AC_CHECK_PROG([PERL],[perl],[perl],[no])
test "x$PERL" = "xno" &&
    AC_MSG_ERROR([perl must be installed])

dnl Check for Pod::Man, Pod::Simple.
AC_MSG_CHECKING([for Pod::Man])
if ! $PERL -MPod::Man -e1 >&AS_MESSAGE_LOG_FD 2>&1; then
    AC_MSG_ERROR([perl Pod::Man must be installed])
else
    AC_MSG_RESULT([yes])
fi
AC_MSG_CHECKING([for Pod::Simple])
if ! $PERL -MPod::Simple -e1 >&AS_MESSAGE_LOG_FD 2>&1; then
    AC_MSG_ERROR([perl Pod::Simple must be installed])
else
    AC_MSG_RESULT([yes])
fi

dnl Define the path to the podwrapper program.
PODWRAPPER="$PERL $(pwd)/podwrapper.pl"
AC_SUBST([PODWRAPPER])

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
AC_CHECK_PROGS([DB_DUMP],
               [db_dump db5.1_dump db4_dump db4.8_dump db4.7_dump db4.6_dump],[no])
AC_CHECK_PROGS([DB_LOAD],
               [db_load db5.1_load db4_load db4.8_load db4.7_load db4.6_load],[no])
if test "x$DB_DUMP" != "xno"; then
    AC_DEFINE_UNQUOTED([DB_DUMP],["$DB_DUMP"],[Name of db_dump program.])
fi
if test "x$DB_LOAD" != "xno"; then
    AC_DEFINE_UNQUOTED([DB_LOAD],["$DB_LOAD"],[Name of db_load program.])
fi

dnl Check for netpbm programs (optional).
AC_CHECK_PROGS([PBMTEXT],[pbmtext],[no])
AC_CHECK_PROGS([PNMTOPNG],[pnmtopng],[no])
AC_CHECK_PROGS([BMPTOPNM],[bmptopnm],[no])
AC_CHECK_PROGS([PAMCUT],[pamcut],[no])
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
AC_CHECK_PROGS([WRESTOOL],[wrestool],[no])
if test "x$WRESTOOL" != "xno"; then
    AC_DEFINE_UNQUOTED([WRESTOOL],["$WRESTOOL"],[Name of wrestool program.])
fi

dnl Check for QEMU for running binaries on this $host_cpu, fall
dnl back to basic 'qemu'.  Allow the user to override it.
qemu_system="`echo qemu-system-$host_cpu | $SED 's/i@<:@456@:>@86/i386/g'`"
default_qemu="qemu-kvm kvm $qemu_system qemu"
AC_ARG_WITH([qemu],
    [AS_HELP_STRING([--with-qemu="bin1 bin2 ..."],
        [set default QEMU binary @<:@default="[qemu-kvm] qemu-system-<host> qemu"@:>@])],
        [],
        [with_qemu="$default_qemu"])
AC_PATH_PROGS([QEMU],[$with_qemu],[no],
    [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin$PATH_SEPARATOR/usr/libexec])
test "x$QEMU" = "xno" && AC_MSG_ERROR([qemu must be installed])
AC_DEFINE_UNQUOTED([QEMU],["$QEMU"],[Location of qemu binary.])

dnl Does the user wish to specify -M, -cpu or other qemu options?
AC_MSG_CHECKING([if the user specified extra options for qemu command line])
AC_ARG_WITH([qemu-options],
    [AS_HELP_STRING([--with-qemu-options="-M ... -cpu ... etc"],
        [pass extra options for qemu command line @<:@default=no@:>@])],
    [QEMU_OPTIONS="$withval"],
    [QEMU_OPTIONS=no])
AS_IF([test "x$QEMU_OPTIONS" = "xno"],[
    AC_MSG_RESULT([no])
    QEMU_OPTIONS=
],[
    AC_MSG_RESULT([$QEMU_OPTIONS])
])
AC_DEFINE_UNQUOTED([QEMU_OPTIONS],["$QEMU_OPTIONS"],
                   [Extra options for qemu command line.])

dnl Check that the chosen qemu has virtio-serial support.
dnl For historical reasons this can be disabled by setting vmchannel_test=no.
if test "x$vmchannel_test" != "xno"; then
    AC_MSG_CHECKING([that $QEMU -help works])
    if $QEMU -help >&AS_MESSAGE_LOG_FD 2>&1; then
        AC_MSG_RESULT([yes])
    else
        AC_MSG_RESULT([no])
        AC_MSG_FAILURE(
[$QEMU -help: command failed.

This could be a very old version of qemu, or qemu might not be
working.
])
    fi

    AC_MSG_CHECKING([that $QEMU -version works])
    if $QEMU -version >&AS_MESSAGE_LOG_FD 2>&1; then
        AC_MSG_RESULT([yes])
    else
        AC_MSG_RESULT([no])
        AC_MSG_FAILURE(
[$QEMU -version: command failed.

This could be a very old version of qemu, or qemu might not be
working.
])
    fi

    AC_MSG_CHECKING([that $QEMU -nographic -machine accel=kvm:tcg -device ? works])
    if $QEMU -nographic -machine accel=kvm:tcg -device \? >&AS_MESSAGE_LOG_FD 2>&1; then
        AC_MSG_RESULT([yes])
    else
        AC_MSG_RESULT([no])
        AC_MSG_FAILURE([$QEMU -nographic -machine accel=kvm:tcg -device ? doesn't work.])
    fi

    AC_MSG_CHECKING([for virtio-serial support in $QEMU])
    if $QEMU $QEMU_OPTIONS -nographic -machine accel=kvm:tcg -device \? 2>&1 | grep -sq virtio-serial; then
        AC_MSG_RESULT([yes])
    else
        AC_MSG_RESULT([no])
        AC_MSG_FAILURE(
[I did not find virtio-serial support in
$QEMU.

virtio-serial support in qemu or KVM is essential for libguestfs
to operate.

Usually this means that you have to install a newer version of qemu
and/or KVM.  Please read the relevant section in the README file for
more information about this.

You can override this test by setting the environment variable
vmchannel_test=no

However if you don't have the right support in your qemu, then this
just delays the pain.

If I am using the wrong qemu or you want to compile qemu from source
and install it in another location, then you should configure with
the --with-qemu option.
])
    fi
fi

dnl Enable packet dumps when in verbose mode.  This generates lots
dnl of debug info, only useful for people debugging the RPC mechanism.
AC_ARG_ENABLE([packet-dump],[
    AS_HELP_STRING([--enable-packet-dump],
        [enable packet dumps in verbose mode @<:@default=no@:>@])],
    [AC_DEFINE([ENABLE_PACKET_DUMP],[1],[Enable packet dumps in verbose mode.])],
    [])

dnl Readline.
AC_ARG_WITH([readline],[
    AS_HELP_STRING([--with-readline],
        [support fancy command line editing @<:@default=check@:>@])],
    [],
    [with_readline=check])

LIBREADLINE=
AS_IF([test "x$with_readline" != xno],[
    AC_CHECK_LIB([readline], [main],
        [AC_SUBST([LIBREADLINE], ["-lreadline -lncurses"])
         AC_DEFINE([HAVE_LIBREADLINE], [1],
                   [Define if you have libreadline.])
        ],
        [if test "x$with_readline" != xcheck; then
         AC_MSG_FAILURE(
             [--with-readline was given, but test for readline failed])
         fi
        ], -lncurses)
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBREADLINE"
    AC_CHECK_FUNCS([append_history completion_matches rl_completion_matches])
    LIBS="$old_LIBS"
    ])

dnl Check for PCRE (required)
PKG_CHECK_MODULES([PCRE], [libpcre])

dnl Check for Augeas >= 1.0.0 (required).
PKG_CHECK_MODULES([AUGEAS],[augeas >= 1.0.0])

dnl libmagic (highly recommended)
AC_CHECK_LIB([magic],[magic_file],[
    AC_CHECK_HEADER([magic.h],[
        AC_SUBST([MAGIC_LIBS], ["-lmagic"])
        AC_DEFINE([HAVE_LIBMAGIC],[1],[libmagic found at compile time.])
    ], [])
],[AC_MSG_WARN([libmagic not found, some core features will be disabled])])

dnl POSIX acl library (highly recommended)
AC_CHECK_LIB([acl],[acl_from_text],[
    AC_CHECK_HEADER([sys/acl.h],[
        AC_SUBST([ACL_LIBS], [-lacl])
        AC_DEFINE([HAVE_ACL], [1], [Define to 1 if the POSIX acl library is available.])
    ], [])
],[AC_MSG_WARN([POSIX acl library not found])])

dnl Linux capabilities library (libcap) (highly recommended)
AC_CHECK_LIB([cap],[cap_from_text],[
    AC_CHECK_HEADER([sys/capability.h],[
        AC_SUBST([CAP_LIBS], [-lcap])
        AC_DEFINE([HAVE_CAP], [1], [Define to 1 if the Linux capabilities library (libcap) is available.])
    ], [])
],[AC_MSG_WARN([Linux capabilities library (libcap) not found])])

dnl libvirt (highly recommended)
AC_ARG_WITH([libvirt],[
    AS_HELP_STRING([--without-libvirt],
                   [disable libvirt support @<:@default=check@:>@])],
    [],
    [with_libvirt=check])
AS_IF([test "$with_libvirt" != "no"],[
    PKG_CHECK_MODULES([LIBVIRT], [libvirt],[
        AC_SUBST([LIBVIRT_CFLAGS])
        AC_SUBST([LIBVIRT_LIBS])
        AC_DEFINE([HAVE_LIBVIRT],[1],[libvirt found at compile time.])
    ],
    [AC_MSG_WARN([libvirt not found, some core features will be disabled])])
])
AM_CONDITIONAL([HAVE_LIBVIRT],[test "x$LIBVIRT_LIBS" != "x"])

libvirt_ro_uri='qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro'
AC_SUBST([libvirt_ro_uri])

dnl libxml2 (highly recommended)
PKG_CHECK_MODULES([LIBXML2], [libxml-2.0],[
    AC_SUBST([LIBXML2_CFLAGS])
    AC_SUBST([LIBXML2_LIBS])
    AC_DEFINE([HAVE_LIBXML2],[1],[libxml2 found at compile time.])
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBXML2_LIBS"
    AC_CHECK_FUNCS([xmlBufferDetach])
    LIBS="$old_LIBS"
],
    [AC_MSG_WARN([libxml2 not found, some core features will be disabled])])
AM_CONDITIONAL([HAVE_LIBXML2],[test "x$LIBXML2_LIBS" != "x"])

dnl libconfig (highly recommended)
PKG_CHECK_MODULES([LIBCONFIG], [libconfig],[
    AC_SUBST([LIBCONFIG_CFLAGS])
    AC_SUBST([LIBCONFIG_LIBS])
    AC_DEFINE([HAVE_LIBCONFIG],[1],[libconfig found at compile time.])
],
    [AC_MSG_WARN([libconfig not found, some features will be disabled])])
AM_CONDITIONAL([HAVE_LIBCONFIG],[test "x$LIBCONFIG_LIBS" != "x"])

dnl hivex library (highly recommended)
dnl This used to be a part of libguestfs, but was spun off into its
dnl own separate upstream project in libguestfs 1.0.85.
PKG_CHECK_MODULES([HIVEX], [hivex],[
    AC_SUBST([HIVEX_CFLAGS])
    AC_SUBST([HIVEX_LIBS])
    AC_DEFINE([HAVE_HIVEX],[1],[hivex library found at compile time.])
],
    [AC_MSG_WARN([hivex not found, some core features will be disabled])])
AM_CONDITIONAL([HAVE_HIVEX],[test "x$HIVEX_LIBS" != "x"])

dnl FUSE is optional to build the FUSE module.
AC_ARG_ENABLE([fuse],
    AS_HELP_STRING([--disable-fuse], [disable FUSE (guestmount) support]),
    [],
    [enable_fuse=yes])
AS_IF([test "x$enable_fuse" != "xno"],[
    PKG_CHECK_MODULES([FUSE],[fuse],[
        AC_SUBST([FUSE_CFLAGS])
        AC_SUBST([FUSE_LIBS])
        AC_DEFINE([HAVE_FUSE],[1],[Define to 1 if you have FUSE.])
        old_LIBS="$LIBS"
        LIBS="$FUSE_LIBS $LIBS"
        AC_CHECK_FUNCS([fuse_opt_add_opt_escaped])
        LIBS="$old_LIBS"
    ],[
        enable_fuse=no
        AC_MSG_WARN([FUSE library and headers are missing, so optional FUSE module won't be built])
    ])
])
AM_CONDITIONAL([HAVE_FUSE],[test "x$enable_fuse" != "xno"])

dnl Check for yajl JSON library (optional).
PKG_CHECK_MODULES([YAJL], [yajl >= 2], [
    AC_SUBST([YAJL_CFLAGS])
    AC_SUBST([YAJL_LIBS])
    AC_DEFINE([HAVE_YAJL],[1],[Define to 1 if you have yajl.])
],[AC_MSG_WARN([yajl not found, some features will be disabled])])

dnl Check for C++ (optional, we just use this to test the header works).
AC_PROG_CXX

dnl The C++ compiler test is pretty useless because even if it fails
dnl it sets CXX=g++.  So test the compiler actually works.
AC_MSG_CHECKING([if the C++ compiler really really works])
AS_IF([$CXX --version >&AS_MESSAGE_LOG_FD 2>&1],[have_cxx=yes],[have_cxx=no])
AC_MSG_RESULT([$have_cxx])
AM_CONDITIONAL([HAVE_CXX], [test "$have_cxx" = "yes"])

dnl If valgrind is present (it's not required), check whether or not
dnl it supports the new 'valgrind --vgdb' option.
AC_CHECK_PROG([VALGRIND],[valgrind],[valgrind],[no])
AS_IF([test "x$VALGRIND" != "xno"],[
    AC_MSG_CHECKING([if $VALGRIND supports the --vgdb option])
    if $VALGRIND --help | grep -sq -- --vgdb; then
        AC_MSG_RESULT([yes])
        AC_SUBST([VALGRIND_NO_VGDB],[--vgdb=no])
    else
        AC_MSG_RESULT([no])
        AC_SUBST([VALGRIND_NO_VGDB],[])
    fi

    # Substitute the whole valgrind command.
    VG='$(VALGRIND) $(VALGRIND_NO_VGDB) --log-file=$(abs_top_builddir)/tmp/valgrind-%q{T}-%p.log --leak-check=full --error-exitcode=119 --suppressions=$(abs_top_srcdir)/valgrind-suppressions'
    ],[
    # No valgrind, so substitute VG with something that will break.
    VG=VALGRIND_IS_NOT_INSTALLED
])
AC_SUBST([VG])
AM_SUBST_NOTMAKE([VG])

dnl Enable profiling?
AC_ARG_ENABLE([code-profiling],
    AS_HELP_STRING([--enable-code-profiling], [enable code profiling]),
    [],
    [enable_code_profiling=no])
AS_IF([test "x$enable_code_profiling" != "xno"],[
    GPROF_CFLAGS="-pg"
    AC_SUBST([GPROF_CFLAGS])
])

dnl Enable code coverage?
AC_ARG_ENABLE([code-coverage],
    AS_HELP_STRING([--enable-code-coverage], [enable code coverage]),
    [],
    [enable_code_coverage=no])
AS_IF([test "x$enable_code_coverage" != "xno"],[
    GCOV_CFLAGS="-fprofile-arcs -ftest-coverage"
    AC_SUBST([GCOV_CFLAGS])
    dnl This is a hack to make OCaml programs work when they
    dnl link to C code that is compiled with gcov flags.
    OCAML_GCOV_LDFLAGS="-cclib -lgcov"
    AC_SUBST([OCAML_GCOV_LDFLAGS])
])

dnl Check for OCaml (optional, for OCaml bindings and OCaml tools).
OCAMLC=no
OCAMLFIND=no
AC_ARG_ENABLE([ocaml],
    AS_HELP_STRING([--disable-ocaml], [disable OCaml language bindings]),
    [],
    [enable_ocaml=yes])
AS_IF([test "x$enable_ocaml" != "xno"],[
    dnl OCAMLC and OCAMLFIND have to be unset first, otherwise
    dnl AC_CHECK_TOOL (inside AC_PROG_OCAML) will not look.
    OCAMLC=
    OCAMLFIND=
    AC_PROG_OCAML
    AC_PROG_FINDLIB
])
AM_CONDITIONAL([HAVE_OCAML],
               [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLDOC],
               [test "x$OCAMLDOC" != "xno"])

OCAML_PKG_gettext=no
AS_IF([test "x$OCAMLC" != "xno"],[
    dnl Check for ocaml-gettext package to translate OCaml tools.
    AC_CHECK_OCAML_PKG(gettext)

    dnl Write a common gettext module used by each OCaml tool.
    dnl If OCaml gettext is not available then we write dummy functions.
    AC_MSG_NOTICE([creating mllib/common_gettext.ml])
    rm -f mllib/common_gettext.ml
    # If we're building in a different directory, then 'mllib/' might
    # not exist yet, so create it:
    mkdir -p mllib

    cat <<EOF > mllib/common_gettext.ml
(* This file is generated automatically by ./configure. *)

(** Gettext functions for OCaml virt tools.

    The Common_gettext module provides gettext functions, or dummy
    functions if ocaml-gettext was not available at configure time.

    {b Note}: Don't translate debug strings, or strings which are
    meant to be read/written only by machine.

    There are two ways to translate constant strings in OCaml programs.

    For ordinary strings, replace [["string"]] with [[s_"string"]].  Since
    this is a function call to a function called [[s_]], you may have
    to put parentheses around the expression.

    For format strings, use:

{v
  printf (f_"zeroing filesystem %s") filename;
v}

    Note for format strings, the parentheses are almost always required,
    and they just go around the [[(f_"string")]], {i not} around the other
    arguments of the printf function.

    At build time, a program parses the OCaml code into an abstract
    syntax tree and statically determines all calls to the special
    [[s_]] and [[f_]] functions, which means: (a) You can be very loose
    with syntax, unlike ordinary xgettext, but (b) you cannot rename
    these functions.
*)

EOF

    if test "x$OCAML_PKG_gettext" != "xno"; then
        # ocaml-gettext available: real module.
        cat <<EOF >>mllib/common_gettext.ml
module Gettext = Gettext.Program (
  struct
    let textdomain = "$PACKAGE_NAME"
    let codeset = None
    let dir = None
    let dependencies = [[]]
  end
) (GettextStub.Native)
EOF
    else
        # No gettext: module containing dummy gettext functions.
        cat <<EOF >>mllib/common_gettext.ml
module Gettext = struct
  external s_ : string -> string = "%identity"
  external f_ : ('a, 'b, 'c, 'd, 'e, 'f) format6
    -> ('a, 'b, 'c, 'd, 'e, 'f) format6
    = "%identity"
  let sn_ : string -> string -> int -> string
    = fun s p n -> if n = 1 then s else p
  let fn_ : ('a, 'b, 'c, 'd, 'e, 'f) format6
    -> ('a, 'b, 'c, 'd, 'e, 'f) format6
    -> int -> ('a, 'b, 'c, 'd, 'e, 'f) format6
    = fun s p n -> if n = 1 then s else p
end
EOF
    fi

    chmod -w mllib/common_gettext.ml
])
AM_CONDITIONAL([HAVE_OCAML_PKG_GETTEXT],
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_gettext" != "xno"])

AC_CHECK_PROG([OCAML_GETTEXT],[ocaml-gettext],[ocaml-gettext],[no])
AM_CONDITIONAL([HAVE_OCAML_GETTEXT],
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_gettext" != "xno" && test "x$OCAML_GETTEXT" != "xno"])

dnl Check for Perl (optional, for Perl bindings and Perl tools).
AC_ARG_ENABLE([perl],
    AS_HELP_STRING([--disable-perl], [disable Perl language bindings]),
    [],
    [enable_perl=yes])
AS_IF([test "x$enable_perl" != "xno"],[
    dnl Check for Perl modules that must be present to compile and
    dnl test the Perl bindings.
    missing_perl_modules=no
    for pm in Test::More ExtUtils::MakeMaker; do
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

dnl Check for Python (optional, for Python bindings).
PYTHON_PREFIX=
PYTHON_VERSION=
PYTHON_INCLUDEDIR=
PYTHON_INSTALLDIR=

AC_ARG_ENABLE([python],
    AS_HELP_STRING([--disable-python], [disable Python language bindings]),
    [],
    [enable_python=yes])
AS_IF([test "x$enable_python" != "xno"],[
    AC_CHECK_PROG([PYTHON],[python],[python],[no])

    if test "x$PYTHON" != "xno"; then
        AC_MSG_CHECKING([Python prefix])
        PYTHON_PREFIX=`$PYTHON -c "import sys; print (sys.prefix)"`
        AC_MSG_RESULT([$PYTHON_PREFIX])

	AC_MSG_CHECKING([Python version])
        PYTHON_VERSION_MAJOR=`$PYTHON -c "import sys; print (sys.version_info@<:@0@:>@)"`
        PYTHON_VERSION_MINOR=`$PYTHON -c "import sys; print (sys.version_info@<:@1@:>@)"`
        PYTHON_VERSION="$PYTHON_VERSION_MAJOR.$PYTHON_VERSION_MINOR"
	AC_MSG_RESULT([$PYTHON_VERSION])

        AC_MSG_CHECKING([for Python include path])
        if test -z "$PYTHON_INCLUDEDIR"; then
            python_path=`$PYTHON -c "import distutils.sysconfig; \
                                     print (distutils.sysconfig.get_python_inc ());"`
            PYTHON_INCLUDEDIR=$python_path
        fi
        AC_MSG_RESULT([$PYTHON_INCLUDEDIR])

        AC_ARG_WITH([python-installdir],
                    [AS_HELP_STRING([--with-python-installdir],
	                [directory to install python modules @<:@default=check@:>@])],
			[PYTHON_INSTALLDIR="$withval"
	                 AC_MSG_NOTICE([Python install dir $PYTHON_INSTALLDIR])],
			[PYTHON_INSTALLDIR=check])

        if test "x$PYTHON_INSTALLDIR" = "xcheck"; then
	    PYTHON_INSTALLDIR=
            AC_MSG_CHECKING([for Python site-packages path])
            if test -z "$PYTHON_INSTALLDIR"; then
                PYTHON_INSTALLDIR=`$PYTHON -c "import distutils.sysconfig; \
                                               print (distutils.sysconfig.get_python_lib(1,0));"`
            fi
            AC_MSG_RESULT([$PYTHON_INSTALLDIR])
        fi

        AC_MSG_CHECKING([for Python extension suffix (PEP-3149)])
        if test -z "$PYTHON_EXT_SUFFIX"; then
            python_ext_suffix=`$PYTHON -c "import distutils.sysconfig; \
                                         print (distutils.sysconfig.get_config_var('EXT_SUFFIX') or distutils.sysconfig.get_config_var('SO'))"`
            PYTHON_EXT_SUFFIX=$python_ext_suffix
        fi
        AC_MSG_RESULT([$PYTHON_EXT_SUFFIX])

        dnl Look for some optional symbols in libpython.
        old_LIBS="$LIBS"

        PYTHON_BLDLIBRARY=`$PYTHON -c "import distutils.sysconfig; \
                                       print (distutils.sysconfig.get_config_var('BLDLIBRARY'))"`
        AC_CHECK_LIB([c],[PyCapsule_New],
                     [AC_DEFINE([HAVE_PYCAPSULE_NEW],1,
                                [Found PyCapsule_New in libpython.])],
                     [],[$PYTHON_BLDLIBRARY])
        AC_CHECK_LIB([c],[PyString_AsString],
                     [AC_DEFINE([HAVE_PYSTRING_ASSTRING],1,
                                [Found PyString_AsString in libpython.])],
                     [],[$PYTHON_BLDLIBRARY])

        LIBS="$old_LIBS"
    fi

    AC_SUBST(PYTHON_PREFIX)
    AC_SUBST(PYTHON_VERSION)
    AC_SUBST(PYTHON_INCLUDEDIR)
    AC_SUBST(PYTHON_INSTALLDIR)
    AC_SUBST(PYTHON_EXT_SUFFIX)
])
AM_CONDITIONAL([HAVE_PYTHON],
    [test "x$PYTHON" != "xno" && test "x$PYTHON_INCLUDEDIR" != "x" && test "x$PYTHON_INSTALLDIR" != "x"])

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
            AC_MSG_RESULT([-l$libruby])
            AC_CHECK_LIB([$libruby],[ruby_init],
                         [have_libruby=1],[have_libruby=])
        ],[
            AC_MSG_RESULT([not found])
        ])
    ])
])
AM_CONDITIONAL([HAVE_RUBY],
    [test -n "$RUBY" && test -n "$RAKE" && test -n "$have_libruby"])

dnl Check for Java.
AC_ARG_WITH(java,
    [AS_HELP_STRING([--with-java],
        [specify path to JDK directory (for the Java language bindings) @<:@default=check@:>@])],
    [],
    [with_java=check])

if test "x$with_java" != "xno"; then
    if test "x$with_java" != "xyes" && test "x$with_java" != "xcheck"
    then
        # Reject unsafe characters in $JAVA
        jh_lf='
'
        case $JAVA in
          *[\\\"\#\$\&\'\`$jh_lf\ \	]*)
            AC_MSG_FAILURE([unsafe \$JAVA directory (use --without-java to disable Java support)]);;
        esac
        if test -d "$with_java"; then
            JAVA="$with_java"
        else
            AC_MSG_FAILURE([$with_java is not a directory (use --without-java to disable Java support)])
        fi
    fi

    if test "x$JAVA" = "x"; then
        # Look for Java in some likely locations.
        for d in \
            /usr/lib/jvm/java \
            /usr/lib/jvm/java-6-openjdk
        do
            if test -d $d && test -f $d/bin/java; then
                JAVA=$d
                break
            fi
        done
    fi

    if test "x$JAVA" != "x"; then
        AC_MSG_CHECKING(for JDK in $JAVA)
        if test ! -x "$JAVA/bin/java"; then
            AC_MSG_ERROR([missing $JAVA/bin/java binary (use --without-java to disable Java support)])
        else
            JAVA_EXE="$JAVA/bin/java"
        fi
        if test ! -x "$JAVA/bin/javac"; then
            AC_MSG_ERROR([missing $JAVA/bin/javac binary])
        else
            JAVAC="$JAVA/bin/javac"
        fi
        if test ! -x "$JAVA/bin/javah"; then
            AC_MSG_ERROR([missing $JAVA/bin/javah binary])
        else
            JAVAH="$JAVA/bin/javah"
        fi
        if test ! -x "$JAVA/bin/javadoc"; then
            AC_MSG_ERROR([missing $JAVA/bin/javadoc binary])
        else
            JAVADOC="$JAVA/bin/javadoc"
        fi
        if test ! -x "$JAVA/bin/jar"; then
            AC_MSG_ERROR([missing $JAVA/bin/jar binary])
        else
            JAR="$JAVA/bin/jar"
        fi
        java_version=`$JAVA_EXE -version 2>&1 | grep "java version"`
        AC_MSG_RESULT(found $java_version in $JAVA)

        dnl Find jni.h.
        AC_MSG_CHECKING([for jni.h])
        if test -f "$JAVA/include/jni.h"; then
            JNI_CFLAGS="-I$JAVA/include"
        else
            if test "`find $JAVA -name jni.h`" != ""; then
                head=`find $JAVA -name jni.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="-I$dir"
            else
                AC_MSG_FAILURE([missing jni.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Find jni_md.h.
        AC_MSG_CHECKING([for jni_md.h])
        case "$build_os" in
        *linux*) system="linux" ;;
        *SunOS*) system="solaris" ;;
        *cygwin*) system="win32" ;;
        *) system="$build_os" ;;
        esac
        if test -f "$JAVA/include/$system/jni_md.h"; then
            JNI_CFLAGS="$JNI_CFLAGS -I$JAVA/include/$system"
        else
            if test "`find $JAVA -name jni_md.h`" != ""; then
                head=`find $JAVA -name jni_md.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="$JNI_CFLAGS -I$dir"
            else
                AC_MSG_FAILURE([missing jni_md.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Need extra version flag?
        AC_MSG_CHECKING([extra javac flags])
        EXTRA_JAVAC_FLAGS=
        javac_version=`$JAVAC -version 2>&1`
        case "$javac_version" in
        *Eclipse*)
            EXTRA_JAVAC_FLAGS="-source 1.5" ;;
        esac
        AC_MSG_RESULT([$EXTRA_JAVAC_FLAGS])

        dnl Extra lint flags?
        AC_MSG_CHECKING([extra javac lint flags])
        if $JAVAC -X >/dev/null 2>&1 && \
           $JAVAC -X 2>&1 | grep -q -- '-Xlint:.*all'; then
            AC_MSG_RESULT([-Xlint:all])
            EXTRA_JAVAC_FLAGS="$EXTRA_JAVAC_FLAGS -Xlint:all"
        else
            AC_MSG_RESULT([no])
        fi

        dnl Where to install jarfiles, jnifiles
        if test -z $JAR_INSTALL_DIR; then
            JAR_INSTALL_DIR=\${prefix}/share/java
        fi
        if test -z $JNI_INSTALL_DIR; then
            JNI_INSTALL_DIR=\${libdir}
        fi

        dnl JNI version.
        jni_major_version=`echo "$VERSION" | awk -F. '{print $1}'`
        jni_minor_version=`echo "$VERSION" | awk -F. '{print $2}'`
        jni_micro_version=`echo "$VERSION" | awk -F. '{print $3}'`
        JNI_VERSION_INFO=`expr "$jni_major_version" + "$jni_minor_version"`":$jni_micro_version:$jni_minor_version"
    fi

    AC_SUBST(JAVA)
    AC_SUBST(JAVA_EXE)
    AC_SUBST(JAVAC)
    AC_SUBST(JAVAH)
    AC_SUBST(JAVADOC)
    AC_SUBST(JAR)
    AC_SUBST(JNI_CFLAGS)
    AC_SUBST(EXTRA_JAVAC_FLAGS)
    AC_SUBST(JAR_INSTALL_DIR)
    AC_SUBST(JNI_INSTALL_DIR)
    AC_SUBST(JNI_VERSION_INFO)
fi

AM_CONDITIONAL([HAVE_JAVA],[test "x$with_java" != "xno" && test -n "$JAVAC"])

dnl Check for Haskell (GHC).
GHC=no
AC_ARG_ENABLE([haskell],
    AS_HELP_STRING([--disable-haskell], [disable Haskell language bindings]),
    [],
    [enable_haskell=yes])
AS_IF([test "x$enable_haskell" != "xno"],[
    GHC=
    AC_CHECK_PROG([GHC],[ghc],[ghc],[no])
])
AM_CONDITIONAL([HAVE_HASKELL],[test "x$GHC" != "xno"])

dnl PHP
PHP=no
AC_ARG_ENABLE([php],
    AS_HELP_STRING([--disable-php], [disable PHP language bindings]),
    [],
    [enable_php=yes])
AS_IF([test "x$enable_php" != "xno"],[
    PHP=
    AC_CHECK_PROG([PHP],[php],[php],[no])
    AC_CHECK_PROG([PHPIZE],[phpize],[phpize],[no])
])
AM_CONDITIONAL([HAVE_PHP], [test "x$PHP" != "xno" && test "x$PHPIZE" != "xno"])

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

dnl Lua
AC_ARG_ENABLE([lua],
    AS_HELP_STRING([--disable-lua], [disable Lua language bindings]),
        [],
        [enable_lua=yes])
AS_IF([test "x$enable_lua" != "xno"],[
    AC_CHECK_PROG([LUA],[lua],[lua],[no])
    AS_IF([test "x$LUA" != "xno"],[
        AC_MSG_CHECKING([for Lua version])
        LUA_VERSION=`$LUA -e 'print(_VERSION)' | awk '{print $2}'`
        AC_MSG_RESULT([$LUA_VERSION])
        dnl On Debian it's 'lua5.1', 'lua5.2' etc.  On Fedora, just 'lua'.
        PKG_CHECK_MODULES([LUA], [lua$LUA_VERSION],[
            AC_SUBST([LUA_CFLAGS])
            AC_SUBST([LUA_LIBS])
            AC_SUBST([LUA_VERSION])
            AC_DEFINE([HAVE_LUA],[1],[Lua library found at compile time])
        ],[
            PKG_CHECK_MODULES([LUA], [lua],[
                AC_SUBST([LUA_CFLAGS])
                AC_SUBST([LUA_LIBS])
                AC_SUBST([LUA_VERSION])
                AC_DEFINE([HAVE_LUA],[1],[Lua library found at compile time])
            ],[
                AC_MSG_WARN([lua $LUA_VERSION not found])
            ])
        ])
    ])
])
AM_CONDITIONAL([HAVE_LUA],[test "x$LUA_LIBS" != "x"])

dnl Check for Perl modules needed by Perl virt tools (virt-df, etc.)
AS_IF([test "x$PERL" != "xno"],[
    missing_perl_modules=no
    for pm in Pod::Usage Getopt::Long Sys::Virt Data::Dumper Locale::TextDomain Win::Hivex Win::Hivex::Regedit; do
        AC_MSG_CHECKING([for $pm])
        if ! $PERL -M$pm -e1 >&AS_MESSAGE_LOG_FD 2>&1; then
            AC_MSG_RESULT([no])
            missing_perl_modules=yes
        else
            AC_MSG_RESULT([yes])
        fi
    done
    if test "x$missing_perl_modules" = "xyes"; then
        AC_MSG_WARN([some Perl modules required to compile the Perl virt-* tools are missing])
    fi
])

AM_CONDITIONAL([HAVE_TOOLS],
    [test "x$PERL" != "xno" && test "x$missing_perl_modules" != "xyes"])

dnl gobject library
AC_ARG_ENABLE([gobject],
    AS_HELP_STRING([--disable-gobject], [disable GObject bindings]),
    [],
    [enable_gobject=yes])
AS_IF([test "x$enable_gobject" != "xno"],[
    PKG_CHECK_MODULES([GOBJECT], [gobject-2.0 >= 2.26.0],[
        AC_SUBST([GOBJECT_CFLAGS])
        AC_SUBST([GOBJECT_LIBS])
        AC_DEFINE([HAVE_GOBJECT],[1],
                  [GObject library found at compile time.])
    ],
    [AC_MSG_WARN([gobject library not found, gobject binding will be disabled])])

    PKG_CHECK_MODULES([GIO], [gio-2.0 >= 2.26.0],[
        AC_SUBST([GIO_CFLAGS])
        AC_SUBST([GIO_LIBS])
        AC_DEFINE([HAVE_GIO],[1],
                  [gio library found at compile time.])
    ],
    [AC_MSG_WARN([gio library not found, gobject binding will be disabled])])
])
AM_CONDITIONAL([HAVE_GOBJECT],
               [test "x$GOBJECT_LIBS" != "x" -a "x$GIO_LIBS" != "x"])

AC_CHECK_PROG([GJS],[gjs],[gjs])
AS_IF([test "x$GJS" = "x"],
      [AC_MSG_WARN([gjs not found, gobject bindtests will not run])])

dnl gobject introspection
m4_ifdef([GOBJECT_INTROSPECTION_CHECK], [
    GOBJECT_INTROSPECTION_CHECK([1.30.0])

    dnl The above check automatically sets HAVE_INTROSPECTION, but we
    dnl want this to be conditional on gobject also being
    dnl available. We can't move the above check inside the gobject if
    dnl block above or HAVE_INTROSPECTION ends up undefined, so we
    dnl recheck it here.
    AM_CONDITIONAL([HAVE_INTROSPECTION],
                   [test "x$HAVE_INTROSPECTION_TRUE" = "x" &&
                    test "x$HAVE_GOBJECT_TRUE" = "x"])
],[
    AM_CONDITIONAL([HAVE_INTROSPECTION], [false])
])

# check for gtk-doc
m4_ifdef([GTK_DOC_CHECK], [
    GTK_DOC_CHECK([1.14],[--flavour no-tmpl])
],[
    AM_CONDITIONAL([ENABLE_GTK_DOC], false)
])

dnl Library versioning.
MAX_PROC_NR=`cat $srcdir/src/MAX_PROC_NR`
AC_SUBST(MAX_PROC_NR)

dnl Replace libtool with a wrapper that clobbers dependency_libs in *.la files
dnl http://lists.fedoraproject.org/pipermail/devel/2010-November/146343.html
LIBTOOL='bash $(top_srcdir)/libtool-kill-dependency_libs.sh $(top_builddir)/libtool'
AC_SUBST([LIBTOOL])

dnl Produce output files.

AC_CONFIG_HEADERS([config.h])

dnl For separated builds, make sure that certain build directories exist.
dnl This avoids having to sprinkle 'mkdir -p' statements throughout
dnl many Makefile.am rules.
mkdir -p \
    appliance/supermin.d \
    java/t \
    ocaml/html \
    ocaml/t \
    tests/guests/guest-aux

dnl http://www.mail-archive.com/automake@gnu.org/msg10204.html
AC_CONFIG_FILES([appliance/libguestfs-make-fixed-appliance],
                [chmod +x,-w appliance/libguestfs-make-fixed-appliance])
AC_CONFIG_FILES([inspector/test-xmllint.sh],
                [chmod +x,-w inspector/test-xmllint.sh])
AC_CONFIG_FILES([pick-guests.pl],
                [chmod +x,-w pick-guests.pl])
AC_CONFIG_FILES([podwrapper.pl],
                [chmod +x,-w podwrapper.pl])
AC_CONFIG_FILES([run],
                [chmod +x,-w run])

AC_CONFIG_FILES([Makefile
                 align/Makefile
                 appliance/Makefile
                 cat/Makefile
                 csharp/Makefile
                 daemon/Makefile
                 df/Makefile
                 edit/Makefile
                 erlang/Makefile
                 erlang/examples/Makefile
                 examples/Makefile
                 fish/Makefile
                 format/Makefile
                 fuse/Makefile
                 generator/Makefile
                 gnulib/lib/Makefile
                 gnulib/tests/Makefile
                 gobject/libguestfs-gobject-1.0.pc
                 gobject/Makefile
                 gobject/docs/Makefile
                 gobject/docs/guestfs-docs.sgml
                 haskell/Makefile
                 inspector/Makefile
                 java/Makefile
                 java/examples/Makefile
                 lua/Makefile
                 lua/examples/Makefile
                 mllib/Makefile
                 mllib/config.ml
                 ocaml/META
                 ocaml/Makefile
                 ocaml/examples/Makefile
                 perl/Makefile
                 perl/Makefile.PL
                 perl/examples/Makefile
                 php/Makefile
                 po-docs/Makefile
                 po-docs/ja/Makefile
                 po-docs/uk/Makefile
                 po/Makefile
                 python/Makefile
                 python/examples/Makefile
                 rescue/Makefile
                 resize/Makefile
                 ruby/Makefile
                 ruby/Rakefile
                 ruby/examples/Makefile
                 ruby/ext/guestfs/extconf.rb
                 sparsify/Makefile
                 src/Makefile
                 src/libguestfs.pc
                 sysprep/Makefile
                 test-tool/Makefile
                 tests/9p/Makefile
                 tests/bigdirs/Makefile
                 tests/btrfs/Makefile
                 tests/c-api/Makefile
                 tests/charsets/Makefile
                 tests/data/Makefile
                 tests/disks/Makefile
                 tests/disk-labels/Makefile
                 tests/guests/Makefile
                 tests/guests/guests.xml
                 tests/hotplug/Makefile
                 tests/luks/Makefile
                 tests/lvm/Makefile
                 tests/md/Makefile
                 tests/mount-local/Makefile
                 tests/ntfsclone/Makefile
                 tests/parallel/Makefile
                 tests/protocol/Makefile
                 tests/qemu/Makefile
                 tests/regressions/Makefile
                 tests/rsync/Makefile
                 tests/selinux/Makefile
                 tests/tmpdirs/Makefile
                 tests/xml/Makefile
                 tools/Makefile])
AC_OUTPUT

dnl Produce summary.
echo
echo
echo "------------------------------------------------------------"
echo "Thank you for downloading $PACKAGE_STRING"
echo
echo "This is how we have configured the optional components for you today:"
echo
echo       "Daemon .............................. $enable_daemon"
echo       "Appliance ........................... $enable_appliance"
echo       "QEMU ................................ $QEMU $QEMU_OPTIONS"
echo       "guestfish and C-based virt tools .... yes"
echo       "FUSE filesystem ..................... $enable_fuse"
AS_ECHO_N(["GNU gettext for i18n ................ "])
if test "x$HAVE_GNU_GETTEXT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["OCaml bindings ...................... "])
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["OCaml-based virt tools .............. "])
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Perl bindings ....................... "])
if test "x$HAVE_PERL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Perl-based virt tools ............... "])
if test "x$HAVE_TOOLS_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Python bindings ..................... "])
if test "x$HAVE_PYTHON_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Ruby bindings ....................... "])
if test "x$HAVE_RUBY_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Java bindings ....................... "])
if test "x$HAVE_JAVA_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Haskell bindings .................... "])
if test "x$HAVE_HASKELL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["PHP bindings ........................ "])
if test "x$HAVE_PHP_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Erlang bindings ..................... "])
if test "x$HAVE_ERLANG_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Lua bindings ........................ "])
if test "x$HAVE_LUA_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject bindings .................... "])
if test "x$HAVE_GOBJECT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject introspection ............... "])
if test "x$HAVE_INTROSPECTION_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo
echo "If any optional component is configured 'no' when you expected 'yes'"
echo "then you should check the preceding messages."
echo
echo "Please report bugs back to the mailing list:"
echo "http://www.redhat.com/mailman/listinfo/libguestfs"
echo
echo "Next you should type 'make' to build the package,"
echo "then 'make check' to run the tests."
echo
echo "Or run 'make help' to list some common targets."
echo "------------------------------------------------------------"
