# libguestfs virt-sysprep tool
# Copyright (C) 2012-2016 Red Hat Inc.
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
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	script1.sh script2.sh script3.sh script4.sh \
	test-virt-sysprep.sh \
	test-virt-sysprep-passwords.sh \
	test-virt-sysprep-script.sh \
	virt-sysprep.pod

CLEANFILES = \
	*~ *.annot *.cmi *.cmo *.cmx *.cmxa *.o \
	stamp-virt-sysprep.pod \
	virt-sysprep \
	virt-sysprep.1

# Filenames sysprep_operation_<name>.ml in alphabetical order.
operations = \
	abrt_data \
	bash_history \
	blkid_tab \
	ca_certificates \
	crash_data \
	cron_spool \
	customize \
	dhcp_client_state \
	dhcp_server_state \
	dovecot_data \
	flag_reconfiguration \
	firewall_rules \
	fs_uuids \
	kerberos_data \
	lvm_uuids \
	logfiles \
	machine_id \
	mail_spool \
	net_hostname \
	net_hwaddr \
	pacct_log \
	package_manager_cache \
	pam_data \
	puppet_data_log \
	rh_subscription_manager \
	rhn_systemid \
	rpm_db \
	samba_db_log \
	script \
	smolt_uuid \
	ssh_hostkeys \
	ssh_userdir \
	sssd_db_log \
	tmp_files \
	udev_persistent_net \
	user_account \
	utmp yum_uuid

SOURCES_MLI = \
	sysprep_operation.mli

SOURCES_ML = \
	sysprep_operation.ml \
	$(patsubst %,sysprep_operation_%.ml,$(operations)) \
	main.ml

SOURCES_C = \
	../mllib/dev_t-c.c \
	../mllib/uri-c.c \
	../mllib/mkdtemp-c.c \
	../customize/crypt-c.c \
	../customize/perl_edit-c.c \
	../fish/uri.c \
	../fish/file-edit.c

if HAVE_OCAML

bin_PROGRAMS = virt-sysprep

virt_sysprep_SOURCES = $(SOURCES_C)
virt_sysprep_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish
virt_sysprep_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

BOBJECTS = \
	$(top_builddir)/mllib/guestfs_config.cmo \
	$(top_builddir)/mllib/common_gettext.cmo \
	$(top_builddir)/mllib/dev_t.cmo \
	$(top_builddir)/mllib/common_utils.cmo \
	$(top_builddir)/mllib/URI.cmo \
	$(top_builddir)/mllib/mkdtemp.cmo \
	$(top_builddir)/mllib/regedit.cmo \
	$(top_builddir)/customize/customize_utils.cmo \
	$(top_builddir)/customize/crypt.cmo \
	$(top_builddir)/customize/urandom.cmo \
	$(top_builddir)/customize/password.cmo \
	$(top_builddir)/customize/random_seed.cmo \
	$(top_builddir)/customize/hostname.cmo \
	$(top_builddir)/customize/timezone.cmo \
	$(top_builddir)/customize/firstboot.cmo \
	$(top_builddir)/customize/perl_edit.cmo \
	$(top_builddir)/customize/ssh_key.cmo \
	$(top_builddir)/customize/subscription_manager.cmo \
	$(top_builddir)/customize/customize_cmdline.cmo \
	$(top_builddir)/customize/customize_run.cmo \
	$(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(top_builddir)/customize
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCLIBS = \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
BEST    = c
OCAMLLINKFLAGS = mlguestfs.cma -custom
else
OBJECTS = $(XOBJECTS)
BEST    = opt
OCAMLLINKFLAGS = mlguestfs.cmxa
endif

virt_sysprep_DEPENDENCIES = $(OBJECTS) $(top_srcdir)/ocaml-link.sh
virt_sysprep_LINK = \
	$(top_srcdir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-sysprep.1
noinst_DATA = $(top_builddir)/website/virt-sysprep.1.html

virt-sysprep.1 $(top_builddir)/website/virt-sysprep.1.html: stamp-virt-sysprep.pod

stamp-virt-sysprep.pod: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(PODWRAPPER) \
	  --man virt-sysprep.1 \
          --insert sysprep-extra-options.pod:__EXTRA_OPTIONS__ \
          --insert sysprep-operations.pod:__OPERATIONS__ \
	  --html $(top_builddir)/website/virt-sysprep.1.html \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

sysprep-extra-options.pod: virt-sysprep
	rm -f $@ $@-t
	$(top_builddir)/run $< --dump-pod-options > $@-t
	mv $@-t $@

sysprep-operations.pod: virt-sysprep
	rm -f $@ $@-t
	$(top_builddir)/run $< --dump-pod > $@-t
	mv $@-t $@

# Tests.

TESTS_ENVIRONMENT = \
	abs_builddir=$(abs_builddir) \
	abs_srcdir=$(abs_srcdir) \
	PATH=$(abs_top_builddir)/fuse:$(PATH) \
	$(top_builddir)/run --test

if ENABLE_APPLIANCE
TESTS = \
	test-virt-sysprep.sh \
	test-virt-sysprep-passwords.sh

if HAVE_FUSE
TESTS += \
	test-virt-sysprep-script.sh
endif HAVE_FUSE
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) TESTS="test-virt-sysprep.sh" VG="$(top_builddir)/run @VG@" check

check-valgrind-local-guests:
	for g in $(GUESTS); do \
	  $(top_builddir)/run --test @VG@ virt-sysprep -n -c "$(libvirt_ro_uri)" -d "$$g" || exit $$?; \
	done

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) -I $(abs_top_builddir)/mllib -I $(abs_top_builddir)/customize $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

DISTCLEANFILES = .depend

.PHONY: depend docs
