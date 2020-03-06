# libguestfs
# Copyright (C) 2009-2020 Red Hat Inc.
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

DOMAIN = $(PACKAGE_NAME)
COPYRIGHT_HOLDER = Red Hat Inc.
MSGID_BUGS_ADDRESS = https://bugzilla.redhat.com/enter_bug.cgi?component=libguestfs&product=Virtualization+Tools

# Languages.
# Don't use LINGUAS (uppercase) as Gentoo defines it (RHBZ#804464).
linguas     := cs de en_GB es eu fr gu hi ja kn ml mr nl or pa pl ru ta te tg uk zh_CN

POTFILES    := $(shell $(SED) 's,^,$(top_srcdir)/,' $(srcdir)/POTFILES)
POTFILES_PL := $(shell $(SED) 's,^,$(top_srcdir)/,' $(srcdir)/POTFILES-pl)
POTFILES_ML := $(shell $(SED) 's,^,$(top_srcdir)/,' $(srcdir)/POTFILES-ml)
POFILES     := $(linguas:%=%.po)
GMOFILES    := $(linguas:%=%.gmo)

EXTRA_DIST = \
	POTFILES POTFILES-pl POTFILES-ml \
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

XGETTEXT_ARGS = \
	--default-domain=$(DOMAIN) \
	--from-code=utf-8 \
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
	--directory=$(top_srcdir)

# For explanation, see
# http://mingw-users.1079350.n2.nabble.com/Getting-rid-of-xgettext-s-quot-CHARSET-quot-warning-td5620533.html
FIX_CHARSET = \
	$(SED) -i 's|text/plain; charset=CHARSET|text/plain; charset=utf-8|g'

$(DOMAIN).pot: Makefile POTFILES $(POTFILES) POTFILES-pl $(POTFILES_PL) POTFILES-ml $(POTFILES_ML)
	rm -f $@-t
	touch $@-t
if HAVE_OCAML_GETTEXT
	$(OCAML_GETTEXT) --action extract --extract-pot $@-t $(POTFILES_ML)
	 \
	$(FIX_CHARSET) $@-t
endif
	$(XGETTEXT) -j -o $@-t $(XGETTEXT_ARGS) \
	  --files-from=$(abs_srcdir)/POTFILES
	$(FIX_CHARSET) $@-t
	$(XGETTEXT) -j -o $@-t $(XGETTEXT_ARGS) --language=Perl \
	  --files-from=$(abs_srcdir)/POTFILES-pl
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
	  install -m 0644 $$lang.gmo $$d/$(DOMAIN).mo; \
	done

.PRECIOUS: $(DOMAIN).pot $(POFILES)

else

# If no GNU gettext, 'make update-po' is a dummy rule.
update-po:

endif
