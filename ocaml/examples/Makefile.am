EXTRA_DIST = LICENSE README lvs.ml

if HAVE_OCAML

lvs:	lvs.ml
	$(OCAMLFIND) ocamlopt -I .. mlguestfs.cmxa $< -o $@

CLEANFILES = *.cmi *.cmo *.cmx *.o lvs

endif