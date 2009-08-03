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

noinst_PROGRAMS = guestfsd
guestfsd_SOURCES = \
	actions.h \
	augeas.c \
	blockdev.c \
	checksum.c \
	cmp.c \
	command.c \
	cpmv.c \
	daemon.h \
	debug.c \
	devsparts.c \
	df.c \
	dir.c \
	dmesg.c \
	dropcaches.c \
	du.c \
	ext2.c \
	fallocate.c \
	file.c \
	find.c \
	fsck.c \
	glob.c \
	grep.c \
	grub.c \
	guestfsd.c \
	headtail.c \
	hexdump.c \
	initrd.c \
	inotify.c \
	link.c \
	ls.c \
	lvm.c \
	mknod.c \
	mount.c \
	names.c \
	ntfs.c \
	pingdaemon.c \
	proto.c \
	readdir.c \
	realpath.c \
	scrub.c \
	sfdisk.c \
	sleep.c \
	stat.c \
	strings.c \
	stubs.c \
	swap.c \
	sync.c \
	tar.c \
	umask.c \
	upload.c \
	wc.c \
	xattr.c \
	zero.c \
	zerofree.c \
	$(top_builddir)/../src/guestfs_protocol.h \
	$(top_builddir)/../src/guestfs_protocol.c

AM_CPPFLAGS = -I$(srcdir)/lib -Ilib
guestfsd_CFLAGS = -Wall
LDADD = lib/libgnu.a
