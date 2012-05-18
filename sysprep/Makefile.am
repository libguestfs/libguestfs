# libguestfs virt-sysprep tool
# Copyright (C) 2012 Red Hat Inc.
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
	test-virt-sysprep.sh \
	test-virt-sysprep-script.sh script1.sh script2.sh script3.sh \
	virt-sysprep.pod

CLEANFILES = \
	*~ *.cmi *.cmo *.cmx *.cmxa *.o \
	virt-sysprep virt-sysprep.1 \
	stamp-virt-sysprep.pod

# Alphabetical order.
SOURCES = \
	main.ml \
	sysprep_gettext.ml \
	sysprep_operation.ml \
	sysprep_operation.mli \
	sysprep_operation_bash_history.ml \
	sysprep_operation_blkid_tab.ml \
	sysprep_operation_ca_certificates.ml \
	sysprep_operation_cron_spool.ml \
	sysprep_operation_dhcp_client_state.ml \
	sysprep_operation_dhcp_server_state.ml \
	sysprep_operation_dovecot_data.ml \
	sysprep_operation_flag_reconfiguration.ml \
	sysprep_operation_hostname.ml \
	sysprep_operation_kerberos_data.ml \
	sysprep_operation_logfiles.ml \
	sysprep_operation_mail_spool.ml \
	sysprep_operation_net_hwaddr.ml \
	sysprep_operation_package_manager_cache.ml \
	sysprep_operation_pam_data.ml \
	sysprep_operation_random_seed.ml \
	sysprep_operation_rhn_systemid.ml \
	sysprep_operation_samba_db_log.ml \
	sysprep_operation_script.ml \
	sysprep_operation_smolt_uuid.ml \
	sysprep_operation_ssh_hostkeys.ml \
	sysprep_operation_ssh_userdir.ml \
	sysprep_operation_sssd_db_log.ml \
	sysprep_operation_udev_persistent_net.ml \
	sysprep_operation_user_account.ml \
	sysprep_operation_utmp.ml \
	sysprep_operation_yum_uuid.ml \
	utils.ml \
	utils.mli

if HAVE_OCAML

# Note this list must be in dependency order.
OBJECTS = \
	sysprep_gettext.cmx \
	utils.cmx \
	sysprep_operation.cmx \
	sysprep_operation_bash_history.cmx \
	sysprep_operation_blkid_tab.cmx \
	sysprep_operation_ca_certificates.cmx \
	sysprep_operation_cron_spool.cmx \
	sysprep_operation_dhcp_client_state.cmx \
	sysprep_operation_dhcp_server_state.cmx \
	sysprep_operation_dovecot_data.cmx \
	sysprep_operation_flag_reconfiguration.cmx \
	sysprep_operation_hostname.cmx \
	sysprep_operation_kerberos_data.cmx \
	sysprep_operation_logfiles.cmx \
	sysprep_operation_mail_spool.cmx \
	sysprep_operation_net_hwaddr.cmx \
	sysprep_operation_package_manager_cache.cmx \
	sysprep_operation_pam_data.cmx \
	sysprep_operation_random_seed.cmx \
	sysprep_operation_rhn_systemid.cmx \
	sysprep_operation_samba_db_log.cmx \
	sysprep_operation_script.cmx \
	sysprep_operation_smolt_uuid.cmx \
	sysprep_operation_ssh_hostkeys.cmx \
	sysprep_operation_ssh_userdir.cmx \
	sysprep_operation_sssd_db_log.cmx \
	sysprep_operation_udev_persistent_net.cmx \
	sysprep_operation_user_account.cmx \
	sysprep_operation_utmp.cmx \
	sysprep_operation_yum_uuid.cmx \
	main.cmx

bin_SCRIPTS = virt-sysprep

# -I $(top_builddir)/src/.libs is a hack which forces corresponding -L
# option to be passed to gcc, so we don't try linking against an
# installed copy of libguestfs.
OCAMLPACKAGES = -package unix -I $(top_builddir)/src/.libs -I $(top_builddir)/ocaml
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCFLAGS = -g -warn-error CDEFLMPSUVYZX $(OCAMLPACKAGES)
OCAMLOPTFLAGS = $(OCAMLCFLAGS)

virt-sysprep: $(OBJECTS)
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) \
	  mlguestfs.cmxa -linkpkg $^ -cclib -lncurses -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLCFLAGS) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLCFLAGS) -c $< -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-sysprep.1
noinst_DATA = $(top_builddir)/html/virt-sysprep.1.html

virt-sysprep.1 $(top_builddir)/html/virt-sysprep.1.html: stamp-virt-sysprep.pod

stamp-virt-sysprep.pod: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(top_builddir)/podwrapper.sh \
	  --man virt-sysprep.1 \
          --insert sysprep-extra-options.pod:@EXTRA_OPTIONS@ \
          --insert sysprep-operations.pod:@OPERATIONS@ \
	  --html $(top_builddir)/html/virt-sysprep.1.html \
	  $<
	touch $@

sysprep-extra-options.pod: virt-sysprep
	rm -f $@ $@-t
	../run ./$< --dump-pod-options > $@-t
	mv $@-t $@

sysprep-operations.pod: virt-sysprep
	rm -f $@ $@-t
	../run ./$< --dump-pod > $@-t
	mv $@-t $@

# Tests.

random_val := $(shell awk 'BEGIN{srand(); print 1+int(255*rand())}' < /dev/null)

TESTS_ENVIRONMENT = \
	MALLOC_PERTURB_=$(random_val) \
	abs_builddir=$(abs_builddir) \
	abs_srcdir=$(abs_srcdir) \
	$(top_builddir)/run

if ENABLE_APPLIANCE
TESTS = \
	test-virt-sysprep.sh \
	test-virt-sysprep-script.sh
endif ENABLE_APPLIANCE

# Dependencies.
depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I ../ocaml -I $(abs_srcdir) $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

endif

.PHONY: depend docs

# Parallel builds don't obey dependencies for some reason we
# don't understand.
.NOTPARALLEL:
