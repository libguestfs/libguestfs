# libguestfs test images
# Copyright (C) 2009-2013 Red Hat Inc.
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
	guest-aux/minimal-hive \
	guest-aux/make-guests-all-good.pl \
	guests.xml.in

disk_images = \
	blank-disk.img \
	blank-part.img \
	blank-fs.img \
	blank-bootroot.img \
	blank-bootrootlv.img \
	debian.img \
	fedora.img \
	fedora-md1.img \
	fedora-md2.img \
	ubuntu.img \
	windows.img

# This is 'check_DATA' because we don't need it until 'make check'
# time and we need the tools we have built in order to make it.
check_DATA = $(disk_images) guests-all-good.xml

CLEANFILES = $(check_DATA) stamp-fedora-md.img *.tmp.*

# Macro to display some information about each created disk, which
# is useful for debugging.
display = \
	-@echo -n '$(1): file size bytes: '; \
	stat -c %s $(1); \
	echo -n '$(1): allocated bytes: '; \
	du -B 1 $(1) | awk '{print $$1}'; \
	echo -n '$(1): MD5 hash:        '; \
	md5sum $(1) | awk '{print $$1}'

# Make several different blank images.  These are not guests, but we
# include them in the libvirt fake XML to make sure that virt-df and
# virt-alignment-scan don't break when they encounter them.
blank-%.img:
	rm -f $@ test1.img
	$(top_builddir)/run \
	  ../../fish/guestfish \
	    -N "$$(echo $@ | sed -e 's/blank-//' -e 's/.img//')" exit
	mv test1.img $@
	$(call display,$@)

# Make a (dummy) Fedora image.
fedora.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	SRCDIR=$(srcdir) LAYOUT=partitions $(top_builddir)/run --test $<
	$(call display,$@)

# Make a (dummy) Fedora image using md devices
fedora-md1.img fedora-md2.img: stamp-fedora-md.img

stamp-fedora-md.img: guest-aux/make-fedora-img.pl \
		guest-aux/fedora-name.db \
		guest-aux/fedora-packages.db
	rm -f $@
	SRCDIR=$(srcdir) LAYOUT=partitions-md $(top_builddir)/run --test $<
	$(call display,fedora-md1.img)
	$(call display,fedora-md2.img)
	touch $@

guest-aux/fedora-name.db: guest-aux/fedora-name.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

guest-aux/fedora-packages.db: guest-aux/fedora-packages.db.txt
	rm -f $@ $@-t
	$(DB_LOAD) $@-t < $<
	mv $@-t $@

# Make a (dummy) Debian image.
debian.img: guest-aux/make-debian-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<
	$(call display,$@)

# Make a (dummy) Ubuntu image.
ubuntu.img: guest-aux/make-ubuntu-img.sh
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<
	$(call display,$@)

# Make a (dummy) Windows image.
windows.img: guest-aux/make-windows-img.sh \
	     guest-aux/windows-software guest-aux/windows-system
	SRCDIR=$(srcdir) $(top_builddir)/run --test $<
	$(call display,$@)

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

guests-all-good.xml: $(disk_images) guest-aux/make-guests-all-good.pl
	rm -f $@ $@-t
	guest-aux/make-guests-all-good.pl $(disk_images) > $@-t
	mv $@-t $@

# Don't construct the guests in parallel.  In automake 1.13, check_DATA
# was changed so it can now run in parallel, but this causes everything
# to fall over on machines with limited memory.
#
# ALSO: the guestfish rules above for making the blank-*.img files are
# NOT safe to run in parallel.
.NOTPARALLEL:
