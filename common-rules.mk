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

# 'common-rules.mk' should be included in every Makefile.am.
# cf. 'subdir-rules.mk'

-include $(top_builddir)/localenv

# Old RHEL 5 autoconf defines these, but RHEL 5 automake doesn't
# create variables for them.  So define them here if they're not
# defined already.
builddir     ?= @builddir@
abs_builddir ?= @abs_builddir@
srcdir       ?= @srcdir@
abs_srcdir   ?= @abs_srcdir@
