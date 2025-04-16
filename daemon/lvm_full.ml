(* guestfs-inspection
 * Copyright (C) 2009-2025 Red Hat Inc.
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
 *)

(* This file implements the complicated lvs-full, vgs-full and pvs-full APIs
 *
 * XXX Deprecate these APIs are replace with APIs for getting single
 * named fields from LVM.  That will be slower but far more flexible
 * and extensible.
 *)

open Unix
open Printf

open Std_utils

open Utils

(* LVM UUIDs are basically 32 byte strings with '-' inserted.
 * Remove the '-' characters and check it's the right length.
 *)
let parse_uuid uuid =
  let uuid' =
    uuid |> String.explode |> List.filter ((<>) '-') |> String.implode in
  if String.length uuid' <> 32 then
    failwithf "lvm-full: parse_uuid: unexpected UUID format: %S" uuid;
  uuid'

(* Parse the percent fields.  These can be empty. *)
let parse_percent pc = if pc = "" then None else Some (float_of_string pc)

(* XXX These must match generator/structs.ml *)
let lvm_pv_cols = [
  "pv_name";                    (* FString *)
  "pv_uuid";                    (* FUUID *)
  "pv_fmt";                     (* FString *)
  "pv_size";                    (* FBytes *)
  "dev_size";                   (* FBytes *)
  "pv_free";                    (* FBytes *)
  "pv_used";                    (* FBytes *)
  "pv_attr";                    (* FString (* XXX *) *)
  "pv_pe_count";                (* FInt64 *)
  "pv_pe_alloc_count";          (* FInt64 *)
  "pv_tags";                    (* FString *)
  "pe_start";                   (* FBytes *)
  "pv_mda_count";               (* FInt64 *)
  "pv_mda_free";                (* FBytes *)
]

let tokenize_pvs = function
  | [ pv_name; pv_uuid; pv_fmt; pv_size; dev_size; pv_free;
      pv_used; pv_attr; pv_pe_count; pv_pe_alloc_count; pv_tags;
      pe_start; pv_mda_count; pv_mda_free ] ->
     { Structs.pv_name =                   pv_name;
       pv_uuid =           parse_uuid      pv_uuid;
       pv_fmt =                            pv_fmt;
       pv_size =           Int64.of_string pv_size;
       dev_size =          Int64.of_string dev_size;
       pv_free =           Int64.of_string pv_free;
       pv_used =           Int64.of_string pv_used;
       pv_attr =                           pv_attr;
       pv_pe_count =       Int64.of_string pv_pe_count;
       pv_pe_alloc_count = Int64.of_string pv_pe_alloc_count;
       pv_tags =                           pv_tags;
       pe_start =          Int64.of_string pe_start;
       pv_mda_count =      Int64.of_string pv_mda_count;
       pv_mda_free =       Int64.of_string pv_mda_free }

  | fields ->
     failwithf "pvs-full: tokenize_pvs: unexpected number of fields: %d"
       (List.length fields)

(* XXX These must match generator/structs.ml *)
let lvm_vg_cols = [
  "vg_name";                    (* FString *)
  "vg_uuid";                    (* FUUID *)
  "vg_fmt";                     (* FString *)
  "vg_attr";                    (* FString (* XXX *) *)
  "vg_size";                    (* FBytes *)
  "vg_free";                    (* FBytes *)
  "vg_sysid";                   (* FString *)
  "vg_extent_size";             (* FBytes *)
  "vg_extent_count";            (* FInt64 *)
  "vg_free_count";              (* FInt64 *)
  "max_lv";                     (* FInt64 *)
  "max_pv";                     (* FInt64 *)
  "pv_count";                   (* FInt64 *)
  "lv_count";                   (* FInt64 *)
  "snap_count";                 (* FInt64 *)
  "vg_seqno";                   (* FInt64 *)
  "vg_tags";                    (* FString *)
  "vg_mda_count";               (* FInt64 *)
  "vg_mda_free";                (* FBytes *)
]

let tokenize_vgs = function
  | [ vg_name; vg_uuid; vg_fmt; vg_attr; vg_size; vg_free; vg_sysid;
      vg_extent_size; vg_extent_count; vg_free_count; max_lv;
      max_pv; pv_count; lv_count; snap_count; vg_seqno; vg_tags;
      vg_mda_count; vg_mda_free ] ->
     { Structs.vg_name =                 vg_name;
       vg_uuid =         parse_uuid      vg_uuid;
       vg_fmt =                          vg_fmt;
       vg_attr =                         vg_attr;
       vg_size =         Int64.of_string vg_size;
       vg_free =         Int64.of_string vg_free;
       vg_sysid =                        vg_sysid;
       vg_extent_size =  Int64.of_string vg_extent_size;
       vg_extent_count = Int64.of_string vg_extent_count;
       vg_free_count =   Int64.of_string vg_free_count;
       max_lv =          Int64.of_string max_lv;
       max_pv =          Int64.of_string max_pv;
       pv_count =        Int64.of_string pv_count;
       lv_count =        Int64.of_string lv_count;
       snap_count =      Int64.of_string snap_count;
       vg_seqno =        Int64.of_string vg_seqno;
       vg_tags =                         vg_tags;
       vg_mda_count =    Int64.of_string vg_mda_count;
       vg_mda_free =     Int64.of_string vg_mda_free }

  | fields ->
     failwithf "pvs-full: tokenize_vgs: unexpected number of fields: %d"
       (List.length fields)

(* XXX These must match generator/structs.ml *)
let lvm_lv_cols = [
  "lv_name";                    (* FString *)
  "lv_uuid";                    (* FUUID *)
  "lv_attr";                    (* FString (* XXX *) *)
  "lv_major";                   (* FInt64 *)
  "lv_minor";                   (* FInt64 *)
  "lv_kernel_major";            (* FInt64 *)
  "lv_kernel_minor";            (* FInt64 *)
  "lv_size";                    (* FBytes *)
  "seg_count";                  (* FInt64 *)
  "origin";                     (* FString *)
  "snap_percent";               (* FOptPercent *)
  "copy_percent";               (* FOptPercent *)
  "move_pv";                    (* FString *)
  "lv_tags";                    (* FString *)
  "mirror_log";                 (* FString *)
  "modules";                    (* FString *)
]

let tokenize_lvs = function
  | [ lv_name; lv_uuid; lv_attr; lv_major; lv_minor; lv_kernel_major;
      lv_kernel_minor; lv_size; seg_count; origin; snap_percent;
      copy_percent; move_pv; lv_tags; mirror_log; modules ] ->
     { Structs.lv_name =                 lv_name;
       lv_uuid =         parse_uuid      lv_uuid;
       lv_attr =                         lv_attr;
       lv_major =        Int64.of_string lv_major;
       lv_minor =        Int64.of_string lv_minor;
       lv_kernel_major = Int64.of_string lv_kernel_major;
       lv_kernel_minor = Int64.of_string lv_kernel_minor;
       lv_size =         Int64.of_string lv_size;
       seg_count =       Int64.of_string seg_count;
       origin =                          origin;
       snap_percent =    parse_percent   snap_percent;
       copy_percent =    parse_percent   copy_percent;
       move_pv =                         move_pv;
       lv_tags =                         lv_tags;
       mirror_log =                      mirror_log;
       modules =                         modules }

  | fields ->
    failwithf "pvs-full: tokenize_vgs: unexpected number of fields: %d"
      (List.length fields)

let rec pvs_full () =
  let out = run_lvm_command "pvs" lvm_pv_cols in
  let lines = trim_and_split out in
  let pvs = List.map tokenize_pvs lines in
  pvs

and vgs_full () =
  let out = run_lvm_command "vgs" lvm_vg_cols in
  let lines = trim_and_split out in
  let vgs = List.map tokenize_vgs lines in
  vgs

and lvs_full () =
  let out = run_lvm_command "lvs" lvm_lv_cols in
  let lines = trim_and_split out in
  let lvs = List.map tokenize_lvs lines in
  lvs

and run_lvm_command typ cols =
  let cols = String.concat "," cols in
  let cmd = [ typ; "-o"; cols;
              "--unbuffered"; "--noheadings"; "--nosuffix";
              "--separator"; "\r"; "--units"; "b" ] in
  command "lvm" cmd

and trim_and_split out =
  (* Split the output into lines. *)
  let lines = String.nsplit "\n" out in

  (* LVM puts leading whitespace on each line so remove that. *)
  let lines = List.map String.triml lines in

  (* Ignore any blank lines. *)
  let lines = List.filter ((<>) "") lines in

  (* Split each line into fields. *)
  let lines = List.map (String.nsplit "\r") lines in
  lines
