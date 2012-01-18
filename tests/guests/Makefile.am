# libguestfs test images
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

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= $(top_builddir)/tests/guests

EXTRA_DIST = \
	guest-aux/make-debian-img.sh \
	guest-aux/debian-packages \
	guest-aux/make-fedora-img.pl \
	guest-aux/fedora-name.db.txt \
	guest-aux/fedora-name.db \
	guest-aux/fedora-packages.db.txt \
	guest-aux/fedora-packages.db \
	guest-aux/make-ubuntu-img.sh \
	guest-aux/make-windows-img.sh \
	guest-aux/windows-software \
	guest-aux/windows-software.reg \
	guest-aux/windows-system \
	guest-aux/windows-system.reg \
	guest-aux/minimal-hive

# This is 'check_DATA' because we don't need it until 'make check'
# time and we need the tools we have built in order to make it.
check_DATA = debian.img fedora.img fedora-md1.img fedora-md2.img ubuntu.img windows.img

CLEANFILES = $(check_DATA)

# Make a (dummy) Fedora image.
fedora.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	TMPDIR=$(top_builddir) \
	SRCDIR=$(srcdir) \
	LAYOUT=partitions \
	../../run $<

# Make a (dummy) Fedora image using md devices
fedora-md1.img fedora-md2.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	TMPDIR=$(top_builddir) \
	SRCDIR=$(srcdir) \
	LAYOUT=partitions-md \
	../../run $<

guest-aux/fedora-name.db: guest-aux/fedora-name.db.txt
	rm -f $@ $@-t
	mkdir -p guest-aux
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

guest-aux/fedora-packages.db: guest-aux/fedora-packages.db.txt
	rm -f $@ $@-t
	mkdir -p guest-aux
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

# Make a (dummy) Debian image.
debian.img: guest-aux/make-debian-img.sh
	TMPDIR=$(top_builddir) \
	SRCDIR=$(srcdir) \
	bash $<

# Make a (dummy) Ubuntu image.
ubuntu.img: guest-aux/make-ubuntu-img.sh
	TMPDIR=$(top_builddir) \
	SRCDIR=$(srcdir) \
	bash $<

# Make a (dummy) Windows image.
windows.img: guest-aux/make-windows-img.sh \
	     guest-aux/windows-software guest-aux/windows-system
	TMPDIR=$(top_builddir) \
	SRCDIR=$(srcdir) \
	bash $<

# Since users might not have the tools needed to create this, we
# also distribute these files.
guest-aux/windows-software: guest-aux/windows-software.reg
	rm -f $@ $@-t
	cp guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SOFTWARE' $<
	mv $@-t $@

guest-aux/windows-system: guest-aux/windows-system.reg
	rm -f $@ $@-t
	cp guest-aux/minimal-hive $@-t
	hivexregedit --merge $@-t --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' $<
	mv $@-t $@
