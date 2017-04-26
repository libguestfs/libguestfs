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

# The major, minor, and release fields MUST be numbers.  Packagers can
# add extra information using --with-extra="..." which may be any
# freeform string.
m4_define([libguestfs_major],   [1])
m4_define([libguestfs_minor],   [37])
m4_define([libguestfs_release], [12])

AC_INIT([libguestfs],libguestfs_major.libguestfs_minor.libguestfs_release)

dnl The date that the above version was released.  This is used in
dnl the website 'index.html' file.
AC_SUBST([RELEASE_DATE], [2017-04-25])

AC_CONFIG_AUX_DIR([build-aux])
AC_REQUIRE_AUX_FILE([guestfs-test-driver])

dnl Initialize automake.
AM_INIT_AUTOMAKE(foreign subdir-objects tar-pax) dnl NB: Do not [quote] this parameter.

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

dnl Check for FUSE.
m4_include([m4/guestfs_fuse.m4])

dnl The daemon and any dependencies.
m4_include([m4/guestfs_daemon.m4])

dnl The appliance and any dependencies.
m4_include([m4/guestfs_appliance.m4])

dnl Check for QEMU.
m4_include([m4/guestfs_qemu.m4])

dnl Miscellaneous libraries used by other programs.
m4_include([m4/guestfs_misc_libraries.m4])

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

dnl Miscellaneous configuration that doesn't fit anywhere else.
m4_include([m4/guestfs_misc.m4])

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
    ocaml/t

dnl http://www.mail-archive.com/automake@gnu.org/msg10204.html
AC_CONFIG_FILES([appliance/libguestfs-make-fixed-appliance],
                [chmod +x,-w appliance/libguestfs-make-fixed-appliance])
AC_CONFIG_FILES([inspector/test-xmllint.sh],
                [chmod +x,-w inspector/test-xmllint.sh])
AC_CONFIG_FILES([inspector/test-virt-inspector.sh],
                [chmod +x,-w inspector/test-virt-inspector.sh])
AC_CONFIG_FILES([installcheck.sh],
                [chmod +x,-w installcheck.sh])
AC_CONFIG_FILES([p2v/virt-p2v-make-disk],
                [chmod +x,-w p2v/virt-p2v-make-disk])
AC_CONFIG_FILES([p2v/virt-p2v-make-kickstart],
                [chmod +x,-w p2v/virt-p2v-make-kickstart])
AC_CONFIG_FILES([p2v/virt-p2v-make-kiwi],
                [chmod +x,-w p2v/virt-p2v-make-kiwi])
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
                 builder/templates/Makefile
                 builder/test-config/virt-builder/repos.d/test-index.conf
                 builder/test-simplestreams/virt-builder/repos.d/cirros.conf
                 builder/test-website/virt-builder/repos.d/libguestfs.conf
                 cat/Makefile
                 common/errnostring/Makefile
                 common/edit/Makefile
                 common/miniexpect/Makefile
                 common/options/Makefile
                 common/parallel/Makefile
                 common/progress/Makefile
                 common/protocol/Makefile
                 common/qemuopts/Makefile
                 common/utils/Makefile
                 common/visit/Makefile
                 common/windows/Makefile
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
                 lib/Makefile
                 lib/libguestfs.pc
                 lua/Makefile
                 lua/examples/Makefile
                 make-fs/Makefile
                 mllib/Makefile
                 mllib/guestfs_config.ml
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
                 python/t/tests_helper.py
                 rescue/Makefile
                 resize/Makefile
                 ruby/Makefile
                 ruby/Rakefile
                 ruby/examples/Makefile
                 ruby/ext/guestfs/extconf.rb
                 sparsify/Makefile
                 sysprep/Makefile
                 test-data/Makefile
                 test-data/binaries/Makefile
                 test-data/blank-disks/Makefile
                 test-data/fake-virtio-win/Makefile
                 test-data/fake-virt-tools/Makefile
                 test-data/files/Makefile
                 test-data/phony-guests/Makefile
                 test-data/phony-guests/guests.xml
                 test-tool/Makefile
                 tests/9p/Makefile
                 tests/bigdirs/Makefile
                 tests/btrfs/Makefile
                 tests/c-api/Makefile
                 tests/charsets/Makefile
                 tests/create/Makefile
                 tests/daemon/Makefile
                 tests/daemon/captive-daemon.pm
                 tests/discard/Makefile
                 tests/disks/Makefile
                 tests/disks/test-qemu-drive-libvirt.xml
                 tests/disk-labels/Makefile
                 tests/events/Makefile
                 tests/gdisk/Makefile
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
                 tests/ntfs/Makefile
                 tests/parallel/Makefile
                 tests/protocol/Makefile
                 tests/qemu/Makefile
                 tests/regressions/Makefile
                 tests/relabel/Makefile
                 tests/relative-paths/Makefile
                 tests/rsync/Makefile
                 tests/selinux/Makefile
                 tests/syslinux/Makefile
                 tests/tmpdirs/Makefile
                 tests/tsk/Makefile
                 tests/xfs/Makefile
                 tests/xml/Makefile
                 tests/yara/Makefile
                 tools/Makefile
                 utils/boot-analysis/Makefile
                 utils/boot-benchmark/Makefile
                 utils/qemu-boot/Makefile
                 utils/qemu-speed-test/Makefile
                 v2v/Makefile
                 v2v/test-harness/Makefile
                 v2v/test-harness/META
                 website/index.html])
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
