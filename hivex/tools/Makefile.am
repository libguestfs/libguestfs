# libguestfs
# Copyright (C) 2009 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# OCaml Windows Registry visualizer.  This was used while reverse
# engineering the hive format, and is not normally compiled.  If you
# do with to compile it, you'll need ocaml-bitstring-devel and
# ocaml-extlib-devel.  Also you'll need a collection of hive files
# from Windows machines to experiment with.
#
# We use '-w y' (disable unused variable warnings) because these
# warnings aren't very reliable with heavily preprocessed code like
# that produced by bitstring.

EXTRA_DIST = \
	visualizer.ml \
	visualizer_utils.ml \
	visualizer_NT_time.ml \
	clearheaderfields.ml \
	fillemptyhbins.ml \
	truncatefile.ml \
	counter.mli \
	counter.ml

visualizer.opt: counter.mli counter.ml visualizer_utils.ml visualizer_NT_time.ml visualizer.ml
	ocamlfind ocamlopt -w y \
	  -package bitstring,bitstring.syntax,extlib \
	  -syntax camlp4 -linkpkg $^ -o $@

fillemptyhbins.opt: fillemptyhbins.ml
	ocamlfind ocamlopt -w y \
	  -package bitstring,bitstring.syntax,extlib \
	  -syntax camlp4 -linkpkg $^ -o $@

clearheaderfields.opt: visualizer_utils.ml clearheaderfields.ml
	ocamlfind ocamlopt -w y \
	  -package bitstring,bitstring.syntax,extlib \
	  -syntax camlp4 -linkpkg $^ -o $@

truncatefile.opt: visualizer_utils.ml truncatefile.ml
	ocamlfind ocamlopt -w y \
	  -package bitstring,bitstring.syntax,extlib \
	  -syntax camlp4 -linkpkg $^ -o $@
