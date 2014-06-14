# libguestfs
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

scripts = \
	guestfish \
	guestmount \
	virt-alignment-scan \
	virt-builder \
	virt-cat \
	virt-df \
	virt-edit \
	virt-filesystems \
	virt-format \
	virt-inspector \
	virt-log \
	virt-ls \
	virt-rescue \
	virt-resize \
	virt-sparsify \
	virt-sysprep

EXTRA_DIST = \
	README \
	$(scripts)

# Some of the scripts are simply symbolic links.
virt-cat:
	ln -sf virt-alignment-scan $@
virt-df:
	ln -sf virt-alignment-scan $@
virt-edit:
	ln -sf virt-alignment-scan $@
virt-filesystems:
	ln -sf virt-alignment-scan $@
virt-format:
	ln -sf virt-alignment-scan $@
virt-inspector:
	ln -sf virt-alignment-scan $@
virt-log:
	ln -sf virt-alignment-scan $@
virt-ls:
	ln -sf virt-alignment-scan $@
virt-sysprep:
	ln -sf virt-alignment-scan $@

virt-builder:
	ln -sf virt-resize $@
virt-sparsify:
	ln -sf virt-resize $@

if HAVE_BASH_COMPLETION

# Bash completion script.

bashcompletiondir = $(BASH_COMPLETIONS_DIR)
bashcompletion_DATA = $(scripts)

endif
