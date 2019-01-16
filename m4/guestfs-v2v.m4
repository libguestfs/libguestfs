# libguestfs
# Copyright (C) 2009-2019 Red Hat Inc.
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

dnl Virt-v2v and virt-p2v.

dnl nbdkit python plugin.
AC_MSG_CHECKING([for the nbdkit python plugin name])
AC_ARG_WITH([virt-v2v-nbdkit-python-plugin],
    [AS_HELP_STRING([--with-virt-v2v-nbdkit-python-plugin="python|..."],
        [set nbdkit python plugin name used by virt-v2v @<:@default=python@:>@])],
    [VIRT_V2V_NBDKIT_PYTHON_PLUGIN="$withval"],
    [VIRT_V2V_NBDKIT_PYTHON_PLUGIN=python])
AC_MSG_RESULT([$VIRT_V2V_NBDKIT_PYTHON_PLUGIN])
AC_SUBST([VIRT_V2V_NBDKIT_PYTHON_PLUGIN])

dnl Check for Gtk 2 or 3 library, used by virt-p2v.
AC_MSG_CHECKING([for --with-gtk option])
AC_ARG_WITH([gtk],
    [AS_HELP_STRING([--with-gtk=2|3|check|no],
        [prefer Gtk version 2 or 3. @<:@default=check@:>@])],
    [with_gtk="$withval"
     AC_MSG_RESULT([$withval])],
    [with_gtk="check"
     AC_MSG_RESULT([not set, will check for installed Gtk])]
)

if test "x$with_gtk" = "x3"; then
    PKG_CHECK_MODULES([GTK], [gtk+-3.0], [
        GTK_VERSION=3
    ])
elif test "x$with_gtk" = "x2"; then
    PKG_CHECK_MODULES([GTK], [gtk+-2.0], [
        GTK_VERSION=2
    ], [])
elif test "x$with_gtk" = "xcheck"; then
    PKG_CHECK_MODULES([GTK], [gtk+-3.0], [
        GTK_VERSION=3
    ], [
        PKG_CHECK_MODULES([GTK], [gtk+-2.0], [
            GTK_VERSION=2
        ], [:])
    ])
fi

dnl D-Bus is an optional dependency of virt-p2v.
PKG_CHECK_MODULES([DBUS], [dbus-1], [
    AC_SUBST([DBUS_CFLAGS])
    AC_SUBST([DBUS_LIBS])
    AC_DEFINE([HAVE_DBUS],[1],[D-Bus found at compile time.])
],[
    AC_MSG_WARN([D-Bus not found, virt-p2v will not be able to inhibit power saving during P2V conversions])
])

dnl Can we build virt-p2v?
AC_MSG_CHECKING([if we can build virt-p2v])
if test "x$GTK_LIBS" != "x"; then
    AC_MSG_RESULT([yes, with Gtk $GTK_VERSION])
    AC_SUBST([GTK_CFLAGS])
    AC_SUBST([GTK_LIBS])
    AC_SUBST([GTK_VERSION])
else
    AC_MSG_RESULT([no])
fi
AM_CONDITIONAL([HAVE_P2V], [test "x$GTK_LIBS" != "x"])
