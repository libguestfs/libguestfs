# libguestfs PHP bindings
# Copyright (C) 2010 Red Hat Inc.
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

# Old RHEL 5 autoconf doesn't have abs_srcdir.
abs_srcdir ?= $(shell cd $(top_srcdir)/php && pwd)

generator_built = \
	extension/php_guestfs_php.h \
	extension/guestfs_php.c

EXTRA_DIST = \
	$(generator_built) \
	run-php-tests.sh \
	extension/guestfs_php_*.phpt \
	extension/config.m4 \
	README-PHP \
	guestfs_php.ini

if HAVE_PHP

phpdir = $(sysconfdir)/php.d
php_DATA = guestfs_php.ini

# In theory: EXTRA_LIBS="-lguestfs"  In fact this doesn't work
# and we need to add the library to EXTRA_LDFLAGS.
all: extension/config.h
	$(MAKE) -C extension \
	  EXTRA_INCLUDES="-I$(abs_srcdir)/../src" \
	  EXTRA_LDFLAGS="-L$(abs_srcdir)/../src/.libs -lguestfs" \
	  all

extension/config.h: extension/config.m4 ../config.status
	cd extension && phpize
	cd extension && ./configure --prefix=$(prefix) --libdir=$(libdir)
	test -f "$@" && touch -- $@

TESTS = run-php-tests.sh

# Before PHP 5.4.0, the extension directory didn't have a 'make clean'
# rule.  Therefore, don't die if this fails.
clean-local:
	-$(MAKE) -C extension clean

install-data-hook:
	$(MAKE) -C extension INSTALL_ROOT=$(DESTDIR) install

endif
