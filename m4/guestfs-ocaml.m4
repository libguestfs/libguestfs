# libguestfs
# Copyright (C) 2009-2020 Red Hat Inc.
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

dnl OCaml >= 4.01 is required.
ocaml_ver_str=4.01
ocaml_min_major=4
ocaml_min_minor=1
AC_MSG_CHECKING([if OCaml version >= $ocaml_ver_str])
ocaml_major="`echo $OCAMLVERSION | $AWK -F. '{print $1}'`"
ocaml_minor="`echo $OCAMLVERSION | $AWK -F. '{print $2}' | sed 's/^0//'`"
AS_IF([test "$ocaml_major" -ge $((ocaml_min_major+1)) || ( test "$ocaml_major" -eq $ocaml_min_major && test "$ocaml_minor" -ge $ocaml_min_minor )],[
    AC_MSG_RESULT([yes ($ocaml_major, $ocaml_minor)])
],[
    AC_MSG_RESULT([no])
    AC_MSG_FAILURE([OCaml compiler is not new enough.  At least OCaml $ocaml_ver_str is required])
])

AM_CONDITIONAL([HAVE_OCAML],
               [test "x$enable_ocaml" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLOPT],
               [test "x$OCAMLOPT" != "xno"])
AM_CONDITIONAL([HAVE_OCAMLDOC],
               [test "x$OCAMLDOC" != "xno"])

dnl Check if ocamlc/ocamlopt -runtime-variant _pic works.  It was
dnl added in OCaml >= 4.03, but in theory might be disabled by
dnl downstream distros.
OCAML_RUNTIME_VARIANT_PIC_OPTION=""
if test "x$OCAMLC" != "xno"; then
    AC_MSG_CHECKING([if OCaml ‘-runtime-variant _pic’ works])
    rm -f conftest.ml contest
    echo 'print_endline "hello world"' > conftest.ml
    if $OCAMLOPT conftest.ml -runtime-variant _pic -o conftest >&5 2>&5 ; then
        AC_MSG_RESULT([yes])
        OCAML_RUNTIME_VARIANT_PIC_OPTION="-runtime-variant _pic"
    else
        AC_MSG_RESULT([no])
    fi
    rm -f conftest.ml contest
fi
AC_SUBST([OCAML_RUNTIME_VARIANT_PIC_OPTION])

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

have_Hivex_OPEN_UNSAFE=no
if test "x$enable_daemon" = "xyes"; then
    OCAML_PKG_hivex=no
    AC_CHECK_OCAML_PKG(hivex)
    if test "x$OCAML_PKG_hivex" = "xno"; then
        AC_MSG_ERROR([the OCaml module 'hivex' is required])
    fi

    # Check if Hivex has 'OPEN_UNSAFE' flag.
    AC_MSG_CHECKING([for Hivex.OPEN_UNSAFE])
    rm -f conftest.ml
    echo 'let s = Hivex.OPEN_UNSAFE' > conftest.ml
    if $OCAMLFIND ocamlc -package hivex -c conftest.ml >&5 2>&5 ; then
        AC_MSG_RESULT([yes])
        have_Hivex_OPEN_UNSAFE=yes
    else
        AC_MSG_RESULT([no])
        have_Hivex_OPEN_UNSAFE=no
    fi

    dnl Check which OCaml runtime to link the daemon again.
    dnl We can't use AC_CHECK_LIB here unfortunately because
    dnl the other symbols are resolved by OCaml itself.
    AC_MSG_CHECKING([which OCaml runtime we should link the daemon with])
    if test "x$OCAMLOPT" != "xno"; then
        for f in asmrun_pic asmrun; do
            if test -f "$OCAMLLIB/lib$f.a"; then
                CAMLRUN=$f
                break
            fi
        done
    else
        for f in camlrun; do
            if test -f "$OCAMLLIB/lib$f.a"; then
                CAMLRUN=$f
                break
            fi
        done
    fi
    if test "x$CAMLRUN" != "x"; then
        AC_MSG_RESULT([$CAMLRUN])
    else
        AC_MSG_ERROR([could not find or link to libasmrun or libcamlrun])
    fi
    AC_SUBST([CAMLRUN])
fi

dnl Define HIVEX_OPEN_UNSAFE_FLAG based on test above.
AS_IF([test "x$have_Hivex_OPEN_UNSAFE" = "xno"],[
    HIVEX_OPEN_UNSAFE_FLAG="None"
],[
    HIVEX_OPEN_UNSAFE_FLAG="Some Hivex.OPEN_UNSAFE"
])
AC_SUBST([HIVEX_OPEN_UNSAFE_FLAG])

OCAML_PKG_gettext=no
OCAML_PKG_oUnit=no
ounit_is_v2=no
have_Bytes_module=no
AS_IF([test "x$OCAMLC" != "xno"],[
    # Create common/mlgettext/common_gettext.ml gettext functions or stubs.

    # If we're building in a different directory, then common/mlgettext
    # might not exist yet, so create it:
    mkdir -p common/mlgettext

    GUESTFS_CREATE_COMMON_GETTEXT_ML([common/mlgettext/common_gettext.ml])

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
AM_CONDITIONAL([HAVE_OCAML_PKG_OUNIT],
               [test "x$OCAML_PKG_oUnit" != "xno" && test "x$ounit_is_v2" != "xno"])

AC_CHECK_PROG([OCAML_GETTEXT],[ocaml-gettext],[ocaml-gettext],[no])
AM_CONDITIONAL([HAVE_OCAML_GETTEXT],
               [test "x$OCAML_PKG_gettext" != "xno" && test "x$OCAML_GETTEXT" != "xno"])

dnl Create the backwards compatibility Bytes module for OCaml < 4.02.
mkdir -p common/mlstdutils
rm -f common/mlstdutils/bytes.ml common/mlstdutils/bytes.mli
AS_IF([test "x$have_Bytes_module" = "xno"],[
    cat > common/mlstdutils/bytes.ml <<EOF
include String
let of_string = String.copy
let to_string = String.copy
let sub_string = String.sub
EOF
    $OCAMLC -i common/mlstdutils/bytes.ml > common/mlstdutils/bytes.mli
    safe_string_option=
],[
    safe_string_option="-safe-string"
])
AM_CONDITIONAL([HAVE_BYTES_COMPAT_ML],
	       [test "x$have_Bytes_module" = "xno"])

dnl Check if OCaml has caml_alloc_initialized_string (added 2017).
AS_IF([test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno" && \
       test "x$enable_ocaml" = "xyes"],[
    AC_MSG_CHECKING([for caml_alloc_initialized_string])
    cat >conftest.c <<'EOF'
#include <caml/alloc.h>
int main () { char *p = (void *) caml_alloc_initialized_string; return 0; }
EOF
    AS_IF([$OCAMLC conftest.c >&AS_MESSAGE_LOG_FD 2>&1],[
        AC_MSG_RESULT([yes])
        AC_DEFINE([HAVE_CAML_ALLOC_INITIALIZED_STRING],[1],
                  [caml_alloc_initialized_string found at compile time.])
    ],[
        AC_MSG_RESULT([no])
    ])
    rm -f conftest.c conftest.o
])

dnl Flags we want to pass to every OCaml compiler call.
OCAML_WARN_ERROR="-warn-error CDEFLMPSUVYZX+52-3"
AC_SUBST([OCAML_WARN_ERROR])
OCAML_FLAGS="-g -annot $safe_string_option"
AC_SUBST([OCAML_FLAGS])
