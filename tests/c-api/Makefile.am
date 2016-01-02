# libguestfs
# Copyright (C) 2009-2016 Red Hat Inc.
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

generator_built = tests.c

BUILT_SOURCES = $(generator_built)

EXTRA_DIST = $(BUILT_SOURCES)

CLEANFILES = \
	test.log \
	testdownload.tmp

check_PROGRAMS = \
	tests \
	test-command \
	test-just-header \
	test-create-handle \
	test-config \
	test-add-drive-opts \
	test-last-errno \
	test-backend-settings \
	test-private-data \
	test-user-cancel \
	test-debug-to-file \
	test-environment \
	test-pwd \
	test-event-string
if HAVE_LIBDL
check_PROGRAMS += \
	test-dlopen
endif

TESTS = \
	tests \
	test-just-header \
	test-create-handle \
	test-config \
	test-add-drive-opts \
	test-last-errno \
	test-backend-settings \
	test-private-data \
	test-user-cancel \
	test-debug-to-file \
	test-environment \
	test-event-string
if HAVE_LIBDL
TESTS += \
	test-dlopen
endif

if HAVE_CXX
check_PROGRAMS += test-just-header-cxx
TESTS += test-just-header-cxx
endif

if HAVE_LIBVIRT
check_PROGRAMS += test-add-libvirt-dom
TESTS += test-add-libvirt-dom
endif
EXTRA_DIST += test-add-libvirt-dom.c

TESTS_ENVIRONMENT = \
	SKIP_TEST_COMMAND=$(shell ldd test-command | grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_COMMAND_LINES=$(shell ldd test-command | grep -sq 'not a dynamic executable' || echo 1) \
	SKIP_TEST_COMMAND=$(shell ldd test-pwd | grep -sq 'not a dynamic executable' || echo 1) \
	$(top_builddir)/run --test $(VG)

#SKIP_TEST_CHECKSUM_8=$(shell if test `find ../initramfs -name squashfs.ko | wc -l` -eq 0; then echo 1; fi)

tests_SOURCES = \
	tests.c \
	tests.h \
	tests-main.c
tests_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
tests_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS)
tests_LDADD = \
	$(PCRE_LIBS) \
	$(top_builddir)/src/libutils.la \
	$(top_builddir)/src/libguestfs.la \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

# This binary must be statically linked.  It is used for testing
# the "guestfs_command" and "guestfs_command_lines" functions.

test_command_SOURCES = test-command.c
test_command_LDFLAGS = -all-static

test_pwd_SOURCES = test-pwd.c
test_pwd_LDFLAGS = -all-static

# Hand-written C API tests.

test_just_header_SOURCES = test-just-header.c
test_just_header_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_just_header_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_just_header_LDADD = \
	$(top_builddir)/src/libguestfs.la

if HAVE_CXX
test_just_header_cxx_SOURCES = test-just-header-cxx.cpp
test_just_header_cxx_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_just_header_cxx_CXXFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_just_header_cxx_LDADD = \
	$(top_builddir)/src/libguestfs.la
endif

test_create_handle_SOURCES = test-create-handle.c
test_create_handle_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_create_handle_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_create_handle_LDADD = \
	$(top_builddir)/src/libguestfs.la

if HAVE_LIBDL
test_dlopen_SOURCES = test-dlopen.c
test_dlopen_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_dlopen_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	-DLIBRARY=\"$(top_builddir)/src/.libs/libguestfs.so.0\"
test_dlopen_LDADD = \
	-ldl
endif

test_config_SOURCES = test-config.c
test_config_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_config_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_config_LDADD = \
	$(top_builddir)/src/libguestfs.la

test_add_drive_opts_SOURCES = test-add-drive-opts.c
test_add_drive_opts_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_add_drive_opts_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_add_drive_opts_LDADD = \
	$(top_builddir)/src/libguestfs.la

test_last_errno_SOURCES = test-last-errno.c
test_last_errno_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_last_errno_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_last_errno_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

test_backend_settings_SOURCES = test-backend-settings.c
test_backend_settings_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_backend_settings_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_backend_settings_LDADD = \
	$(top_builddir)/src/libutils_la-utils.lo \
	$(LTLIBINTL) \
	$(top_builddir)/src/libguestfs.la

test_private_data_SOURCES = test-private-data.c
test_private_data_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_private_data_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_private_data_LDADD = \
	$(top_builddir)/src/libguestfs.la

test_user_cancel_SOURCES = test-user-cancel.c
test_user_cancel_CPPFLAGS = \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(top_srcdir)/src -I$(top_builddir)/src
test_user_cancel_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_user_cancel_LDADD = \
	$(top_builddir)/src/libguestfs.la -lm \
	$(top_builddir)/gnulib/lib/libgnu.la

test_debug_to_file_SOURCES = test-debug-to-file.c
test_debug_to_file_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
test_debug_to_file_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_debug_to_file_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	$(top_builddir)/gnulib/lib/libgnu.la

test_environment_SOURCES = test-environment.c
test_environment_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
test_environment_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_environment_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

test_event_string_SOURCES = test-event-string.c
test_event_string_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
test_event_string_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_event_string_LDADD = \
	$(top_builddir)/src/libguestfs.la \
	$(LTLIBINTL) \
	$(top_builddir)/gnulib/lib/libgnu.la

if HAVE_LIBVIRT
test_add_libvirt_dom_SOURCES = test-add-libvirt-dom.c
test_add_libvirt_dom_CPPFLAGS = \
	-I$(top_srcdir)/src -I$(top_builddir)/src \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_builddir)/gnulib/lib
test_add_libvirt_dom_CFLAGS = \
	$(LIBVIRT_CFLAGS) \
	$(WARN_CFLAGS) $(WERROR_CFLAGS)
test_add_libvirt_dom_LDADD = \
	$(top_builddir)/src/libguestfs.la $(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	$(LTLIBTHREAD) $(top_builddir)/gnulib/lib/libgnu.la
endif

check-valgrind:
	$(MAKE) VG="$(top_builddir)/run @VG@" check
