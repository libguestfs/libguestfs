# libguestfs virt-p2v
# Copyright (C) 2009-2017 Red Hat Inc.
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

# This directory contains a copy of the miniexpect library from
# http://git.annexia.org/?p=miniexpect.git;a=summary
# This is used in virt-p2v.
noinst_LTLIBRARIES = libminiexpect.la

libminiexpect_la_SOURCES = \
	miniexpect.c \
	miniexpect.h
libminiexpect_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(PCRE_CFLAGS)
libminiexpect_la_LIBADD = \
	$(PCRE_LIBS)
