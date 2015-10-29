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

# NB: AC_CHECK_PROG(S) or AC_PATH_PROG(S)?
# Use AC_CHECK_PROG(S) for programs which are only used during build.
# Use AC_PATH_PROG(S) for program names which are compiled into the
# binary and used at run time.  The reason is so that we know which
# programs the binary actually uses.

# The major, minor, and release fields MUST be numbers.  Packagers can
# add extra information using --with-extra="..." which may be any
# freeform string.
m4_define([libguestfs_major],   [1])
m4_define([libguestfs_minor],   [31])
m4_define([libguestfs_release], [20])

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
AM_INIT_AUTOMAKE(foreign serial_tests subdir-objects) dnl NB: Do not [quote] this parameter.

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
PACKAGE_VERSION_FULL="libguestfs_major.libguestfs_minor.libguestfs_release${libguestfs_extra}"
AC_DEFINE_UNQUOTED([PACKAGE_VERSION_FULL],["$PACKAGE_VERSION_FULL"],[Full version string.])
AC_SUBST([PACKAGE_VERSION_FULL])

# Define $(SED).
m4_ifdef([AC_PROG_SED],[
    AC_PROG_SED
],[
    dnl ... else hope for the best
    AC_SUBST([SED], "sed")
])

# Define $(AWK).
AC_PROG_AWK

dnl Early gnulib initialization.
gl_EARLY
gl_INIT

AC_PROG_LIBTOOL
AC_PROG_LN_S

dnl Define the host CPU architecture (defines 'host_cpu')
AC_CANONICAL_HOST

dnl Check for basic C environment.
AC_PROG_CC_STDC
AC_PROG_INSTALL
AC_PROG_CPP

AC_ARG_ENABLE([werror],
    [AS_HELP_STRING([--enable-werror],
                    [turn GCC warnings into errors (for developers)])],
    [case $enableval in
     yes|no) ;;
     *)      AC_MSG_ERROR([bad value $enableval for werror option]) ;;
     esac
     gl_gcc_werror=$enableval],
    [gl_gcc_werror=no]
)

if test "$gl_gcc_werror" = yes; then
    gl_WARN_ADD([-Werror], [WERROR_CFLAGS])
    AC_SUBST([WERROR_CFLAGS])
fi

dnl This, $nw, is the list of warnings we disable.
nw=
nw="$nw -Waggregate-return"          # anachronistic
nw="$nw -Wc++-compat"                # We don't care about C++ compilers
nw="$nw -Wundef"                     # Warns on '#if GNULIB_FOO' etc in gnulib
nw="$nw -Wtraditional"               # Warns on #elif which we use often
nw="$nw -Wcast-qual"                 # Too many warnings for now
nw="$nw -Wconversion"                # Too many warnings for now
nw="$nw -Wsystem-headers"            # Don't let system headers trigger warnings
nw="$nw -Wsign-conversion"           # Not an error
nw="$nw -Wtraditional-conversion"    # Don't care about pre-ANSI compilers
nw="$nw -Wpadded"                    # Our structs are not padded
nw="$nw -Wvla"                       # two warnings in mount.c
dnl things I might fix soon:
nw="$nw -Wmissing-format-attribute"  # daemon.h's asprintf_nowarn
nw="$nw -Winline"                    # daemon.h's asprintf_nowarn
nw="$nw -Wshadow"                    # numerous, plus we're not unanimous
nw="$nw -Wunsafe-loop-optimizations" # just a warning that an optimization
                                     # was not possible, safe to ignore
nw="$nw -Wpacked"                    # Allow attribute((packed)) on structs
nw="$nw -Wlong-long"                 # Allow long long since it's required
                                     # by Python, Ruby and xstrtoll.
nw="$nw -Wsuggest-attribute=pure"    # Don't suggest pure functions.
nw="$nw -Wsuggest-attribute=const"   # Don't suggest const functions.
nw="$nw -Wunsuffixed-float-constants" # Don't care about these.
nw="$nw -Wswitch-default"            # This warning is actively dangerous.
nw="$nw -Woverlength-strings"        # Who cares about stupid ISO C99 limit.

gl_MANYWARN_ALL_GCC([ws])
gl_MANYWARN_COMPLEMENT([ws], [$ws], [$nw])
for w in $ws; do
    gl_WARN_ADD([$w])
done

dnl Normally we disable warnings in $nw above.  However $nw only
dnl filters out exact matching warning strings from a list inside
dnl gnulib (see m4/manywarnings.m4).  So we need to explicitly list a
dnl few disabled warnings below.

dnl Unused parameters are not a bug.
gl_WARN_ADD([-Wno-unused-parameter])

dnl Missing field initializers is not a bug in C.
gl_WARN_ADD([-Wno-missing-field-initializers])

dnl Display the name of the warning option with the warning.
gl_WARN_ADD([-fdiagnostics-show-option])

dnl Now some warnings we want to enable and/or customize ...

dnl Warn about large stack allocations.  10000 happens to be the
dnl same size as Coverity warns about.
gl_WARN_ADD([-Wframe-larger-than=10000])

AC_SUBST([WARN_CFLAGS])

AC_DEFINE([lint], [1], [Define to 1 if the compiler is checking for lint.])
AC_DEFINE([GNULIB_PORTCHECK], [1], [Enable some gnulib portability checks.])
AH_VERBATIM([FORTIFY_SOURCE],[
/* Enable compile-time and run-time bounds-checking, and some warnings. */
#if __OPTIMIZE__ && (! defined (_FORTIFY_SOURCE) || _FORTIFY_SOURCE < 2)
# undef _FORTIFY_SOURCE
# define _FORTIFY_SOURCE 2
#endif])

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

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
AC_CHECK_MEMBER([struct stat.st_atim.tv_nsec],[
    AC_DEFINE([HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC],[1],[Define to 1 if 'st_mtim.tv_nsec' is a member of 'struct stat'.])])
AC_CHECK_MEMBER([struct stat.st_mtim.tv_nsec],[
    AC_DEFINE([HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC],[1],[Define to 1 if 'st_mtim.tv_nsec' is a member of 'struct stat'.])])
AC_CHECK_MEMBER([struct stat.st_ctim.tv_nsec],[
    AC_DEFINE([HAVE_STRUCT_STAT_ST_CTIM_TV_NSEC],[1],[Define to 1 if 'st_mtim.tv_nsec' is a member of 'struct stat'.])])

dnl Define a C symbol for the host CPU architecture.
AC_DEFINE_UNQUOTED([host_cpu],["$host_cpu"],[Host architecture.])

dnl Check if libc has program_invocation_short_name.
AC_CHECK_DECLS([program_invocation_short_name], [], [], [#include <errno.h>])

dnl Headers.
AC_CHECK_HEADERS([\
    attr/xattr.h \
    byteswap.h \
    endian.h \
    sys/endian.h \
    errno.h \
    linux/fs.h \
    linux/raid/md_u.h \
    printf.h \
    sys/inotify.h \
    sys/resource.h \
    sys/socket.h \
    sys/statvfs.h \
    sys/time.h \
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
    getprogname \
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
    removexattr \
    setitimer \
    setrlimit \
    setxattr \
    sigaction \
    statvfs \
    sync])

dnl Check for UNIX_PATH_MAX, creating a custom one if not available.
AC_MSG_CHECKING([for UNIX_PATH_MAX])
AC_COMPILE_IFELSE([
  AC_LANG_PROGRAM([[
#include <sys/un.h>
  ]], [[
#ifndef UNIX_PATH_MAX
#error UNIX_PATH_MAX not defined
#endif
  ]])], [
    AC_MSG_RESULT([yes])
  ], [
    AC_MSG_RESULT([no])
    AC_MSG_CHECKING([for size of sockaddr_un.sun_path])
    AC_COMPUTE_INT(unix_path_max, [sizeof (myaddr.sun_path)], [
#include <sys/un.h>
struct sockaddr_un myaddr;
      ], [
        AC_MSG_ERROR([cannot get it])
      ])
    AC_MSG_RESULT([$unix_path_max])
    AC_DEFINE_UNQUOTED([UNIX_PATH_MAX], $unix_path_max, [Custom value for UNIX_PATH_MAX])
  ])

dnl tgetent, tputs and UP [sic] are all required.  They come from the lower
dnl tinfo library, but might be part of ncurses directly.
PKG_CHECK_MODULES([LIBTINFO], [tinfo], [], [
    PKG_CHECK_MODULES([LIBTINFO], [ncurses])
])
AC_SUBST([LIBTINFO_CFLAGS])
AC_SUBST([LIBTINFO_LIBS])

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

dnl Check for gettext.
AM_GNU_GETTEXT([external])

dnl Default backend.
AC_MSG_CHECKING([if the user specified a default backend])
AC_ARG_WITH([default-backend],
    [AS_HELP_STRING([--with-default-backend="direct|libvirt|..."],
        [set default backend @<:@default=direct@:>@])],
    [DEFAULT_BACKEND="$withval"],
    [DEFAULT_BACKEND=direct])
AC_MSG_RESULT([$DEFAULT_BACKEND])
AC_DEFINE_UNQUOTED([DEFAULT_BACKEND],["$DEFAULT_BACKEND"],
                   [Default backend.])

dnl Fail with error if user does --with-default-attach-method.
AC_ARG_WITH([default-attach-method],
    [AS_HELP_STRING([--with-default-attach-method="..."],
        [use --with-default-backend instead])],
    [AC_MSG_FAILURE([--with-default-attach-method no longer works in
this version of libguestfs, use
  ./configure --with-default-backend=$withval
instead.])])

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

dnl Build the appliance?
AC_MSG_CHECKING([if we should build the appliance])
AC_ARG_ENABLE([appliance],
    [AS_HELP_STRING([--enable-appliance],
        [enable building the appliance @<:@default=yes@:>@])],
        [ENABLE_APPLIANCE="$enableval"],
        [ENABLE_APPLIANCE=yes])
AM_CONDITIONAL([ENABLE_APPLIANCE],[test "x$ENABLE_APPLIANCE" = "xyes"])
AC_MSG_RESULT([$ENABLE_APPLIANCE])
AC_SUBST([ENABLE_APPLIANCE])

if test "x$enable_daemon" != "xyes" && test "x$ENABLE_APPLIANCE" = "xyes" ; then
    AC_MSG_FAILURE([conflicting ./configure arguments: if you --disable-daemon
then you have to --disable-appliance as well, since the appliance contains
the daemon inside it.])
fi

dnl Check for supermin >= 5.1.0.
AC_PATH_PROG([SUPERMIN],[supermin],[no])

dnl Pass supermin --packager-config option.
SUPERMIN_PACKAGER_CONFIG=no

AC_MSG_CHECKING([for --with-supermin-packager-config option])
AC_ARG_WITH([supermin-packager-config],
    [AS_HELP_STRING([--with-supermin-packager-config=FILE],
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

if test "x$ENABLE_APPLIANCE" = "xyes"; then
    supermin_major_min=5
    supermin_minor_min=1
    supermin_min=$supermin_major_min.$supermin_minor_min

    test "x$SUPERMIN" = "xno" &&
        AC_MSG_ERROR([supermin >= $supermin_min must be installed])

    AC_MSG_CHECKING([supermin is new enough])
    $SUPERMIN --version >&AS_MESSAGE_LOG_FD 2>&1 ||
        AC_MSG_ERROR([supermin >= $supermin_min must be installed, your version is too old])
    supermin_major="`$SUPERMIN --version | $AWK '{print $2}' | $AWK -F. '{print $1}'`"
    supermin_minor="`$SUPERMIN --version | $AWK '{print $2}' | $AWK -F. '{print $2}'`"
    AC_MSG_RESULT([$supermin_major.$supermin_minor])

    if test "$supermin_major" -lt "$supermin_major_min" || \
       ( test "$supermin_major" -eq "$supermin_major_min" && test "$supermin_minor" -lt "$supermin_minor_min" ); then
        AC_MSG_ERROR([supermin >= $supermin_min must be installed, your version is too old])
    fi
fi

AC_DEFINE_UNQUOTED([SUPERMIN],["$SUPERMIN"],[Name of supermin program])

dnl Which distro?
dnl
dnl This used to be Very Important but is now just used to select
dnl which packages to install in the appliance, since the package
dnl names vary slightly across distros.  (See
dnl appliance/packagelist.in, appliance/excludefiles.in,
dnl appliance/hostfiles.in)
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
if test -f /etc/SuSE-release; then
    DISTRO=SUSE
fi
if test -f /etc/frugalware-release; then
    DISTRO=FRUGALWARE
fi
if test -f /etc/mageia-release; then
    DISTRO=MAGEIA
fi
AC_MSG_RESULT([$DISTRO])
AC_SUBST([DISTRO])

dnl Add extra packages to the appliance.
AC_ARG_WITH([extra-packages],
    [AS_HELP_STRING([--with-extra-packages="pkg1 pkg2 ..."],
                    [add extra packages to the appliance])],
    [EXTRA_PACKAGES="$withval"],
    [EXTRA_PACKAGES=])
AC_SUBST([EXTRA_PACKAGES])

dnl Check if crypt() is provided by a separate library.
old_LIBS="$LIBS"
AC_SEARCH_LIBS([crypt],[crypt])
LIBS="$old_LIBS"
if test "$ac_cv_search_crypt" = "-lcrypt" ; then
  LIBCRYPT_LIBS="-lcrypt"
fi
AC_SUBST([LIBCRYPT_LIBS])

dnl Check for libdl/dlopen (optional - only used to test if the library
dnl can be used with libdl).
AC_CHECK_LIB([dl],[dlopen],[have_libdl=yes],[have_libdl=no])
AC_CHECK_HEADERS([dlfcn.h],[have_dlfcn=yes],[have_dlfcn=no])
AM_CONDITIONAL([HAVE_LIBDL],
               [test "x$have_libdl" = "xyes" && test "x$have_dlfcn" = "xyes"])

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
    SELINUX_LIBS="-lselinux"

    old_LIBS="$LIBS"
    LIBS="$LIBS $SELINUX_LIBS"
    AC_CHECK_FUNCS([setcon getcon])
    LIBS="$old_LIBS"
],[have_libselinux=no])
if test "x$have_libselinux" = "xyes"; then
    AC_DEFINE([HAVE_LIBSELINUX],[1],[Define to 1 if you have libselinux.])
fi
AC_SUBST([SELINUX_LIBS])

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

dnl liblzma can be used by virt-builder (optional).
PKG_CHECK_MODULES([LIBLZMA], [liblzma], [
    AC_SUBST([LIBLZMA_CFLAGS])
    AC_SUBST([LIBLZMA_LIBS])
    AC_DEFINE([HAVE_LIBLZMA],[1],[liblzma found at compile time.])

    dnl Old lzma in RHEL 6 didn't have some APIs we need.
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBLZMA_LIBS"
    AC_CHECK_FUNCS([lzma_index_stream_flags lzma_index_stream_padding])
    LIBS="$old_LIBS"
],
[AC_MSG_WARN([liblzma not found, virt-builder will be slower])])

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

dnl Check for QEMU.
m4_include([m4/guestfs_qemu.m4])

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

dnl libxml2 (required)
PKG_CHECK_MODULES([LIBXML2], [libxml-2.0])
old_LIBS="$LIBS"
LIBS="$LIBS $LIBXML2_LIBS"
AC_CHECK_FUNCS([xmlBufferDetach])
LIBS="$old_LIBS"

dnl libconfig (highly recommended)
PKG_CHECK_MODULES([LIBCONFIG], [libconfig],[
    AC_SUBST([LIBCONFIG_CFLAGS])
    AC_SUBST([LIBCONFIG_LIBS])
    AC_DEFINE([HAVE_LIBCONFIG],[1],[libconfig found at compile time.])
],
    [AC_MSG_WARN([libconfig not found, some features will be disabled])])
AM_CONDITIONAL([HAVE_LIBCONFIG],[test "x$LIBCONFIG_LIBS" != "x"])

dnl Check for gtk2 library, used by virt-p2v.
PKG_CHECK_MODULES([GTK2], [gtk+-2.0], [
    AC_SUBST([GTK2_CFLAGS])
    AC_SUBST([GTK2_LIBS])
],
    [AC_MSG_WARN([gtk2 not found, virt-p2v will be disabled])])

dnl Can we build virt-p2v?
AM_CONDITIONAL([HAVE_P2V], [test "x$GTK2_LIBS" != "x"])

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

dnl systemd journal library (optional)
PKG_CHECK_MODULES([SD_JOURNAL], [libsystemd],[
    AC_SUBST([SD_JOURNAL_CFLAGS])
    AC_SUBST([SD_JOURNAL_LIBS])
    AC_DEFINE([HAVE_SD_JOURNAL],[1],[systemd journal library found at compile time.])
],[
    PKG_CHECK_MODULES([SD_JOURNAL], [libsystemd-journal >= 196],[
        AC_SUBST([SD_JOURNAL_CFLAGS])
        AC_SUBST([SD_JOURNAL_LIBS])
        AC_DEFINE([HAVE_SD_JOURNAL],[1],[systemd journal library found at compile time.])
    ],[
        AC_MSG_WARN([systemd journal library not found, some features will be disabled])
    ])
])

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
PKG_CHECK_MODULES([YAJL], [yajl >= 2.0.4], [
    AC_SUBST([YAJL_CFLAGS])
    AC_SUBST([YAJL_LIBS])
    AC_DEFINE([HAVE_YAJL],[1],[Define to 1 if you have yajl.])
],[AC_MSG_WARN([yajl not found, some features will be disabled])])
AM_CONDITIONAL([HAVE_YAJL],[test "x$YAJL_LIBS" != "x"])

dnl Check for C++ (optional, we just use this to test the header works).
AC_PROG_CXX

dnl The C++ compiler test is pretty useless because even if it fails
dnl it sets CXX=g++.  So test the compiler actually works.
AC_MSG_CHECKING([if the C++ compiler really really works])
AS_IF([$CXX --version >&AS_MESSAGE_LOG_FD 2>&1],[have_cxx=yes],[have_cxx=no])
AC_MSG_RESULT([$have_cxx])
AM_CONDITIONAL([HAVE_CXX], [test "$have_cxx" = "yes"])

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

dnl Check for language bindings.
m4_include([m4/guestfs_ocaml.m4])
m4_include([m4/guestfs_perl.m4])
m4_include([m4/guestfs_python.m4])
m4_include([m4/guestfs_ruby.m4])
m4_include([m4/guestfs_java.m4])
m4_include([m4/guestfs_haskell.m4])
m4_include([m4/guestfs_php.m4])
m4_include([m4/guestfs_erlang.m4])
m4_include([m4/guestfs_lua.m4])
m4_include([m4/guestfs_golang.m4])
m4_include([m4/guestfs_gobject.m4])

dnl Bash completion.
m4_include([m4/guestfs_bash_completion.m4])

dnl For search paths.
AC_DEFINE_UNQUOTED([PATH_SEPARATOR],["$PATH_SEPARATOR"],
                   [Character that separates path elements in search paths])

AC_MSG_CHECKING([if we should run the GNUlib tests])
AC_ARG_ENABLE([gnulib-tests],
    [AS_HELP_STRING([--disable-gnulib-tests],
        [disable running GNU Portability library tests @<:@default=yes@:>@])],
        [ENABLE_GNULIB_TESTS="$enableval"],
        [ENABLE_GNULIB_TESTS=yes])
AM_CONDITIONAL([ENABLE_GNULIB_TESTS],[test "x$ENABLE_GNULIB_TESTS" = "xyes"])
AC_MSG_RESULT([$ENABLE_GNULIB_TESTS])

dnl Library versioning.
MAX_PROC_NR=`cat $srcdir/src/MAX_PROC_NR`
AC_SUBST(MAX_PROC_NR)

dnl Replace libtool with a wrapper that clobbers dependency_libs in *.la files
dnl http://lists.fedoraproject.org/pipermail/devel/2010-November/146343.html
LIBTOOL='bash $(top_srcdir)/libtool-kill-dependency_libs.sh $(top_builddir)/libtool'
AC_SUBST([LIBTOOL])

dnl Work around autoconf's lack of expanded variables.
eval my_sysconfdir="\"[$]sysconfdir\""
eval my_sysconfdir="\"$my_sysconfdir\""
SYSCONFDIR="${my_sysconfdir}"
AC_SUBST(SYSCONFDIR)

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
AC_CONFIG_FILES([installcheck.sh],
                [chmod +x,-w installcheck.sh])
AC_CONFIG_FILES([p2v/virt-p2v-make-disk],
                [chmod +x,-w p2v/virt-p2v-make-disk])
AC_CONFIG_FILES([p2v/virt-p2v-make-kickstart],
                [chmod +x,-w p2v/virt-p2v-make-kickstart])
AC_CONFIG_FILES([php/extension/php-for-tests.sh],
                [chmod +x,-w php/extension/php-for-tests.sh])
AC_CONFIG_FILES([pick-guests.pl],
                [chmod +x,-w pick-guests.pl])
AC_CONFIG_FILES([podwrapper.pl],
                [chmod +x,-w podwrapper.pl])
AC_CONFIG_FILES([run],
                [chmod +x,-w run])

AC_CONFIG_FILES([Makefile
                 align/Makefile
                 appliance/Makefile
                 bash/Makefile
                 builder/Makefile
                 builder/libguestfs.conf
                 builder/opensuse.conf
                 builder/test-config/virt-builder/repos.d/test-index.conf
                 builder/test-simplestreams/virt-builder/repos.d/cirros.conf
                 builder/test-website/virt-builder/repos.d/libguestfs.conf
                 builder/website/Makefile
                 cat/Makefile
                 csharp/Makefile
                 customize/Makefile
                 daemon/Makefile
                 df/Makefile
                 dib/Makefile
                 diff/Makefile
                 docs/Makefile
                 edit/Makefile
                 erlang/Makefile
                 erlang/examples/Makefile
                 examples/Makefile
                 fish/Makefile
                 format/Makefile
                 fuse/Makefile
                 generator/Makefile
                 get-kernel/Makefile
                 gnulib/lib/Makefile
                 gnulib/tests/Makefile
                 gobject/libguestfs-gobject-1.0.pc
                 gobject/Makefile
                 gobject/docs/Makefile
                 gobject/docs/guestfs-docs.sgml
                 golang/Makefile
                 golang/examples/Makefile
                 haskell/Makefile
                 inspector/Makefile
                 java/Makefile
                 java/examples/Makefile
                 lua/Makefile
                 lua/examples/Makefile
                 make-fs/Makefile
                 mllib/Makefile
                 mllib/config.ml
                 ocaml/META
                 ocaml/Makefile
                 ocaml/examples/Makefile
                 p2v/Makefile
                 perl/Build.PL
                 perl/Makefile
                 perl/examples/Makefile
                 php/Makefile
                 po-docs/Makefile
                 po-docs/ja/Makefile
                 po-docs/uk/Makefile
                 po/Makefile
                 python/Makefile
                 python/examples/Makefile
                 python/setup.py
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
                 tests/create/Makefile
                 tests/data/Makefile
                 tests/daemon/Makefile
                 tests/daemon/captive-daemon.pm
                 tests/discard/Makefile
                 tests/disks/Makefile
                 tests/disks/test-qemu-drive-libvirt.xml
                 tests/disk-labels/Makefile
                 tests/events/Makefile
                 tests/fuzz/Makefile
                 tests/guests/Makefile
                 tests/guests/guests.xml
                 tests/hotplug/Makefile
                 tests/http/Makefile
                 tests/journal/Makefile
                 tests/luks/Makefile
                 tests/lvm/Makefile
                 tests/md/Makefile
                 tests/mount-local/Makefile
                 tests/mountable/Makefile
                 tests/nbd/Makefile
                 tests/network/Makefile
                 tests/ntfsclone/Makefile
                 tests/parallel/Makefile
                 tests/protocol/Makefile
                 tests/qemu/Makefile
                 tests/regressions/Makefile
                 tests/relative-paths/Makefile
                 tests/rsync/Makefile
                 tests/selinux/Makefile
                 tests/syslinux/Makefile
                 tests/tmpdirs/Makefile
                 tests/xfs/Makefile
                 tests/xml/Makefile
                 tools/Makefile
                 v2v/Makefile
                 v2v/test-harness/Makefile
                 v2v/test-harness/META])
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
echo       "Appliance ........................... $ENABLE_APPLIANCE"
echo       "QEMU ................................ $QEMU $QEMU_OPTIONS"
echo       "guestfish and C-based virt tools .... yes"
echo       "FUSE filesystem ..................... $enable_fuse"
AS_ECHO_N(["GNU gettext for i18n ................ "])
if test "x$HAVE_GNU_GETTEXT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["virt-p2v ............................ "])
if test "x$HAVE_P2V_TRUE" = "x"; then echo "yes"; else echo "no"; fi
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
AS_ECHO_N(["Go bindings ......................... "])
if test "x$HAVE_GOLANG_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject bindings .................... "])
if test "x$HAVE_GOBJECT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject introspection ............... "])
if test "x$HAVE_INTROSPECTION_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["bash completion ..................... "])
if test "x$HAVE_BASH_COMPLETION_TRUE" = "x"; then echo "yes"; else echo "no"; fi
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
