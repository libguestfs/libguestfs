# libguestfs-daemon
# Copyright (C) 2009 Red Hat Inc.
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

ACLOCAL_AMFLAGS = -I m4

SUBDIRS = lib tests .

libsrcdir = $(top_builddir)/../src

generator_built = \
	actions.h \
	stubs.c \
	names.c

.PHONY: force

$(generator_built): $(libsrcdir)/stamp-generator
$(libsrcdir)/stamp-generator: force
	$(MAKE) -C $(libsrcdir) stamp-generator

BUILT_SOURCES = \
	$(generator_built) \
	guestfs_protocol.c \
	guestfs_protocol.h

EXTRA_DIST = $(BUILT_SOURCES) \
	.gitignore

# This convenience library is solely to avoid compiler warnings
# in its generated sources.
noinst_LIBRARIES = libprotocol.a
libprotocol_a_SOURCES = \
	guestfs_protocol.c \
	guestfs_protocol.h
libprotocol_a_CFLAGS =

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

noinst_PROGRAMS = guestfsd
guestfsd_SOURCES = \
	actions.h \
	available.c \
	augeas.c \
	blkid.c \
	blockdev.c \
	checksum.c \
	cmp.c \
	command.c \
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
	link.c \
	ls.c \
	lvm.c \
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
	libprotocol.a \
	lib/libgnu.a \
	$(GETADDRINFO_LIB) \
	$(HOSTENT_LIB) \
	$(INET_NTOP_LIB) \
	$(LIBSOCKET) \
	$(LIB_CLOCK_GETTIME) \
	$(LIBINTL) \
	$(SERVENT_LIB)

AM_CPPFLAGS = -I$(srcdir)/lib -Ilib
guestfsd_CFLAGS = $(WARN_CFLAGS) $(WERROR_CFLAGS)
