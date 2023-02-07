# libguestfs
# Copyright (C) 2009-2023 Red Hat Inc.
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

EXTRA_DIST =

generator_built = c-api/tests.c

BUILT_SOURCES = $(generator_built)

TESTS = $(SLOW_TESTS)
SLOW_TESTS =
check_PROGRAMS =

TESTS_ENVIRONMENT = \
	SKIP_TEST_COMMAND=$(shell ldd c-api/test-command |& grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_COMMAND_LINES=$(shell ldd c-api/test-command |& grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_COMMAND=$(shell ldd c-api/test-pwd |& grep -sq 'not a dynamic executable' || echo 1) \
	NOEXEC_CHECK="$(top_builddir)/lib/.libs/libguestfs.so $(top_builddir)/daemon/guestfsd" \
	$(top_builddir)/run --test
#SKIP_TEST_CHECKSUM_8=$(shell if test `find ../initramfs -name squashfs.ko | wc -l` -eq 0; then echo 1; fi)
# XXX Only for C programs somehow.
#LOG_COMPILER = $(VG)

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

check-valgrind:
	$(MAKE) VG="@VG@" check

SLOW_TESTS += bigdirs/test-big-dirs.pl
EXTRA_DIST += bigdirs/test-big-dirs.pl

TESTS += \
	btrfs/test-btrfs-misc.pl \
	btrfs/test-btrfs-devices.sh \
	btrfs/test-btrfs-subvolume-default.pl \
	btrfs/test-btrfs-replace.sh
EXTRA_DIST += \
	btrfs/test-btrfs-misc.pl \
	btrfs/test-btrfs-devices.sh \
	btrfs/test-btrfs-subvolume-default.pl \
	btrfs/test-btrfs-replace.sh

CLEANFILES += \
	c-api/test.log \
	c-api/testdownload.tmp

check_PROGRAMS += \
	c-api/tests \
	c-api/test-command \
	c-api/test-just-header \
	c-api/test-create-handle \
	c-api/test-config \
	c-api/test-add-drive-opts \
	c-api/test-last-errno \
	c-api/test-backend-settings \
	c-api/test-private-data \
	c-api/test-user-cancel \
	c-api/test-debug-to-file \
	c-api/test-environment \
	c-api/test-pwd \
	c-api/test-event-string \
	c-api/test-threads
if HAVE_LIBDL
check_PROGRAMS += \
	c-api/test-dlopen
endif

TESTS += \
	c-api/tests \
	c-api/test-just-header \
	c-api/test-create-handle \
	c-api/test-config \
	c-api/test-add-drive-opts \
	c-api/test-last-errno \
	c-api/test-backend-settings \
	c-api/test-private-data \
	c-api/test-user-cancel \
	c-api/test-debug-to-file \
	c-api/test-environment \
	c-api/test-event-string \
	c-api/test-threads
if HAVE_LIBDL
TESTS += \
	c-api/test-dlopen
endif

if HAVE_CXX
check_PROGRAMS += c-api/test-just-header-cxx
TESTS += c-api/test-just-header-cxx
endif

if HAVE_LIBVIRT
check_PROGRAMS += c-api/test-add-libvirt-dom
TESTS += c-api/test-add-libvirt-dom
endif
EXTRA_DIST += c-api/test-add-libvirt-dom.c

c_api_tests_SOURCES = \
	c-api/tests.c \
	c-api/tests.h \
	c-api/tests-main.c
c_api_tests_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
c_api_tests_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE2_CFLAGS)
c_api_tests_LDADD = \
	$(PCRE2_LIBS) \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

# This binary must be statically linked.  It is used for testing
# the "guestfs_command" and "guestfs_command_lines" functions.

c_api_test_command_SOURCES = c-api/test-command.c
c_api_test_command_LDFLAGS = -all-static

c_api_test_pwd_SOURCES = c-api/test-pwd.c
c_api_test_pwd_LDFLAGS = -all-static

# Hand-written C API tests.

c_api_test_just_header_SOURCES = c-api/test-just-header.c
c_api_test_just_header_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_just_header_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_just_header_LDADD = \
	$(top_builddir)/lib/libguestfs.la

if HAVE_CXX
c_api_test_just_header_cxx_SOURCES = c-api/test-just-header-cxx.cpp
c_api_test_just_header_cxx_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_just_header_cxx_CXXFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_just_header_cxx_LDADD = \
	$(top_builddir)/lib/libguestfs.la
endif

c_api_test_create_handle_SOURCES = c-api/test-create-handle.c
c_api_test_create_handle_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_create_handle_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_create_handle_LDADD = \
	$(top_builddir)/lib/libguestfs.la

if HAVE_LIBDL
c_api_test_dlopen_SOURCES = c-api/test-dlopen.c
c_api_test_dlopen_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_dlopen_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-DLIBRARY=\"$(top_builddir)/lib/.libs/libguestfs.so.0\"
c_api_test_dlopen_LDADD = \
	-ldl
endif

c_api_test_config_SOURCES = c-api/test-config.c
c_api_test_config_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_config_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_config_LDADD = \
	$(top_builddir)/lib/libguestfs.la

c_api_test_add_drive_opts_SOURCES = c-api/test-add-drive-opts.c
c_api_test_add_drive_opts_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_add_drive_opts_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_add_drive_opts_LDADD = \
	$(top_builddir)/lib/libguestfs.la

c_api_test_last_errno_SOURCES = c-api/test-last-errno.c
c_api_test_last_errno_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_last_errno_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_last_errno_LDADD = \
	$(top_builddir)/lib/libguestfs.la

c_api_test_backend_settings_SOURCES = c-api/test-backend-settings.c
c_api_test_backend_settings_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
c_api_test_backend_settings_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_backend_settings_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(LTLIBINTL) \
	$(top_builddir)/lib/libguestfs.la

c_api_test_private_data_SOURCES = c-api/test-private-data.c
c_api_test_private_data_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_private_data_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_private_data_LDADD = \
	$(top_builddir)/lib/libguestfs.la

c_api_test_user_cancel_SOURCES = c-api/test-user-cancel.c
c_api_test_user_cancel_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
c_api_test_user_cancel_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_user_cancel_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la -lm \
	$(top_builddir)/gnulib/lib/libgnu.la

c_api_test_debug_to_file_SOURCES = c-api/test-debug-to-file.c
c_api_test_debug_to_file_CPPFLAGS = \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib
c_api_test_debug_to_file_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_debug_to_file_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

c_api_test_environment_SOURCES = c-api/test-environment.c
c_api_test_environment_CPPFLAGS = -I$(top_srcdir)/include
c_api_test_environment_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_environment_LDADD = \
	$(top_builddir)/lib/libguestfs.la

c_api_test_event_string_SOURCES = c-api/test-event-string.c
c_api_test_event_string_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
c_api_test_event_string_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_event_string_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

c_api_test_threads_SOURCES = c-api/test-threads.c
c_api_test_threads_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
c_api_test_threads_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_threads_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(LTLIBTHREAD) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

if HAVE_LIBVIRT
c_api_test_add_libvirt_dom_SOURCES = c-api/test-add-libvirt-dom.c
c_api_test_add_libvirt_dom_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
c_api_test_add_libvirt_dom_CFLAGS = \
	$(LIBVIRT_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
c_api_test_add_libvirt_dom_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la $(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(LTLIBTHREAD) $(top_builddir)/gnulib/lib/libgnu.la
endif

TESTS += charsets/test-charset-fidelity

check_PROGRAMS += charsets/test-charset-fidelity

charsets_test_charset_fidelity_SOURCES = charsets/test-charset-fidelity.c
charsets_test_charset_fidelity_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
charsets_test_charset_fidelity_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
charsets_test_charset_fidelity_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

TESTS += create/test-disk-create.sh
EXTRA_DIST += create/test-disk-create.sh

TESTS += \
	discard/test-blkdiscard.pl \
	discard/test-discard.pl \
	discard/test-fstrim.pl
EXTRA_DIST += \
	discard/test-blkdiscard.pl \
	discard/test-discard.pl \
	discard/test-fstrim.pl

TESTS += disk-labels/test-disk-labels.pl
EXTRA_DIST += disk-labels/test-disk-labels.pl

TESTS += disks/test-qemu-drive.sh
EXTRA_DIST += disks/test-qemu-drive.sh

if HAVE_LIBVIRT
TESTS += \
	disks/test-qemu-drive-libvirt.sh \
	disks/test-qemu-drive-with-blocksize-libvirt.sh
EXTRA_DIST += \
	disks/test-qemu-drive-libvirt.sh \
	disks/test-qemu-drive-with-blocksize-libvirt.sh

if ENABLE_APPLIANCE
TESTS += \
	disks/test-27-disks.sh \
	disks/test-255-disks.sh \
	disks/test-add-lots-of-disks.sh \
	disks/test-add-drive-with-blocksize.sh
EXTRA_DIST += \
	disks/test-27-disks.sh \
	disks/test-255-disks.sh \
	disks/test-add-lots-of-disks.sh \
	disks/test-add-drive-with-blocksize.sh
endif
endif

SLOW_TESTS += disks/test-max-disks.sh
EXTRA_DIST += disks/test-max-disks.sh

check_PROGRAMS += disks/test-add-disks

disks_test_add_disks_SOURCES = \
	disks/test-add-disks.c
disks_test_add_disks_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib
disks_test_add_disks_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
disks_test_add_disks_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la \
	$(LIBXML2_LIBS)

EXTRA_DIST += disks/debug-qemu.sh

EXTRA_DIST += \
	events/test-console-debug.pl \
	events/libvirt-auth.xml

TESTS += events/test-console-debug.pl
EXTRA_DIST += events/test-console-debug.pl

if HAVE_LIBVIRT
TESTS += events/test-libvirt-auth-callbacks
check_PROGRAMS += events/test-libvirt-auth-callbacks

events_test_libvirt_auth_callbacks_SOURCES = \
	events/test-libvirt-auth-callbacks.c
events_test_libvirt_auth_callbacks_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
events_test_libvirt_auth_callbacks_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBVIRT_CFLAGS)
events_test_libvirt_auth_callbacks_LDADD = \
        $(top_builddir)/common/utils/libutils.la \
        $(top_builddir)/lib/libguestfs.la \
        $(LIBVIRT_LIBS) \
        $(LIBXML2_LIBS) \
        $(LTLIBINTL) \
        $(top_builddir)/gnulib/lib/libgnu.la
endif

TESTS += gdisk/test-expand-gpt.pl
EXTRA_DIST += gdisk/test-expand-gpt.pl

# Test uses the Python SimpleHTTPServer module which is
# conveniently part of Python core.

if HAVE_PYTHON

# Test disabled for now.  Several things conspire to stop this working:
#
# (1) Python may throw "Broken pipe" errors:
# http://bugs.python.org/issue14574
# Fixed upstream in Python >= 2.7.5.
#
# (2) Fedora 18's Curl is broken.  Can be resolved by compiling Curl
# from git and setting LD_LIBRARY_PATH=~/curl/lib/.libs

# TESTS = test-http.py
#
# TESTS_ENVIRONMENT = $(top_builddir)/run --test $(PYTHON)

endif

EXTRA_DIST += http/test-http.py

TESTS += journal/test-journal.pl
EXTRA_DIST += journal/test-journal.pl

TESTS += \
	luks/test-luks.sh \
	luks/test-luks-list.sh \
	luks/test-key-option.sh \
	luks/test-key-option-inspect-luks-on-lvm.sh \
	luks/test-key-option-inspect-lvm-on-luks.sh
EXTRA_DIST += \
	luks/test-luks.sh \
	luks/test-luks-list.sh \
	luks/test-key-option.sh \
	luks/test-key-option-inspect-luks-on-lvm.sh \
	luks/test-key-option-inspect-lvm-on-luks.sh

TESTS += \
	lvm/test-lvm-filtering.sh \
	lvm/test-lvm-mapping.pl
EXTRA_DIST += \
	lvm/test-lvm-filtering.sh \
	lvm/test-lvm-mapping.pl

TESTS += \
	md/test-inspect-fstab.sh \
	md/test-inspect-fstab-md.sh \
	md/test-list-filesystems.sh \
	md/test-list-md-devices.sh \
	md/test-lvm-on-md-device.sh \
	md/test-md-and-lvm-devices.sh \
	md/test-mdadm.sh \
	md/test-partitioned-md-devices.sh
EXTRA_DIST += \
	md/test-inspect-fstab.sh \
	md/test-inspect-fstab-md.sh \
	md/test-list-filesystems.sh \
	md/test-list-md-devices.sh \
	md/test-lvm-on-md-device.sh \
	md/test-md-and-lvm-devices.sh \
	md/test-mdadm.sh \
	md/test-partitioned-md-devices.sh

TESTS += \
	mountable/test-internal-parse-mountable \
	mountable/test-mountable-inspect.sh
EXTRA_DIST += \
	mountable/test-mountable-inspect.sh
check_PROGRAMS += \
	mountable/test-internal-parse-mountable

mountable_test_internal_parse_mountable_SOURCES = \
	mountable/test-internal-parse-mountable.c
mountable_test_internal_parse_mountable_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
mountable_test_internal_parse_mountable_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
mountable_test_internal_parse_mountable_LDADD = \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

if HAVE_FUSE

TESTS += mount-local/test-parallel-mount-local
check_PROGRAMS += mount-local/test-parallel-mount-local

mount_local_test_parallel_mount_local_SOURCES = \
	mount-local/test-parallel-mount-local.c
mount_local_test_parallel_mount_local_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/parallel -I$(top_builddir)/common/parallel
mount_local_test_parallel_mount_local_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(FUSE_CFLAGS)
mount_local_test_parallel_mount_local_LDADD = \
	$(FUSE_LIBS) \
	$(top_builddir)/common/parallel/libparallel.la \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

endif

TESTS += nbd/test-nbd.pl
EXTRA_DIST += nbd/test-nbd.pl

TESTS += network/test-network.sh
EXTRA_DIST += network/test-network.sh

TESTS += \
	ntfs/test-ntfscat.sh \
	ntfs/test-ntfsclone.sh
EXTRA_DIST += \
	ntfs/test-ntfscat.sh \
	ntfs/test-ntfsclone.sh

SLOW_TESTS += parallel/test-parallel
EXTRA_DIST += parallel/test-parallel

check_PROGRAMS += parallel/test-parallel

parallel_test_parallel_SOURCES = parallel/test-parallel.c
parallel_test_parallel_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
parallel_test_parallel_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
parallel_test_parallel_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

TESTS += \
	protocol/test-both-ends-cancel.sh \
	protocol/test-cancellation-download-librarycancels.sh \
	protocol/test-cancellation-upload-daemoncancels.sh \
	protocol/test-error-messages \
	protocol/test-launch-race.pl \
	protocol/test-qemudie-killsub.sh \
	protocol/test-qemudie-midcommand.sh \
	protocol/test-qemudie-synch.sh
EXTRA_DIST += \
	protocol/test-both-ends-cancel.sh \
	protocol/test-cancellation-download-librarycancels.sh \
	protocol/test-cancellation-upload-daemoncancels.sh \
	protocol/test-launch-race.pl \
	protocol/test-qemudie-killsub.sh \
	protocol/test-qemudie-midcommand.sh \
	protocol/test-qemudie-synch.sh

check_PROGRAMS += protocol/test-error-messages

protocol_test_error_messages_SOURCES = \
	../common/protocol/guestfs_protocol.h \
	protocol/test-error-messages.c
protocol_test_error_messages_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/protocol -I$(top_builddir)/common/protocol \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
protocol_test_error_messages_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(RPC_CFLAGS)
protocol_test_error_messages_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(top_builddir)/gnulib/lib/libgnu.la

TESTS += \
	qemu/qemu-liveness.sh \
	qemu/qemu-snapshot-isolation-add-drive-opts-readonly.sh \
	qemu/qemu-snapshot-isolation-add-drive-ro.sh \
	qemu/qemu-snapshot-isolation-qcow2.sh \
	qemu/qemu-force-tcg.sh
EXTRA_DIST += \
	qemu/qemu-liveness.sh \
	qemu/qemu-snapshot-isolation-add-drive-opts-readonly.sh \
	qemu/qemu-snapshot-isolation-add-drive-ro.sh \
	qemu/qemu-snapshot-isolation-qcow2.sh \
	qemu/qemu-force-tcg.sh

TESTS += \
	regressions/rhbz501893 \
	regressions/rhbz503169c13.sh \
	regressions/rhbz557655.sh \
	regressions/rhbz563450.sh \
	regressions/rhbz563450b.sh \
	regressions/rhbz576879.sh \
	regressions/rhbz578407.sh \
	regressions/rhbz580246.sh \
	regressions/rhbz602997.sh \
	regressions/rhbz690819.sh \
	regressions/rhbz789960.sh \
	regressions/rhbz790721 \
	regressions/rhbz811649.sh \
	regressions/rhbz895904.sh \
	regressions/rhbz914931 \
	regressions/rhbz957772.sh \
	regressions/rhbz975797.sh \
	regressions/rhbz1001875.sh \
	regressions/rhbz1054761.sh \
	regressions/rhbz1055452 \
	regressions/rhbz1091803.sh \
	regressions/rhbz1011907-1165785.sh \
	regressions/rhbz1174551.sh \
	regressions/rhbz1175196.sh \
	regressions/rhbz1370424.sh \
	regressions/rhbz1477623.sh \
	regressions/rhbz1930996.sh \
	regressions/test-big-heap \
	regressions/test-noexec-stack.pl
EXTRA_DIST += \
	regressions/rhbz503169c13.sh \
	regressions/rhbz557655.sh \
	regressions/rhbz557655-expected.stdout \
	regressions/rhbz557655-expected.stderr \
	regressions/rhbz563450.sh \
	regressions/rhbz563450b.sh \
	regressions/rhbz576879.sh \
	regressions/rhbz578407.sh \
	regressions/rhbz580246.sh \
	regressions/rhbz602997.sh \
	regressions/rhbz690819.sh \
	regressions/rhbz727178.sh \
	regressions/rhbz789960.sh \
	regressions/rhbz811649.sh \
	regressions/rhbz895904.sh \
	regressions/rhbz909624.sh \
	regressions/rhbz957772.sh \
	regressions/rhbz975797.sh \
	regressions/rhbz1001875.sh \
	regressions/rhbz1011907-1165785.sh \
	regressions/rhbz1044014.sh \
	regressions/rhbz1044014.in \
	regressions/rhbz1044014.xml \
	regressions/rhbz1054761.sh \
	regressions/rhbz1091803.sh \
	regressions/rhbz1174551.sh \
	regressions/rhbz1175196.sh \
	regressions/rhbz1370424.sh \
	regressions/rhbz1370424.xml \
	regressions/rhbz1477623.sh \
	regressions/rhbz1930996.sh \
	regressions/test-noexec-stack.pl

if HAVE_LIBVIRT
TESTS += regressions/rhbz1044014.sh
endif
EXTRA_DIST += regressions/rhbz1044014.sh

tests_not_run = regressions/rhbz727178.sh
EXTRA_DIST += regressions/rhbz727178.sh

check_PROGRAMS += \
	regressions/rhbz501893 \
	regressions/rhbz790721 \
	regressions/rhbz914931 \
	regressions/rhbz1055452 \
	regressions/test-big-heap

regressions_rhbz501893_SOURCES = regressions/rhbz501893.c
regressions_rhbz501893_CPPFLAGS = \
	-DGUESTFS_NO_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
regressions_rhbz501893_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
regressions_rhbz501893_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

regressions_rhbz790721_SOURCES = regressions/rhbz790721.c
regressions_rhbz790721_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
regressions_rhbz790721_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
regressions_rhbz790721_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

regressions_rhbz914931_SOURCES = regressions/rhbz914931.c
regressions_rhbz914931_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-DGUESTFS_PRIVATE=1
regressions_rhbz914931_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
regressions_rhbz914931_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(LTLIBINTL) \
	$(top_builddir)/lib/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

regressions_rhbz1055452_SOURCES = regressions/rhbz1055452.c
regressions_rhbz1055452_CPPFLAGS = \
	-DGUESTFS_NO_WARN_DEPRECATED=1 \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
regressions_rhbz1055452_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
regressions_rhbz1055452_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

regressions_test_big_heap_SOURCES = regressions/test-big-heap.c
regressions_test_big_heap_CPPFLAGS = \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include
regressions_test_big_heap_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
regressions_test_big_heap_LDADD = \
	$(top_builddir)/common/utils/libutils.la \
	$(top_builddir)/lib/libguestfs.la

SLOW_TESTS += regressions/rhbz909624.sh
EXTRA_DIST += regressions/rhbz909624.sh

TESTS += relabel/test-relabel.pl
EXTRA_DIST += relabel/test-relabel.pl

# Test relative paths to backing files.  Mainly this is a test that we
# don't break this.
#
# See eg:
# https://bugzilla.redhat.com/show_bug.cgi?id=1053684
# https://www.redhat.com/archives/libguestfs/2014-January/thread.html#00087
# (and more)

TESTS += relative-paths/test-relative-paths.sh
EXTRA_DIST += relative-paths/test-relative-paths.sh

TESTS += rsync/test-rsync.sh
EXTRA_DIST += rsync/test-rsync.sh

# Test extended attributes and SELinux labelling, both using the API
# directly, and over FUSE.

TESTS += \
	selinux/test-xattrs-direct.sh \
	selinux/test-selinux-direct.sh

if HAVE_FUSE
TESTS += \
	selinux/test-xattrs-fuse.sh \
	selinux/test-selinux-fuse.sh
endif

EXTRA_DIST += \
	selinux/run-test.pl \
	selinux/test-xattrs-direct.sh \
	selinux/test-xattrs-fuse.sh \
	selinux/test-selinux-direct.sh \
	selinux/test-selinux-fuse.sh

TESTS += \
	syslinux/test-syslinux.sh \
	syslinux/test-extlinux.sh

EXTRA_DIST += \
	syslinux/README \
	syslinux/test-syslinux.sh \
	syslinux/test-extlinux.sh \
	syslinux/test-syslinux.pl

CLEANFILES += syslinux/syslinux-guest.img syslinux/extlinux-guest.img

TESTS += tmpdirs/test-tmpdirs.pl
EXTRA_DIST += tmpdirs/test-tmpdirs.pl

TESTS += \
	tsk/test-download-inode.sh \
	tsk/test-download-blocks.sh \
	tsk/test-filesystem-walk.sh \
	tsk/test-find-inode.sh
EXTRA_DIST += \
	tsk/test-download-inode.sh \
	tsk/test-download-blocks.sh \
	tsk/test-filesystem-walk.sh \
	tsk/test-find-inode.sh

TESTS += xfs/test-xfs-misc.pl
EXTRA_DIST += xfs/test-xfs-misc.pl

# XXX Fix these tests.
# if HAVE_LIBVIRT

# # This LD_PRELOAD library can be used to precisely control the XML
# # returned by libvirt.
# check_LTLIBRARIES = xml/libfakevirtxml.la

# xml_libfakevirtxml_la_SOURCES = xml/fake-libvirt-xml.c
# xml_libfakevirtxml_la_CFLAGS = $(LIBVIRT_CFLAGS)
# # -version-info and -rpath force libtool to build a shared library.
# xml_libfakevirtxml_la_LDFLAGS = -version-info 0:0:0 -rpath /nowhere

# TESTS_ENVIRONMENT = \
# 	abs_srcdir=$(abs_srcdir) \
# 	LD_PRELOAD=.libs/libfakevirtxml.so \
# 	$(top_builddir)/run --test

# TESTS += xml/rhbz701814.pl
# endif

EXTRA_DIST += \
	xml/fake-libvirt-xml.c \
	xml/rhbz701814.pl \
	xml/rhbz701814-faked.xml \
	xml/rhbz701814-node.xml

TESTS += yara/test-yara-scan.sh
EXTRA_DIST += yara/test-yara-scan.sh
