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

dnl Check for OCaml (optional, for OCaml bindings and OCaml tools).
OCAMLC=no
OCAMLFIND=no
AC_ARG_ENABLE([ocaml],
    AS_HELP_STRING([--disable-ocaml], [disable OCaml language bindings]),
    [],
    [enable_ocaml=yes])
AS_IF([test "x$enable_ocaml" != "xno"],[
    dnl OCAMLC and OCAMLFIND have to be unset first, otherwise
    dnl AC_CHECK_TOOL (inside AC_PROG_OCAML) will not look.
    OCAMLC=
    OCAMLFIND=
    AC_PROG_OCAML
    AC_PROG_FINDLIB

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
])
AM_CONDITIONAL([HAVE_OCAML],
               [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLOPT],
               [test "x$OCAMLOPT" != "xno" && test "x$OCAMLFIND" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLDOC],
               [test "x$OCAMLDOC" != "xno"])

dnl OCaml is required if we need to run the generator.
AS_IF([test "x$OCAMLC" = "xno" || test "x$OCAMLFIND" = "xno"],[
    AS_IF([! test -f $srcdir/common/protocol/guestfs_protocol.x],[
        AC_MSG_FAILURE([OCaml compiler and findlib is required to build from git.
If you don't have OCaml available, you should build from a tarball from
http://libguestfs.org/download])
    ])
])

AS_IF([test "x$OCAMLC" != "xno"],[
    dnl Check for <caml/unixsupport.h> header.
    old_CPPFLAGS="$CPPFLAGS"
    CPPFLAGS="$CPPFLAGS -I`$OCAMLC -where`"
    AC_CHECK_HEADERS([caml/unixsupport.h],[],[],[#include <caml/mlvalues.h>])
    CPPFLAGS="$old_CPPFLAGS"
])

OCAML_PKG_gettext=no
OCAML_PKG_libvirt=no
OCAML_PKG_oUnit=no
ounit_is_v2=no
have_Bytes_module=no
AS_IF([test "x$OCAMLC" != "xno"],[
    # Create mllib/common_gettext.ml, gettext functions or stubs.

    # If we're building in a different directory, then mllib/ might
    # not exist yet, so create it:
    mkdir -p mllib

    GUESTFS_CREATE_COMMON_GETTEXT_ML([mllib/common_gettext.ml])

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
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_gettext" != "xno"])
AM_CONDITIONAL([HAVE_OCAML_PKG_LIBVIRT],
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_libvirt" != "xno"])
AM_CONDITIONAL([HAVE_OCAML_PKG_OUNIT],
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_oUnit" != "xno" && test "x$ounit_is_v2" != "xno"])

AC_CHECK_PROG([OCAML_GETTEXT],[ocaml-gettext],[ocaml-gettext],[no])
AM_CONDITIONAL([HAVE_OCAML_GETTEXT],
    [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && test "x$OCAML_PKG_gettext" != "xno" && test "x$OCAML_GETTEXT" != "xno"])

dnl Create the backwards compatibility Bytes module for OCaml < 4.02.
mkdir -p generator mllib
rm -f generator/bytes.ml mllib/bytes.ml
AS_IF([test "x$have_Bytes_module" = "xno"],[
    cat > generator/bytes.ml <<EOF
include String
let of_string = String.copy
let to_string = String.copy
EOF
    ln -s ../generator/bytes.ml mllib/bytes.ml
    OCAML_GENERATOR_BYTES_COMPAT_CMO='$(top_builddir)/generator/bytes.cmo'
    OCAML_BYTES_COMPAT_CMO='$(top_builddir)/mllib/bytes.cmo'
    OCAML_BYTES_COMPAT_ML='$(top_builddir)/mllib/bytes.ml'
    safe_string_option=
],[
    OCAML_GENERATOR_BYTES_COMPAT_CMO=
    OCAML_BYTES_COMPAT_CMO=
    OCAML_BYTES_COMPAT_ML=
    safe_string_option="-safe-string"
])
AC_SUBST([OCAML_GENERATOR_BYTES_COMPAT_CMO])
AC_SUBST([OCAML_BYTES_COMPAT_CMO])
AC_SUBST([OCAML_BYTES_COMPAT_ML])

dnl Flags we want to pass to every OCaml compiler call.
OCAML_WARN_ERROR="-warn-error CDEFLMPSUVYZX-3"
AC_SUBST([OCAML_WARN_ERROR])
OCAML_FLAGS="-g -annot $safe_string_option"
AC_SUBST([OCAML_FLAGS])
