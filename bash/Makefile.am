# libguestfs
# Copyright (C) 2013-2023 Red Hat Inc.
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
	guestunmount \
	libguestfs-test-tool \
	virt-rescue

# Some of the scripts are simply symbolic links.
symlinks = \
	virt-copy-in \
	virt-copy-out \
	virt-tar-in \
	virt-tar-out

# Note: Don't distribute the symbolic links, only the real files.
EXTRA_DIST = \
	README \
	$(scripts) \
	$(TESTS)

CLEANFILES += \
	$(symlinks)

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

# Tests.
TESTS_ENVIRONMENT = \
	scripts="$(scripts)" \
	symlinks="$(scripts)" \
	commands="$(scripts) $(symlinks)" \
	$(top_builddir)/run --test

TESTS = \
	test-complete-in-script.sh
