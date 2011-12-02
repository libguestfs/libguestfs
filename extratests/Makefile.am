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
#   - libtool
#
# These tests may fail for reasons which aren't necessarily real problems.
#
# XXX Not tested:
#
# ../clone/virt-sysprep
#   - hard to test because it's a shell script
#
# ../edit/virt-edit
#
# Perl bindings
# ../edit/virt-edit -e
# ../tools/virt-win-reg (Perl)
# ../tools/virt-make-fs (Perl)
#   - hard because Perl doesn't cooperate by freeing memory
#
# Python bindings
#   - as for Perl
#
# Ruby bindings
#   - these look feasible to test using valgrind
#
# Java bindings
#
# ../fuse/guestmount
#   - hard to test because guestmount forks into the background, and
#     if valgrind reports errors it doesn't stop the test shell script

EXTRA_DIST = suppressions

VG = valgrind \
	--log-file=$(abs_builddir)/valgrind.log \
	--leak-check=full \
	--error-exitcode=119 \
	--suppressions=$(abs_srcdir)/suppressions
RUN_VG = $(abs_top_builddir)/run $(VG)

export LIBVIRT_DEFAULT_URI = \
	qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro

GUESTS = $(shell virsh -c $(LIBVIRT_DEFAULT_URI) list --all | \
		 head -n -1 | \
		 tail -n +3 | \
		 awk '{print $$2}')

extra-tests: \
	test-prerequisites \
	test-capitests \
	test-tools-null \
	test-tools-internal \
	test-df-real \
	test-filesystems-real \
	test-inspector-real \
	test-ocaml \
	test-resize \
	test-sparsify

test-prerequisites:
	@libtool --help >/dev/null 2>&1 || { \
	  echo "extra-tests: libtool is not installed"; \
	  exit 1; \
	}
	@valgrind --help >/dev/null 2>&1 || { \
	  echo "extra-tests: valgrind is not installed"; \
	  exit 1; \
	}

# Null invocations of the basic tools shouldn't leak memory.
test-tools-null:
	$(RUN_VG) ../fish/guestfish -N part exit
	$(RUN_VG) ../align/virt-alignment-scan -a test1.img >/dev/null
	rm test1.img
	$(RUN_VG) ../cat/virt-filesystems -a /dev/null >/dev/null
	$(RUN_VG) ../cat/virt-filesystems -a /dev/null --all --long -h --uuid >/dev/null
	$(RUN_VG) ../df/virt-df -a /dev/null >/dev/null
	$(RUN_VG) ../fish/guestfish -a /dev/null run
	$(RUN_VG) ../inspector/virt-inspector -a /dev/null >/dev/null
	$(RUN_VG) ../test-tool/libguestfs-test-tool >/dev/null 2>&1

# Invocations of tools on internal images shouldn't leak memory.
test-tools-internal:
	$(RUN_VG) ../cat/virt-cat -a ../images/fedora.img /etc/fstab >/dev/null
	$(RUN_VG) ../cat/virt-filesystems -a ../images/fedora.img >/dev/null
	$(RUN_VG) ../cat/virt-filesystems -a ../images/fedora.img --all --long -h --uuid >/dev/null
	$(RUN_VG) ../cat/virt-ls -a ../images/fedora.img / >/dev/null
	$(RUN_VG) ../cat/virt-ls -a ../images/fedora.img -l / >/dev/null
	$(RUN_VG) ../cat/virt-ls -a ../images/fedora.img -R / >/dev/null
	$(RUN_VG) ../cat/virt-ls -a ../images/fedora.img -lR / >/dev/null
	$(RUN_VG) ../df/virt-df -a ../images/fedora.img >/dev/null
	$(RUN_VG) ../df/virt-df -a ../images/fedora.img -h >/dev/null
	$(RUN_VG) ../fish/guestfish -a ../images/fedora.img run
	$(RUN_VG) ../fish/guestfish -a ../images/fedora.img -i exit
	$(RUN_VG) ../inspector/virt-inspector -a ../images/debian.img >/dev/null
	$(RUN_VG) ../inspector/virt-inspector -a ../images/fedora.img >/dev/null
	$(RUN_VG) ../inspector/virt-inspector -a ../images/ubuntu.img >/dev/null
	$(RUN_VG) ../inspector/virt-inspector -a ../images/windows.img >/dev/null

# Invocations of tools on real images shouldn't leak memory.
test-df-real:
	$(RUN_VG) virt-df >/dev/null
	$(RUN_VG) virt-df -h >/dev/null

test-filesystems-real:
	@for g in $(GUESTS); do \
	  echo $(RUN_VG) ../cat/virt-filesystems -d $$g --all --long -h --uuid; \
	  $(RUN_VG) ../cat/virt-filesystems -d $$g --all --long -h --uuid > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done

test-inspector-real:
	@for g in $(GUESTS); do \
	  echo $(RUN_VG) ../inspector/virt-inspector -d $$g; \
	  $(RUN_VG) ../inspector/virt-inspector -d $$g > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done

# Run virt-resize tests under valgrind.
test-resize:
	$(MAKE) -C ../resize VG="$(VG)" check

# Run virt-sparsify tests under valgrind.
test-sparsify:
	$(MAKE) -C ../sparsify VG="$(VG)" check

# Run capitests under valgrind.
test-capitests:
	$(MAKE) -C ../capitests VG="$(RUN_VG)" check

# Test OCaml bindings under valgrind.
test-ocaml:
	$(MAKE) -C ../ocaml VG="$(VG)" check
