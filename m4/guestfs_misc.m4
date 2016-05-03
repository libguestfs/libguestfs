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

dnl Miscellaneous configuration that doesn't fit anywhere else.

dnl Replace libtool with a wrapper that clobbers dependency_libs in *.la files
dnl http://lists.fedoraproject.org/pipermail/devel/2010-November/146343.html
LIBTOOL='bash $(top_srcdir)/libtool-kill-dependency_libs.sh $(top_builddir)/libtool'
AC_SUBST([LIBTOOL])

dnl Only build boot-analysis program on x86-64 and aarch64.  It
dnl requires custom work to port to each architecture.
AM_CONDITIONAL([HAVE_BOOT_ANALYSIS],
               [test "$host_cpu" = "x86_64" || test "$host_cpu" = "aarch64"])
