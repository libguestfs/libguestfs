(* libguestfs
 * Copyright (C) 2017-2019 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Std_utils
open Utils
open Pr
open Docstrings

type role = Development | Quality_assurance | Documentation | V2V_and_P2V
(** Not exclusive, you can be in multiple roles :-) *)

(* Note that the following list interacts with
 * [make maintainer-check-authors] in [libguestfs.git/Makefile.am].
 *
 * The second field (list of aliases) is not actually used in any
 * code, but it keeps [make maintainer-check-authors] happy.
 *)
let authors = [
"Adam Huffman", [], [ Development ];
"Adam Robinson", [], [ Development ];
"Andrea Bolognani", [], [ Development ];
"Angus Salkeld", [], [ Development ];
"Ani Peter", [], [ Development ];
"Bastien ROUCARIÈS", [], [ Development ];
"Bernhard M. Wiedemann", [], [ Development ];
"Cao jin", [], [ Development ];
"Charles Duffy", [], [ Development ];
"Chen Hanxiao", [], [ Development ];
"Cole Robinson", [], [ Development ];
"Colin Walters", [], [ Development ];
"Cédric Bosdonnat", [], [ Development; V2V_and_P2V ];
"Dan Lipsitt", [], [ Development ];
"Daniel P. Berrangé", [ "Daniel Berrange" ], [ Development ];
"Daniel Cabrera", [], [ Development ];
"Daniel Erez", [], [ Development ];
"Daniel Exner", [], [ Development ];
"Dave Vasilevsky", [], [ Development ];
"David Sommerseth", [], [ Development ];
"Dawid Zamirski", [], [ Development ];
"Douglas Schilling Landgraf", [], [ Development ];
"Eric Blake", [], [ Development ];
"Erik Nolte", [], [ Development ];
"Evaggelos Balaskas", [], [ Development ];
"Florian Klink", [], [ Development ];
"Gabriele Cerami", [], [ Development ];
"Geert Warrink", [], [ Development ];
"Guido Günther", [], [ Development ];
"Hilko Bengen", [], [ Development ];
"Hu Tao", [], [ Development ];
"infernix", [], [ Development ];
"Jamie Iles", [], [ Development ];
"Jaswinder Singh", [], [ Development ];
"Jim Meyering", [], [ Development ];
"Jiri Popelka", [], [ Development ];
"John Eckersberg", [], [ Development; V2V_and_P2V ];
"Joseph Wang", [], [ Development ];
"Junqin Zhou", [], [ Quality_assurance; V2V_and_P2V ];
"Karel Klíč", [], [ Development ];
"Kashyap Chamarthy", [], [ Development ];
"Kean Li", [], [ Quality_assurance; V2V_and_P2V ];
"Ken Stailey", [], [ Development ];
"Kun Wei", [], [ Quality_assurance; V2V_and_P2V ];
"Lars Kellogg-Stedman", [], [ Development ];
"Lars Seipel", [], [ Development ];
"Laura Bailey", [], [ Documentation; V2V_and_P2V ];
"Lee Yarwood", [], [ Development ];
"Lin Ma", [], [ Development ];
"Marcin Gibula", [], [ Development ];
"Margaret Lewicka", [], [ Development ];
"Maros Zatko", [], [ Development ];
"Martin Kletzander", [], [ Development ];
"Masami HIRATA", [], [ Development ];
"Matteo Cafasso", [], [ Development ];
"Matthew Booth", [], [ Development; V2V_and_P2V ];
"Maxim Koltsov", [], [ Development ];
"Maxim Perevedentsev", [], [ Development ];
"Menanteau Guy", [], [ Development ];
"Michael Scherer", [], [ Development ];
"Mike Frysinger", [], [ Development ];
"Mike Kelly", [], [ Development ];
"Mike Latimer", [], [ V2V_and_P2V ];
"Ming Xie", [], [ Quality_assurance; V2V_and_P2V ];
"Mykola Ivanets", [], [ Development ]; (* alias: "Nikolay Ivanets" *)
"Nicholas Strugnell", [], [ Development ];
"Nikita A Menkovich", [], [ Development ];
"Nikita Menkovich", [], [ Development ];
"Nikos Skalkotos", [], [ Development ];
"Nir Soffer", [], [ Development ];
"Olaf Hering", [], [ Development ];
"Or Goshen", [], [ Development ];
"Paul Mackerras", [], [ Development ];
"Pavel Butsykin", [], [ Development ];
"Pino Toscano", [], [ Development; V2V_and_P2V ];
"Piotr Drąg", [], [ Development ];
"Qin Guan", [], [ Development ];
"Rajesh Ranjan", [], [ Development ];
"Richard W.M. Jones", [], [ Development; V2V_and_P2V ];
"Robert Antoni Buj Gelonch", [], [ Development ];
"Roman Kagan", [], [ Development; V2V_and_P2V ];
"Sandeep Shedmake", [], [ Development ];
"Sebastian Meyer", [], [ Development ];
"Shahar Havivi", [], [ Development; V2V_and_P2V ];
"Shahar Lev", [], [ Development ];
"Shankar Prasad", [], [ Development ];
"Thomas S Hatch", [], [ Development ];
"Tingting Zheng", [], [ Quality_assurance; V2V_and_P2V ];
"Tomáš Golembiovský", [], [ Development ];
"Török Edwin", [], [ Development ];
"Wanlong Gao", [], [ Development ];
"Wulf C. Krueger", [], [ Development ];
"Xiang Hua Chen", [], [ Quality_assurance; V2V_and_P2V ];
"Yann E. MORIN", [], [ Development ];
"Yehuda Zimmerman", [], [ Documentation; V2V_and_P2V ];
"Yuri Chornoivan", [], [ Documentation ];
]
(** List of authors and roles. *)

let generate_authors () =
  List.iter (fun (name, _, _) -> pr "%s\n" name) authors

let generate_p2v_about_authors_c () =
  generate_header CStyle GPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include \"p2v.h\"\n";
  pr "\n";

  (* Split up the list according to how we want to add people to
   * credit sections.  However don't assign anyone to more than a
   * single category.  Be aware that with Gtk < 3.4, only the
   * "authors" and "documenters" categories are actually displayed.
   *)
  let authors, qa, documenters, others =
    let rec loop (authors, qa, documenters, others) = function
      | [] -> authors, qa, documenters, others
      | ((_, _, roles) as a) :: rest ->
         if List.mem V2V_and_P2V roles then
           loop (a :: authors, qa, documenters, others) rest
         else if List.mem Quality_assurance roles then
           loop (authors, a :: qa, documenters, others) rest
         else if List.mem Documentation roles then
           loop (authors, qa, a :: documenters, others) rest
         else
           loop (authors, qa, documenters, a :: others) rest
    in
    let authors, qa, documenters, others = loop ([],[],[],[]) authors in
    List.rev authors, List.rev qa, List.rev documenters, List.rev others in

  let fn (name, _, _) = pr "  \"%s\",\n" name in

  pr "/* Authors involved with virt-v2v and virt-p2v directly. */\n";
  pr "const char *authors[] = {\n";
  List.iter fn authors;
  pr "  NULL\n";
  pr "};\n\n";
  pr "/* Libguestfs quality assurance (if not included above). */\n";
  pr "const char *qa[] = {\n";
  List.iter fn qa;
  pr "  NULL\n";
  pr "};\n\n";
  pr "/* Libguestfs documentation (if not included above). */\n";
  pr "const char *documenters[] = {\n";
  List.iter fn documenters;
  pr "  NULL\n";
  pr "};\n\n";
  pr "/* Libguestfs developers (if not included above). */\n";
  pr "const char *others[] = {\n";
  List.iter fn others;
  pr "  NULL\n";
  pr "};\n"

let generate_p2v_authors () =
  let p2v_authors =
    List.filter_map (
      fun (name, _, roles) ->
        if List.mem V2V_and_P2V roles then Some name
        else None
    ) authors in
  List.iter (pr "%s\n") p2v_authors
