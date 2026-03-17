# libguestfs
# Copyright (C) 2009-2025 Red Hat Inc.
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

dnl Check for QEMU for running binaries on this $host_cpu, fall
dnl back to basic 'qemu'.  Allow the user to override it.
AS_CASE([$host_cpu],
        [i@<:@456@:>@86],[qemu_cpu=i386],
        [arm*],[qemu_cpu=arm],
        [amd64],[qemu_cpu=x86_64],
        [powerpc64 | ppc64le | powerpc64le],[qemu_cpu=ppc64],
        [qemu_cpu=$host_cpu])
default_qemu="qemu-kvm kvm qemu-system-$qemu_cpu qemu"
AC_ARG_WITH([qemu],
    [AS_HELP_STRING([--with-qemu="bin1 bin2 ..."],
        [set default QEMU binary @<:@default="[qemu-kvm] qemu-system-<host> qemu"@:>@])],
    dnl --with-qemu or --without-qemu:
    [],
    dnl neither option was given:
    [with_qemu="$default_qemu"]
)

AS_IF([test "x$with_qemu" = "xno"],[
    AC_MSG_WARN([qemu was disabled, libguestfs may not work at all])
    QEMU=no
],[
    AC_PATH_PROGS([QEMU],[$with_qemu],[no],
        [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin$PATH_SEPARATOR/usr/libexec])
    test "x$QEMU" = "xno" && AC_MSG_ERROR([qemu must be installed])

    AC_DEFINE_UNQUOTED([QEMU],["$QEMU"],[Location of qemu binary.])
])
