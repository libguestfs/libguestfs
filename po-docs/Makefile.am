# libguestfs translations of man pages and POD files
# Copyright (C) 2010-2012 Red Hat Inc.
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

# XXX The use of po4a is naive here.  Also we should integrate this
# into the po/ directory and the translations into the usual
# libguestfs.pot file.

# Languages.
LINGUAS = ja uk

EXTRA_DIST = \
	libguestfs-docs.pot \
	$(LINGUAS:%=%.po)

CLEANFILES = po4a.conf

# Build the final man pages from the translated POD files.  Each
# language directory contains a Makefile.am that we need to keep up to
# date (note each $lang/Makefile.am should be identical).
# XXX Is there a better way?
SUBDIRS = $(LINGUAS)

update-po: libguestfs-docs.pot

# Note: po4a leaves empty '=encoding' lines in POD files.  Also it
# includes a large warning message which ends up in the output.  We
# post-process the output to remove both.
libguestfs-docs.pot: po4a.conf
	$(PO4A) \
	  -M utf-8 -L utf-8 -A utf-8 \
	  -v \
	  -k 0 \
	  --package-name $(PACKAGE_NAME) \
	  --package-version $(PACKAGE_VERSION) \
	  --msgid-bugs-address libguestfs@redhat.com \
	  --copyright-holder "Red Hat Inc." \
	  po4a.conf
	for f in `find $(LINGUAS) -name '*.pod' -o -name '*.pl'`; do \
	  echo '=encoding utf8' > $$f.new; \
	  awk 'FNR >= 14 { print }' < $$f >> $$f.new; \
	  mv $$f.new $$f; \
	done

po4a.conf: podfiles
	rm -f $@-t
	echo "[po_directory] ." >> $@-t
	echo >> $@-t
	for f in `cat podfiles`; do \
	  b=`basename -- $$f`; \
	  echo "[type: pod] $$f \$$lang:\$$lang/$$b" >> $@-t; \
	  echo >> $@-t; \
	done;
	mv $@-t $@

podfiles: Makefile
	rm -f $@ $@-t
	find $(top_srcdir) -name '*.pod' | \
	  grep -v /debian/ | \
	  grep -v /libguestfs-1 | \
	  grep -v /po-docs/ | \
	  grep -v /stamp- \
	  > $@-t
	find $(top_srcdir)/tools -name 'virt-*.pl' >> $@-t
	LC_ALL=C sort -o $@-t $@-t
	mv $@-t $@
