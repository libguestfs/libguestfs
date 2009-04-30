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

noinst_PROGRAMS = guestfsd
guestfsd_SOURCES = \
	actions.h \
	augeas.c \
	blockdev.c \
	checksum.c \
	command.c \
	daemon.h \
	debug.c \
	devsparts.c \
	dir.c \
	ext2.c \
	file.c \
	fsck.c \
	grub.c \
	guestfsd.c \
	ls.c \
	lvm.c \
	mount.c \
	proto.c \
	stat.c \
	stubs.c \
	sync.c \
	tar.c \
	upload.c \
	zero.c \
	../src/guestfs_protocol.h \
	../src/guestfs_protocol.c

guestfsd_CFLAGS = -Wall
