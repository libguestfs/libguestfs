# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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

CLEANFILES = \
	stamp-guestfish.pod \
	stamp-virt-copy-in.pod \
	stamp-virt-copy-out.pod \
	stamp-virt-tar-in.pod \
	stamp-virt-tar-out.pod

bin_PROGRAMS = guestfish

generator_built = \
	cmds.c \
	cmds-gperf.gperf \
	completion.c \
	event-names.c \
	fish-cmds.h \
	guestfish-actions.pod \
	guestfish-commands.pod \
	prepopts.h \
	prepopts.c

BUILT_SOURCES = \
	$(generator_built) \
	cmds-gperf.c \
	rc_protocol.h \
	rc_protocol.c

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	rc_protocol.x \
	guestfish.pod \
	guestfish-bash-completion.sh \
	libguestfs-tools.conf \
	virt-copy-in \
	virt-copy-out \
	virt-tar-in \
	virt-tar-out \
	virt-copy-in.pod \
	virt-copy-out.pod \
	virt-tar-in.pod \
	virt-tar-out.pod

# These source files (mostly related to option parsing) are shared
# between guestfish, guestmount and some other virt tools.  Keep a
# convenient list here just so we know which ones are shared.  These
# files must not include other guestfish files.
SHARED_SOURCE_FILES = \
	config.c \
	domain.c \
	inspect.c \
	keys.c \
	options.h \
	options.c \
	progress.h \
	progress.c

guestfish_SOURCES = \
	$(generator_built) \
	$(SHARED_SOURCE_FILES) \
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
librc_protocol_la_CFLAGS = -Wall -Wno-unused -fno-strict-aliasing

# Build the command lookup perfect hash code.  The generated code has
# lots of warnings so we must compile it in a separate mini-library.
libcmds_la_SOURCES = cmds-gperf.c
libcmds_la_CFLAGS =

cmds-gperf.c: cmds-gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@

guestfish_CFLAGS = \
	-DGUESTFS_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/fish -I$(top_builddir)/fish \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCONFIG_CFLAGS)

guestfish_LDADD = \
	$(LIBCONFIG_LIBS) \
	$(LIBREADLINE) \
	$(top_builddir)/src/libguestfs.la -lm

# Make guestfish use the convenience libraries.
noinst_LTLIBRARIES = libcmds.la librc_protocol.la
guestfish_LDADD += libcmds.la librc_protocol.la ../gnulib/lib/libgnu.la

if HAVE_RPCGEN
RPCGEN_DEFS =
if HAVE_XDR_U_INT64_T
RPCGEN_DEFS += -DHAVE_XDR_U_INT64_T=1
else
if HAVE_XDR_UINT64_T
RPCGEN_DEFS += -DHAVE_XDR_UINT64_T=1
endif
endif

rc_protocol.c: rc_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) $(RPCGEN_DEFS) -c -o $@-t $<
	sed 's,\.\./\(\.\./\)*fish,.,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

rc_protocol.h: rc_protocol.x
	rm -f $@-t
	$(RPCGEN) $(RPCGEN_DEFS) -h -o $@-t $<
	mv $@-t $@
endif

# Script wrappers.

bin_SCRIPTS = virt-copy-in virt-copy-out virt-tar-in virt-tar-out

# Manual pages.

man_MANS = \
	guestfish.1 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-tar-in.1 \
	virt-tar-out.1
noinst_DATA = \
	$(top_builddir)/html/guestfish.1.html \
	$(top_builddir)/html/virt-copy-in.1.html \
	$(top_builddir)/html/virt-copy-out.1.html \
	$(top_builddir)/html/virt-tar-in.1.html \
	$(top_builddir)/html/virt-tar-out.1.html

guestfish.1 $(top_builddir)/html/guestfish.1.html: stamp-guestfish.pod

stamp-guestfish.pod: guestfish.pod guestfish-actions.pod guestfish-commands.pod
	$(PODWRAPPER) \
	  --man guestfish.1 \
	  --html $(top_builddir)/html/guestfish.1.html \
	  --insert $(srcdir)/guestfish-actions.pod:@ACTIONS@ \
	  --insert $(srcdir)/guestfish-commands.pod:@FISH_COMMANDS@ \
	  $<
	touch $@

virt-copy-in.1 $(top_builddir)/html/virt-copy-in.1.html: stamp-virt-copy-in.pod

stamp-virt-copy-in.pod: virt-copy-in.pod
	$(PODWRAPPER) \
	  --man virt-copy-in.1 \
	  --html $(top_builddir)/html/virt-copy-in.1.html \
	  $<
	touch $@

virt-copy-out.1 $(top_builddir)/html/virt-copy-out.1.html: stamp-virt-copy-out.pod

stamp-virt-copy-out.pod: virt-copy-out.pod
	$(PODWRAPPER) \
	  --man virt-copy-out.1 \
	  --html $(top_builddir)/html/virt-copy-out.1.html \
	  $<
	touch $@

virt-tar-in.1 $(top_builddir)/html/virt-tar-in.1.html: stamp-virt-tar-in.pod

stamp-virt-tar-in.pod: virt-tar-in.pod
	$(PODWRAPPER) \
	  --man virt-tar-in.1 \
	  --html $(top_builddir)/html/virt-tar-in.1.html \
	  $<
	touch $@

virt-tar-out.1 $(top_builddir)/html/virt-tar-out.1.html: stamp-virt-tar-out.pod

stamp-virt-tar-out.pod: virt-tar-out.pod
	$(PODWRAPPER) \
	  --man virt-tar-out.1 \
	  --html $(top_builddir)/html/virt-tar-out.1.html \
	  $<
	touch $@

# libguestfs tools config file.

toolsconfdir = $(sysconfdir)
toolsconf_DATA = libguestfs-tools.conf

# Bash completion script.

bashcompletiondir = $(sysconfdir)/bash_completion.d
bashcompletion_DATA = guestfish-bash-completion.sh

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	$(top_builddir)/run

TESTS = \
	test-a.sh \
	test-add-domain.sh \
	test-d.sh \
	test-escapes.sh \
	test-events.sh \
	test-tilde.sh

if ENABLE_APPLIANCE
TESTS += \
	test-copy.sh \
	test-edit.sh \
	test-find0.sh \
	test-glob.sh \
	test-mount-local.sh \
	test-read-file.sh \
	test-remote.sh \
	test-reopen.sh \
	test-stringlist.sh \
	test-upload-to-dir.sh
endif

EXTRA_DIST += \
	test-a.sh \
	test-add-domain.sh \
	test-copy.sh \
	test-d.sh \
	test-edit.sh \
	test-escapes.sh \
	test-events.sh \
	test-find0.sh \
	test-glob.sh \
	test-mount-local.sh \
	test-read-file.sh \
	test-remote.sh \
	test-reopen.sh \
	test-stringlist.sh \
	test-tilde.sh \
	test-upload-to-dir.sh
