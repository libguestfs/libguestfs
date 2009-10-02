EXTRA_DIST = LICENSE README lvs.ml viewer.ml Throbber.png Throbber.gif

CLEANFILES = throbber.ml *.cmi *.cmo *.cmx *.o lvs

if HAVE_OCAML

noinst_SCRIPTS = lvs

OCAMLFINDFLAGS = -ccopt '-L $(top_builddir)/src/.libs'

lvs:	lvs.ml
	$(OCAMLFIND) ocamlopt $(OCAMLFINDFLAGS) \
          -warn-error A -I .. mlguestfs.cmxa $< -o $@

if BUILD_OCAML_VIEWER

noinst_SCRIPTS += viewer

viewer: throbber.ml xmllight_loader.mli xmllight_loader.ml viewer.ml
	ocamlducefind opt $(OCAMLFINDFLAGS) \
	  -warn-error A \
	  -thread \
	  -package libvirt,lablgtk2,extlib,xml-light,ocamlduce,threads -I .. \
	  -predicates init,threads \
	  -linkpkg mlguestfs.cmxa gtkThread.cmx \
	  $^ -o $@

throbber.ml: Throbber.png Throbber.gif
	gdk_pixbuf_mlsource --build-list \
	  static Throbber.png \
	  animation Throbber.gif \
	  > $@-t && mv $@-t $@

endif

endif
