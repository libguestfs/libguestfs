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

generator_built = \
	extension/php_guestfs_php.h \
	extension/guestfs_php.c

EXTRA_DIST = \
	$(generator_built) \
	run-php-tests.sh \
	extension/tests/guestfs_*.phpt \
	extension/config.m4 \
	README-PHP \
	guestfs_php.ini

if HAVE_PHP

phpdir = $(sysconfdir)/php.d
php_DATA = guestfs_php.ini

# In theory: EXTRA_LIBS="-lguestfs"  In fact this doesn't work
# and we need to add the library to EXTRA_LDFLAGS.
all: check-builddir-equals-srcdir extension/config.h
	$(MAKE) -C extension \
	  EXTRA_INCLUDES="-I$(abs_srcdir)/../common/utils -I$(abs_srcdir)/../lib -I$(abs_srcdir)/../include" \
	  EXTRA_LDFLAGS="-L$(abs_srcdir)/../lib/.libs -lguestfs" \
	  EXTRA_CFLAGS="-DGUESTFS_PRIVATE=1" \
	  all

# It looks like this is going to be very hard to make work, so
# disallow it for now.
check-builddir-equals-srcdir:
	@if [ $(builddir) != $(srcdir) ]; then \
	  echo "***"; \
	  echo "PHP cannot be built with builddir != srcdir"; \
	  echo "Use ./configure --disable-php"; \
	  echo "***"; \
	  exit 1; \
	fi

extension/config.h: extension/config.m4 ../config.status
	cd extension && phpize
	cd extension && ./configure --prefix=$(prefix) --libdir=$(libdir)
	test -f "$@" && touch -- $@

# Don't use --test because PHP always returns a success code.
TESTS_ENVIRONMENT = \
	MAKE=$(MAKE) \
	$(top_builddir)/run

TESTS = run-php-tests.sh

# Before PHP 5.4.0, the extension directory didn't have a 'make clean'
# rule.  Therefore, don't die if this fails.
clean-local:
	-$(MAKE) -C extension clean
	rm -f extension/tests/*.exp
	rm -f extension/tests/*.log
	rm -f extension/tests/*.out
	rm -f extension/tests/*.php
	rm -f extension/tests/*.sh

install-data-hook:
	$(MAKE) -C extension INSTALL_ROOT=$(DESTDIR) install

endif
