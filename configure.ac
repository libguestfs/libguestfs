# libguestfs
# Copyright (C) 2009-2010 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# major/minor/release must be numbers
m4_define([libguestfs_major],   [1])
m4_define([libguestfs_minor],   [7])
m4_define([libguestfs_release], [12])
# extra can be any string
m4_define([libguestfs_extra],   [])

AC_INIT([libguestfs],libguestfs_major.libguestfs_minor.libguestfs_release)
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign])

m4_ifndef([AM_SILENT_RULES], [m4_define([AM_SILENT_RULES],[])])
AM_SILENT_RULES([yes]) # make --enable-silent-rules the default.

AC_CONFIG_MACRO_DIR([m4])

dnl Split up the version string.
AC_DEFINE([PACKAGE_VERSION_MAJOR],[libguestfs_major],[Major version number])
AC_DEFINE([PACKAGE_VERSION_MINOR],[libguestfs_minor],[Minor version number])
AC_DEFINE([PACKAGE_VERSION_RELEASE],[libguestfs_release],[Release number])
AC_DEFINE([PACKAGE_VERSION_EXTRA],["libguestfs_extra"],[Extra version string])

dnl Stable or unstable version?
AC_MSG_CHECKING([if this is a stable or unstable branch of libguestfs])
AS_IF([test "$((libguestfs_minor % 2))" -eq 0 ],[
            AC_MSG_RESULT([stable])
       ],[
            AC_MSG_RESULT([unstable])
            AC_MSG_NOTICE([
***
This is a development version of libguestfs. Some APIs may be unstable
until they appear in a stable release of libguestfs (at which point
the C API and ABI is guaranteed to remain stable forever).  For
more information about stable and development branches of libguestfs
please see the section "LIBGUESTFS VERSION NUMBERS" in guestfs(3).
***])
       ])

dnl Die if the user tries to configure as root, see:
dnl https://www.redhat.com/archives/libguestfs/2010-April/msg00098.html
AC_MSG_CHECKING([if you are trying to configure as root])
AS_IF([test "`id -u`" = 0 ],[
            AC_MSG_RESULT([yes])
            AC_MSG_FAILURE([Don't run './configure' or 'make' as root.])
      ],[
            AC_MSG_RESULT([no])
      ])

dnl Early gnulib initialization.
gl_EARLY
gl_INIT

AC_PROG_LIBTOOL

dnl Check for basic C environment.
AC_PROG_CC_STDC
AC_PROG_INSTALL
AC_PROG_CPP

AC_ARG_ENABLE([gcc-warnings],
  [AS_HELP_STRING([--enable-gcc-warnings],
                  [turn on lots of GCC warnings (for developers)])],
  [case $enableval in
     yes|no) ;;
     *)      AC_MSG_ERROR([bad value $enableval for gcc-warnings option]) ;;
   esac
   gl_gcc_warnings=$enableval],
  [gl_gcc_warnings=no]
)

if test "$gl_gcc_warnings" = yes; then
  gl_WARN_ADD([-Werror], [WERROR_CFLAGS])
  AC_SUBST([WERROR_CFLAGS])

  nw=
  # This, $nw, is the list of warnings we disable.
  nw="$nw -Wdeclaration-after-statement" # too useful to forbid
  nw="$nw -Waggregate-return"       # anachronistic
  nw="$nw -Wc++-compat"             # We don't care about C++ compilers
  nw="$nw -Wundef"                  # Warns on '#if GNULIB_FOO' etc in gnulib
  nw="$nw -Wtraditional"            # Warns on #elif which we use often
  nw="$nw -Wcast-qual"              # Too many warnings for now
  nw="$nw -Wconversion"             # Too many warnings for now
  nw="$nw -Wsystem-headers"         # Don't let system headers trigger warnings
  nw="$nw -Wsign-conversion"        # Too many warnings for now
  nw="$nw -Wtraditional-conversion" # Too many warnings for now
  nw="$nw -Wunreachable-code"       # Too many warnings for now
  nw="$nw -Wpadded"                 # Our structs are not padded
  nw="$nw -Wredundant-decls"        # openat.h declares e.g., mkdirat
  nw="$nw -Wlogical-op"             # any use of fwrite provokes this
  nw="$nw -Wvla"                    # two warnings in mount.c
  # things I might fix soon:
  nw="$nw -Wmissing-format-attribute" # daemon.h's asprintf_nowarn
  nw="$nw -Winline"                 # daemon.h's asprintf_nowarn
  nw="$nw -Wshadow"                 # numerous, plus we're not unanimous
  nw="$nw -Wunsafe-loop-optimizations" # just a warning that an optimization
                                    # was not possible, safe to ignore
  nw="$nw -Wpacked"                 # Allow attribute((packed)) on structs
  nw="$nw -Wlong-long"              # Allow long long since it's required
                                    # by Python, Ruby and xstrtoll.

  gl_MANYWARN_ALL_GCC([ws])
  gl_MANYWARN_COMPLEMENT([ws], [$ws], [$nw])
  for w in $ws; do
    gl_WARN_ADD([$w])
  done
  gl_WARN_ADD([-Wno-unused-parameter]) # stubs.c
  gl_WARN_ADD([-Wno-jump-misses-init]) # stubs.c
  gl_WARN_ADD([-Wno-unused-variable]) # FIXME: only temporary, for guestfs_protocol.c, etc

  # In spite of excluding -Wlogical-op above, it is enabled, as of
  # gcc 4.5.0 20090517, and it provokes warnings in cat.c, dd.c, truncate.c
  gl_WARN_ADD([-Wno-logical-op])

  # Work around warning in src/inspect.c.  This seems to be a bug in gcc 4.5.1.
  gl_WARN_ADD([-Wno-strict-overflow])

  gl_WARN_ADD([-fdiagnostics-show-option])

  AC_SUBST([WARN_CFLAGS])

  AC_DEFINE([lint], [1], [Define to 1 if the compiler is checking for lint.])
  AC_DEFINE([_FORTIFY_SOURCE], [2],
    [enable compile-time and run-time bounds-checking, and some warnings])
  AC_DEFINE([GNULIB_PORTCHECK], [1], [enable some gnulib portability checks])
fi

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

dnl Work out how to specify the linker script to the linker.
VERSION_SCRIPT_FLAGS=-Wl,--version-script=
`/usr/bin/ld --help 2>&1 | grep -- --version-script >/dev/null` || \
    VERSION_SCRIPT_FLAGS="-Wl,-M -Wl,"
AC_SUBST(VERSION_SCRIPT_FLAGS)

dnl Check support for 64 bit file offsets.
AC_SYS_LARGEFILE

dnl Check sizeof long.
AC_CHECK_SIZEOF([long])

dnl Define a C symbol for the host CPU architecture.
AC_DEFINE_UNQUOTED([host_cpu],["$host_cpu"],[Host architecture.])

dnl Headers.
AC_CHECK_HEADERS([errno.h sys/types.h sys/un.h sys/wait.h sys/socket.h endian.h byteswap.h])

dnl Functions.
AC_CHECK_FUNCS([posix_fallocate])

dnl Build the daemon?
AC_MSG_CHECKING([if we should build the daemon])
AC_ARG_ENABLE([daemon],
        [AS_HELP_STRING([--enable-daemon],
          [enable building the daemon @<:@default=yes@:>@])],
        [],
        [enable_daemon=yes])
AM_CONDITIONAL([ENABLE_DAEMON],[test "x$enable_daemon" = "xyes"])
AC_MSG_RESULT([$enable_daemon])

dnl Build the appliance?
AC_MSG_CHECKING([if we should build the appliance])
AC_ARG_ENABLE([appliance],
        [AS_HELP_STRING([--enable-appliance],
          [enable building the appliance @<:@default=yes@:>@])],
        [],
        [enable_appliance=yes])
AM_CONDITIONAL([ENABLE_APPLIANCE],[test "x$enable_appliance" = "xyes"])
AC_MSG_RESULT([$enable_appliance])

dnl Check for rpcgen and XDR library.  rpcgen is optional.
AC_CHECK_PROG([RPCGEN],[rpcgen],[rpcgen],[no])
AM_CONDITIONAL([HAVE_RPCGEN],[test "x$RPCGEN" != "xno"])
AC_CHECK_LIB([portablexdr],[xdrmem_create],[],[
        AC_SEARCH_LIBS([xdrmem_create],[rpc xdr nsl])
        ])

dnl Check for cpio which isn't in the default Pardus install amazingly.
AC_CHECK_PROG([CPIO],[cpio],[cpio],[no])
test "x$CPIO" = "xno" &&
     AC_MSG_ERROR([cpio must be installed])

dnl Check for gperf.
AC_CHECK_PROG([GPERF],[gperf],[gperf],[no])
test "x$GPERF" = "xno" &&
     AC_MSG_ERROR([gperf must be installed])

dnl Check for pod2man and pod2text.
AC_CHECK_PROG([POD2MAN],[pod2man],[pod2man],[no])
test "x$POD2MAN" = "xno" &&
     AC_MSG_ERROR([pod2man must be installed])
AC_CHECK_PROG([POD2TEXT],[pod2text],[pod2text],[no])
test "x$POD2TEXT" = "xno" &&
     AC_MSG_ERROR([pod2text must be installed])

dnl Check for mkisofs.
AC_PATH_PROGS([MKISOFS],[mkisofs],[no],
        [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin])
test "x$MKISOFS" = "xno" && AC_MSG_ERROR([mkisofs must be installed])

dnl Check for optional xmllint.
AC_CHECK_PROG([XMLLINT],[xmllint],[xmllint],[no])
AM_CONDITIONAL([HAVE_XMLLINT],[test "x$XMLLINT" != "xno"])

dnl po4a for translating man pages and POD files (optional).
AC_CHECK_PROG([PO4A],[po4a],[po4a],[no])
AM_CONDITIONAL([HAVE_PO4A], [test "x$PO4A" != "xno"])

dnl Check for QEMU for running binaries on this $host_cpu, fall
dnl back to basic 'qemu'.  Allow the user to override it.
default_qemu="qemu-kvm kvm qemu-system-$host_cpu qemu"
AC_ARG_WITH([qemu],
        [AS_HELP_STRING([--with-qemu],
          [set default QEMU binary @<:@default=[qemu-kvm] qemu-system-<host> qemu@:>@])],
        [],
        [with_qemu="$default_qemu"])
AC_PATH_PROGS([QEMU],[$with_qemu],[no],
        [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/sbin$PATH_SEPARATOR/usr/libexec])
test "x$QEMU" = "xno" && AC_MSG_ERROR([qemu must be installed])
AC_DEFINE_UNQUOTED([QEMU],["$QEMU"],[Location of qemu binary.])

dnl Check that the chosen qemu has virtio-serial support.
if test "x$vmchannel_test" != "xno"; then
    AC_MSG_CHECKING([for virtio-serial support in $QEMU])
    if $QEMU -nographic -device \? 2>&1 | grep -sq virtio-serial; then
        AC_MSG_RESULT([yes])
        vmchannel_guestfwd=guestfwd
    else
        AC_MSG_RESULT([no])
        AC_MSG_FAILURE(
[I did not find virtio-serial support in
$QEMU.

virtio-serial support in qemu or KVM is essential for libguestfs
to operate.

Usually this means that you have to install a newer version of qemu
and/or KVM.  Please read the relevant section in the README file for
more information about this.

You can override this test by setting the environment variable
vmchannel_test=no  However if you don't have the right support
in your qemu, then this just delays the pain.

If I am using the wrong qemu or you want to compile qemu from source
and install it in another location, then you should configure with
the --with-qemu option.
])
    fi
fi

dnl Set default drive interface used by the guestfs_add_drive_opts call
dnl ('-drive ...,if=...' option to qemu).
dnl
dnl If you encounter performance problems with virtio (RHBZ#509383)
dnl then try '--with-drive-if=ide'.
AC_ARG_WITH([drive-if],
        [AS_HELP_STRING([--with-drive-if],
          [set default driver (ide|scsi|virtio) @<:@default=virtio@:>@])],
        [],
        [with_drive_if=virtio])
AC_DEFINE_UNQUOTED([DRIVE_IF],["$with_drive_if"],[Default drive interface.])

dnl Set interface used by the network.  Normally you should
dnl leave this at the default (virtio-net-pci) but you can use the
dnl alternative (ne2k_pci) because of bugs in virtio networking
dnl eg. https://bugzilla.redhat.com/show_bug.cgi?id=516022
AC_ARG_WITH([net-if],
        [AS_HELP_STRING([--with-net-if],
          [set default net driver (virtio-net-pci|ne2k_pci) @<:@default=virtio-net-pci@:>@])],
        [],
        [with_net_if=virtio-net-pci])
AC_DEFINE_UNQUOTED([NET_IF],["$with_net_if"],[Default network interface.])

dnl Check for febootstrap etc.
if test "x$enable_appliance" = "xyes"; then
    AC_CHECK_PROG([FEBOOTSTRAP],
                  [febootstrap],[febootstrap],[no])
    if test "x$FEBOOTSTRAP" != "xno"; then
      AC_CHECK_PROG([FEBOOTSTRAP_RUN],
                    [febootstrap-run],[febootstrap-run],[no])
      test "x$FEBOOTSTRAP_RUN" = "xno" && \
          AC_MSG_ERROR([febootstrap-run must be installed])
      AC_CHECK_PROG([FEBOOTSTRAP_INSTALL],
                    [febootstrap-install],[febootstrap-install],[no])
      test "x$FEBOOTSTRAP_INSTALL" = "xno" && \
          AC_MSG_ERROR([febootstrap-install must be installed])
      AC_CHECK_PROG([FEBOOTSTRAP_MINIMIZE],
                    [febootstrap-minimize],[febootstrap-minimize],[no])
      test "x$FEBOOTSTRAP_MINIMIZE" = "xno" && \
          AC_MSG_ERROR([febootstrap-minimize must be installed])
      AC_CHECK_PROG([FEBOOTSTRAP_TO_INITRAMFS],
                    [febootstrap-to-initramfs],[febootstrap-to-initramfs],[no])
      test "x$FEBOOTSTRAP_TO_INITRAMFS" = "xno" && \
          AC_MSG_ERROR([febootstrap-to-initramfs must be installed])
      AC_CHECK_PROG([FEBOOTSTRAP_TO_SUPERMIN],
                    [febootstrap-to-supermin],[febootstrap-to-supermin],[no])
      test "x$FEBOOTSTRAP_TO_SUPERMIN" = "xno" && \
          AC_MSG_ERROR([febootstrap-to-supermin must be installed])

      dnl Check we have fakechroot >= 2.9 (it's an indirect requirement
      dnl of febootstrap, but old versions will fail with yum).
      AC_CHECK_PROG([FAKECHROOT],
                    [fakechroot],[fakechroot],[no])
      test "x$FAKECHROOT" = "xno" && \
         AC_MSG_ERROR([fakechroot must be installed])

      AC_MSG_CHECKING([fakechroot version])
      fakechroot_version=`$FAKECHROOT --version | awk '{print $3}'`
      if test -z "$fakechroot_version"; then
        AC_MSG_RESULT([failed])
        AC_MSG_WARN([fakechroot --version command failed, proceeding anyway])
      else
        AC_MSG_RESULT([$fakechroot_version])
        fakechroot_major=`echo "$fakechroot_version" | awk -F. '{print $1}'`
        fakechroot_minor=`echo "$fakechroot_version" | awk -F. '{print $2}'`
        if test "$fakechroot_major" -lt 2 || \
          ( test "$fakechroot_major" -eq 2 && test "$fakechroot_minor" -lt 9 ); then
          AC_MSG_ERROR([fakechroot version must be >= 2.9])
        fi
      fi
      DIST="REDHAT"
    else
      # check for debootstrap and debirf
      AC_CHECK_PROG([DEBOOTSTRAP],
                    [debootstrap],[debootstrap],[no])
      test "x$DEBOOTSTRAP" = "xno" && \
          AC_MSG_ERROR([Either febootstrap or debootstrap must be installed])
      AC_CHECK_PROG([DEBIRF],[debirf],[debirf],[no])
      test "x$DEBIRF" = "xno" &&
          AC_MSG_ERROR([debirf must be installed])
      DIST="DEBIAN"
      case "$host_cpu" in
      *86)
          DEBIAN_KERNEL_ARCH=486
          ;;
      x86_64)
          DEBIAN_KERNEL_ARCH=amd64
          ;;
      *)
         DEBIAN_KERNEL_ARCH=$host_cpu
         ;;
      esac
      AC_SUBST(DEBIAN_KERNEL_ARCH)
    fi
    AC_SUBST(DIST)

    dnl --with-updates to specify a Fedora updates repository.
    AC_ARG_WITH([updates],
        [AS_HELP_STRING([--with-updates],
          [set name of Fedora updates repository @<:@default=updates-released-f12@:>@])],
        [],
        [with_updates=updates-released-f12])
    UPDATES="$with_updates"
    AC_SUBST(UPDATES)

    dnl --with-mirror to specify a local Fedora mirror.
    AC_ARG_WITH([mirror],
        [AS_HELP_STRING([--with-mirror],
          [set URI of a local Fedora mirror])],
        [],
        [with_mirror=])
    MIRROR="$with_mirror"
    AC_SUBST(MIRROR)
fi

dnl --with-repo to specify a repository.
AC_ARG_WITH([repo],
        [AS_HELP_STRING([--with-repo],
          [set name of Fedora repository @<:@default=fedora-13@:>@])],
        [],
        [with_repo=fedora-13])
REPO="$with_repo"
AC_SUBST(REPO)
AC_DEFINE_UNQUOTED([REPO],["$REPO"],[Name of software repository.])

dnl Build the supermin appliance?  Please see README file before
dnl enabling this option.
AC_ARG_ENABLE([supermin],
        [AS_HELP_STRING([--enable-supermin],
          [enable supermin appliance (see README) @<:@default=no@:>@])],
        [AC_DEFINE([ENABLE_SUPERMIN],[1],[Supermin appliance enabled.])],
        [enable_supermin=no])
AM_CONDITIONAL([SUPERMIN],[test "x$enable_supermin" = "xyes"])

dnl Enable packet dumps when in verbose mode.  This generates lots
dnl of debug info, only useful for people debugging the RPC mechanism.
AC_ARG_ENABLE([packet-dump],
        [AS_HELP_STRING([--enable-packet-dump],
          [enable packet dumps in verbose mode @<:@default=no@:>@])],
        [AC_DEFINE([ENABLE_PACKET_DUMP],[1],[Enable packet dumps in verbose mode.])],
        [])

dnl Readline.
AC_ARG_WITH([readline],
    [AS_HELP_STRING([--with-readline],
        [support fancy command line editing @<:@default=check@:>@])],
    [],
    [with_readline=check])

LIBREADLINE=
AS_IF([test "x$with_readline" != xno],
    [AC_CHECK_LIB([readline], [main],
        [AC_SUBST([LIBREADLINE], ["-lreadline -lncurses"])
         AC_DEFINE([HAVE_LIBREADLINE], [1],
                   [Define if you have libreadline])
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

dnl For i18n.
AM_GNU_GETTEXT([external])
AM_GNU_GETTEXT_VERSION([0.17])

dnl libmagic (highly recommended)
AC_CHECK_LIB([magic],[magic_file],
        [AC_CHECK_HEADER([magic.h],
                [AC_SUBST([MAGIC_LIBS], ["-lmagic"])
                 AC_DEFINE([HAVE_LIBMAGIC],[1],[libmagic found at compile time.])
                ], [])
        ],
        [AC_MSG_WARN([libmagic not found, some core features will be disabled])])

dnl Check for PCRE (highly recommended)
PKG_CHECK_MODULES([PCRE], [libpcre],
        [AC_SUBST([PCRE_CFLAGS])
         AC_SUBST([PCRE_LIBS])
         AC_DEFINE([HAVE_PCRE],[1],[PCRE found at compile time.])
        ],
        [AC_MSG_WARN([PCRE not found, some core features will be disabled])])

dnl libvirt (highly recommended)
PKG_CHECK_MODULES([LIBVIRT], [libvirt],
        [AC_SUBST([LIBVIRT_CFLAGS])
         AC_SUBST([LIBVIRT_LIBS])
         AC_DEFINE([HAVE_LIBVIRT],[1],[libvirt found at compile time.])
        ],
        [AC_MSG_WARN([libvirt not found, some core features will be disabled])])
AM_CONDITIONAL([HAVE_LIBVIRT],[test "x$LIBVIRT_LIBS" != "x"])

dnl libxml2 (highly recommended)
PKG_CHECK_MODULES([LIBXML2], [libxml-2.0],
        [AC_SUBST([LIBXML2_CFLAGS])
         AC_SUBST([LIBXML2_LIBS])
         AC_DEFINE([HAVE_LIBXML2],[1],[libxml2 found at compile time.])
        ],
        [AC_MSG_WARN([libxml2 not found, some core features will be disabled])])
AM_CONDITIONAL([HAVE_LIBXML2],[test "x$LIBXML2_LIBS" != "x"])

dnl hivex library (highly recommended)
dnl This used to be a part of libguestfs, but was spun off into its
dnl own separate upstream project in libguestfs 1.0.85.
PKG_CHECK_MODULES([HIVEX], [hivex],
        [AC_SUBST([HIVEX_CFLAGS])
         AC_SUBST([HIVEX_LIBS])
         AC_DEFINE([HAVE_HIVEX],[1],[hivex library found at compile time.])
        ],
        [AC_MSG_WARN([hivex not found, some core features will be disabled])])

dnl FUSE is optional to build the FUSE module.
AC_ARG_ENABLE([fuse],
        AS_HELP_STRING([--disable-fuse], [Disable FUSE (guestmount) support]),
        [],
        [enable_fuse=yes])
AS_IF([test "x$enable_fuse" != "xno"],
        [PKG_CHECK_MODULES([FUSE],[fuse],,[
                enable_fuse=no
                AC_MSG_WARN([FUSE library and headers are missing, so optional FUSE module won't be built])])])
AM_CONDITIONAL([HAVE_FUSE],[test "x$enable_fuse" != "xno"])

dnl Check for OCaml (optional, for OCaml bindings).
OCAMLC=no
OCAMLFIND=no
AC_ARG_ENABLE([ocaml],
        AS_HELP_STRING([--disable-ocaml], [Disable OCaml language bindings]),
        [],
        [enable_ocaml=yes])
AS_IF([test "x$enable_ocaml" != "xno"],
        [dnl OCAMLC and OCAMLFIND have to be unset first, otherwise
         dnl AC_CHECK_TOOL (inside AC_PROG_OCAML) will not look.
         OCAMLC=
         OCAMLFIND=
         AC_PROG_OCAML
         AC_PROG_FINDLIB
        ])
AM_CONDITIONAL([HAVE_OCAML],
               [test "x$OCAMLC" != "xno" && test "x$OCAMLFIND" != "xno"])

dnl Check for Perl (optional, for Perl bindings).
PERL=no
AC_ARG_ENABLE([perl],
        AS_HELP_STRING([--disable-perl], [Disable Perl language bindings]),
        [],
        [enable_perl=yes])
AS_IF([test "x$enable_perl" != "xno"],
        [
        PERL=
        AC_CHECK_PROG([PERL],[perl],[perl],[no])

        dnl Check for Perl modules that must be present to compile and
        dnl test the Perl bindings.
        missing_perl_modules=no
        for pm in Test::More ExtUtils::MakeMaker; do
            AC_MSG_CHECKING([for $pm])
            if ! perl -M$pm -e1 >/dev/null 2>&1; then
                AC_MSG_RESULT([no])
                missing_perl_modules=yes
            else
                AC_MSG_RESULT([yes])
            fi
        done
        if test "x$missing_perl_modules" = "xyes"; then
            AC_MSG_WARN([some Perl modules required to compile or test the Perl bindings are missing])
        fi
        ])
AM_CONDITIONAL([HAVE_PERL],
    [test "x$PERL" != "xno" && test "x$missing_perl_modules" != "xyes"])

dnl Check for Python (optional, for Python bindings).
PYTHON_PREFIX=
PYTHON_VERSION=
PYTHON_INCLUDEDIR=
PYTHON_SITE_PACKAGES=

AC_ARG_ENABLE([python],
        AS_HELP_STRING([--disable-python], [Disable Python language bindings]),
        [],
        [enable_python=yes])
AS_IF([test "x$enable_python" != "xno"],
        [
        AC_CHECK_PROG([PYTHON],[python],[python],[no])

        if test "x$PYTHON" != "xno"; then
            PYTHON_PREFIX=`$PYTHON -c "import sys; print sys.prefix"`
            PYTHON_VERSION=`$PYTHON -c "import sys; print sys.version[[0:3]]"`
            for d in \
                $PYTHON_PREFIX/include/python$PYTHON_VERSION \
                /usr/include/python$PYTHON_VERSION \
                /usr/local/include/python$PYTHON_VERSION
            do
                AC_MSG_CHECKING([Python.h in $d])
                if test -r "$d/Python.h"; then
                    AC_MSG_RESULT([found])
                    PYTHON_INCLUDEDIR=$d
                    break
                fi
                AC_MSG_RESULT([not found])
            done
            if test "x$PYTHON_INCLUDEDIR" = "x"; then
                AC_MSG_WARN([Python include directory not found])
            fi

            for d in \
                $PYTHON_PREFIX/lib64/python$PYTHON_VERSION/site-packages \
                $PYTHON_PREFIX/lib/python$PYTHON_VERSION/site-packages \
                /usr/lib64/python$PYTHON_VERSION/site-packages \
                /usr/lib/python$PYTHON_VERSION/site-packages \
                /usr/local/lib/python$PYTHON_VERSION/site-packages
            do
                AC_MSG_CHECKING([for $d])
                if test -d "$d"; then
                    AC_MSG_RESULT([found])
                    PYTHON_SITE_PACKAGES=$d
                    break
                fi
                AC_MSG_RESULT([not found])
            done
            if test "x$PYTHON_SITE_PACKAGES" = "x"; then
                AC_MSG_WARN([Python site-packages directory not found])
            fi

            old_LIBS="$LIBS"
            LIBS="$LIBS -lpython$PYTHON_VERSION"
            AC_CHECK_FUNCS([PyCapsule_New])
            LIBS="$old_LIBS"
        fi

        AC_SUBST(PYTHON_PREFIX)
        AC_SUBST(PYTHON_VERSION)
        AC_SUBST(PYTHON_INCLUDEDIR)
        AC_SUBST(PYTHON_SITE_PACKAGES)
        ])
AM_CONDITIONAL([HAVE_PYTHON],
    [test "x$PYTHON_INCLUDEDIR" != "x" && test "x$PYTHON_SITE_PACKAGES" != "x"])

dnl Check for Ruby and rake (optional, for Ruby bindings).
AC_ARG_ENABLE([ruby],
        AS_HELP_STRING([--disable-ruby], [Disable Ruby language bindings]),
        [],
        [enable_ruby=yes])
AS_IF([test "x$enable_ruby" != "xno"],
        [
        AC_CHECK_LIB([ruby],[ruby_init],[HAVE_LIBRUBY=1],[HAVE_LIBRUBY=0])
        AC_CHECK_PROG([RAKE],[rake],[rake],[no])
        ])
AM_CONDITIONAL([HAVE_RUBY],
    [test "x$RAKE" != "xno" && test -n "$HAVE_LIBRUBY"])

dnl Check for Java.
AC_ARG_WITH(java_home,
    [AS_HELP_STRING([--with-java-home],
        [specify path to JDK directory @<:@default=check@:>@])],
    [],
    [with_java_home=check])

if test "x$with_java_home" != "xno"; then
    if test "x$with_java_home" != "xyes" && test "x$with_java_home" != "xcheck"
    then
        # Reject unsafe characters in $JAVA_HOME
        jh_lf='
'
        case $JAVA_HOME in
          *[\\\"\#\$\&\'\`$jh_lf\ \	]*)
            AC_MSG_FAILURE([unsafe \$JAVA_HOME directory (use --with-java-home=no to disable Java support)]);;
        esac
        if test -d "$with_java_home"; then
            JAVA_HOME="$with_java_home"
        else
            AC_MSG_FAILURE([$with_java_home is not a directory (use --with-java-home=no to disable Java support)])
        fi
    fi

    if test "x$JAVA_HOME" = "x"; then
        # Look for Java in some likely locations.
        for d in \
            /usr/lib/jvm/java \
            /usr/lib/jvm/java-6-openjdk
        do
            if test -d $d && test -f $d/bin/java; then
                JAVA_HOME=$d
                break
            fi
        done
    fi

    if test "x$JAVA_HOME" != "x"; then
        AC_MSG_CHECKING(for JDK in $JAVA_HOME)
        if test ! -x "$JAVA_HOME/bin/java"; then
            AC_MSG_ERROR([missing $JAVA_HOME/bin/java binary (use --with-java-home=no to disable Java support)])
        else
            JAVA="$JAVA_HOME/bin/java"
        fi
        if test ! -x "$JAVA_HOME/bin/javac"; then
            AC_MSG_ERROR([missing $JAVA_HOME/bin/javac binary])
        else
            JAVAC="$JAVA_HOME/bin/javac"
        fi
        if test ! -x "$JAVA_HOME/bin/javah"; then
            AC_MSG_ERROR([missing $JAVA_HOME/bin/javah binary])
        else
            JAVAH="$JAVA_HOME/bin/javah"
        fi
        if test ! -x "$JAVA_HOME/bin/javadoc"; then
            AC_MSG_ERROR([missing $JAVA_HOME/bin/javadoc binary])
        else
            JAVADOC="$JAVA_HOME/bin/javadoc"
        fi
        if test ! -x "$JAVA_HOME/bin/jar"; then
            AC_MSG_ERROR([missing $JAVA_HOME/bin/jar binary])
        else
            JAR="$JAVA_HOME/bin/jar"
        fi
        java_version=`$JAVA -version 2>&1 | grep "java version"`
        AC_MSG_RESULT(found $java_version in $JAVA_HOME)

        dnl Find jni.h.
        AC_MSG_CHECKING([for jni.h])
        if test -f "$JAVA_HOME/include/jni.h"; then
            JNI_CFLAGS="-I$JAVA_HOME/include"
        else
            if test "`find $JAVA_HOME -name jni.h`" != ""; then
                head=`find $JAVA_HOME -name jni.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="-I$dir"
            else
                AC_MSG_FAILURE([missing jni.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Find jni_md.h.
        AC_MSG_CHECKING([for jni_md.h])
        case "$build_os" in
        *linux*) system="linux" ;;
        *SunOS*) system="solaris" ;;
        *cygwin*) system="win32" ;;
        *) system="$build_os" ;;
        esac
        if test -f "$JAVA_HOME/include/$system/jni_md.h"; then
            JNI_CFLAGS="$JNI_CFLAGS -I$JAVA_HOME/include/$system"
        else
            if test "`find $JAVA_HOME -name jni_md.h`" != ""; then
                head=`find $JAVA_HOME -name jni_md.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="$JNI_CFLAGS -I$dir"
            else
                AC_MSG_FAILURE([missing jni_md.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Need extra version flag?
        AC_MSG_CHECKING([extra javac flags])
        JAVAC_FLAGS=
        javac_version=`$JAVAC -version 2>&1`
        case "$javac_version" in
        *Eclipse*)
            JAVAC_FLAGS="-source 1.5" ;;
        esac
        AC_MSG_RESULT([$JAVAC_FLAGS])

        dnl Where to install jarfiles.
        dnl XXX How to make it configurable?
        JAR_INSTALL_DIR=\${prefix}/share/java
        JNI_INSTALL_DIR=\${libdir}

        dnl JNI version.
        jni_major_version=`echo "$VERSION" | awk -F. '{print $1}'`
        jni_minor_version=`echo "$VERSION" | awk -F. '{print $2}'`
        jni_micro_version=`echo "$VERSION" | awk -F. '{print $3}'`
        JNI_VERSION_INFO=`expr "$jni_major_version" + "$jni_minor_version"`":$jni_micro_version:$jni_minor_version"
    fi
fi

AC_SUBST(JAVA_HOME)
AC_SUBST(JAVA)
AC_SUBST(JAVAC)
AC_SUBST(JAVAH)
AC_SUBST(JAVADOC)
AC_SUBST(JAR)
AC_SUBST(JNI_CFLAGS)
AC_SUBST(JAVAC_FLAGS)
AC_SUBST(JAR_INSTALL_DIR)
AC_SUBST(JNI_INSTALL_DIR)
AC_SUBST(JNI_VERSION_INFO)

AM_CONDITIONAL([HAVE_JAVA],[test -n "$JAVAC"])

dnl Check for Haskell (GHC).
GHC=no
AC_ARG_ENABLE([haskell],
        AS_HELP_STRING([--disable-haskell], [Disable Haskell language bindings]),
        [],
        [enable_haskell=yes])
AS_IF([test "x$enable_haskell" != "xno"],
        [
        GHC=
        AC_CHECK_PROG([GHC],[ghc],[ghc],[no])
        ])
AM_CONDITIONAL([HAVE_HASKELL],
    [test "x$GHC" != "xno"])

dnl PHP
PHP=no
AC_ARG_ENABLE([php],
        AS_HELP_STRING([--disable-php], [Disable PHP language bindings]),
        [],
        [enable_php=yes])
AS_IF([test "x$enable_php" != "xno"],
        [
        PHP=
        AC_CHECK_PROG([PHP],[php],[php],[no])
        AC_CHECK_PROG([PHPIZE],[phpize],[phpize],[no])
        ])
AM_CONDITIONAL([HAVE_PHP], [test "x$PHP" != "xno" && test "x$PHPIZE" != "xno"])

dnl Check for Perl modules needed by Perl virt tools (virt-df, etc.)
AS_IF([test "x$PERL" != "xno"],
        [
        missing_perl_modules=no
        for pm in Pod::Usage Getopt::Long Sys::Virt Data::Dumper Locale::TextDomain Win::Hivex Win::Hivex::Regedit; do
            AC_MSG_CHECKING([for $pm])
            if ! $PERL -M$pm -e1 >/dev/null 2>&1; then
                AC_MSG_RESULT([no])
                missing_perl_modules=yes
            else
                AC_MSG_RESULT([yes])
            fi
        done
        if test "x$missing_perl_modules" = "xyes"; then
            AC_MSG_WARN([some Perl modules required to compile the Perl virt-* tools are missing])
        fi
        ])

AM_CONDITIONAL([HAVE_TOOLS],
    [test "x$PERL" != "xno" && test "x$missing_perl_modules" != "xyes"])

dnl Library versioning.
MAX_PROC_NR=`cat $srcdir/src/MAX_PROC_NR`
AC_SUBST(MAX_PROC_NR)

dnl Run in subdirs.
if test "x$enable_daemon" = "xyes"; then
    AC_CONFIG_SUBDIRS([daemon])
fi

dnl Produce output files.
AC_CONFIG_HEADERS([config.h])
dnl http://www.mail-archive.com/automake@gnu.org/msg10204.html
AC_CONFIG_FILES([appliance/update.sh],
                [chmod +x appliance/update.sh])
AC_CONFIG_FILES([Makefile
                 generator/Makefile
                 src/Makefile fish/Makefile po/Makefile.in examples/Makefile
                 appliance/Makefile
                 appliance/debian/debirf.conf
                 images/Makefile
                 capitests/Makefile
                 regressions/Makefile
                 test-tool/Makefile
                 ocaml/Makefile ocaml/examples/Makefile
                 perl/Makefile
                 python/Makefile
                 ruby/Makefile ruby/Rakefile
                 java/Makefile
                 haskell/Makefile
                 inspector/Makefile
                 tools/Makefile
                 libguestfs.pc
                 gnulib/lib/Makefile
                 gnulib/tests/Makefile
                 fuse/Makefile
                 po-docs/Makefile
                 po-docs/ja/Makefile
                 php/Makefile
                 csharp/Makefile
                 cat/Makefile
                 ocaml/META perl/Makefile.PL])
AC_OUTPUT

dnl Produce summary.
echo
echo
echo "------------------------------------------------------------"
echo "Thank you for downloading $PACKAGE_STRING"
echo
echo "This is how we have configured the optional components for you today:"
echo
echo    "Daemon .............................. $enable_daemon"
echo    "Appliance ........................... $enable_appliance"
echo    "QEMU ................................ $QEMU"
echo -n "OCaml bindings ...................... "
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "Perl bindings ....................... "
if test "x$HAVE_PERL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "Python bindings ..................... "
if test "x$HAVE_PYTHON_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "Ruby bindings ....................... "
if test "x$HAVE_RUBY_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "Java bindings ....................... "
if test "x$HAVE_JAVA_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "Haskell bindings .................... "
if test "x$HAVE_HASKELL_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "PHP bindings ........................ "
if test "x$HAVE_PHP_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo -n "virt-* tools ........................ "
if test "x$HAVE_TOOLS_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo "supermin appliance .................. $enable_supermin"
echo "FUSE filesystem ..................... $enable_fuse"
echo
echo "If any optional component is configured 'no' when you expected 'yes'"
echo "then you should check the preceeding messages."
echo
echo "Please report bugs back to the mailing list:"
echo "http://www.redhat.com/mailman/listinfo/libguestfs"
echo
echo "Next you should type 'make' to build the package,"
echo "then 'make check' to run the tests."
echo "------------------------------------------------------------"
