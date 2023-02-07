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

dnl Bash completion.
PKG_CHECK_MODULES([BASH_COMPLETION], [bash-completion >= 2.0], [
    bash_completion=yes
    AC_MSG_CHECKING([for bash-completions directory])
    BASH_COMPLETIONS_DIR="`pkg-config --variable=completionsdir bash-completion`"
    AC_MSG_RESULT([$BASH_COMPLETIONS_DIR])
    AC_SUBST([BASH_COMPLETIONS_DIR])
],[
    bash_completion=no
    AC_MSG_WARN([bash-completion not installed])
])
AM_CONDITIONAL([HAVE_BASH_COMPLETION],[test "x$bash_completion" = "xyes"])
