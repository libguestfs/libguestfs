# libguestfs
# Copyright (C) 2009-2011 Red Hat Inc.
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
	cmds_gperf.gperf \
	completion.c \
	fish-cmds.h \
	guestfish-actions.pod \
	guestfish-commands.pod \
	prepopts.h \
	prepopts.c

BUILT_SOURCES = \
	$(generator_built) \
	cmds_gperf.c \
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
	inspect.c \
	keys.c \
	options.h \
	options.c \
	progress.h \
	progress.c \
	virt.c

guestfish_SOURCES = \
	$(generator_built) \
	$(SHARED_SOURCE_FILES) \
	alloc.c \
	cmds_gperf.h \
	copy.c \
	destpaths.c \
	display.c \
	echo.c \
	edit.c \
	fish.c \
	fish.h \
	glob.c \
	help.c \
	hexedit.c \
	lcd.c \
	man.c \
	more.c \
	prep.c \
	prep_disk.c \
	prep_part.c \
	prep_fs.c \
	prep_lv.c \
	prep_boot.c \
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
libcmds_la_SOURCES = cmds_gperf.c
libcmds_la_CFLAGS =

cmds_gperf.c: cmds_gperf.gperf
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
rc_protocol.c: rc_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) -c -o $@-t $<
	sed 's,\.\./\.\./fish/,,' < $@-t > $@-t2
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
	$(top_builddir)/podwrapper.sh \
	  --man guestfish.1 \
	  --html $(top_builddir)/html/guestfish.1.html \
	  --insert $(srcdir)/guestfish-actions.pod:@ACTIONS@ \
	  --insert $(srcdir)/guestfish-commands.pod:@FISH_COMMANDS@ \
	  $<
	touch $@

virt-copy-in.1 $(top_builddir)/html/virt-copy-in.1.html: stamp-virt-copy-in.pod

stamp-virt-copy-in.pod: virt-copy-in.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-copy-in.1 \
	  --html $(top_builddir)/html/virt-copy-in.1.html \
	  $<
	touch $@

virt-copy-out.1 $(top_builddir)/html/virt-copy-out.1.html: stamp-virt-copy-out.pod

stamp-virt-copy-out.pod: virt-copy-out.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-copy-out.1 \
	  --html $(top_builddir)/html/virt-copy-out.1.html \
	  $<
	touch $@

virt-tar-in.1 $(top_builddir)/html/virt-tar-in.1.html: stamp-virt-tar-in.pod

stamp-virt-tar-in.pod: virt-tar-in.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-tar-in.1 \
	  --html $(top_builddir)/html/virt-tar-in.1.html \
	  $<
	touch $@

virt-tar-out.1 $(top_builddir)/html/virt-tar-out.1.html: stamp-virt-tar-out.pod

stamp-virt-tar-out.pod: virt-tar-out.pod
	$(top_builddir)/podwrapper.sh \
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
