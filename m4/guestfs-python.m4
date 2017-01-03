# libguestfs
# Copyright (C) 2009-2018 Red Hat Inc.
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

dnl Check for Python (optional, for Python bindings).
PYTHON_PREFIX=
PYTHON_VERSION=
PYTHON_INSTALLDIR=

AC_ARG_ENABLE([python],
    AS_HELP_STRING([--disable-python], [disable Python language bindings]),
    [],
    [enable_python=yes])
AS_IF([test "x$enable_python" != "xno"],[
    AC_CHECK_PROG([PYTHON],[python],[python],[no])

    if test "x$PYTHON" != "xno"; then
	AC_MSG_CHECKING([Python version])
        PYTHON_VERSION_MAJOR=`$PYTHON -c "import sys; print (sys.version_info@<:@0@:>@)"`
        PYTHON_VERSION_MINOR=`$PYTHON -c "import sys; print (sys.version_info@<:@1@:>@)"`
        PYTHON_VERSION="$PYTHON_VERSION_MAJOR.$PYTHON_VERSION_MINOR"
	AC_MSG_RESULT([$PYTHON_VERSION])
        # Debian: python-2.7.pc, python-3.2.pc
        PKG_CHECK_MODULES([PYTHON], [python-"$PYTHON_VERSION"],[
            AC_SUBST([PYTHON_CFLAGS])
            AC_SUBST([PYTHON_LIBS])
            AC_SUBST([PYTHON_VERSION])
            AC_DEFINE([HAVE_PYTHON],[1],[Python library found at compile time])
        ],[
            PKG_CHECK_MODULES([PYTHON], [python],[
                AC_SUBST([PYTHON_CFLAGS])
                AC_SUBST([PYTHON_LIBS])
                AC_SUBST([PYTHON_VERSION])
                AC_DEFINE([HAVE_PYTHON],[1],[Python library found at compile time])
            ],[
                AC_MSG_WARN([python $PYTHON_VERSION not found])
            ])
        ])
        AC_MSG_CHECKING([Python prefix])
        PYTHON_PREFIX=`$PYTHON -c "import sys; print (sys.prefix)"`
        AC_MSG_RESULT([$PYTHON_PREFIX])

        AC_ARG_WITH([python-installdir],
                    [AS_HELP_STRING([--with-python-installdir],
	                [directory to install python modules @<:@default=check@:>@])],
			[PYTHON_INSTALLDIR="$withval"
	                 AC_MSG_NOTICE([Python install dir $PYTHON_INSTALLDIR])],
			[PYTHON_INSTALLDIR=check])

        if test "x$PYTHON_INSTALLDIR" = "xcheck"; then
	    PYTHON_INSTALLDIR=
            AC_MSG_CHECKING([for Python site-packages path])
            if test -z "$PYTHON_INSTALLDIR"; then
                PYTHON_INSTALLDIR=`$PYTHON -c "import distutils.sysconfig; \
                                               print (distutils.sysconfig.get_python_lib(1,0));"`
            fi
            AC_MSG_RESULT([$PYTHON_INSTALLDIR])
        fi

        AC_MSG_CHECKING([for Python extension suffix (PEP-3149)])
        if test -z "$PYTHON_EXT_SUFFIX"; then
            python_ext_suffix=`$PYTHON -c "import distutils.sysconfig; \
                                         print (distutils.sysconfig.get_config_var('EXT_SUFFIX') or distutils.sysconfig.get_config_var('SO'))"`
            PYTHON_EXT_SUFFIX=$python_ext_suffix
        fi
        AC_MSG_RESULT([$PYTHON_EXT_SUFFIX])

        dnl Look for some optional symbols in libpython.
        old_LIBS="$LIBS"

        PYTHON_BLDLIBRARY=`$PYTHON -c "import distutils.sysconfig; \
                                       print (distutils.sysconfig.get_config_var('BLDLIBRARY'))"`
        AC_CHECK_LIB([c],[PyCapsule_New],
                     [AC_DEFINE([HAVE_PYCAPSULE_NEW],1,
                                [Found PyCapsule_New in libpython.])],
                     [],[$PYTHON_BLDLIBRARY])
        AC_CHECK_LIB([c],[PyString_AsString],
                     [AC_DEFINE([HAVE_PYSTRING_ASSTRING],1,
                                [Found PyString_AsString in libpython.])],
                     [],[$PYTHON_BLDLIBRARY])

        LIBS="$old_LIBS"
    fi

    AC_SUBST(PYTHON_PREFIX)
    AC_SUBST(PYTHON_VERSION)
    AC_SUBST(PYTHON_INSTALLDIR)
    AC_SUBST(PYTHON_EXT_SUFFIX)
])
AM_CONDITIONAL([HAVE_PYTHON],
    [test "x$PYTHON" != "xno" && test "x$PYTHON_LIBS" != "x" ])
