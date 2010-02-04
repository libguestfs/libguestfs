(* Windows Registry reverse-engineering tool.
 * Copyright (C) 2010 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * For existing information on the registry format, please refer
 * to the following documents.  Note they are both incomplete
 * and inaccurate in some respects.
 *
 * http://www.sentinelchicken.com/data/TheWindowsNTRegistryFileFormat.pdf
 * http://pogostick.net/~pnh/ntpasswd/WinReg.txt
 *)

open Bitstring
open ExtString
open Printf
open Visualizer_utils
open Visualizer_NT_time

let () =
  if Array.length Sys.argv <> 2 then (
    eprintf "Error: missing argument.
Usage: %s hivefile > out
where
  'hivefile' is the input hive file from a Windows machine
  'out' is an output file where we will write all the keys,
    values etc for extended debugging purposes.
Errors, inconsistencies and unexpected fields in the hive file
are written to stderr.
" Sys.executable_name;
    exit 1
  )

let filename = Sys.argv.(1)
let basename = Filename.basename filename

(* Load the file. *)
let bits = bitstring_of_file filename

(* Split into header + data at the 4KB boundary. *)
let header, data = takebits (4096 * 8) bits, dropbits (4096 * 8) bits

(* Define a persistent pattern which matches the header fields.  By
 * using persistent patterns, we can reuse them later in the
 * program.
 *)
let bitmatch header_fields =
  { "regf" : 4*8 : string;
    seq1 : 4*8 : littleendian;
    seq2 : 4*8 : littleendian;
    last_modified : 64
      : littleendian, bind (nt_to_time_t last_modified);
    major : 4*8 : littleendian;
    minor : 4*8 : littleendian;

    (* "Type".  Contains 0. *)
    unknown1 : 4*8 : littleendian;

    (* "Format".  Contains 1. *)
    unknown2 : 4*8 : littleendian;

    root_key : 4*8
      : littleendian, bind (get_offset root_key);
    end_pages : 4*8
      : littleendian, bind (get_offset end_pages);

    (* "Cluster".  Contains 1. *)
    unknown3 : 4*8 : littleendian;

    filename : 64*8 : string;

    (* All three GUIDs here confirmed in Windows 7 registries.  In
     * Windows <= 2003 these GUID fields seem to contain junk.
     * 
     * If you write zeroes to the GUID fields, load and unload in Win7
     * REGEDIT, then Windows 7 writes some random GUIDs.
     * 
     * Also (on Win7) unknownguid1 == unknownguid2.  unknownguid3 is
     * different.
     *)
    unknownguid1 : 16*8 : bitstring;
    unknownguid2 : 16*8 : bitstring;

    (* Wrote zero to unknown4, loaded and unloaded it in Win7 REGEDIT,
     * and it still contained zero.  In existing registries it seems to
     * contain random junk.
     *)
    unknown4 : 4*8 : littleendian;
    unknownguid3 : 16*8 : bitstring;

    (* If you write zero to unknown5, load and unload it in REGEDIT,
     * Windows 7 puts the string "rmtm" here.  Existing registries also
     * seen containing this string.  However on older Windows it can
     * be all zeroes.
     *)
    unknown5 : 4*8 : string;

    (* This seems to contain junk from other parts of the registry.  I
     * wrote zeroes here, loaded and unloaded it in Win7 REGEDIT, and
     * it still contained zeroes.
     *)
    unknown6 : 340*8 : bitstring;
    csum : 4*8
      : littleendian, save_offset_to (crc_offset),
    check (assert (crc_offset = 0x1fc * 8); true);
    unknown7 : (0x1000-0x200)*8 : bitstring }

let fprintf_header chan bits =
  bitmatch bits with
  | { :header_fields } ->
      fprintf chan
        "HD %6ld %6ld %s %ld.%ld %08lx %08lx %s %s %08lx %s %s %s %08lx %s %s %s %08lx %s\n"
        seq1 seq2 (print_time last_modified) major minor
        unknown1 unknown2
        (print_offset root_key) (print_offset end_pages)
        unknown3 (print_utf16 filename)
        (print_guid unknownguid1) (print_guid unknownguid2)
        unknown4 (print_guid unknownguid3) unknown5
        (print_bitstring unknown6)
        csum (print_bitstring unknown7)

(* Parse the header and check it. *)
let root_key, end_pages =
  bitmatch header with
  |  { :header_fields } ->
       fprintf_header stdout header;

       if major <> 1_l then
         eprintf "HD hive file major <> 1 (major.minor = %ld.%ld)\n"
           major minor;
       if seq1 <> seq2 then
         eprintf "HD hive file sequence numbers should match (%ld <> %ld)\n"
           seq1 seq2;
       if unknown1 <> 0_l then
         eprintf "HD unknown1 field <> 0 (%08lx)\n" unknown1;
       if unknown2 <> 1_l then
         eprintf "HD unknown2 field <> 1 (%08lx)\n" unknown2;
       if unknown3 <> 1_l then
         eprintf "HD unknown3 field <> 1 (%08lx)\n" unknown3;
       if not (equals unknownguid1 unknownguid2) then
         eprintf "HD unknownguid1 <> unknownguid2 (%s, %s)\n"
           (print_guid unknownguid1) (print_guid unknownguid2);
       (* We think this is junk.
       if unknown4 <> 0_l then
         eprintf "HD unknown4 field <> 0 (%08lx)\n" unknown4;
       *)
       if unknown5 <> "rmtm" && unknown5 <> "\000\000\000\000" then
         eprintf "HD unknown5 field <> \"rmtm\" & <> zeroes (%s)\n" unknown5;
       (* We think this is junk.
       if not (is_zero_bitstring unknown6) then
         eprintf "HD unknown6 area is not zero (%s)\n"
           (print_bitstring unknown6);
       *)
       if not (is_zero_bitstring unknown7) then
         eprintf "HD unknown7 area is not zero (%s)\n"
           (print_bitstring unknown7);

       root_key, end_pages
  | {_} ->
      failwithf "%s: this doesn't look like a registry hive file\n" basename

(* Define persistent patterns to match page and block fields. *)
let bitmatch page_fields =
  { "hbin" : 4*8 : string;
    page_offset : 4*8
      : littleendian, bind (get_offset page_offset);
    page_size : 4*8
      : littleendian, check (Int32.rem page_size 4096_l = 0_l),
        bind (Int32.to_int page_size);

    (* In the first hbin in the file these fields contain something.
     * In subsequent hbins these fields are all zero.
     *
     * From existing hives (first hbin only):
     *
     * unknown1     unknown2                               unknown5
     * 00 00 00 00  00 00 00 00  9C 77 3B 02  6A 7D CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  50 3A 15 07  B5 9B CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  57 86 90 D4  9A 58 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  52 3F 90 9D  CF 7C CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  E8 86 C1 17  BD 06 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  4A 77 CE 7A  CF 7C CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  E4 EA 23 FF  69 7D CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  50 13 BA 8D  A2 9A CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  0E 07 93 13  BD 06 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  9D 55 D0 B3  99 58 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  46 AC FF 8B  CF 7C CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  80 29 2D 02  6A 7D CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  90 8D 36 07  B5 9B CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  5C 9B 8B B8  6A 06 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  85 9F BB 99  9A 58 CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  BE 3D 21 02  6A 7D CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  70 53 09 07  B5 9B CA 01  00 00 00 00
     * 00 00 00 00  00 00 00 00  5B 62 42 B6  9A 58 CA 01  00 00 00 00
     * 01 00 00 00  00 00 00 00  B2 46 9B 9E  CF 7C CA 01  00 00 00 00
     * 01 00 00 00  00 00 00 00  CA 88 EE 1A  BD 06 CA 01  00 00 00 00
     *
     * From the above we worked out that fields 3 and 4 are an NT
     * timestamp, which seems to be "last modified" (when REGEDIT
     * unloads a hive it updates this timestamp even if nothing
     * has been changed).
     *)
    unknown1 : 4*8 : littleendian;  (* usually zero, occasionally 1 *)
    unknown2 : 4*8 : littleendian;  (* always zero? *)
    last_modified : 64
      : littleendian,
        bind (if page_offset = 0 then nt_to_time_t last_modified
              else (
                assert (last_modified = 0_L);
                0.
              )
             );
    (* The "B.D." document said this field contains the page size, but
     * this is not true.  This misinformation has been copied to the
     * sentinelchicken documentation too.
     *)
    unknown5 : 4*8 : littleendian;  (* always zero? *)

    (* Now the blocks in this page follow. *)
    blocks : (page_size - 32) * 8 : bitstring;

    rest : -1 : bitstring }

let fprintf_page chan bits =
  bitmatch bits with
  | { :page_fields } ->
      fprintf chan "HB %s %08x %08lx %08lx %s %08lx\n"
        (print_offset page_offset)
        page_size unknown1 unknown2
        (if page_offset = 0 then print_time last_modified
         else string_of_float last_modified) unknown5

let bitmatch block_fields =
  { seg_len : 4*8
      : littleendian, bind (Int32.to_int seg_len);
    block_data : (abs seg_len - 4) * 8 : bitstring;
    rest : -1 : bitstring }

let fprintf_block chan block_offset bits =
  bitmatch bits with
  | { :block_fields } ->
      fprintf chan "BL %s %s %d\n"
        (print_offset block_offset)
        (if seg_len < 0 then "used" else "free")
        (if seg_len < 0 then -seg_len else seg_len)

(* Iterate over the pages and blocks.  In the process we will examine
 * each page (hbin) header.  Also we will build block_list which is a
 * list of (block offset, length, used flag, data).
 *)
let block_list = ref []
let () =
  let rec loop_over_pages data data_offset =
    if data_offset < end_pages then (
      bitmatch data with
      | { rest : -1 : bitstring } when bitstring_length rest = 0 -> ()

      | { :page_fields } ->
          fprintf_page stdout data;

          assert (page_offset = data_offset);

          if data_offset = 0 then (     (* first hbin only *)
            if unknown1 <> 0_l then
              eprintf "HB %s unknown1 field <> 0 (%08lx)\n"
                (print_offset page_offset) unknown1;
            if unknown2 <> 0_l then
              eprintf "HB %s unknown2 field <> 0 (%08lx)\n"
                (print_offset page_offset) unknown2;
            if unknown5 <> 0_l then
              eprintf "HB %s unknown5 field <> 0 (%08lx)\n"
                (print_offset page_offset) unknown5
          ) else (                      (* subsequent hbins *)
            if unknown1 <> 0_l || unknown2 <> 0_l || unknown5 <> 0_l then
                eprintf "HB %s unknown fields <> 0 (%08lx %08lx %08lx)\n"
                  (print_offset page_offset)
                  unknown1 unknown2 unknown5;
            if last_modified <> 0. then
                eprintf "HB %s last_modified <> 0. (%g)\n"
                  (print_offset page_offset) last_modified
          );

          (* Loop over the blocks in this page. *)
          loop_over_blocks blocks (data_offset + 32);

          (* Loop over rest of the pages. *)
          loop_over_pages rest (data_offset + page_size)

      | {_} ->
          failwithf "%s: invalid hbin at offset %s\n"
            basename (print_offset data_offset)
    ) else (
      (* Reached the end of the official hbins in this file, BUT the
       * file can be larger than this and might contain stuff.  What
       * does it contain after the hbins?  We think just junk, but
       * we're not sure.
       *)
      if not (is_zero_bitstring data) then (
        eprintf "Junk in file after end of pages:\n";
        let rec loop data data_offset =
          bitmatch data with
          | { rest : -1 : bitstring } when bitstring_length rest = 0 -> ()
          | { :page_fields } ->
              eprintf "\tjunk hbin %s 0x%08x\n"
                (print_offset data_offset) page_size;
              loop rest (data_offset + page_size);
          | { _ } ->
              eprintf "\tother junk %s %s\n"
                (print_offset data_offset) (print_bitstring data)
        in
        loop data data_offset
      )
    )
  and loop_over_blocks blocks block_offset =
    bitmatch blocks with
    | { rest : -1 : bitstring } when bitstring_length rest = 0 -> ()

    | { :block_fields } ->
        assert (block_offset mod 8 = 0);

        fprintf_block stdout block_offset blocks;

        let used, seg_len =
          if seg_len < 0 then true, -seg_len else false, seg_len in

        let block = block_offset, (seg_len, used, block_data) in
        block_list := block :: !block_list;

        (* Loop over the rest of the blocks in this page. *)
        loop_over_blocks rest (block_offset + seg_len)

    | {_} ->
        failwithf "%s: invalid block near offset %s\n"
          basename (print_offset block_offset)
  in
  loop_over_pages data 0

(* Turn the block_list into a map so we can quickly look up a block
 * from its offset.
 *)
let block_list = !block_list
let block_map =
  List.fold_left (
    fun map (block_offset, block) -> IntMap.add block_offset block map
  ) IntMap.empty block_list
let lookup fn offset =
  try
    let (_, used, _) as block = IntMap.find offset block_map in
    if not used then
      failwithf "%s: %s: lookup: free block %s referenced from hive tree"
        basename fn (print_offset offset);
    block
  with Not_found ->
    failwithf "%s: %s: lookup: unknown block %s referenced from hive tree"
      basename fn (print_offset offset)

(* Use this to mark blocks that we've visited.  If the hive contains
 * no unreferenced blocks, then by the end this should just contain
 * free blocks.
 *)
let mark_visited, is_not_visited, unvisited_blocks =
  let v = ref block_map in
  let mark_visited offset = v := IntMap.remove offset !v
  and is_not_visited offset = IntMap.mem offset !v
  and unvisited_blocks () = !v in
  mark_visited, is_not_visited, unvisited_blocks

(* Define persistent patterns to match nk-records, vk-records and
 * sk-records, which are the record types that we especially want to
 * analyze later.  Other blocks types (eg. value lists, lf-records)
 * have no "spare space" so everything is known about them and we don't
 * store these.
 *)
let bitmatch nk_fields =
  { "nk" : 2*8 : string;
    (* Flags stored in the file as a little endian word, hence the
     * unusual ordering:
     *)
    virtmirrored : 1;
    predefinedhandle : 1; keynameascii : 1; symlinkkey : 1;
    cannotbedeleted : 1; isroot : 1; ismountpoint : 1; isvolatile : 1;
    unknownflag8000 : 1; unknownflag4000 : 1;
    unknownflag2000 : 1; unknownflag1000 : 1;
    unknownflag0800 : 1; unknownflag0400 : 1;
    virtualstore : 1; virttarget : 1;
    timestamp : 64 : littleendian, bind (nt_to_time_t timestamp);
    unknown1 : 4*8 : littleendian;
    parent : 4*8 : littleendian, bind (get_offset parent);
    nr_subkeys : 4*8 : littleendian, bind (Int32.to_int nr_subkeys);
    nr_subkeys_vol : 4*8;
    subkeys : 4*8 : littleendian, bind (get_offset subkeys);
    subkeys_vol : 4*8;
    nr_values : 4*8 : littleendian, bind (Int32.to_int nr_values);
    vallist : 4*8 : littleendian, bind (get_offset vallist);
    sk : 4*8 : littleendian, bind (get_offset sk);
    classname : 4*8 : littleendian, bind (get_offset classname);
    (* sentinelchicken.com says this is a single 32 bit field
     * containing maximum number of bytes in a subkey name, however
     * that does not seem to be correct.  We think it is two 16 bit
     * fields, the first being the maximum number of bytes in the
     * UTF16-LE encoded version of the subkey names, (since subkey
     * names are usually ASCII, that would be max length of names * 2).
     * This is a historical maximum, so it can be greater than the
     * current maximum name field.
     * 
     * The second field is often non-zero, but the purpose is unknown.
     * In the hives we examined it had values 0, 1, 0x20, 0x21, 0xa0,
     * 0xa1, 0xe1, suggesting some sort of flags.
     *)
    max_subkey_name_len : 2*8 : littleendian;
    unknown2 : 2*8 : littleendian;
    (* sentinelchicken.com says: maximum subkey CLASSNAME length,
     * however that does not seem to be correct.  In hives I looked
     * at, it has value 0, 0xc, 0x10, 0x18, 0x1a, 0x28.
     *)
    unknown3 : 4*8 : littleendian;
    (* sentinelchicken.com says: maximum number of bytes in a value
     * name, however that does not seem to be correct.  We think it is
     * the maximum number of bytes in the UTF16-LE encoded version of
     * the value names (since value names are usually ASCII, that would
     * be max length of names * 2).  This is a historical maximum, so
     * it can be greater than the current maximum name field.
     *)
    max_vk_name_len : 4*8 : littleendian, bind (Int32.to_int max_vk_name_len);
    (* sentinelchicken.com says: maximum value data size, and this
     * agrees with my observations.  It is the largest data size (not
     * seg_len, but vk.data_len) for any value in this key.  We think
     * that this field is a historical max, so eg if a maximally sized
     * value is deleted then this field is not reduced.  Certainly
     * max_vk_data_len >= the measured maximum in all the hives that we
     * have observed.
     *)
    max_vk_data_len : 4*8 : littleendian, bind (Int32.to_int max_vk_data_len);
    unknown6 : 4*8 : littleendian;
    name_len : 2*8 : littleendian;
    classname_len : 2*8 : littleendian;
    name : name_len * 8 : string }

let fprintf_nk chan nk =
  let (_, _, bits) = lookup "fprintf_nk" nk in
  bitmatch bits with
  | { :nk_fields } ->
      fprintf chan
        "NK %s %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s %s %08lx %s %d %ld %s %08lx %d %s %s %s %d %04x %08lx %d %d %08lx %d %d %s\n"
        (print_offset nk)
        (if unknownflag8000 then "8" else ".")
        (if unknownflag4000 then "4" else ".")
        (if unknownflag2000 then "2" else ".")
        (if unknownflag1000 then "1" else ".")
        (if unknownflag0800 then "8" else ".")
        (if unknownflag0400 then "4" else ".")
        (if virtualstore then "s" else ".")
        (if virttarget then "t" else ".")
        (if virtmirrored then "m" else ".")
        (if predefinedhandle then "P" else ".")
        (if keynameascii then "A" else ".")
        (if symlinkkey then "S" else ".")
        (if cannotbedeleted then "N" else ".")
        (if isroot then "R" else ".")
        (if ismountpoint then "M" else ".")
        (if isvolatile then "V" else ".")
        (print_time timestamp)
        unknown1 (print_offset parent) nr_subkeys nr_subkeys_vol
        (print_offset subkeys) subkeys_vol
        nr_values (print_offset vallist)
        (print_offset sk) (print_offset classname)
        max_subkey_name_len unknown2 unknown3
        max_vk_name_len max_vk_data_len unknown6
        name_len classname_len name

type data_t = Inline of bitstring | Offset of int
let bitmatch vk_fields =
  { "vk" : 2*8 : string;
    name_len : 2*8 : littleendian;
    (* No one documents the important fact that data_len can have the
     * top bit set (randomly or is it meaningful?).  The length can
     * also be 0 (or 0x80000000) if the data type is NONE.
     *)
    data_len : 4*8
      : littleendian, bind (
        let data_len = Int32.logand data_len 0x7fff_ffff_l in
        Int32.to_int data_len
      );
    (* Inline data if len <= 4, offset otherwise.
     *
     * The data itself depends on the type field.
     *
     * For REG_SZ type, the data always seems to be NUL-terminated, which
     * means because these strings are often UTF-16LE, that the string will
     * end with \0\0 bytes.  The termination bytes are included in data_len.
     *
     * For REG_MULTI_SZ, see
     * http://blogs.msdn.com/oldnewthing/archive/2009/10/08/9904646.aspx
     *)
    data : 4*8
      : bitstring, bind (
        if data_len <= 4 then
          Inline (takebits (data_len*8) data)
        else (
          let offset =
            bitmatch data with { offset : 4*8 : littleendian } -> offset in
          let offset = get_offset offset in
          Offset offset
        )
      );
    t : 4*8 : littleendian, bind (Int32.to_int t);
    (* Flags, stored as a little-endian word: *)
    unknown1 : 7;
    nameisascii : 1;  (* Clear for default [zero-length] name, always set
                       * otherwise in registries that we found.  Perhaps this
                       * is really "nameisdefault" flag?
                       *)
    unknown2 : 8;
    (* Unknown field, usually contains something. *)
    unknown3 : 2*8 : littleendian;
    name : name_len * 8 : string }

let fprintf_vk chan vk =
  let (_, _, bits) = lookup "fprintf_vk" vk in
  bitmatch bits with
  | { :vk_fields } ->
      let real_data =
        match data with
        | Inline data -> data
        | Offset offset ->
            let (_, _, bits) = lookup "fprintf_vk (data)" offset in
            bits in
      fprintf chan "VK %s %s %d %s%s %s %08x %s %08x %08x\n"
        (print_offset vk)
        name data_len
        (match data with
         | Inline _ -> ""
         | Offset offset -> "["^print_offset offset^"]")
        (print_bitstring real_data)
        (print_vk_type t)
        unknown1 (if nameisascii then "A" else "L")
        unknown2 unknown3

let bitmatch sk_fields =
  { "sk" : 2*8 : string;
    unknown1 : 2*8 : littleendian;
    sk_next : 4*8 : littleendian, bind (get_offset sk_next);
    sk_prev : 4*8 : littleendian, bind (get_offset sk_prev);
    refcount : 4*8 : littleendian, bind (Int32.to_int refcount);
    sec_len : 4*8 : littleendian, bind (Int32.to_int sec_len);
    sec_desc : sec_len * 8 : bitstring }

let fprintf_sk chan sk =
  let (_, _, bits) = lookup "fprintf_sk" sk in
  bitmatch bits with
  | { :sk_fields } ->
      fprintf chan "SK %s %04x %s %s %d %d\n"
        (print_offset sk) unknown1
        (print_offset sk_next) (print_offset sk_prev)
        refcount sec_len
        (* print_bitstring sec_desc -- suppress this *)

(* Store lists of records we encounter (lists of offsets). *)
let nk_records = ref []
and vk_records = ref []
and sk_records = ref []

(* Functions to visit each block, starting at the root.  Each block
 * that we visit is printed.
 *)
let rec visit_nk ?(nk_is_root = false) nk =
  let (_, _, bits) = lookup "visit_nk" nk in
  mark_visited nk;
  (bitmatch bits with
   | { :nk_fields } ->
       fprintf_nk stdout nk;

       nk_records := nk :: !nk_records;

       (* Check the isroot flag is only set on the root node. *)
       assert (isroot = nk_is_root);

       if unknownflag8000 then
         eprintf "NK %s unknownflag8000 is set\n" (print_offset nk);
       if unknownflag4000 then
         eprintf "NK %s unknownflag4000 is set\n" (print_offset nk);
       if unknownflag2000 then
         eprintf "NK %s unknownflag2000 is set\n" (print_offset nk);
       if unknownflag1000 then
         eprintf "NK %s unknownflag1000 is set\n" (print_offset nk);
       if unknownflag0800 then
         eprintf "NK %s unknownflag0800 is set\n" (print_offset nk);
       if unknownflag0400 then
         eprintf "NK %s unknownflag0400 is set\n" (print_offset nk);
       if unknown1 <> 0_l then
         eprintf "NK %s unknown1 <> 0 (%08lx)\n" (print_offset nk) unknown1;
       if unknown2 <> 0 then
         eprintf "NK %s unknown2 <> 0 (%04x)\n" (print_offset nk) unknown2;
       if unknown3 <> 0_l then
         eprintf "NK %s unknown3 <> 0 (%08lx)\n" (print_offset nk) unknown3;
       if unknown6 <> 0_l then
         eprintf "NK %s unknown6 <> 0 (%08lx)\n" (print_offset nk) unknown6;

       (* -- common, assume it's not an error
       if classname = -1 then
         eprintf "NK %s has no classname\n" (print_offset nk);
       if classname_len = 0 then
         eprintf "NK %s has zero-length classname\n" (print_offset nk);
       *)
       if sk = -1 then
         eprintf "NK %s has no sk-record\n" (print_offset nk);
       if name_len = 0 then
         eprintf "NK %s has zero-length name\n" (print_offset nk);

       (* Visit the values first at this node. *)
       let max_data_len, max_name_len =
         if vallist <> -1 then
           visit_vallist nr_values vallist
         else
           0, 0 in

       if max_vk_data_len < max_data_len then
         eprintf "NK %s nk.max_vk_data_len (%d) < actual max data_len (%d)\n"
           (print_offset nk) max_vk_data_len max_data_len;

       if max_vk_name_len < max_name_len * 2 then
         eprintf "NK %s nk.max_vk_name_len (%d) < actual max name_len * 2 (%d)\n"
           (print_offset nk) max_vk_name_len (max_name_len * 2);

       (* Visit the subkeys of this node. *)
       if subkeys <> -1 then (
         let counted, max_name_len, _ = visit_subkeys subkeys in

         if counted <> nr_subkeys then
           failwithf "%s: incorrect count of subkeys (%d, counted %d) in subkey list at %s\n"
             basename nr_subkeys counted (print_offset subkeys);

         if max_subkey_name_len < max_name_len * 2 then
           eprintf "NK %s nk.max_subkey_name_len (%d) < actual max name_len * 2 (%d)\n"
             (print_offset nk) max_subkey_name_len (max_name_len * 2);
       );

       (* Visit the sk-record and classname. *)
       if sk <> -1 then
         visit_sk sk;
       if classname <> -1 then
         visit_classname classname classname_len;

   | {_} ->
       failwithf "%s: invalid nk block at offset %s\n"
         basename (print_offset nk)
  )

and visit_vallist nr_values vallist =
  let (seg_len, _, bits) = lookup "visit_vallist" vallist in
  mark_visited vallist;
  printf "VL %s %d %d\n" (print_offset vallist) nr_values seg_len;
  visit_values_in_vallist nr_values vallist bits

and visit_values_in_vallist nr_values vallist bits =
  if nr_values > 0 then (
    bitmatch bits with
    | { rest : -1 : bitstring } when bitstring_length rest = 0 ->
        assert (nr_values = 0);
        0, 0

    | { value : 4*8 : littleendian, bind (get_offset value);
        rest : -1 : bitstring } ->
        let data_len, name_len = visit_vk value in
        let max_data_len, max_name_len =
          visit_values_in_vallist (nr_values-1) vallist rest in
        max max_data_len data_len, max max_name_len name_len

    | {_} ->
        failwithf "%s: invalid offset in value list at %s\n"
          basename (print_offset vallist)
  ) else 0, 0

and visit_vk vk =
  let (_, _, bits) = lookup "visit_vk" vk in
  mark_visited vk;

  (bitmatch bits with
   | { :vk_fields } ->
       fprintf_vk stdout vk;

       if unknown1 <> 0 then
         eprintf "VK %s unknown1 flags set (%02x)\n"
           (print_offset vk) unknown1;
       if unknown2 <> 0 then
         eprintf "VK %s unknown2 flags set (%02x)\n"
           (print_offset vk) unknown2;
       if unknown3 <> 0 then
         eprintf "VK %s unknown3 flags set (%04x)\n"
           (print_offset vk) unknown3;

       (* Note this is common for default [ie. zero-length] key names. *)
       if not nameisascii && name_len > 0 then
         eprintf "VK %s has non-ASCII name flag set (name is %s)\n"
           (print_offset vk) (print_binary_string name);

       vk_records := vk :: !vk_records;
       (match data with
        | Inline data -> ()
        | Offset offset ->
            let _ = lookup "visit_vk (data)" offset in
            mark_visited offset
       );

       data_len, name_len

   | {_} ->
       failwithf "%s: invalid vk block at offset %s\n"
         basename (print_offset vk)
  )

(* Visits subkeys, recursing through intermediate lf/lh/ri structures,
 * and returns the number of subkeys actually seen.
 *)
and visit_subkeys subkeys =
  let (_, _, bits) = lookup "visit_subkeys" subkeys in
  mark_visited subkeys;
  (bitmatch bits with
   | { "lf" : 2*8 : string;
       len : 2*8 : littleendian; (* number of subkeys of this node *)
       rest : len*8*8 : bitstring } ->
       printf "LF %s %d\n" (print_offset subkeys) len;
       visit_subkeys_in_lf_list false subkeys len rest

   | { "lh" : 2*8 : string;
       len : 2*8 : littleendian; (* number of subkeys of this node *)
       rest : len*8*8 : bitstring } ->
       printf "LF %s %d\n" (print_offset subkeys) len;
       visit_subkeys_in_lf_list true subkeys len rest

   | { "ri" : 2*8 : string;
       len : 2*8 : littleendian;
       rest : len*4*8 : bitstring } ->
       printf "RI %s %d\n" (print_offset subkeys) len;
       visit_subkeys_in_ri_list subkeys len rest

   (* In theory you can have an li-record here, but we've never
    * seen one.
    *)

   | { "nk" : 2*8 : string } ->
       visit_nk subkeys;
       let name, name_len = name_of_nk subkeys in
       1, name_len, name

   | {_} ->
       failwithf "%s: invalid subkey node found at %s\n"
         basename (print_offset subkeys)
  )

and visit_subkeys_in_lf_list newstyle_hash subkeys_top len bits =
  if len > 0 then (
    bitmatch bits with
    | { rest : -1 : bitstring } when bitstring_length rest = 0 ->
        assert (len = 0);
        0, 0, ""

    | { offset : 4*8 : littleendian, bind (get_offset offset);
        hash : 4*8 : bitstring;
        rest : -1 : bitstring } ->
        let c1, name_len1, name = visit_subkeys offset in

        check_hash offset newstyle_hash hash name;

        let c2, name_len2, _ =
          visit_subkeys_in_lf_list newstyle_hash subkeys_top (len-1) rest in
        c1 + c2, max name_len1 name_len2, ""

    | {_} ->
        failwithf "%s: invalid subkey in lf/lh list at %s\n"
          basename (print_offset subkeys_top)
  ) else 0, 0, ""

and visit_subkeys_in_ri_list subkeys_top len bits =
  if len > 0 then (
    bitmatch bits with
    | { rest : -1 : bitstring } when bitstring_length rest = 0 ->
        assert (len = 0);
        0, 0, ""

    | { offset : 4*8 : littleendian, bind (get_offset offset);
        rest : -1 : bitstring } ->
        let c1, name_len1, _ = visit_subkeys offset in
        let c2, name_len2, _ =
          visit_subkeys_in_ri_list subkeys_top (len-1) rest in
        c1 + c2, max name_len1 name_len2, ""

    | {_} ->
        failwithf "%s: invalid subkey in ri list at %s\n"
          basename (print_offset subkeys_top)
  ) else 0, 0, ""

and check_hash offset newstyle_hash hash name =
  if not newstyle_hash then (
    (* Old-style lf record hash the first four bytes of the name
     * as the has.
     *)
    let len = String.length name in
    let name_bits =
      if len >= 4 then
        bitstring_of_string (String.sub name 0 4)
      else (
        let zeroes = zeroes_bitstring ((4-len)*8) in
        concat [bitstring_of_string name; zeroes]
      ) in
    if not (equals hash name_bits) then
      eprintf "LF incorrect hash for name %s, expected %s, actual %s\n"
        name (print_bitstring name_bits) (print_bitstring hash)
  ) else (
    (* New-style lh record has a proper hash. *)
    let actual = bitmatch hash with { hash : 4*8 : littleendian } -> hash in
    let h = ref 0_l in
    String.iter (
      fun c ->
        h := Int32.mul !h 37_l;
        h := Int32.add !h (Int32.of_int (Char.code (Char.uppercase c)))
    ) name;
    if actual <> !h then
      eprintf "LH incorrect hash for name %s, expected 0x%08lx, actual 0x%08lx\n"
        name !h actual
  )

and name_of_nk nk =
  let (_, _, bits) = lookup "name_of_nk" nk in
  bitmatch bits with
  | { :nk_fields } -> name, name_len

and visit_sk sk =
  let (_, _, bits) = lookup "visit_sk" sk in
  if is_not_visited sk then (
    mark_visited sk;
    (bitmatch bits with
     | { :sk_fields } ->
         fprintf_sk stdout sk;

         if unknown1 <> 0 then
           eprintf "SK %s unknown1 <> 0 (%04x)\n" (print_offset sk) unknown1;

         sk_records := sk :: !sk_records

     | {_} ->
         failwithf "%s: invalid sk-record at %s\n"
           basename (print_offset sk)
    )
  )

and visit_classname classname classname_len =
  let (seg_len, _, bits) = lookup "visit_classname" classname in
  mark_visited classname;
  assert (seg_len >= classname_len);
  printf "CL %s %s\n" (print_offset classname) (print_bitstring bits)

let () =
  visit_nk ~nk_is_root:true root_key

(* These are immutable now. *)
let nk_records = !nk_records
let vk_records = !vk_records
let sk_records = !sk_records

(* So we can rapidly tell what is an nk/vk/sk offset. *)
let nk_set =
  List.fold_left (fun set offs -> IntSet.add offs set) IntSet.empty nk_records
let vk_set =
  List.fold_left (fun set offs -> IntSet.add offs set) IntSet.empty vk_records
let sk_set =
  List.fold_left (fun set offs -> IntSet.add offs set) IntSet.empty sk_records

(* Now after visiting all the blocks, are there any used blocks which
 * are unvisited?  If there are any then that would indicate either (a)
 * that the hive contains unreferenced blocks, or (b) that there are
 * referenced blocks that we did not visit because we don't have a full
 * understanding of the hive format.
 *
 * Windows 7 registries often contain a few of these -- not clear
 * how serious they are, but don't fail here.
 *)
let () =
  let unvisited = unvisited_blocks () in
  IntMap.iter (
    fun offset block ->
      match block with
      | (_, false, _) -> () (* ignore unused blocks *)
      | (seg_len, true, _) ->
          eprintf "used block %s (length %d) is not referenced\n"
            (print_offset offset) seg_len
  ) unvisited

(* Check the SKs are:
 * (a) linked into a single circular list through the sk_prev/sk_next
 * pointers
 * (b) refcounts are correct
 *)
let () =
  if List.length sk_records > 0 then (
    let sk0 = List.hd sk_records in (* start at any arbitrary sk *)
    (* This loop follows the chain of sk pointers until we arrive
     * back at the original, checking prev/next are consistent.
     *)
    let rec loop visited prevsk sk =
      if sk <> sk0 then (
        if not (IntSet.mem sk sk_set) then
          eprintf "SK %s not an sk-record (faulty sk_next somewhere)\n"
            (print_offset sk)
        else (
          let _, _, bits = lookup "loop sk circular list" sk in
          bitmatch bits with
          | { :sk_fields } ->
              if sk_prev <> prevsk then
                eprintf "SK %s sk_prev != previous sk (%s, %s)\n"
                  (print_offset sk)
                  (print_offset sk_prev) (print_offset prevsk);
              if IntSet.mem sk visited then
                eprintf "SK %s already visited (bad circular list)\n"
                  (print_offset sk);
              let visited = IntSet.add sk visited in
              loop visited sk sk_next
        )
      )
    in
    let _, _, bits = lookup "start sk circular list" sk0 in
    (bitmatch bits with
     | { :sk_fields } ->
         loop IntSet.empty sk_prev sk0
    );

    (* For every nk-record, if it references an sk-record count that,
     * then check this matches the refcounts in the sk-records
     * themselves.
     *)
    let refcounts = Counter.create () in
    List.iter (
      fun nk ->
        let _, _, bits = lookup "sk refcounter (nk)" nk in
        (bitmatch bits with
         | { :nk_fields } ->
             Counter.incr refcounts sk
        )
    ) nk_records;

    List.iter (
      fun sk ->
        let _, _, bits = lookup "sk refcounter (sk)" sk in
        (bitmatch bits with
         | { :sk_fields } ->
             let actual = Counter.get refcounts sk in
             if actual <> refcount then
               eprintf "SK %s incorrect refcount (actual %d, in file %d)\n"
                 (print_offset sk) actual refcount
        )
    ) sk_records
  )
