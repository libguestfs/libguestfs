# virt-customize
# Copyright (C) 2014-2019 Red Hat Inc.
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

EXTRA_DIST = \
	$(generator_built) \
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	customize_main.ml \
	test-firstboot.sh \
	test-password.pl \
	test-selinuxrelabel.sh \
	test-settings.sh \
	test-virt-customize.sh \
	test-virt-customize-docs.sh \
	virt-customize.pod

generator_built = \
	customize_cmdline.mli \
	customize_cmdline.ml \
	customize-options.pod \
	customize-synopsis.pod

SOURCES_MLI = \
	append_line.mli \
	crypt.mli \
	customize_cmdline.mli \
	customize_main.mli \
	customize_run.mli \
	firstboot.mli \
	hostname.mli \
	password.mli \
	perl_edit.mli \
	random_seed.mli \
	SELinux_relabel.mli \
	ssh_key.mli \
	subscription_manager.mli \
	timezone.mli

# This list must be in dependency order.
SOURCES_ML = \
	append_line.ml \
	crypt.ml \
	firstboot.ml \
	hostname.ml \
	password.ml \
	perl_edit.ml \
	random_seed.ml \
	SELinux_relabel.ml \
	ssh_key.ml \
	subscription_manager.ml \
	timezone.ml \
	customize_cmdline.ml \
	customize_run.ml

SOURCES_C = \
	../common/edit/file-edit.c \
	../common/edit/file-edit.h \
	crypt-c.c \
	perl_edit-c.c

if HAVE_OCAML

# Build the virt-customize objects into a library, since these are
# reused by virt-builder and virt-sysprep.  We pretend we are building
# a C library.  automake handles the compilation of C sources for us.
# At the end we take the C objects and OCaml objects and link them
# into the OCaml library.  This C library is never used.
noinst_LIBRARIES = libcustomize.a

if !HAVE_OCAMLOPT
CUSTOMIZE_CMA = customize.cma
else
CUSTOMIZE_CMA = customize.cmxa
endif

noinst_DATA = $(CUSTOMIZE_CMA)

libcustomize_a_SOURCES = $(SOURCES_C)
libcustomize_a_CPPFLAGS = \
	-DCAML_NAME_SPACE \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib \
	-I$(top_srcdir)/common/edit
libcustomize_a_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBCRYPT_CFLAGS) \
	$(LIBVIRT_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	-fPIC

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

# -I $(top_builddir)/lib/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/lib/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/common/mlgettext \
	-I $(top_builddir)/common/mlpcre \
	-I $(top_builddir)/common/mltools \
	-I $(builddir)
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

libcustomize_a_DEPENDENCIES = $(OBJECTS)

$(CUSTOMIZE_CMA): $(OBJECTS) libcustomize.a
	$(OCAMLFIND) mklib $(OCAMLPACKAGES) \
	    $(OBJECTS) $(libcustomize_a_OBJECTS) -o customize

# Build the virt-customize program.
bin_PROGRAMS = virt-customize

virt_customize_SOURCES = dummy.c

CUSTOMIZE_BOBJECTS = customize_main.cmo
CUSTOMIZE_XOBJECTS = $(CUSTOMIZE_BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_BOBJECTS)
else
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_XOBJECTS)
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlguestfs.$(MLARCHIVE) \
	mlgettext.$(MLARCHIVE) \
	mlpcre.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	mltools.$(MLARCHIVE) \
	customize.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

OCAMLCLIBS = \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

virt_customize_DEPENDENCIES = \
	$(top_srcdir)/ocaml-link.sh \
	$(CUSTOMIZE_THEOBJECTS) \
	$(CUSTOMIZE_CMA) \
	../common/mlutils/mlcutils.$(MLARCHIVE) \
	../common/mlgettext/mlgettext.$(MLARCHIVE) \
	../common/mlpcre/mlpcre.$(MLARCHIVE) \
	../common/mltools/mltools.$(MLARCHIVE)
virt_customize_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(CUSTOMIZE_THEOBJECTS) -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-customize.1
noinst_DATA += $(top_builddir)/website/virt-customize.1.html

virt-customize.1 $(top_builddir)/website/virt-customize.1.html: stamp-virt-customize.pod

stamp-virt-customize.pod: virt-customize.pod $(top_srcdir)/customize/customize-synopsis.pod $(top_srcdir)/customize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-customize.1 \
	  --html $(top_builddir)/website/virt-customize.1.html \
	  --insert $(top_srcdir)/customize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/customize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-customize-docs.sh

if ENABLE_APPLIANCE
TESTS += \
	test-virt-customize.sh \
	$(SLOW_TESTS)
endif

check-valgrind:
	$(MAKE) VG="@VG@" check

# Slow tests of virt-customize functionality in real guests.

SLOW_TESTS = \
	$(firstboot_test_scripts) \
	$(password_test_scripts) \
	test-selinuxrelabel.sh \
	$(settings_test_scripts)

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

firstboot_test_scripts := \
	test-firstboot-rhel-4.9.sh \
	test-firstboot-rhel-5.11.sh \
	test-firstboot-rhel-6.8.sh \
	test-firstboot-rhel-7.2.sh \
	test-firstboot-debian-6.sh \
	test-firstboot-debian-7.sh \
	test-firstboot-debian-8.sh \
	test-firstboot-fedora-26.sh \
	test-firstboot-fedora-27.sh \
	test-firstboot-ubuntu-10.04.sh \
	test-firstboot-ubuntu-12.04.sh \
	test-firstboot-ubuntu-14.04.sh \
	test-firstboot-ubuntu-16.04.sh \
	test-firstboot-ubuntu-18.04.sh \
	test-firstboot-windows-6.2-server.sh \
	test-firstboot-windows-6.3-server.sh \
	test-firstboot-windows-10.0-server.sh
# Firstboot is known-broken on RHEL 3:
#	test-firstboot-rhel-3.9.sh

test-firstboot-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-firstboot-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-firstboot.sh' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

password_test_scripts := \
	test-password-centos-7.2.sh \
	test-password-debian-6.sh \
	test-password-debian-7.sh \
	test-password-debian-8.sh \
	test-password-fedora-27.sh \
	test-password-rhel-3.9.sh \
	test-password-rhel-4.9.sh \
	test-password-rhel-5.11.sh \
	test-password-rhel-6.9.sh \
	test-password-rhel-7.2.sh \
	test-password-ubuntu-10.04.sh \
	test-password-ubuntu-12.04.sh \
	test-password-ubuntu-14.04.sh \
	test-password-ubuntu-16.04.sh \
	test-password-ubuntu-18.04.sh

test-password-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-password-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-password.pl' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

settings_test_scripts := \
	test-settings-rhel-4.9.sh \
	test-settings-rhel-5.11.sh \
	test-settings-rhel-6.8.sh \
	test-settings-rhel-7.2.sh \
	test-settings-debian-6.sh \
	test-settings-debian-7.sh \
	test-settings-debian-8.sh \
	test-settings-fedora-27.sh \
	test-settings-ubuntu-10.04.sh \
	test-settings-ubuntu-12.04.sh \
	test-settings-ubuntu-14.04.sh \
	test-settings-ubuntu-16.04.sh \
	test-settings-ubuntu-18.04.sh
# Since firstboot is broken, we cannot test settings in RHEL 3:
#	test-settings-rhel-3.9.sh

test-settings-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-settings-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-settings.sh' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

CLEANFILES += \
	$(firstboot_test_scripts) \
	$(password_test_scripts) \
	$(settings_test_scripts) \
	firstboot-*.img \
	password-*.img \
	password-*.log \
	settings-*.img

# OCaml dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif

.PHONY: docs
