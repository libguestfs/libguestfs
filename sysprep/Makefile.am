# libguestfs virt-sysprep tool
# Copyright (C) 2012-2014 Red Hat Inc.
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
	$(SOURCES) \
	script1.sh script2.sh script3.sh script4.sh \
	test-virt-sysprep.sh \
	test-virt-sysprep-passwords.sh \
	test-virt-sysprep-script.sh \
	virt-sysprep.pod

CLEANFILES = \
	*~ *.cmi *.cmo *.cmx *.cmxa *.o \
	virt-sysprep virt-sysprep.1 \
	stamp-virt-sysprep.pod

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

# Alphabetical order.
SOURCES = \
	main.ml \
	sysprep_operation.ml \
	sysprep_operation.mli \
	$(patsubst %,sysprep_operation_%.ml,$(operations))

if HAVE_OCAML

# Note this list must be in dependency order.
deps = \
	$(top_builddir)/mllib/config.cmx \
	$(top_builddir)/mllib/common_gettext.cmx \
	$(top_builddir)/mllib/tty-c.o \
	$(top_builddir)/mllib/tTY.cmx \
	$(top_builddir)/mllib/common_utils.cmx \
	$(top_builddir)/mllib/uri-c.o \
	$(top_builddir)/mllib/uRI.cmx \
	$(top_builddir)/mllib/mkdtemp-c.o \
	$(top_builddir)/mllib/mkdtemp.cmx \
	$(top_builddir)/mllib/regedit.cmx \
	$(top_builddir)/customize/crypt-c.o \
	$(top_builddir)/customize/crypt.cmx \
	$(top_builddir)/customize/urandom.cmx \
	$(top_builddir)/customize/password.cmx \
	$(top_builddir)/customize/random_seed.cmx \
	$(top_builddir)/customize/hostname.cmx \
	$(top_builddir)/customize/timezone.cmx \
	$(top_builddir)/customize/firstboot.cmx \
	$(top_builddir)/customize/perl_edit-c.o \
	$(top_builddir)/customize/perl_edit.cmx \
	$(top_builddir)/customize/customize_cmdline.cmx \
	$(top_builddir)/customize/customize_run.cmx \
	$(top_builddir)/fish/guestfish-uri.o \
	$(top_builddir)/fish/guestfish-file-edit.o \
	sysprep_operation.cmx \
	$(patsubst %,sysprep_operation_%.cmx,$(operations)) \
	main.cmx

if HAVE_OCAMLOPT
OBJECTS = $(deps)
else
OBJECTS = $(patsubst %.cmx,%.cmo,$(deps))
endif

bin_SCRIPTS = virt-sysprep

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = \
	-package str,unix \
	-I $(top_builddir)/src/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/mllib \
	-I $(top_builddir)/customize
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX-3 $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

OCAMLCLIBS  = \
	$(LIBXML2_LIBS) -lncurses -lcrypt \
	-L../src/.libs -lutils \
	-L../gnulib/lib/.libs -lgnu

if HAVE_OCAMLOPT
virt-sysprep: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -o $@
else
virt-sysprep: $(OBJECTS)
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) \
	  mlguestfs.cma -linkpkg $^ \
	  -cclib '$(OCAMLCLIBS)' \
	  -custom \
	  -o $@
endif

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
if HAVE_OCAMLOPT
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -c $< -o $@
endif

# automake will decide we don't need C support in this file.  Really
# we do, so we have to provide it ourselves.

DEFAULT_INCLUDES = \
	-I. \
	-I$(top_builddir) \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/src \
	-I$(top_srcdir)/fish

.c.o:
	$(CC) $(CFLAGS) $(PROF_CFLAGS) $(DEFAULT_INCLUDES) -c $< -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-sysprep.1
noinst_DATA = $(top_builddir)/html/virt-sysprep.1.html

virt-sysprep.1 $(top_builddir)/html/virt-sysprep.1.html: stamp-virt-sysprep.pod

stamp-virt-sysprep.pod: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(PODWRAPPER) \
	  --man virt-sysprep.1 \
          --insert sysprep-extra-options.pod:__EXTRA_OPTIONS__ \
          --insert sysprep-operations.pod:__OPERATIONS__ \
	  --html $(top_builddir)/html/virt-sysprep.1.html \
	  --license GPLv2+ \
	  $<
	touch $@

sysprep-extra-options.pod: virt-sysprep
	rm -f $@ $@-t
	$(top_builddir)/run ./$< --dump-pod-options > $@-t
	mv $@-t $@

sysprep-operations.pod: virt-sysprep
	rm -f $@ $@-t
	$(top_builddir)/run ./$< --dump-pod > $@-t
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
	test-virt-sysprep-passwords.sh \
	test-virt-sysprep-script.sh
endif ENABLE_APPLIANCE

check-valgrind:
	$(MAKE) TESTS="test-virt-sysprep.sh" VG="$(top_builddir)/run @VG@" check

check-valgrind-local-guests:
	for g in $(GUESTS); do \
	  $(top_builddir)/run --test @VG@ ./virt-sysprep -n -c "$(libvirt_ro_uri)" -d "$$g" || exit $$?; \
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
