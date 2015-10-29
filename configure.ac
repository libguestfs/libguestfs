# libguestfs
# Copyright (C) 2009-2015 Red Hat Inc.
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

# The major, minor, and release fields MUST be numbers.  Packagers can
# add extra information using --with-extra="..." which may be any
# freeform string.
m4_define([libguestfs_major],   [1])
m4_define([libguestfs_minor],   [31])
m4_define([libguestfs_release], [20])

AC_INIT([libguestfs],libguestfs_major.libguestfs_minor.libguestfs_release)
AC_CONFIG_AUX_DIR([build-aux])

dnl Initialize automake.  automake < 1.12 didn't have serial-tests and
dnl gives an error if it sees this, but for automake >= 1.13
dnl serial-tests is required so we have to include it.  Solution is to
dnl test for the version of automake (by running an external command)
dnl and provide it if necessary.  Note we have to do this entirely using
dnl m4 macros since automake queries this macro by running
dnl 'autoconf --trace'.
m4_define([serial_tests], [
    m4_esyscmd([automake --version | head -1 | awk '
                     {
                       split ($NF, version, ".");
                       if (version[1] == 1 && version[2] >= 12)
                         print "serial-tests";
                     }'
    ])
])
AM_INIT_AUTOMAKE(foreign serial_tests subdir-objects) dnl NB: Do not [quote] this parameter.

m4_ifndef([AM_SILENT_RULES], [m4_define([AM_SILENT_RULES],[])])
AM_SILENT_RULES([yes]) # make --enable-silent-rules the default.

AC_CONFIG_MACRO_DIR([m4])

dnl Stable or development version?
BRANCH_NUMBER=libguestfs_major.libguestfs_minor
AC_SUBST([BRANCH_NUMBER])
AC_MSG_CHECKING([if $BRANCH_NUMBER is a stable or development branch of libguestfs])
AS_IF([test "$((libguestfs_minor % 2))" -eq 0 ],[
    BRANCH_TYPE=stable
    AC_MSG_RESULT([$BRANCH_TYPE])
],[
    BRANCH_TYPE=development
    AC_MSG_RESULT([$BRANCH_TYPE])
    AC_MSG_NOTICE([
***
This is a development version of libguestfs. Some APIs may be unstable
until they appear in a stable release of libguestfs (at which point
the C API and ABI is guaranteed to remain stable forever).  For
more information about stable and development branches of libguestfs
please see the section "LIBGUESTFS VERSION NUMBERS" in guestfs(3).
***])
])
AC_SUBST([BRANCH_TYPE])

dnl Extra string, a freeform string defined by packagers.
AC_ARG_WITH([extra],
    [AS_HELP_STRING([--with-extra],
                    [extra version string (for use by packagers)])],
    [libguestfs_extra="$withval"],
    [libguestfs_extra=]
)

AC_MSG_NOTICE([libguestfs version libguestfs_major.libguestfs_minor.libguestfs_release$libguestfs_extra])

dnl Split up the version string.
AC_DEFINE([PACKAGE_VERSION_MAJOR],[libguestfs_major],[Major version number.])
AC_DEFINE([PACKAGE_VERSION_MINOR],[libguestfs_minor],[Minor version number.])
AC_DEFINE([PACKAGE_VERSION_RELEASE],[libguestfs_release],[Release number.])
AC_DEFINE_UNQUOTED([PACKAGE_VERSION_EXTRA],["$libguestfs_extra"],[Extra version string.])
PACKAGE_VERSION_FULL="libguestfs_major.libguestfs_minor.libguestfs_release${libguestfs_extra}"
AC_DEFINE_UNQUOTED([PACKAGE_VERSION_FULL],["$PACKAGE_VERSION_FULL"],[Full version string.])
AC_SUBST([PACKAGE_VERSION_FULL])

dnl Early gnulib initialization.
gl_EARLY
gl_INIT

dnl Check for external programs required to either build or run
dnl libguestfs.
m4_include([m4/guestfs_progs.m4])

dnl The C compiler environment.
m4_include([m4/guestfs_c.m4])

dnl Any C libraries required by the libguestfs C library (not the daemon).
m4_include([m4/guestfs_libraries.m4])

dnl The daemon and any dependencies.
m4_include([m4/guestfs_daemon.m4])

dnl The appliance and any dependencies.
m4_include([m4/guestfs_appliance.m4])

dnl Check if crypt() is provided by a separate library.
old_LIBS="$LIBS"
AC_SEARCH_LIBS([crypt],[crypt])
LIBS="$old_LIBS"
if test "$ac_cv_search_crypt" = "-lcrypt" ; then
  LIBCRYPT_LIBS="-lcrypt"
fi
AC_SUBST([LIBCRYPT_LIBS])

dnl liblzma can be used by virt-builder (optional).
PKG_CHECK_MODULES([LIBLZMA], [liblzma], [
    AC_SUBST([LIBLZMA_CFLAGS])
    AC_SUBST([LIBLZMA_LIBS])
    AC_DEFINE([HAVE_LIBLZMA],[1],[liblzma found at compile time.])

    dnl Old lzma in RHEL 6 didn't have some APIs we need.
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBLZMA_LIBS"
    AC_CHECK_FUNCS([lzma_index_stream_flags lzma_index_stream_padding])
    LIBS="$old_LIBS"
],
[AC_MSG_WARN([liblzma not found, virt-builder will be slower])])

dnl Check for QEMU.
m4_include([m4/guestfs_qemu.m4])

dnl Readline.
AC_ARG_WITH([readline],[
    AS_HELP_STRING([--with-readline],
        [support fancy command line editing @<:@default=check@:>@])],
    [],
    [with_readline=check])

LIBREADLINE=
AS_IF([test "x$with_readline" != xno],[
    AC_CHECK_LIB([readline], [main],
        [AC_SUBST([LIBREADLINE], ["-lreadline -lncurses"])
         AC_DEFINE([HAVE_LIBREADLINE], [1],
                   [Define if you have libreadline.])
        ],
        [if test "x$with_readline" != xcheck; then
         AC_MSG_FAILURE(
             [--with-readline was given, but test for readline failed])
         fi
        ], -lncurses)
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBREADLINE"
    AC_CHECK_FUNCS([append_history completion_matches rl_completion_matches])
    LIBS="$old_LIBS"
    ])

dnl libconfig (highly recommended)
PKG_CHECK_MODULES([LIBCONFIG], [libconfig],[
    AC_SUBST([LIBCONFIG_CFLAGS])
    AC_SUBST([LIBCONFIG_LIBS])
    AC_DEFINE([HAVE_LIBCONFIG],[1],[libconfig found at compile time.])
],
    [AC_MSG_WARN([libconfig not found, some features will be disabled])])
AM_CONDITIONAL([HAVE_LIBCONFIG],[test "x$LIBCONFIG_LIBS" != "x"])

dnl Check for gtk2 library, used by virt-p2v.
PKG_CHECK_MODULES([GTK2], [gtk+-2.0], [
    AC_SUBST([GTK2_CFLAGS])
    AC_SUBST([GTK2_LIBS])
],
    [AC_MSG_WARN([gtk2 not found, virt-p2v will be disabled])])

dnl Can we build virt-p2v?
AM_CONDITIONAL([HAVE_P2V], [test "x$GTK2_LIBS" != "x"])

dnl FUSE is optional to build the FUSE module.
AC_ARG_ENABLE([fuse],
    AS_HELP_STRING([--disable-fuse], [disable FUSE (guestmount) support]),
    [],
    [enable_fuse=yes])
AS_IF([test "x$enable_fuse" != "xno"],[
    PKG_CHECK_MODULES([FUSE],[fuse],[
        AC_SUBST([FUSE_CFLAGS])
        AC_SUBST([FUSE_LIBS])
        AC_DEFINE([HAVE_FUSE],[1],[Define to 1 if you have FUSE.])
        old_LIBS="$LIBS"
        LIBS="$FUSE_LIBS $LIBS"
        AC_CHECK_FUNCS([fuse_opt_add_opt_escaped])
        LIBS="$old_LIBS"
    ],[
        enable_fuse=no
        AC_MSG_WARN([FUSE library and headers are missing, so optional FUSE module won't be built])
    ])
])
AM_CONDITIONAL([HAVE_FUSE],[test "x$enable_fuse" != "xno"])

dnl Check for language bindings.
m4_include([m4/guestfs_ocaml.m4])
m4_include([m4/guestfs_perl.m4])
m4_include([m4/guestfs_python.m4])
m4_include([m4/guestfs_ruby.m4])
m4_include([m4/guestfs_java.m4])
m4_include([m4/guestfs_haskell.m4])
m4_include([m4/guestfs_php.m4])
m4_include([m4/guestfs_erlang.m4])
m4_include([m4/guestfs_lua.m4])
m4_include([m4/guestfs_golang.m4])
m4_include([m4/guestfs_gobject.m4])

dnl Bash completion.
m4_include([m4/guestfs_bash_completion.m4])

dnl Replace libtool with a wrapper that clobbers dependency_libs in *.la files
dnl http://lists.fedoraproject.org/pipermail/devel/2010-November/146343.html
LIBTOOL='bash $(top_srcdir)/libtool-kill-dependency_libs.sh $(top_builddir)/libtool'
AC_SUBST([LIBTOOL])

dnl Work around autoconf's lack of expanded variables.
eval my_sysconfdir="\"[$]sysconfdir\""
eval my_sysconfdir="\"$my_sysconfdir\""
SYSCONFDIR="${my_sysconfdir}"
AC_SUBST(SYSCONFDIR)

dnl Produce output files.

AC_CONFIG_HEADERS([config.h])

dnl For separated builds, make sure that certain build directories exist.
dnl This avoids having to sprinkle 'mkdir -p' statements throughout
dnl many Makefile.am rules.
mkdir -p \
    appliance/supermin.d \
    java/t \
    ocaml/html \
    ocaml/t \
    tests/guests/guest-aux

dnl http://www.mail-archive.com/automake@gnu.org/msg10204.html
AC_CONFIG_FILES([appliance/libguestfs-make-fixed-appliance],
                [chmod +x,-w appliance/libguestfs-make-fixed-appliance])
AC_CONFIG_FILES([inspector/test-xmllint.sh],
                [chmod +x,-w inspector/test-xmllint.sh])
AC_CONFIG_FILES([installcheck.sh],
                [chmod +x,-w installcheck.sh])
AC_CONFIG_FILES([p2v/virt-p2v-make-disk],
                [chmod +x,-w p2v/virt-p2v-make-disk])
AC_CONFIG_FILES([p2v/virt-p2v-make-kickstart],
                [chmod +x,-w p2v/virt-p2v-make-kickstart])
AC_CONFIG_FILES([php/extension/php-for-tests.sh],
                [chmod +x,-w php/extension/php-for-tests.sh])
AC_CONFIG_FILES([pick-guests.pl],
                [chmod +x,-w pick-guests.pl])
AC_CONFIG_FILES([podwrapper.pl],
                [chmod +x,-w podwrapper.pl])
AC_CONFIG_FILES([run],
                [chmod +x,-w run])

AC_CONFIG_FILES([Makefile
                 align/Makefile
                 appliance/Makefile
                 bash/Makefile
                 builder/Makefile
                 builder/libguestfs.conf
                 builder/opensuse.conf
                 builder/test-config/virt-builder/repos.d/test-index.conf
                 builder/test-simplestreams/virt-builder/repos.d/cirros.conf
                 builder/test-website/virt-builder/repos.d/libguestfs.conf
                 builder/website/Makefile
                 cat/Makefile
                 csharp/Makefile
                 customize/Makefile
                 daemon/Makefile
                 df/Makefile
                 dib/Makefile
                 diff/Makefile
                 docs/Makefile
                 edit/Makefile
                 erlang/Makefile
                 erlang/examples/Makefile
                 examples/Makefile
                 fish/Makefile
                 format/Makefile
                 fuse/Makefile
                 generator/Makefile
                 get-kernel/Makefile
                 gnulib/lib/Makefile
                 gnulib/tests/Makefile
                 gobject/libguestfs-gobject-1.0.pc
                 gobject/Makefile
                 gobject/docs/Makefile
                 gobject/docs/guestfs-docs.sgml
                 golang/Makefile
                 golang/examples/Makefile
                 haskell/Makefile
                 inspector/Makefile
                 java/Makefile
                 java/examples/Makefile
                 lua/Makefile
                 lua/examples/Makefile
                 make-fs/Makefile
                 mllib/Makefile
                 mllib/config.ml
                 ocaml/META
                 ocaml/Makefile
                 ocaml/examples/Makefile
                 p2v/Makefile
                 perl/Build.PL
                 perl/Makefile
                 perl/examples/Makefile
                 php/Makefile
                 po-docs/Makefile
                 po-docs/ja/Makefile
                 po-docs/uk/Makefile
                 po/Makefile
                 python/Makefile
                 python/examples/Makefile
                 python/setup.py
                 rescue/Makefile
                 resize/Makefile
                 ruby/Makefile
                 ruby/Rakefile
                 ruby/examples/Makefile
                 ruby/ext/guestfs/extconf.rb
                 sparsify/Makefile
                 src/Makefile
                 src/libguestfs.pc
                 sysprep/Makefile
                 test-tool/Makefile
                 tests/9p/Makefile
                 tests/bigdirs/Makefile
                 tests/btrfs/Makefile
                 tests/c-api/Makefile
                 tests/charsets/Makefile
                 tests/create/Makefile
                 tests/data/Makefile
                 tests/daemon/Makefile
                 tests/daemon/captive-daemon.pm
                 tests/discard/Makefile
                 tests/disks/Makefile
                 tests/disks/test-qemu-drive-libvirt.xml
                 tests/disk-labels/Makefile
                 tests/events/Makefile
                 tests/fuzz/Makefile
                 tests/guests/Makefile
                 tests/guests/guests.xml
                 tests/hotplug/Makefile
                 tests/http/Makefile
                 tests/journal/Makefile
                 tests/luks/Makefile
                 tests/lvm/Makefile
                 tests/md/Makefile
                 tests/mount-local/Makefile
                 tests/mountable/Makefile
                 tests/nbd/Makefile
                 tests/network/Makefile
                 tests/ntfsclone/Makefile
                 tests/parallel/Makefile
                 tests/protocol/Makefile
                 tests/qemu/Makefile
                 tests/regressions/Makefile
                 tests/relative-paths/Makefile
                 tests/rsync/Makefile
                 tests/selinux/Makefile
                 tests/syslinux/Makefile
                 tests/tmpdirs/Makefile
                 tests/xfs/Makefile
                 tests/xml/Makefile
                 tools/Makefile
                 v2v/Makefile
                 v2v/test-harness/Makefile
                 v2v/test-harness/META])
AC_OUTPUT

dnl Produce summary.
echo
echo
echo "------------------------------------------------------------"
echo "Thank you for downloading $PACKAGE_STRING"
echo
echo "This is how we have configured the optional components for you today:"
echo
echo       "Daemon .............................. $enable_daemon"
echo       "Appliance ........................... $ENABLE_APPLIANCE"
echo       "QEMU ................................ $QEMU $QEMU_OPTIONS"
echo       "guestfish and C-based virt tools .... yes"
echo       "FUSE filesystem ..................... $enable_fuse"
AS_ECHO_N(["GNU gettext for i18n ................ "])
if test "x$HAVE_GNU_GETTEXT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["virt-p2v ............................ "])
if test "x$HAVE_P2V_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["OCaml bindings ...................... "])
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["OCaml-based virt tools .............. "])
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Perl bindings ....................... "])
if test "x$HAVE_PERL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Perl-based virt tools ............... "])
if test "x$HAVE_TOOLS_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Python bindings ..................... "])
if test "x$HAVE_PYTHON_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Ruby bindings ....................... "])
if test "x$HAVE_RUBY_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Java bindings ....................... "])
if test "x$HAVE_JAVA_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Haskell bindings .................... "])
if test "x$HAVE_HASKELL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["PHP bindings ........................ "])
if test "x$HAVE_PHP_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Erlang bindings ..................... "])
if test "x$HAVE_ERLANG_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Lua bindings ........................ "])
if test "x$HAVE_LUA_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Go bindings ......................... "])
if test "x$HAVE_GOLANG_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject bindings .................... "])
if test "x$HAVE_GOBJECT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["gobject introspection ............... "])
if test "x$HAVE_INTROSPECTION_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["bash completion ..................... "])
if test "x$HAVE_BASH_COMPLETION_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo
echo "If any optional component is configured 'no' when you expected 'yes'"
echo "then you should check the preceding messages."
echo
echo "Please report bugs back to the mailing list:"
echo "http://www.redhat.com/mailman/listinfo/libguestfs"
echo
echo "Next you should type 'make' to build the package,"
echo "then 'make check' to run the tests."
echo
echo "Or run 'make help' to list some common targets."
echo "------------------------------------------------------------"
