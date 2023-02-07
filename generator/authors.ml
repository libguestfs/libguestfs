(* libguestfs
 * Copyright (C) 2017-2023 Red Hat Inc.
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
"Andrey Shinkevich", [], [ Development ];
"Angus Salkeld", [], [ Development ];
"Ani Peter", [], [ Development ];
"Bastien ROUCARIÈS", [], [ Development ];
"Bernhard M. Wiedemann", [], [ Development ];
"Bernhard Rosenkränzer", [], [ Development ];
"Cao jin", [], [ Development ];
"Charles Duffy", [], [ Development ];
"Chen Hanxiao", [], [ Development ];
"Chris Lamb", [], [ Development ];
"Cole Robinson", [], [ Development ];
"Colin Walters", [], [ Development ];
"Cédric Bosdonnat", [], [ Development; V2V_and_P2V ];
"Corentin Noël", [], [ Development ];
"Csaba Henk", [], [ Development ];
"Dan Lipsitt", [], [ Development ];
"Daniel P. Berrangé", [ "Daniel Berrange" ], [ Development ];
"Daniel Cabrera", [], [ Development ];
"Daniel Erez", [], [ Development ];
"Daniel Exner", [], [ Development ];
"Daria Phoebe Brashear", [], [ Development ];
"Dave Vasilevsky", [], [ Development ];
"David Sommerseth", [], [ Development ];
"Dawid Zamirski", [], [ Development ];
"Denis Plotnikov", [], [ Development ];
"Douglas Schilling Landgraf", [], [ Development ];
"Eric Blake", [], [ Development ];
"Erik Nolte", [], [ Development ];
"Evaggelos Balaskas", [], [ Development ];
"Florian Klink", [], [ Development ];
"Gabriele Cerami", [], [ Development ];
"Geert Warrink", [], [ Development ];
"Guido Günther", [], [ Development ];
"Hilko Bengen", [], [ Development ];
"Hiroyuki Katsura", [ "Hiroyuki_Katsura" ], [ Development ];
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
"Sam Eiderman", [], [ Development ];
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
