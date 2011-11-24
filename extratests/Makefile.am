# libguestfs
# Copyright (C) 2009-2011 Red Hat Inc.
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

# Extra tests.
#
# Requires:
#   - some local libvirt guests are available
#   - the disks of these guests are accessible by the current user
#     (tip: add yourself to the 'disk' group)
#   - valgrind
#
# These tests may fail for reasons which aren't necessarily real problems.

EXTRA_DIST = suppressions

VG = ../run \
	valgrind \
	--log-file=valgrind.log \
	--leak-check=full \
	--error-exitcode=119 \
	--suppressions=suppressions

export LIBVIRT_DEFAULT_URI = \
	qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro

GUESTS = $(shell virsh -c $(LIBVIRT_DEFAULT_URI) list --all | \
		 head -n -1 | \
		 tail -n +3 | \
		 awk '{print $$2}')

extra-tests: test-tools-null test-tools-internal test-tools-real

# Null invocations of the basic tools shouldn't leak memory.
test-tools-null:
	$(VG) ../fish/guestfish -N part exit
	$(VG) ../align/virt-alignment-scan -a test1.img >/dev/null
	rm test1.img
	$(VG) ../cat/virt-filesystems -a /dev/null >/dev/null
	$(VG) ../cat/virt-filesystems -a /dev/null --all --long -h --uuid >/dev/null
	$(VG) ../df/virt-df -a /dev/null >/dev/null
	$(VG) ../fish/guestfish -a /dev/null run
	$(VG) ../inspector/virt-inspector -a /dev/null >/dev/null
	$(VG) ../test-tool/libguestfs-test-tool >/dev/null 2>&1

# Invocations of tools on internal images shouldn't leak memory.
test-tools-internal:
	$(VG) ../cat/virt-cat -a ../images/fedora.img /etc/fstab >/dev/null
	$(VG) ../cat/virt-filesystems -a ../images/fedora.img >/dev/null
	$(VG) ../cat/virt-filesystems -a ../images/fedora.img --all --long -h --uuid >/dev/null
	$(VG) ../cat/virt-ls -a ../images/fedora.img / >/dev/null
	$(VG) ../cat/virt-ls -a ../images/fedora.img -l / >/dev/null
	$(VG) ../cat/virt-ls -a ../images/fedora.img -R / >/dev/null
	$(VG) ../cat/virt-ls -a ../images/fedora.img -lR / >/dev/null
	$(VG) ../df/virt-df -a ../images/fedora.img >/dev/null
	$(VG) ../df/virt-df -a ../images/fedora.img -h >/dev/null
	$(VG) ../fish/guestfish -a ../images/fedora.img run
	$(VG) ../fish/guestfish -a ../images/fedora.img -i exit
	$(VG) ../inspector/virt-inspector -a ../images/debian.img >/dev/null
	$(VG) ../inspector/virt-inspector -a ../images/fedora.img >/dev/null
	$(VG) ../inspector/virt-inspector -a ../images/ubuntu.img >/dev/null
	$(VG) ../inspector/virt-inspector -a ../images/windows.img >/dev/null

# Invocations of tools on real images shouldn't leak memory.
test-tools-real:
	$(VG) virt-df >/dev/null
	$(VG) virt-df -h >/dev/null
	@for g in $(GUESTS); do \
	  echo $(VG) ../inspector/virt-inspector -d $$g; \
	  $(VG) ../inspector/virt-inspector -d $$g > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done
	@for g in $(GUESTS); do \
	  echo $(VG) ../cat/virt-filesystems -d $$g --all --long -h --uuid; \
	  $(VG) ../cat/virt-filesystems -d $$g --all --long -h --uuid > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done


# XXX Not tested:
# ../clone/virt-sysprep
# ../edit/virt-edit
# ../edit/virt-edit -e
# ../fuse/guestmount
# ../resize/virt-resize (OCaml)
# ../sparsify/virt-sparsify (OCaml)
# ../tools/virt-win-reg (Perl)
# ../tools/virt-make-fs (Perl)
