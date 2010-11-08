EXTRA_DIST = \
	LICENSE README \
	lvs.ml

CLEANFILES = throbber.ml *.cmi *.cmo *.cmx *.o lvs

if HAVE_OCAML

noinst_SCRIPTS = lvs

OCAMLFINDFLAGS = -cclib -L$(top_builddir)/src/.libs

lvs:	lvs.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFINDFLAGS) \
          -warn-error A -I .. mlguestfs.cmxa $< -o $@

endif
