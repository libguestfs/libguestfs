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

dnl The appliance and any dependencies.

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
