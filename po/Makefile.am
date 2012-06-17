# libguestfs
# Copyright (C) 2009-2012 Red Hat Inc.
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
abs_srcdir ?= $(shell cd $(top_srcdir)/po && pwd)

DOMAIN = $(PACKAGE_NAME)
COPYRIGHT_HOLDER = Red Hat Inc.
MSGID_BUGS_ADDRESS = https://bugzilla.redhat.com/enter_bug.cgi?component=libguestfs&product=Virtualization+Tools

# Languages.
# Don't use LINGUAS (uppercase) as Gentoo defines it (RHBZ#804464).
linguas     := en_GB es gu hi kn ml mr nl or pa pl ta te uk

POTFILES    := $(shell $(SED) 's,^,$(top_srcdir)/,' $(srcdir)/POTFILES)
POTFILES_ML := $(shell $(SED) 's,^,$(top_srcdir)/,' $(srcdir)/POTFILES-ml)
POFILES     := $(linguas:%=%.po)
GMOFILES    := $(linguas:%=%.gmo)

EXTRA_DIST = \
	POTFILES POTFILES-ml \
	$(DOMAIN).pot \
	$(POFILES) \
	$(GMOFILES)

if HAVE_GNU_GETTEXT

dist-hook:
	$(MAKE) update-po
	cp *.po *.gmo $(distdir)/

update-po:
	$(MAKE) $(DOMAIN).pot
	$(MAKE) $(POFILES)
	$(MAKE) update-gmo

update-gmo: Makefile $(GMOFILES)

$(DOMAIN).pot: Makefile $(POTFILES) $(POTFILES-ml)
	rm -f $@-t $@-ml
	$(XGETTEXT) \
	  -o $@-t \
	  --default-domain=$(DOMAIN) \
	  --add-comments=TRANSLATORS: \
	  --keyword=_ --keyword=N_ --keyword=__ --keyword=__x \
	  --flag=error:3:c-format \
	  --flag=error_at_line:5:c-format \
	  --flag=asprintf:2:c-format \
	  --flag=vasprintf:2:c-format \
	  --flag=xasprintf:1:c-format \
	  --copyright-holder='$(COPYRIGHT_HOLDER)' \
	  --package-name="$(PACKAGE_NAME)" \
	  --package-version="$(PACKAGE_VERSION)" \
	  --msgid-bugs-address="$(MSGID_BUGS_ADDRESS)" \
	  --directory=$(top_srcdir) \
	  --files-from=$(abs_srcdir)/POTFILES
if HAVE_OCAML_GETTEXT
	$(OCAML_GETTEXT) --action extract --extract-pot $@-ml $(POTFILES_ML)
# Don't trust msgcat since it will definitely screw up.  Instead, chop
# the head from the second file and append it to the first.
	echo >> $@-t
	awk '/^#:/{i++}i{print}' < $@-ml >> $@-t
	rm $@-ml
endif
	mv $@-t $@

%.po: $(DOMAIN).pot
	cd $(srcdir) && $(MSGMERGE) -N --update $@ $(DOMAIN).pot

.po.gmo:
	rm -f $@ $@-t
	$(MSGFMT) -c -o $@-t $(srcdir)/$<
	mv $@-t $@

# Install.
# Cannot use 'localedir' since this conflicts with autoconf.
langinstdir = $(datadir)/locale

install-data-hook: $(GMOFILES)
	mkdir -p $(DESTDIR)$(langinstdir)
	for lang in $(linguas); do \
	  d=$(DESTDIR)$(langinstdir)/$$lang/LC_MESSAGES; \
	  mkdir -p $$d; \
	  install -m 0755 $$lang.gmo $$d/$(DOMAIN).mo; \
	done

.PRECIOUS: $(DOMAIN).pot $(POFILES)
SUFFIXES = .po .gmo

else

# If no GNU gettext, 'make update-po' is a dummy rule.
update-po:

endif
