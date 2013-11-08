# libguestfs virt-builder tool
# Copyright (C) 2013 Red Hat Inc.
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
	.gitignore \
	compress.sh \
	test-guest.sh \
	validate.sh \
	README \
	index \
	index.asc \
	centos.sh \
	centos-6.xz.sig \
	debian.preseed \
	debian.sh \
	debian-6.xz.sig \
	debian-7.xz.sig \
	fedora.sh \
	fedora-18.xz.sig \
	fedora-19.xz.sig \
	rhel.sh \
	scientificlinux.sh \
	scientificlinux-6.xz.sig \
	ubuntu.preseed \
	ubuntu.sh \
	ubuntu-10.04.xz.sig \
	ubuntu-12.04.xz.sig \
	ubuntu-13.10.xz.sig

CLEANFILES = *~

# Validates the index file.
TESTS_ENVIRONMENT = $(top_builddir)/run --test
TESTS = validate.sh
