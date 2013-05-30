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

EXTRA_DIST = \
	test-http.py
