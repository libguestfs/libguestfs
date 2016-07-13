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

CLEANFILES = \
	stamp-guestfsd.pod \
	guestfsd.8

generator_built = \
	actions.h \
	stubs.c \
	names.c

shared_with_library = \
	guestfs_protocol.c \
	guestfs_protocol.h \
	errnostring-gperf.gperf \
	errnostring.c \
	errnostring.h

BUILT_SOURCES = \
	$(generator_built) \
	$(shared_with_library) \
	errnostring-gperf.c

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	guestfsd.pod

$(shared_with_library): %: $(top_srcdir)/src/%
	rm -f $@
	ln $< $@

noinst_LIBRARIES = libprotocol.a

# This convenience library is solely to compile its generated sources with
# custom flags.
libprotocol_a_SOURCES = guestfs_protocol.c guestfs_protocol.h
libprotocol_a_CFLAGS = -Wall -Wno-unused -fno-strict-aliasing

$(top_builddir)/src/guestfs_protocol.c: force
	$(MAKE) -C $(top_builddir)/src guestfs_protocol.c
$(top_builddir)/src/guestfs_protocol.h: force
	$(MAKE) -C $(top_builddir)/src guestfs_protocol.h

# Build the errnostring perfect hash code.  The generated code has lots
# of warnings so we must compile it in a separate mini-library.
noinst_LIBRARIES += liberrnostring.a
liberrnostring_a_SOURCES = \
	errnostring-gperf.c \
	errnostring.h \
	errnostring.c
liberrnostring_a_CFLAGS =

errnostring-gperf.c: errnostring-gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@

if INSTALL_DAEMON
sbin_PROGRAMS = guestfsd
else
noinst_PROGRAMS = guestfsd
endif

# Compile the largest file (stubs.c) first.  The other files are
# listed alphabetically.  See also:
# https://rwmj.wordpress.com/2015/09/30/make-and-queuing-theory/#content
guestfsd_SOURCES = \
	stubs.c \
	acl.c \
	actions.h \
	available.c \
	augeas.c \
	base64.c \
	blkdiscard.c \
	blkid.c \
	blockdev.c \
	btrfs.c \
	cap.c \
	checksum.c \
	cleanups.c \
	cleanups.h \
	cmp.c \
	command.c \
	command.h \
	compress.c \
	copy.c \
	cpio.c \
	cpmv.c \
	daemon.h \
	dd.c \
	debug.c \
	debug-bmap.c \
	devsparts.c \
	df.c \
	dir.c \
	dmesg.c \
	dropcaches.c \
	du.c \
	echo-daemon.c \
	ext2.c \
	fallocate.c \
	file.c \
	findfs.c \
	fill.c \
	find.c \
	format.c \
	fs-min-size.c \
	fsck.c \
	fstrim.c \
	glob.c \
	grep.c \
	grub.c \
	guestfsd.c \
	headtail.c \
	hexdump.c \
	hotplug.c \
	hivex.c \
	htonl.c \
	initrd.c \
	inotify.c \
	internal.c \
	is.c \
	isoinfo.c \
	journal.c \
	labels.c \
	ldm.c \
	link.c \
	ls.c \
	luks.c \
	lvm.c \
	lvm-filter.c \
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
	realpath.c \
	rename.c \
	rsync.c \
	scrub.c \
	selinux.c \
	selinux-relabel.c \
	sfdisk.c \
	sh.c \
	sleep.c \
	stat.c \
	statvfs.c \
	strings.c \
	swap.c \
	sync.c \
	syslinux.c \
	tar.c \
	truncate.c \
	umask.c \
	upload.c \
	utimens.c \
	utsname.c \
	uuids.c \
	wc.c \
	xattr.c \
	xfs.c \
	zero.c \
	zerofree.c

guestfsd_LDADD = \
	liberrnostring.a \
	libprotocol.a \
	$(ACL_LIBS) \
	$(CAP_LIBS) \
	$(YAJL_LIBS) \
	$(SELINUX_LIBS) \
	$(AUGEAS_LIBS) \
	$(HIVEX_LIBS) \
	$(SD_JOURNAL_LIBS) \
	$(top_builddir)/gnulib/lib/.libs/libgnu.a \
	$(GETADDRINFO_LIB) \
	$(HOSTENT_LIB) \
	$(INET_NTOP_LIB) \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LIBINTL) \
	$(SERVENT_LIB) \
	$(PCRE_LIBS)

guestfsd_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src \
	-I$(top_builddir)/src
guestfsd_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(AUGEAS_CFLAGS) \
	$(HIVEX_CFLAGS) \
	$(SD_JOURNAL_CFLAGS) \
	$(YAJL_CFLAGS) \
	$(PCRE_CFLAGS)

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
