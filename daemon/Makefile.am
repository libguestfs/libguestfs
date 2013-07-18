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

generator_built = \
	actions.h \
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

BUILT_SOURCES = \
	$(generator_built)

EXTRA_DIST = \
	$(BUILT_SOURCES) \
	guestfsd.pod

if INSTALL_DAEMON
sbin_PROGRAMS = guestfsd
else
noinst_PROGRAMS = guestfsd
endif

guestfsd_SOURCES = \
	../common/errnostring/errnostring.h \
	../common/protocol/guestfs_protocol.h \
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
	dispatch.c \
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
	realpath.c \
	rename.c \
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
	statvfs.c \
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
	tar.c \
	tsk.c \
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
	../common/errnostring/liberrnostring.la \
	../common/protocol/libprotocol.la \
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
	$(PCRE_LIBS) \
	$(TSK_LIBS)

guestfsd_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/lib \
	-I$(top_builddir)/lib \
	-I$(top_srcdir)/common/errnostring \
	-I$(top_builddir)/common/errnostring \
	-I$(top_srcdir)/common/protocol \
	-I$(top_builddir)/common/protocol
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
