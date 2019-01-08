# libguestfs virt-builder tool
# Copyright (C) 2013-2019 Red Hat Inc.
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

index_fragments = $(wildcard *.index-fragment)

EXTRA_DIST = \
	$(index_fragments) \
	*.ks \
	*.virt-install-cmd \
	debian.preseed \
	make-template.ml \
	ubuntu.preseed \
	validate.sh

# Create the index file under the top level website/ directory.
noinst_DATA = $(top_builddir)/website/download/builder/index

$(top_builddir)/website/download/builder/index: $(index_fragments)
	rm -f $@ $@-t
	LANG=C sh -c 'cat *.index-fragment' > $@-t
	mv $@-t $@
	@echo "NOTE: $@.asc must be updated by running:"
	@echo "    gpg --clearsign --armor $@"

# Validates the index file.
TESTS_ENVIRONMENT = $(top_builddir)/run --test
TESTS = validate.sh

check-valgrind:
	$(MAKE) VG="@VG@" check
