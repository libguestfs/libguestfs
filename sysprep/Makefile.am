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

# Old RHEL 5 autoconf doesn't have builddir.
builddir ?= .

# Old RHEL 5 autoconf doesn't have abs_srcdir.
abs_srcdir ?= $(shell cd $(top_srcdir)/sysprep && pwd)

# Old RHEL 5 autoconf doesn't have abs_builddir.
abs_builddir ?= $(shell pwd)

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

# Filenames sysprep_operation_<name>.ml in alphabetical order.
operations = \
	bash_history blkid_tab ca_certificates cron_spool \
	dhcp_client_state dhcp_server_state dovecot_data flag_reconfiguration \
	hostname kerberos_data logfiles mail_spool net_hwaddr \
	package_manager_cache pam_data random_seed \
	rhn_systemid samba_db_log script smolt_uuid ssh_hostkeys \
	ssh_userdir sssd_db_log udev_persistent_net user_account \
	utmp yum_uuid

# Alphabetical order.
SOURCES = \
	main.ml \
	sysprep_gettext.ml \
	sysprep_operation.ml \
	sysprep_operation.mli \
	$(patsubst %,sysprep_operation_%.ml,$(operations)) \
	utils.ml \
	utils.mli

if HAVE_OCAML

# Note this list must be in dependency order.
OBJECTS = \
	sysprep_gettext.cmx \
	utils.cmx \
	sysprep_operation.cmx \
	$(patsubst %,sysprep_operation_%.cmx,$(operations)) \
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
	$(OCAMLFIND) ocamlopt $(OCAMLOPTFLAGS) -c $< -o $@

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
