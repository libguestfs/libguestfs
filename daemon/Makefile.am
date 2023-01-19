# libguestfs-daemon
# Copyright (C) 2011 Red Hat Inc.
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

include $(top_srcdir)/subdir-rules.mk

BUILT_SOURCES = \
	actions.h \
	caml-stubs.c \
	dispatch.c \
	names.c \
	lvm-tokenization.c \
	structs-cleanups.c \
	structs-cleanups.h \
	stubs-0.c \
	stubs-1.c \
	stubs-2.c \
	stubs-3.c \
	stubs-4.c \
	stubs-5.c \
	stubs-6.c \
	stubs.h

generator_built = \
	$(BUILT_SOURCES) \
	blkid.mli \
	btrfs.mli \
	callbacks.ml \
	cryptsetup.mli \
	devsparts.mli \
	file.mli \
	filearch.mli \
	findfs.mli \
	inspect.mli \
	is.mli \
	isoinfo.mli \
	ldm.mli \
	link.mli \
	listfs.mli \
	lvm.mli \
	lvm_dm.mli \
	md.mli \
	mount.mli \
	optgroups.ml \
	optgroups.mli \
	parted.mli \
	realpath.mli \
	rpm.mli \
	statvfs.mli \
	structs.ml \
	structs.mli

CONFIGURE_GENERATED_ML = \
	daemon_config.ml

EXTRA_DIST = \
	$(generator_built) \
	$(SOURCES_MLI) \
	$(filter-out $(CONFIGURE_GENERATED_ML),$(SOURCES_ML)) \
	daemon_utils_tests.ml \
	guestfsd.pod

if INSTALL_DAEMON
sbin_PROGRAMS = guestfsd
else
noinst_PROGRAMS = guestfsd
endif

guestfsd_SOURCES = \
	../common/errnostring/errnostring.h \
	../common/protocol/guestfs_protocol.h \
	../common/utils/cleanups.h \
	../common/utils/guestfs-utils.h \
	9p.c \
	acl.c \
	actions.h \
	available.c \
	augeas.c \
	base64.c \
	blkdiscard.c \
	blkid.c \
	blockdev.c \
	btrfs.c \
	caml-stubs.c \
	cap.c \
	checksum.c \
	cleanups.c \
	clevis-luks.c \
	cmp.c \
	command.c \
	command.h \
	compress.c \
	copy.c \
	cpio.c \
	cpmv.c \
	daemon-c.c \
	daemon-c.h \
	daemon.h \
	dd.c \
	debug.c \
	debug-bmap.c \
	device-name-translation.c \
	devsparts.c \
	df.c \
	dir.c \
	dispatch.c \
	dmesg.c \
	dropcaches.c \
	du.c \
	echo-daemon.c \
	ext2.c \
	f2fs.c \
	fallocate.c \
	file.c \
	fill.c \
	find.c \
	fs-min-size.c \
	fsck.c \
	fstrim.c \
	glob.c \
	grep.c \
	grub.c \
	guestfsd.c \
	headtail.c \
	hexdump.c \
	hivex.c \
	htonl.c \
	initrd.c \
	inotify.c \
	internal.c \
	is.c \
	journal.c \
	labels.c \
	ldm.c \
	link.c \
	ls.c \
	luks.c \
	lvm.c \
	lvm-filter.c \
	lvm-tokenization.c \
	md.c \
	mkfs.c \
	mknod.c \
	mktemp.c \
	modprobe.c \
	mount.c \
	mountable.c \
	names.c \
	ntfs.c \
	ntfsclone.c \
	optgroups.c \
	optgroups.h \
	parted.c \
	pingdaemon.c \
	proto.c \
	readdir.c \
	rename.c \
	rpm-c.c \
	rsync.c \
	scrub.c \
	selinux.c \
	selinux-relabel.c \
	sfdisk.c \
	sh.c \
	sleep.c \
	sleuthkit.c \
	squashfs.c \
	stat.c \
	strings.c \
	structs-cleanups.c \
	structs-cleanups.h \
	stubs-0.c \
	stubs-1.c \
	stubs-2.c \
	stubs-3.c \
	stubs-4.c \
	stubs-5.c \
	stubs-6.c \
	stubs.h \
	stubs-macros.h \
	swap.c \
	sync.c \
	syslinux.c \
	sysroot-c.c \
	tar.c \
	tsk.c \
	truncate.c \
	umask.c \
	upload.c \
	utils.c \
	utils-c.c \
	utimens.c \
	utsname.c \
	uuids.c \
	wc.c \
	xattr.c \
	xfs.c \
	yara.c \
	zero.c \
	zerofree.c

guestfsd_LDFLAGS = \
	-L$(shell $(OCAMLC) -where) \
	-L$(shell $(OCAMLFIND) query hivex) \
	-L$(shell $(OCAMLFIND) query augeas) \
	-L../common/mlutils \
	-L../common/mlstdutils \
	-L../common/mlpcre
guestfsd_LDADD = \
	camldaemon.o \
	$(ACL_LIBS) \
	$(CAP_LIBS) \
	$(JANSSON_LIBS) \
	$(SELINUX_LIBS) \
	$(AUGEAS_LIBS) \
	$(HIVEX_LIBS) \
	$(SD_JOURNAL_LIBS) \
	$(top_builddir)/gnulib/lib/.libs/libgnu.a \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LIBINTL) \
	$(PCRE2_LIBS) \
	$(LIBRPM_LIBS) \
	$(TSK_LIBS) \
	$(RPC_LIBS) \
	$(YARA_LIBS) \
	$(OCAML_LIBS) \
	../common/errnostring/liberrnostring.la \
	../common/protocol/libprotocol.la \
	../common/utils/libutils.la

guestfsd_CPPFLAGS = \
	-DCAML_NAME_SPACE \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/lib \
	-I$(top_builddir)/lib \
	-I$(top_srcdir)/common/errnostring \
	-I$(top_builddir)/common/errnostring \
	-I$(top_srcdir)/common/protocol \
	-I$(top_builddir)/common/protocol \
	-I$(top_srcdir)/common/utils \
	-I$(top_builddir)/common/utils
guestfsd_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS) \
	$(AUGEAS_CFLAGS) \
	$(HIVEX_CFLAGS) \
	$(SD_JOURNAL_CFLAGS) \
	$(JANSSON_CFLAGS) \
	$(PCRE2_CFLAGS) \
	$(LIBRPM_CFLAGS)

# Parts of the daemon are written in OCaml.  These are linked into a
# library and then linked to the daemon.  See
# https://caml.inria.fr/pub/docs/manual-ocaml/intfc.html
SOURCES_MLI = \
	blkid.mli \
	btrfs.mli \
	callbacks.mli \
	chroot.mli \
	cryptsetup.mli \
	daemon.mli \
	daemon_config.mli \
	devsparts.mli \
	file.mli \
	filearch.mli \
	findfs.mli \
	inspect.mli \
	inspect_fs.mli \
	inspect_fs_unix.mli \
	inspect_fs_unix_fstab.mli \
	inspect_fs_windows.mli \
	inspect_types.mli \
	inspect_utils.mli \
	is.mli \
	isoinfo.mli \
	ldm.mli \
	link.mli \
	listfs.mli \
	lvm.mli \
	lvm_dm.mli \
	lvm_utils.mli \
	md.mli \
	mount.mli \
	mount_utils.mli \
	mountable.mli \
	optgroups.mli \
	parted.mli \
	realpath.mli \
	rpm.mli \
	statvfs.mli \
	structs.mli \
	sysroot.mli \
	utils.mli

SOURCES_ML = \
	$(CONFIGURE_GENERATED_ML) \
	utils.ml \
	structs.ml \
	optgroups.ml \
	sysroot.ml \
	mountable.ml \
	chroot.ml \
	blkid.ml \
	btrfs.ml \
	cryptsetup.ml \
	devsparts.ml \
	file.ml \
	filearch.ml \
	isoinfo.ml \
	is.ml \
	ldm.ml \
	link.ml \
	lvm.ml \
	lvm_utils.ml \
	lvm_dm.ml \
	findfs.ml \
	md.ml \
	mount.ml \
	mount_utils.ml \
	parted.ml \
	listfs.ml \
	realpath.ml \
	statvfs.ml \
	inspect_types.ml \
	inspect_utils.ml \
	inspect_fs_unix_fstab.ml \
	inspect_fs_unix.ml \
	inspect_fs_windows.ml \
	inspect_fs.ml \
	inspect.ml \
	rpm.ml \
	callbacks.ml \
	daemon.ml

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

OCAMLPACKAGES = \
	-package str,unix,augeas,hivex \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/common/mlpcre \
	-I $(top_builddir)/common/mlpcre/.libs \
	-I $(top_builddir)/gnulib/lib/.libs

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif
OCAML_LIBS = \
	-lmlpcre \
	-lmlcutils \
	-lmlstdutils \
	-lmlaugeas \
	-lmlhivex \
	-lcamlstr \
	-lunix \
	-l$(CAMLRUN) -ldl -lm

CLEANFILES += camldaemon.o

camldaemon.o: $(OBJECTS)
	$(OCAMLFIND) $(BEST) -output-obj -o $@ \
	    $(OCAMLFLAGS) $(OCAMLPACKAGES) \
	    -linkpkg \
	    mlpcre.$(MLARCHIVE) \
	    mlstdutils.$(MLARCHIVE) \
	    mlcutils.$(MLARCHIVE) \
	    $(OBJECTS)

# OCaml dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

# Tests.

check_PROGRAMS = daemon_utils_tests
TESTS_ENVIRONMENT = $(top_builddir)/run --test
TESTS = \
	daemon_utils_tests

check-valgrind:
	$(MAKE) VG="@VG@" check

daemon_utils_tests_SOURCES = \
	command.c \
	daemon-utils-tests-stubs.c \
	utils.c \
	utils-c.c
daemon_utils_tests_CPPFLAGS = \
	-DCAML_NAME_SPACE \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/errnostring \
	-I$(top_builddir)/common/errnostring \
	-I$(top_srcdir)/common/protocol \
	-I$(top_builddir)/common/protocol \
	-I$(top_srcdir)/common/utils \
	-I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_builddir)/lib
daemon_utils_tests_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS)
daemon_utils_tests_BOBJECTS = \
	utils.cmo \
	daemon_utils_tests.cmo
daemon_utils_tests_XOBJECTS = $(daemon_utils_tests_BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
daemon_utils_tests_THEOBJECTS = $(daemon_utils_tests_BOBJECTS)
else
daemon_utils_tests_THEOBJECTS = $(daemon_utils_tests_XOBJECTS)
endif

OCAMLLINKFLAGS = \
	mlpcre.$(MLARCHIVE) \
	mlstdutils.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

daemon_utils_tests_DEPENDENCIES = \
	$(daemon_utils_tests_THEOBJECTS) \
	$(top_builddir)/ocaml-link.sh
daemon_utils_tests_LINK = \
	$(top_builddir)/ocaml-link.sh \
	  -cclib '-lutils -lgnu $(HIVEX_LIBS)' \
	  -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLLINKFLAGS) \
	  $(OCAMLPACKAGES) \
	  $(daemon_utils_tests_THEOBJECTS) -o $@

# Manual pages and HTML files for the website.
if INSTALL_DAEMON
man_MANS = guestfsd.8
noinst_DATA =
else
# It should be noinst_MANS but that doesn't work.
noinst_DATA = guestfsd.8
endif
noinst_DATA += $(top_builddir)/website/guestfsd.8.html

guestfsd.8 $(top_builddir)/website/guestfsd.8.html: stamp-guestfsd.pod

stamp-guestfsd.pod: guestfsd.pod
	$(PODWRAPPER) \
	  --section 8 \
	  --man guestfsd.8 \
	  --html $(top_builddir)/website/guestfsd.8.html \
	  --license GPLv2+ \
	  $<
	touch $@

.PHONY: force
