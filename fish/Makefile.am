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

include $(top_srcdir)/subdir-rules.mk

bin_PROGRAMS = guestfish

generator_built = \
	cmds.c \
	cmds-gperf.gperf \
	completion.c \
	entries-0.c \
	entries-1.c \
	entries-2.c \
	entries-3.c \
	entries-4.c \
	entries-5.c \
	entries-6.c \
	event-names.c \
	fish-cmds.h \
	guestfish-actions.pod \
	guestfish-commands.pod \
	guestfish-prepopts.pod \
	prepopts.h \
	prepopts.c \
	run-0.c \
	run-1.c \
	run-2.c \
	run-3.c \
	run-4.c \
	run-5.c \
	run-6.c \
	run.h

BUILT_SOURCES = \
	$(generator_built) \
	cmds-gperf.c \
	rc_protocol.h \
	rc_protocol.c

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	rc_protocol.x \
	guestfish.pod \
	libguestfs-tools.conf \
	libguestfs-tools.conf.pod \
	virt-copy-in \
	virt-copy-out \
	virt-tar-in \
	virt-tar-out \
	virt-copy-in.pod \
	virt-copy-out.pod \
	virt-tar-in.pod \
	virt-tar-out.pod

guestfish_SOURCES = \
	$(generator_built) \
	alloc.c \
	cmds-gperf.h \
	copy.c \
	destpaths.c \
	display.c \
	echo.c \
	edit.c \
	events.c \
	fish.c \
	fish.h \
	glob.c \
	help.c \
	hexedit.c \
	lcd.c \
	man.c \
	more.c \
	prep.c \
	prep-disk.c \
	prep-part.c \
	prep-fs.c \
	prep-lv.c \
	prep-boot.c \
	rc.c \
	reopen.c \
	setenv.c \
	supported.c \
	tilde.c \
	time.c

# This convenience library is solely to compile its generated sources with
# custom flags.
librc_protocol_la_SOURCES = rc_protocol.c rc_protocol.h
librc_protocol_la_CFLAGS = -Wall -Wno-unused -fno-strict-aliasing $(RPC_CFLAGS)

# Build the command lookup perfect hash code.  The generated code has
# lots of warnings so we must compile it in a separate mini-library.
libcmds_la_SOURCES = cmds-gperf.c
libcmds_la_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib
libcmds_la_CFLAGS =
libcmds_la_LIBADD = \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(LTLIBINTL)

cmds-gperf.c: cmds-gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@

guestfish_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/edit -I$(top_builddir)/common/edit \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/progress -I$(top_builddir)/common/progress \
	-I$(top_srcdir)/fish -I$(top_builddir)/fish \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

guestfish_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS) \
	$(LIBCONFIG_CFLAGS) \
	$(LIBXML2_CFLAGS)

guestfish_LDADD = \
	$(top_builddir)/common/edit/libedit.la \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/progress/libprogress.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBCONFIG_LIBS) \
	$(LIBREADLINE) \
	$(LIBTINFO_LIBS) \
	$(LTLIBINTL) \
	$(RPC_LIBS) \
	-lm

# Make guestfish use the convenience libraries.
noinst_LTLIBRARIES = libcmds.la librc_protocol.la
guestfish_LDADD += libcmds.la librc_protocol.la ../gnulib/lib/libgnu.la

if HAVE_RPCGEN

rc_protocol.c: rc_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) -c -o $@-t $<
	$(SED) 's,\.\./\(\.\./\)*fish,.,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

rc_protocol.h: rc_protocol.x
	rm -f $@-t
	$(RPCGEN) -h -o $@-t $<
	mv $@-t $@
endif

# Script wrappers.

bin_SCRIPTS = virt-copy-in virt-copy-out virt-tar-in virt-tar-out

# Manual pages.

man_MANS = \
	guestfish.1 \
	libguestfs-tools.conf.5 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-tar-in.1 \
	virt-tar-out.1
noinst_DATA = \
	$(top_builddir)/website/guestfish.1.html \
	$(top_builddir)/website/libguestfs-tools.conf.5.html \
	$(top_builddir)/website/virt-copy-in.1.html \
	$(top_builddir)/website/virt-copy-out.1.html \
	$(top_builddir)/website/virt-tar-in.1.html \
	$(top_builddir)/website/virt-tar-out.1.html

guestfish.1 $(top_builddir)/website/guestfish.1.html: stamp-guestfish.pod

stamp-guestfish.pod: guestfish.pod guestfish-actions.pod guestfish-commands.pod guestfish-prepopts.pod
	$(PODWRAPPER) \
	  --man guestfish.1 \
	  --html $(top_builddir)/website/guestfish.1.html \
	  --path $(srcdir) --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning ro-option \
	  $<
	touch $@

libguestfs-tools.conf.5 $(top_builddir)/website/libguestfs-tools.conf.5.html: stamp-libguestfs-tools.conf.pod

stamp-libguestfs-tools.conf.pod: libguestfs-tools.conf.pod
	$(PODWRAPPER) \
	  --section 5 \
	  --man libguestfs-tools.conf.5 \
	  --html $(top_builddir)/website/libguestfs-tools.conf.5.html \
	  --license GPLv2+ \
	  $<
	touch $@

virt-copy-in.1 $(top_builddir)/website/virt-copy-in.1.html: stamp-virt-copy-in.pod

stamp-virt-copy-in.pod: virt-copy-in.pod
	$(PODWRAPPER) \
	  --man virt-copy-in.1 \
	  --html $(top_builddir)/website/virt-copy-in.1.html \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

virt-copy-out.1 $(top_builddir)/website/virt-copy-out.1.html: stamp-virt-copy-out.pod

stamp-virt-copy-out.pod: virt-copy-out.pod
	$(PODWRAPPER) \
	  --man virt-copy-out.1 \
	  --html $(top_builddir)/website/virt-copy-out.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

virt-tar-in.1 $(top_builddir)/website/virt-tar-in.1.html: stamp-virt-tar-in.pod

stamp-virt-tar-in.pod: virt-tar-in.pod
	$(PODWRAPPER) \
	  --man virt-tar-in.1 \
	  --html $(top_builddir)/website/virt-tar-in.1.html \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

virt-tar-out.1 $(top_builddir)/website/virt-tar-out.1.html: stamp-virt-tar-out.pod

stamp-virt-tar-out.pod: virt-tar-out.pod
	$(PODWRAPPER) \
	  --man virt-tar-out.1 \
	  --html $(top_builddir)/website/virt-tar-out.1.html \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# libguestfs tools config file.

toolsconfdir = $(sysconfdir)
toolsconf_DATA = libguestfs-tools.conf

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-a.sh \
	test-add-uri.sh \
	test-docs.sh \
	test-escapes.sh \
	test-events.sh \
	test-invalid-params.sh \
	test-tilde.sh

if HAVE_LIBVIRT
TESTS += \
	test-add-domain.sh \
	test-d.sh
endif

if ENABLE_APPLIANCE
TESTS += \
	test-copy.sh \
	test-edit.sh \
	test-file-attrs.sh \
	test-find0.sh \
	test-inspect.sh \
	test-glob.sh \
	test-prep.sh \
	test-read-file.sh \
	test-remote.sh \
	test-remote-events.sh \
	test-reopen.sh \
	test-run.sh \
	test-stringlist.sh \
	test-upload-to-dir.sh

if HAVE_FUSE
TESTS += \
	test-mount-local.sh
endif
endif

check-valgrind:
	$(MAKE) TESTS="test-a.sh test-add-domain.sh test-add-uri.sh test-copy.sh test-d.sh test-edit.sh test-escapes.sh test-events.sh test-find0.sh test-glob.sh test-inspect.sh test-prep.sh test-read-file.sh test-remote.sh test-remote-events.sh test-reopen.sh test-run.sh test-stringlist.sh test-tilde.sh test-upload-to-dir.sh" VG="@VG@" check

EXTRA_DIST += \
	test-a.sh \
	test-add-domain.sh \
	test-add-uri.sh \
	test-alloc.sh \
	test-copy.sh \
	test-d.sh \
	test-docs.sh \
	test-edit.sh \
	test-escapes.sh \
	test-events.sh \
	test-file-attrs.sh \
	test-find0.sh \
	test-glob.sh \
	test-inspect.sh \
	test-invalid-params.sh \
	test-mount-local.sh \
	test-prep.sh \
	test-read-file.sh \
	test-remote.sh \
	test-remote-events.sh \
	test-reopen.sh \
	test-run.sh \
	test-stringlist.sh \
	test-tilde.sh \
	test-upload-to-dir.sh
