#!/usr/bin/ocamlrun /usr/bin/ocaml

(* Convert *.qtr (qemu block device trace) to Postscript.
 * Copyright (C) 2009-2012 Red Hat Inc.
 * By Richard W.M. Jones <rjones@redhat.com>.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* Note that we use ordinary OCaml ints, which means this program is
 * limited to: ~1TB disks for 32 bit machines, or effectively unlimited
 * for 64 bit machines.  Also we make several 512 byte sector
 * assumptions.
 *)

#use "topfind";;
#require "extlib";;

open ExtList
open Scanf
open Printf

type op = Read | Write

(* If 'true' then print debug messages. *)
let debug = true

(* Width of each row (in sectors) in the output. *)
let row_size = 64

(* Desirable alignment (sectors). *)
let alignment = 8

(* Height (in 1/72 inch) of the final image. *)
let height = 6.*.72.

(* Width (in 1/72 inch) of the final image. *)
let width = 6.*.72.

(* Reserve at left for the sector number (comes out of width). *)
let sn_width = 36.

let input =
  if Array.length Sys.argv = 2 then
    Sys.argv.(1)
  else
    failwith "usage: tracetops filename.qtr"

(* Read the input file. *)
let nb_sectors, accesses =
  let chan = open_in input in
  let nb_sectors =
    let summary = input_line chan in
    if String.length summary < 1 || summary.[0] <> 'S' then
      failwith (sprintf "%s: input is not a qemu block device trace file"
                  input);
    sscanf summary "S %d" (fun x -> x) in

  if nb_sectors mod row_size <> 0 then
    failwith (sprintf "input nb_sectors (%d) not divisible by row size (%d)"
                nb_sectors row_size);

  (* Read the reads and writes from the remainder of the file. *)
  let accesses = ref [] in
  let rec loop () =
    let line = input_line chan in
    let rw, s, n = sscanf line "%c %d %d" (fun rw s n -> (rw, s, n)) in
    let rw =
      match rw with
      | 'R' -> Read | 'W' -> Write
      | c -> failwith
          (sprintf "%s: error reading input: got '%c', expecting 'R' or 'W'"
             input c) in
    if n < 0 || s < 0 || s+n > nb_sectors then
      failwith (sprintf "%s: s (%d), n (%d) out of range" input s n);
    let aligned = s mod alignment = 0 && n mod alignment = 0 in
    accesses := (rw, aligned, s, n) :: !accesses;
    loop ()
  in
  (try loop () with
   | End_of_file -> ()
   | Scan_failure msg ->
       failwith (sprintf "%s: error reading input: %s" input msg)
  );
  close_in chan;

  let accesses = List.rev !accesses in

  if debug then (
    eprintf "%s: nb_sectors = %d, accesses = %d\n"
      input nb_sectors (List.length accesses)
  );

  nb_sectors, accesses

(* If the accesses list contains any qtrace on/off patterns (in
 * guestfish: debug "qtrace /dev/vda (on|off)") then filter out the
 * things we want to display.  Otherwise leave the whole trace.
 *)
let accesses =
  let contains_qtrace_patterns =
    let rec loop = function
      | [] -> false
      | (Read, _, 2, 1) :: (Read, _, 21, 1) :: (Read, _, 15, 1) ::
          (Read, _, 2, 1) :: _ -> true
      | (Read, _, 2, 1) :: (Read, _, 15, 1) :: (Read, _, 21, 1) ::
          (Read, _, 2, 1) :: _ -> true
      | _ :: rest -> loop rest
    in
    loop accesses in

  if contains_qtrace_patterns then (
    if debug then eprintf "%s: contains qtrace on/off patterns\n%!" input;

    let rec find_qtrace_on = function
      | [] -> []
      | (Read, _, 2, 1) :: (Read, _, 21, 1) :: (Read, _, 15, 1) ::
          (Read, _, 2, 1) :: rest -> rest
      | (Read, _, 2, 1) :: (Read, _, 15, 1) :: (Read, _, 21, 1) ::
          (Read, _, 2, 1) :: rest ->
          eprintf "ignored 'qtrace off' pattern when expecting 'qtrace on'\n";
          find_qtrace_on rest
      | _ :: rest -> find_qtrace_on rest
    and split_until_qtrace_off = function
      | [] -> [], []
      | (Read, _, 2, 1) :: (Read, _, 15, 1) :: (Read, _, 21, 1) ::
          (Read, _, 2, 1) :: rest -> [], rest
      | (Read, _, 2, 1) :: (Read, _, 21, 1) :: (Read, _, 15, 1) ::
          (Read, _, 2, 1) :: rest ->
          eprintf "found 'qtrace on' pattern when expecting 'qtrace off'\n";
          split_until_qtrace_off rest
      | x :: ys ->
          let xs, ys = split_until_qtrace_off ys in
          x :: xs, ys
    and filter_accesses xs =
      let xs = find_qtrace_on xs in
      if xs <> [] then (
        let xs, ys = split_until_qtrace_off xs in
        let ys = filter_accesses ys in
        xs @ ys
      ) else
        []
    in
    filter_accesses accesses
  ) else
    accesses

let ranges =
  (* Given the number of sectors, make the row array. *)
  let nr_rows = nb_sectors / row_size in
  let rows = Array.make nr_rows false in

  List.iter (
    fun (_, _, s, n) ->
      let i0 = s / row_size in
      let i1 = (s+n-1) / row_size in
      for i = i0 to i1 do rows.(i) <- true done;
  ) accesses;

  (* Coalesce rows into a list of ranges of rows we will draw. *)
  let rows = Array.to_list rows in
  let rows = List.mapi (fun i v -> (v, i)) rows in
  let ranges =
    (* When called, we are in the middle of a range which started at i0. *)
    let rec loop i0 = function
      | (false, _) :: (false, _) :: (true, i1) :: []
      | _ :: (_, i1) :: []
      | (_, i1) :: [] ->
          [i0, i1]
      | (false, _) :: (false, _) :: (true, _) :: rest
      | (false, _) :: (true, _) :: rest
      | (true, _) :: rest ->
          loop i0 rest
      | (false, i1) :: rest ->
          let i1 = i1 - 1 in
          let rest = List.dropwhile (function (v, _) -> not v) rest in
          (match rest with
           | [] -> [i0, i1]
           | (_, i2) :: rest -> (i0, i1) :: loop i2 rest)
      | [] -> assert false
    in
    loop 0 (List.tl rows) in

  if debug then (
    eprintf "%s: rows = %d (ranges = %d)\n" input nr_rows (List.length ranges);
    List.iter (
      fun (i0, i1) ->
        eprintf "  %d - %d (rows %d - %d)\n"
          (i0 * row_size) ((i1 + 1) * row_size - 1) i0 i1
    ) ranges
  );

  ranges

(* Locate where we will draw the rows and cells in the final image. *)
let iter_rows, mapxy, row_height, cell_width =
  let nr_ranges = List.length ranges in
  let nr_breaks = nr_ranges - 1 in
  let nr_rows =
    List.fold_left (+) 0 (List.map (fun (i0,i1) -> i1-i0+1) ranges) in
  let nr_rnb = nr_rows + nr_breaks in
  let row_height = height /. float nr_rnb in
  let cell_width = (width -. sn_width) /. float row_size in

  if debug then (
    eprintf "number of rows and breaks = %d\n" nr_rnb;
    eprintf "row_height x cell_width = %g x %g\n" row_height cell_width
  );

  (* Create a higher-order function to iterate over the rows. *)
  let rec iter_rows f =
    let rec loop row = function
      | [] -> ()
      | (i0,i1) :: rows ->
          for i = i0 to i1 do
            let y = float (row+i-i0) *. row_height in
            f y (Some i)
          done;
          (* Call an extra time for the break. *)
          let y = float (row+i1-i0+1) *. row_height in
          if rows <> [] then f y None;
          (* extra +1 here is to skip the break *)
          loop (row+i1-i0+1+1) rows
    in
    loop 0 ranges
  in

  (* Create a hash which maps from the row number to the position
   * where we draw the row.  If the row is not drawn, the hash value
   * is missing.
   *)
  let row_y = Hashtbl.create nr_rows in
  iter_rows (
    fun y ->
      function
      | Some i -> Hashtbl.replace row_y i y
      | None -> ()
  );

  (* Create a function which maps from the sector number to the final
   * position that we will draw it.
   *)
  let mapxy s =
    let r = s / row_size in
    let y = try Hashtbl.find row_y r with Not_found -> assert false in
    let x = sn_width +. cell_width *. float (s mod row_size) in
    x, y
  in

  iter_rows, mapxy, row_height, cell_width

(* Start the PostScript file. *)
let () =
  printf "%%!PS-Adobe-3.0 EPSF-3.0\n";
  printf "%%%%BoundingBox: -10 -10 %g %g\n"
    (width +. 10.) (height +. row_height +. 20.);
  printf "%%%%Creator: tracetops.ml (part of libguestfs)\n";
  printf "%%%%Title: %s\n" input;
  printf "%%%%LanguageLevel: 2\n";
  printf "%%%%Pages: 1\n";
  printf "%%%%Page: 1 1\n";
  printf "\n";

  printf "/min { 2 copy gt { exch } if pop } def\n";
  printf "/max { 2 copy lt { exch } if pop } def\n";

  (* Function for drawing cells. *)
  printf "/cell {\n";
  printf "  newpath\n";
  printf "    moveto\n";
  printf "    %g 0 rlineto\n" cell_width;
  printf "    0 %g rlineto\n" row_height;
  printf "    -%g 0 rlineto\n" cell_width;
  printf "  closepath\n";
  printf "  gsave fill grestore 0.75 setgray stroke\n";
  printf "} def\n";

  (* Define colours for different cell types. *)
  printf "/unalignedread  { 0.95 0.95 0 setrgbcolor } def\n";
  printf "/unalignedwrite { 0.95 0 0    setrgbcolor } def\n";
  printf "/alignedread    { 0 0.95 0    setrgbcolor } def\n";
  printf "/alignedwrite   { 0 0 0.95    setrgbcolor } def\n";

  (* Get width of text. *)
  printf "/textwidth { stringwidth pop } def\n";

  (* Draw the outline. *)
  printf "/outline {\n";
  printf "  newpath\n";
  printf "    %g 0 moveto\n" sn_width;
  printf "    %g 0 lineto\n" width;
  printf "    %g %g lineto\n" width height;
  printf "    %g %g lineto\n" sn_width height;
  printf "  closepath\n";
  printf "  0.5 setlinewidth 0.3 setgray stroke\n";
  printf "} def\n";

  (* Draw the outline breaks. *)
  printf "/breaks {\n";
  iter_rows (
    fun y ->
      function
      | Some _ -> ()
      | None ->
          let f xmin xmax =
            let yll = y +. row_height /. 3. -. 2. in
            let ylr = y +. row_height /. 2. -. 2. in
            let yur = y +. 2. *. row_height /. 3. in
            let yul = y +. row_height /. 2. in
            printf "  newpath\n";
            printf "    %g %g moveto\n" xmin yll;
            printf "    %g %g lineto\n" xmax ylr;
            printf "    %g %g lineto\n" xmax yur;
            printf "    %g %g lineto\n" xmin yul;
            printf "  closepath\n";
            printf "  1 setgray fill\n";
            printf "  newpath\n";
            printf "    %g %g moveto\n" xmin yll;
            printf "    %g %g lineto\n" xmax ylr;
            printf "    %g %g moveto\n" xmax yur;
            printf "    %g %g lineto\n" xmin yul;
            printf "  closepath\n";
            printf "  0.5 setlinewidth 0.3 setgray stroke\n"
          in
          f (sn_width -. 6.) (sn_width +. 6.);
          f (width -. 6.) (width +. 6.)
  );
  printf "} def\n";

  (* Draw the labels. *)
  printf "/labels {\n";
  printf "  /Courier findfont\n";
  printf "  0.75 %g mul 10 min scalefont\n" row_height;
  printf "  setfont\n";
  iter_rows (
    fun y ->
      function
      | Some i ->
          let sector = i * row_size in
          printf "  newpath\n";
          printf "    /s { (%d) } def\n" sector;
          printf "    %g s textwidth sub 4 sub %g moveto\n" sn_width (y +. 2.);
          printf "  s show\n"
      | None -> ()
  );
  printf "} def\n";

  (* Print the key. *)
  printf "/key {\n";
  printf "  /Times-Roman findfont\n";
  printf "  10. scalefont\n";
  printf "  setfont\n";
  let x = sn_width and y = height +. 10. in
  printf "  unalignedwrite %g %g cell\n" x y;
  let x = x +. cell_width +. 4. in
  printf "  newpath %g %g moveto (unaligned write) 0.3 setgray show\n" x y;
  let x = x +. 72. in
  printf "  unalignedread %g %g cell\n" x y;
  let x = x +. cell_width +. 4. in
  printf "  newpath %g %g moveto (unaligned read) 0.3 setgray show\n" x y;
  let x = x +. 72. in
  printf "  alignedwrite %g %g cell\n" x y;
  let x = x +. cell_width +. 4. in
  printf "  newpath %g %g moveto (aligned write) 0.3 setgray show\n" x y;
  let x = x +. 72. in
  printf "  alignedread %g %g cell\n" x y;
  let x = x +. cell_width +. 4. in
  printf "  newpath %g %g moveto (aligned read) 0.3 setgray show\n" x y;
  printf "} def\n";

  printf "\n"

(* Draw the accesses. *)
let () =
  (* Sort the accesses so unaligned ones are displayed at the end (on
   * top of aligned ones) and writes on top of reads.  This isn't
   * really perfect, but it'll do.
   *)
  let cmp (rw, aligned, s, n) (rw', aligned', s', n') =
    let r = compare rw rw' (* Write later *) in
    if r <> 0 then r else (
      let r = compare aligned' aligned (* unaligned later *) in
      if r <> 0 then r else
        compare (n, s) (n', s')
    )
  in
  let accesses = List.sort ~cmp accesses in

  List.iter (
    fun op ->
      let col, s, n =
        match op with
        | Read, false, s, n ->
            "unalignedread", s, n
        | Write, false, s, n ->
            "unalignedwrite", s, n
        | Read, true, s, n ->
            "alignedread", s, n
        | Write, true, s, n ->
            "alignedwrite", s, n in
      for i = s to s+n-1 do
        let x, y = mapxy i in
        printf "%s %g %g cell\n" col x y
      done;
      printf "\n"
  ) accesses

(* Finish off the PostScript output. *)
let () =
  printf "outline breaks labels key\n";
  printf "%%%%EOF\n"
