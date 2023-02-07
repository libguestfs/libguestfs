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

    dnl Check that the chosen qemu has virtio-serial support.
    dnl For historical reasons this can be disabled by setting
    dnl vmchannel_test=no.
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

        AC_MSG_CHECKING([for $QEMU version >= 1])
        if $QEMU -version | grep -sq 'version @<:@1-9@:>@'; then
            AC_MSG_RESULT([yes])
        else
            AC_MSG_RESULT([no])
            AC_MSG_FAILURE([$QEMU version must be >= 1.0.])
        fi

	dnl Unfortunately $QEMU -device \? won't just work.  We probably
	dnl need to add a cocktail of different arguments which differ
	dnl on the various emulators.  Thanks, qemu.
	AC_MSG_CHECKING([what extra options we need to use for qemu feature tests])
	QEMU_OPTIONS_FOR_CONFIGURE=
	# Note: the order we test these matters.
	for opt in "-machine virt" "-machine accel=kvm:tcg" "-display none"; do
	    if $QEMU $QEMU_OPTIONS_FOR_CONFIGURE $opt -device \? >&AS_MESSAGE_LOG_FD 2>&1; then
	        QEMU_OPTIONS_FOR_CONFIGURE="$QEMU_OPTIONS_FOR_CONFIGURE $opt"
	    fi
	done
	AC_MSG_RESULT([$QEMU_OPTIONS_FOR_CONFIGURE])

        AC_MSG_CHECKING([that $QEMU $QEMU_OPTIONS_FOR_CONFIGURE -device ? works])
        if $QEMU $QEMU_OPTIONS_FOR_CONFIGURE -device \? >&AS_MESSAGE_LOG_FD 2>&1; then
            AC_MSG_RESULT([yes])
        else
            AC_MSG_RESULT([no])
            AC_MSG_FAILURE([$QEMU $QEMU_OPTIONS_FOR_CONFIGURE -device ? doesn't work.])
        fi

        AC_MSG_CHECKING([for virtio-serial support in $QEMU])
        if $QEMU $QEMU_OPTIONS_FOR_CONFIGURE -device \? 2>&1 | grep -sq virtio-serial; then
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
])
