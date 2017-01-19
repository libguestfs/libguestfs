# libguestfs
# Copyright (C) 2017 Red Hat Inc.
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
	guestfs_protocol.x

BUILT_SOURCES = \
	$(generator_built) \
	guestfs_protocol.c \
	guestfs_protocol.h

EXTRA_DIST = \
	$(BUILT_SOURCES)

noinst_LTLIBRARIES = libprotocol.la

# Because rpcgen generates archaic code, we cannot use ordinary
# warnings here.
libprotocol_la_SOURCES = guestfs_protocol.c  guestfs_protocol.h
libprotocol_la_CFLAGS = \
	-Wall -Wno-unused -fno-strict-aliasing $(GCC_VISIBILITY_HIDDEN)

if HAVE_RPCGEN
RPCGEN_DEFS =
if HAVE_XDR_U_INT64_T
RPCGEN_DEFS += -DHAVE_XDR_U_INT64_T=1
else
if HAVE_XDR_UINT64_T
RPCGEN_DEFS += -DHAVE_XDR_UINT64_T=1
endif
endif

guestfs_protocol.c: guestfs_protocol.x
	rm -f $@-t $@-t2
	$(RPCGEN) $(RPCGEN_DEFS) -c -o $@-t $<
	$(SED) 's,\.\./\(\.\./\)*src,.,' < $@-t > $@-t2
	rm $@-t
	mv $@-t2 $@

guestfs_protocol.h: guestfs_protocol.x
	rm -f $@-t
	$(RPCGEN) $(RPCGEN_DEFS) -h -o $@-t $<
	mv $@-t $@
endif
