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

dnl Bash completion.
AC_ARG_WITH([bash-completion],
  [AS_HELP_STRING([--with-bash-completion],[Enable bash completions @<:@default=auto@:>@])],
  [with_bash_completion="$withval"],
  [with_bash_completion=auto])

AS_IF([test "x$with_bash_completion" = "xauto"], [
       PKG_CHECK_MODULES([BASH_COMPLETION], [bash-completion >= 2.0],
       [], [
         AC_MSG_WARN([bash-completion not installed])
       BASH_COMPLETION=no
])],[BASH_COMPLETION=$with_bash_completion])
AM_CONDITIONAL([HAVE_BASH_COMPLETION],[test "x$BASH_COMPLETION" != "xno"])

AC_ARG_WITH([bash-completion-dir],
  [AS_HELP_STRING([--with-bash-completion-dir],[Directory to install bash completions @<:@default=auto@:>@])],
  [with_bash_completion_dir="$withval"],
  [with_bash_completion_dir=auto])

AS_IF([test "x$BASH_COMPLETION" != "xno"], [
  AC_MSG_CHECKING([for bash-completions directory])
  AS_IF([test "x$with_bash_completion_dir" = "xauto" || test "x$with_bash_completion_dir" = "xyes"], [
    PKG_CHECK_VAR([BASH_COMPLETIONS_DIR], [bash-completion], [completionsdir], [], [
      BASH_COMPLETIONS_DIR="${datadir}/bash-completion/completions"])
  ],
  [BASH_COMPLETIONS_DIR=$with_bash_completion_dir])
  AC_MSG_RESULT([$BASH_COMPLETIONS_DIR])
  AC_SUBST([BASH_COMPLETIONS_DIR])
])
