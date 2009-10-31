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
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign])

m4_ifndef([AM_SILENT_RULES], [m4_define([AM_SILENT_RULES],[])])
AM_SILENT_RULES([yes]) # make --enable-silent-rules the default.

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

dnl Enable packet dumps when in verbose mode.  This generates lots
dnl of debug info, only useful for people debugging the RPC mechanism.
AC_ARG_ENABLE([packet-dump],
        [AS_HELP_STRING([--enable-packet-dump],
          [enable packet dumps in verbose mode @<:@default=no@:>@])],
        [AC_DEFINE([ENABLE_PACKET_DUMP],[1],[Enable packet dumps in verbose mode.])],
        [])

dnl For strchrnul(3), asprintf(3), futimens(2) and getline(3).
AC_GNU_SOURCE

dnl Check for basic C environment.
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_CPP

gl_EARLY
gl_INIT

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
  nw="$nw -Waggregate-return"       # anachronistic
  nw="$nw -Wc++-compat"             # We don't care about C++ compilers
  nw="$nw -Wundef"                  # Warns on '#if GNULIB_FOO' etc in gnulib
  nw="$nw -Wtraditional"            # Warns on #elif which we use often
  nw="$nw -Wcast-qual"              # Too many warnings for now
  nw="$nw -Wconversion"             # Too many warnings for now
  nw="$nw -Wsystem-headers"         # Don't let system headers trigger warnings
  nw="$nw -Wsign-conversion"        # Too many warnings for now
  nw="$nw -Wtraditional-conversion" # Too many warnings for now
  nw="$nw -Wunreachable-code"       # Too many warnings for now
  nw="$nw -Wpadded"                 # Our structs are not padded
  nw="$nw -Wredundant-decls"        # openat.h declares e.g., mkdirat
  nw="$nw -Wlogical-op"             # any use of fwrite provokes this
  nw="$nw -Wvla"                    # two warnings in mount.c
  # things I might fix soon:
  nw="$nw -Wmissing-format-attribute" # daemon.h's asprintf_nowarn
  nw="$nw -Winline"                 # daemon.h's asprintf_nowarn
  nw="$nw -Wshadow"                 # numerous, plus we're not unanimous
  # ?? -Wstrict-overflow
  nw="$nw -Wunsafe-loop-optimizations" # just a warning that an optimization
                                    # was not possible, safe to ignore

  gl_MANYWARN_ALL_GCC([ws])
  gl_MANYWARN_COMPLEMENT([ws], [$ws], [$nw])
  for w in $ws; do
    gl_WARN_ADD([$w])
  done
  gl_WARN_ADD([-Wno-unused-parameter]) # stubs.c
  gl_WARN_ADD([-Wno-jump-misses-init]) # stubs.c
  gl_WARN_ADD([-Wno-unused-variable]) # FIXME: only temporary, for guestfs_protocol.c, etc

  # In spite of excluding -Wlogical-op above, it is enabled, as of
  # gcc 4.5.0 20090517, and it provokes warnings in cat.c, dd.c, truncate.c
  gl_WARN_ADD([-Wno-logical-op])

  gl_WARN_ADD([-fdiagnostics-show-option])

  AC_SUBST([WARN_CFLAGS])

  AC_DEFINE([lint], [1], [Define to 1 if the compiler is checking for lint.])
  AC_DEFINE([_FORTIFY_SOURCE], [2],
    [enable compile-time and run-time bounds-checking, and some warnings])
  AC_DEFINE([GNULIB_PORTCHECK], [1], [enable some gnulib portability checks])
fi

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

dnl Check for libselinux (optional).
AC_CHECK_HEADERS([selinux/selinux.h])
AC_CHECK_LIB([selinux],[setexeccon],[
        LIBS="-lselinux $LIBS"
        have_libselinux="$ac_cv_header_selinux_selinux_h"
        AC_CHECK_FUNCS([setcon getcon])
        ],[have_libselinux=no])
if test "x$have_libselinux" = "xyes"; then
        AC_DEFINE([HAVE_LIBSELINUX],[1],[Define to 1 if you have libselinux])
fi

dnl Check for XDR library.
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
        AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
        ])

dnl Functions which may not be available in older distributions.
AC_CHECK_FUNCS([futimens listxattr llistxattr getxattr lgetxattr setxattr lsetxattr removexattr lremovexattr inotify_init1])

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
AC_CONFIG_FILES([Makefile lib/Makefile tests/Makefile])
AC_OUTPUT
