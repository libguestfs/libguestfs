# libguestfs
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

# Extra tests.
#
# Requires:
#   - some local libvirt guests are available
#   - the disks of these guests are accessible by the current user
#     (tip: add yourself to the 'disk' group)
#   - valgrind
#   - libtool
#   - qemu in $QEMUDIR
#
# These tests may fail for reasons which aren't necessarily real problems.
#
# XXX Not tested:
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

# Old RHEL 5 autoconf doesn't have abs_srcdir.
abs_srcdir ?= $(shell cd $(top_srcdir)/tests/extra && pwd)

# Old RHEL 5 autoconf doesn't have abs_builddir.
abs_builddir ?= $(shell pwd)

EXTRA_DIST = pick-guests.pl suppressions

VG = $(VALGRIND) \
	$(VALGRIND_NO_VGDB) \
	--log-file=$(abs_builddir)/valgrind.log \
	--leak-check=full \
	--error-exitcode=119 \
	--suppressions=$(abs_srcdir)/suppressions
RUN_VG = $(abs_top_builddir)/run $(VG)

export LIBVIRT_DEFAULT_URI = \
	qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro

# Choose guests at random on each run.
#
# 'export LIBVIRT_DEFAULT_URI' above doesn't appear to have an effect
# for $(shell ...) commands, so we have to redefine LIBVIRT_DEFAULT_URI here.
random_guests := \
	$(shell \
	  LIBVIRT_DEFAULT_URI='qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro' \
	    $(abs_top_builddir)/run $(srcdir)/pick-guests.pl 5)

extra-tests: \
	test-guests \
	test-prerequisites \
	test-c-api \
	test-tools-null \
	test-tools-internal \
	test-df-real \
	test-filesystems-real \
	test-inspector-real \
	test-sysprep-real \
	test-ocaml \
	test-resize \
	test-sparsify \
	test-upstream-qemu

test-guests:
	$(MAKE) -C ../guests check

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
	$(RUN_VG) ../../fish/guestfish -N part exit
	$(RUN_VG) ../../align/virt-alignment-scan -a test1.img >/dev/null
	$(RUN_VG) ../../format/virt-format -a test1.img >/dev/null
	rm test1.img
	$(RUN_VG) ../../cat/virt-filesystems -a /dev/null >/dev/null
	$(RUN_VG) ../../cat/virt-filesystems -a /dev/null --all --long -h --uuid >/dev/null
	$(RUN_VG) ../../df/virt-df -a /dev/null >/dev/null
	$(RUN_VG) ../../fish/guestfish -a /dev/null run
	$(RUN_VG) ../../inspector/virt-inspector -a /dev/null >/dev/null
	$(RUN_VG) ../../test-tool/libguestfs-test-tool >/dev/null 2>&1

# Invocations of tools on internal images shouldn't leak memory.
test-tools-internal:
	$(RUN_VG) ../../cat/virt-cat -a ../guests/fedora.img /etc/fstab >/dev/null
	$(RUN_VG) ../../cat/virt-filesystems -a ../guests/fedora.img >/dev/null
	$(RUN_VG) ../../cat/virt-filesystems -a ../guests/fedora.img --all --long -h --uuid >/dev/null
	$(RUN_VG) ../../cat/virt-ls -a ../guests/fedora.img / >/dev/null
	$(RUN_VG) ../../cat/virt-ls -a ../guests/fedora.img -l / >/dev/null
	$(RUN_VG) ../../cat/virt-ls -a ../guests/fedora.img -R / >/dev/null
	$(RUN_VG) ../../cat/virt-ls -a ../guests/fedora.img -lR / >/dev/null
	$(RUN_VG) ../../df/virt-df -a ../guests/fedora.img >/dev/null
	$(RUN_VG) ../../df/virt-df -a ../guests/fedora.img -h >/dev/null
	$(RUN_VG) ../../fish/guestfish -a ../guests/fedora.img run
	$(RUN_VG) ../../fish/guestfish -a ../guests/fedora.img -i exit
	$(RUN_VG) ../../inspector/virt-inspector -a ../guests/debian.img >/dev/null
	$(RUN_VG) ../../inspector/virt-inspector -a ../guests/fedora.img >/dev/null
	$(RUN_VG) ../../inspector/virt-inspector -a ../guests/fedora-md1.img -a ../guests/fedora-md2.img >/dev/null
	$(RUN_VG) ../../inspector/virt-inspector -a ../guests/ubuntu.img >/dev/null
	$(RUN_VG) ../../inspector/virt-inspector -a ../guests/windows.img >/dev/null
	$(RUN_VG) ../../sysprep/virt-sysprep -n -a ../guests/debian.img
	$(RUN_VG) ../../sysprep/virt-sysprep -n -a ../guests/fedora.img
	$(RUN_VG) ../../sysprep/virt-sysprep -n -a ../guests/fedora-md1.img -a ../guests/fedora-md2.img
	$(RUN_VG) ../../sysprep/virt-sysprep -n -a ../guests/ubuntu.img
	$(RUN_VG) ../../sysprep/virt-sysprep -n -a ../guests/windows.img

# Invocations of tools on real images shouldn't leak memory.
test-df-real:
	$(RUN_VG) ../../df/virt-df >/dev/null
	$(RUN_VG) ../../df/virt-df -h >/dev/null

test-filesystems-real:
	@for g in $(random_guests); do \
	  echo $(RUN_VG) ../../cat/virt-filesystems -d $$g --all --long -h --uuid; \
	  $(RUN_VG) ../../cat/virt-filesystems -d $$g --all --long -h --uuid > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done

test-inspector-real:
	@for g in $(random_guests); do \
	  echo $(RUN_VG) ../../inspector/virt-inspector -d $$g; \
	  $(RUN_VG) ../../inspector/virt-inspector -d $$g > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done

test-sysprep-real:
	@for g in $(random_guests); do \
	  echo $(RUN_VG) ../../sysprep/virt-sysprep -n -d $$g; \
	  $(RUN_VG) ../../sysprep/virt-sysprep -n -d $$g > /dev/null; \
	  r=$$?; \
	  if [ $$r -ne 0 ]; then exit $$r; fi; \
	done

# Run virt-resize tests under valgrind.
test-resize:
	$(MAKE) -C ../../resize VG="$(VG)" check

# Run virt-sparsify tests under valgrind.
test-sparsify:
	$(MAKE) -C ../../sparsify VG="$(VG)" check

# Run c-api tests under valgrind.
test-c-api:
	$(MAKE) -C ../c-api VG="$(RUN_VG)" check

# Test OCaml bindings under valgrind.
test-ocaml:
	$(MAKE) -C ../../ocaml VG="$(VG)" check

# When running the extra tests, if directory $HOME/d/qemu exists then
# we will try to run the basic tests using the version of qemu from
# that directory.  eg. That might be qemu from git.
#
# The directory name can be overridden using:
#   make extra-tests QEMUDIR=/path/to/other/qemu

QEMUDIR = $(HOME)/d/qemu
export QEMUDIR
export abs_srcdir
export MAKE

test-upstream-qemu:
	./test-upstream-qemu.sh
