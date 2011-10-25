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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

include $(top_srcdir)/subdir-rules.mk

libsrcdir = $(top_builddir)/src

generator_built = \
	actions.h \
	stubs.c \
	names.c

BUILT_SOURCES = \
	$(generator_built) \
	guestfs_protocol.c \
	guestfs_protocol.h \
	errnostring_gperf.c \
	errnostring_gperf.gperf \
	errnostring.c \
	errnostring.h

EXTRA_DIST = $(BUILT_SOURCES)

noinst_LIBRARIES = libprotocol.a

# This convenience library is solely to compile its generated sources with
# custom flags.
libprotocol_a_SOURCES = guestfs_protocol.c guestfs_protocol.h
libprotocol_a_CFLAGS = -Wall -Wno-unused -fno-strict-aliasing

guestfs_protocol.c: $(libsrcdir)/guestfs_protocol.c
	rm -f $@
	ln $< $@
guestfs_protocol.h: $(libsrcdir)/guestfs_protocol.h
	rm -f $@
	ln $< $@
$(libsrcdir)/guestfs_protocol.c: force
	$(MAKE) -C $(libsrcdir) guestfs_protocol.c
$(libsrcdir)/guestfs_protocol.h: force
	$(MAKE) -C $(libsrcdir) guestfs_protocol.h

# Build the errnostring perfect hash code.  The generated code has lots
# of warnings so we must compile it in a separate mini-library.
noinst_LIBRARIES += liberrnostring.a
liberrnostring_a_SOURCES = \
	errnostring_gperf.c \
	errnostring.h \
	errnostring.c
liberrnostring_a_CFLAGS =

errnostring_gperf.c: errnostring_gperf.gperf
	rm -f $@
	$(GPERF) -t $< > $@-t
	mv $@-t $@
errnostring_gperf.gperf: $(libsrcdir)/errnostring_gperf.gperf
	rm -f $@
	ln $< $@
errnostring.c: $(libsrcdir)/errnostring.c
	rm -f $@
	ln $< $@
errnostring.h: $(libsrcdir)/errnostring.h
	rm -f $@
	ln $< $@

if INSTALL_DAEMON
sbin_PROGRAMS = guestfsd
else
noinst_PROGRAMS = guestfsd
endif

guestfsd_SOURCES = \
	9p.c \
	actions.h \
	available.c \
	augeas.c \
	base64.c \
	blkid.c \
	blockdev.c \
	btrfs.c \
	checksum.c \
	cmp.c \
	command.c \
	compress.c \
	copy.c \
	cpmv.c \
	daemon.h \
	dd.c \
	debug.c \
	devsparts.c \
	df.c \
	dir.c \
	dmesg.c \
	dropcaches.c \
	du.c \
	echo_daemon.c \
	ext2.c \
	fallocate.c \
	file.c \
	findfs.c \
	fill.c \
	find.c \
	fsck.c \
	glob.c \
	grep.c \
	grub.c \
	guestfsd.c \
	headtail.c \
	hexdump.c \
	htonl.c \
	initrd.c \
	inotify.c \
	is.c \
	link.c \
	ls.c \
	luks.c \
	lvm.c \
	lvm-filter.c \
	mkfs.c \
	mknod.c \
	modprobe.c \
	mount.c \
	names.c \
	ntfs.c \
	optgroups.c \
	optgroups.h \
	parted.c \
	pingdaemon.c \
	proto.c \
	readdir.c \
	realpath.c \
	scrub.c \
	selinux.c \
	sfdisk.c \
	sleep.c \
	stat.c \
	statvfs.c \
	strings.c \
	stubs.c \
	swap.c \
	sync.c \
	tar.c \
	truncate.c \
	umask.c \
	upload.c \
	utimens.c \
	wc.c \
	xattr.c \
	zero.c \
	zerofree.c
guestfsd_LDADD = \
	liberrnostring.a \
	libprotocol.a \
	$(SELINUX_LIB) \
	$(AUGEAS_LIB) \
	$(top_builddir)/gnulib/lib/.libs/libgnu.a \
	$(GETADDRINFO_LIB) \
	$(HOSTENT_LIB) \
	$(INET_NTOP_LIB) \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LIBINTL) \
	$(SERVENT_LIB)

guestfsd_CPPFLAGS = -I$(top_srcdir)/gnulib/lib
guestfsd_CFLAGS = $(WARN_CFLAGS) $(WERROR_CFLAGS)

.PHONY: force
