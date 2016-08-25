# libguestfs
# Copyright (C) 2013-2016 Red Hat Inc.
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

scripts = \
	guestfish \
	guestmount \
	virt-alignment-scan \
	virt-rescue \
	virt-v2v

# Some of the scripts are simply symbolic links.
symlinks = \
	guestunmount \
	virt-builder \
	virt-cat \
	virt-copy-in \
	virt-copy-out \
	virt-customize \
	virt-diff \
	virt-df \
	virt-dib \
	virt-edit \
	virt-filesystems \
	virt-format \
	virt-get-kernel \
	virt-inspector \
	virt-log \
	virt-ls \
	virt-p2v-make-disk \
	virt-p2v-make-kickstart \
	virt-p2v-make-kiwi \
	virt-resize \
	virt-sparsify \
	virt-sysprep \
	virt-tar-in \
	virt-tar-out

# Note: Don't distribute the symbolic links, only the real files.
EXTRA_DIST = \
	README \
	$(scripts)

CLEANFILES = \
	$(symlinks)

# Any tool that has --short-options and --long-options is handled by
# this common script.  However this script cannot deal with commands
# that use --ro/--rw (eg. virt-rescue), nor commands that have lots of
# exceptions (eg. guestfish).  Those tools have to be handled
# individually.
guestunmount \
virt-builder virt-cat virt-customize virt-df virt-dib virt-diff \
virt-edit virt-filesystems virt-format virt-get-kernel virt-inspector \
virt-log virt-ls \
virt-p2v-make-disk virt-p2v-make-kickstart virt-p2v-make-kiwi \
virt-resize virt-sparsify virt-sysprep:
	rm -f $@
	$(LN_S) virt-alignment-scan $@

# guestfish is handled specially.
virt-copy-in virt-copy-out virt-tar-in virt-tar-out:
	rm -f $@
	$(LN_S) guestfish $@

if HAVE_BASH_COMPLETION

# Bash completion script.

bashcompletiondir = $(BASH_COMPLETIONS_DIR)
#bashcompletion_DATA = $(scripts)

all-local: $(scripts) $(symlinks)
	-test $(srcdir) != $(builddir) && cd $(srcdir) && cp $(scripts) $(abs_builddir)/

install-data-local:
	$(mkdir_p) $(DESTDIR)$(bashcompletiondir)
	cp -d $(scripts) $(symlinks) $(DESTDIR)$(bashcompletiondir)

clean-local:
	-test $(srcdir) != $(builddir) && rm -f $(scripts)

endif
