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
