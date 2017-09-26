# libguestfs
# Copyright (C) 2009-2017 Red Hat Inc.
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

dnl Check for OCaml (required, for OCaml bindings and OCaml tools).

dnl OCAMLC and OCAMLFIND have to be unset first, otherwise
dnl AC_CHECK_TOOL (inside AC_PROG_OCAML) will not look.
OCAMLC=
OCAMLFIND=
AC_PROG_OCAML
AC_PROG_FINDLIB

AS_IF([test "x$OCAMLC" = "xno"],[
    AC_MSG_ERROR([OCaml compiler is required])
])

AS_IF([test "x$OCAMLFIND" = "xno"],[
    AC_MSG_ERROR([OCaml findlib is required])
])

dnl --disable-ocaml only disables OCaml bindings and OCaml virt tools.
AC_ARG_ENABLE([ocaml],
    AS_HELP_STRING([--disable-ocaml], [disable OCaml language bindings and tools]),
    [],
    [enable_ocaml=yes])

dnl OCaml >= 3.11 is required.
AC_MSG_CHECKING([if OCaml version >= 3.11])
ocaml_major="`echo $OCAMLVERSION | $AWK -F. '{print $1}'`"
ocaml_minor="`echo $OCAMLVERSION | $AWK -F. '{print $2}'`"
AS_IF([test "$ocaml_major" -ge 4 || ( test "$ocaml_major" -eq 3 && test "$ocaml_minor" -ge 11 )],[
    AC_MSG_RESULT([yes])
],[
    AC_MSG_RESULT([no])
    AC_MSG_FAILURE([OCaml compiler is not new enough.  At least OCaml 3.11 is required])
])

AM_CONDITIONAL([HAVE_OCAML],
               [test "x$enable_ocaml" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLOPT],
               [test "x$OCAMLOPT" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLDOC],
               [test "x$OCAMLDOC" != "xno"])

dnl Check if ocamldep has options -all and -one-line (not present in RHEL 6).
AC_MSG_CHECKING([if ocamldep has the ‘-all’ option])
if ocamldep -all >&AS_MESSAGE_LOG_FD 2>&1; then
    AC_MSG_RESULT([yes])
    OCAMLDEP_ALL="-all"
else
    AC_MSG_RESULT([no])
    OCAMLDEP_ALL=""
fi
AC_SUBST([OCAMLDEP_ALL])
AC_MSG_CHECKING([if ocamldep has the ‘-one-line’ option])
if ocamldep -one-line >&AS_MESSAGE_LOG_FD 2>&1; then
    AC_MSG_RESULT([yes])
    OCAMLDEP_ONE_LINE="-one-line"
else
    AC_MSG_RESULT([no])
    OCAMLDEP_ONE_LINE=""
fi
AC_SUBST([OCAMLDEP_ONE_LINE])

if test "x$enable_daemon" = "xyes"; then
    OCAML_PKG_hivex=no
    AC_CHECK_OCAML_PKG(hivex)
    if test "x$OCAML_PKG_hivex" = "xno"; then
        AC_MSG_ERROR([the OCaml module 'hivex' is required])
    fi
fi

OCAML_PKG_gettext=no
OCAML_PKG_libvirt=no
OCAML_PKG_oUnit=no
ounit_is_v2=no
have_Bytes_module=no
AS_IF([test "x$OCAMLC" != "xno"],[
    # Create common/mlgettext/common_gettext.ml gettext functions or stubs.

    # If we're building in a different directory, then common/mlgettext
    # might not exist yet, so create it:
    mkdir -p common/mlgettext

    GUESTFS_CREATE_COMMON_GETTEXT_ML([common/mlgettext/common_gettext.ml])

    AC_CHECK_OCAML_PKG(libvirt)
    AC_CHECK_OCAML_PKG(oUnit)

    # oUnit >= 2 is required, so check that it has OUnit2.
    if test "x$OCAML_PKG_oUnit" != "xno"; then
        AC_CHECK_OCAML_MODULE(ounit_is_v2,[OUnit.OUnit2],OUnit2,[+oUnit])
    fi

    # Check if we have the 'Bytes' module.  If not (OCaml < 4.02) then
    # we need to create a compatibility module.
    # AC_CHECK_OCAML_MODULE is a bit broken, so open code this test.
    AC_MSG_CHECKING([for OCaml module Bytes])
    rm -f conftest.ml
    echo 'let s = Bytes.empty' > conftest.ml
    if $OCAMLC -c conftest.ml >&5 2>&5 ; then
        AC_MSG_RESULT([yes])
        have_Bytes_module=yes
    else
        AC_MSG_RESULT([not found])
        have_Bytes_module=no
    fi
])
AM_CONDITIONAL([HAVE_OCAML_PKG_GETTEXT],
               [test "x$OCAML_PKG_gettext" != "xno"])
AM_CONDITIONAL([HAVE_OCAML_PKG_LIBVIRT],
               [test "x$OCAML_PKG_libvirt" != "xno"])
AM_CONDITIONAL([HAVE_OCAML_PKG_OUNIT],
               [test "x$OCAML_PKG_oUnit" != "xno" && test "x$ounit_is_v2" != "xno"])

AC_CHECK_PROG([OCAML_GETTEXT],[ocaml-gettext],[ocaml-gettext],[no])
AM_CONDITIONAL([HAVE_OCAML_GETTEXT],
               [test "x$OCAML_PKG_gettext" != "xno" && test "x$OCAML_GETTEXT" != "xno"])

dnl Create the backwards compatibility Bytes module for OCaml < 4.02.
mkdir -p common/mlstdutils
rm -f common/mlstdutils/bytes.ml
AS_IF([test "x$have_Bytes_module" = "xno"],[
    cat > common/mlstdutils/bytes.ml <<EOF
include String
let of_string = String.copy
let to_string = String.copy
let sub_string = String.sub
EOF
    OCAML_BYTES_COMPAT_CMO='$(top_builddir)/common/mlstdutils/bytes.cmo'
    OCAML_BYTES_COMPAT_ML='$(top_builddir)/common/mlstdutils/bytes.ml'
    safe_string_option=
],[
    OCAML_BYTES_COMPAT_CMO=
    OCAML_BYTES_COMPAT_ML=
    safe_string_option="-safe-string"
])
AC_SUBST([OCAML_BYTES_COMPAT_CMO])
AC_SUBST([OCAML_BYTES_COMPAT_ML])
AM_CONDITIONAL([HAVE_BYTES_COMPAT_ML],
	       [test "x$OCAML_BYTES_COMPAT_ML" != "x"])

dnl Flags we want to pass to every OCaml compiler call.
OCAML_WARN_ERROR="-warn-error CDEFLMPSUVYZX-3"
AC_SUBST([OCAML_WARN_ERROR])
OCAML_FLAGS="-g -annot $safe_string_option"
AC_SUBST([OCAML_FLAGS])
