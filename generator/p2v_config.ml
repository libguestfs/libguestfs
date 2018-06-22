(* libguestfs
 * Copyright (C) 2018 Red Hat Inc.
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

open Printf

open Std_utils
open Docstrings
open Pr

let generate_header = generate_header ~inputs:["generator/p2v_config.ml"]

type enum_choice = string * string (* name, comment *)
type enum = string * enum_choice list

type config_entry =
  | ConfigString of string
  | ConfigInt of string * int     (* field name, initial value *)
  | ConfigUnsigned of string
  | ConfigUInt64 of string
  | ConfigEnum of string * string (* field name, enum *)
  | ConfigBool of string
  | ConfigStringList of string
  | ConfigSection of string * config_entry list

(* Enums. *)
let enums = [
  "basis", [
    "BASIS_UNKNOWN",   "RTC could not be read";
    "BASIS_UTC",       "RTC is either UTC or an offset from UTC";
    "BASIS_LOCALTIME", "RTC is localtime";
  ];
  "output_allocation", [
    "OUTPUT_ALLOCATION_NONE",   "output allocation not set";
    "OUTPUT_ALLOCATION_SPARSE", "sparse";
    "OUTPUT_ALLOCATION_PREALLOCATED", "preallocated";
  ];
]

(* Configuration fields. *)
let fields = [
  ConfigSection ("remote", [
                   ConfigString  "server";
                   ConfigInt     ("port", 22);
                 ]);
  ConfigSection ("auth", [
                   ConfigString  "username";
                   ConfigString  "password";
                   ConfigSection ("identity", [
                                    ConfigString  "url";
                                    ConfigString  "file";
                                    ConfigBool    "file_needs_update";
                                 ]);
                   ConfigBool    "sudo";
                ]);
  ConfigString  "guestname";
  ConfigInt     ("vcpus", 0);
  ConfigUInt64  "memory";
  ConfigSection ("cpu", [
                   ConfigString   "vendor";
                   ConfigString   "model";
                   ConfigUnsigned "sockets";
                   ConfigUnsigned "cores";
                   ConfigUnsigned "threads";
                   ConfigBool     "acpi";
                   ConfigBool     "apic";
                   ConfigBool     "pae";
                ]);
  ConfigSection ("rtc", [
                   ConfigEnum     ("basis", "basis");
                   ConfigInt      ("offset", 0);
                ]);
  ConfigStringList "disks";
  ConfigStringList "removable";
  ConfigStringList "interfaces";
  ConfigStringList "network_map";
  ConfigSection ("output", [
                   ConfigString  "type";
                   ConfigEnum    ("allocation", "output_allocation");
                   ConfigString  "connection";
                   ConfigString  "format";
                   ConfigString  "storage";
                ]);
]

let name_of_config_entry = function
  | ConfigString n
  | ConfigInt (n, _)
  | ConfigUnsigned n
  | ConfigUInt64 n
  | ConfigEnum (n, _)
  | ConfigBool n
  | ConfigStringList n
  | ConfigSection (n, _) -> n

let rec generate_p2v_config_h () =
  generate_header CStyle GPLv2plus;

  pr "\
#ifndef GUESTFS_P2V_CONFIG_H
#define GUESTFS_P2V_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

";

  (* Generate enums. *)
  List.iter (
    fun (name, fields) ->
      pr "enum %s {\n" name;
      List.iter (
        fun (n, comment) ->
          pr "  %-25s /* %s */\n" (n ^ ",") comment
      ) fields;
      pr "};\n";
      pr "\n"
  ) enums;

  (* Generate struct config. *)
  generate_config_struct "config" fields;

  pr "\
extern struct config *new_config (void);
extern struct config *copy_config (struct config *);
extern void free_config (struct config *);
extern void print_config (struct config *, FILE *);

#endif /* GUESTFS_P2V_CONFIG_H */
"

and generate_config_struct name fields =
  (* If there are any ConfigSection (sub-structs) in any of the
   * fields then output those first.
   *)
  List.iter (
    function
    | ConfigSection (name, fields) ->
       generate_config_struct (name ^ "_config") fields
    | _ -> ()
  ) fields;

  (* Now generate this struct. *)
  pr "struct %s {\n" name;
  List.iter (
    function
    | ConfigString n ->       pr "  char *%s;\n" n
    | ConfigInt (n, _) ->     pr "  int %s;\n" n
    | ConfigUnsigned n ->     pr "  unsigned %s;\n" n
    | ConfigUInt64 n ->       pr "  uint64_t %s;\n" n
    | ConfigEnum (n, enum) -> pr "  enum %s %s;\n" enum n
    | ConfigBool n ->         pr "  bool %s;\n" n
    | ConfigStringList n ->   pr "  char **%s;\n" n
    | ConfigSection (n, _) -> pr "  struct %s_config %s;\n" n n
  ) fields;
  pr "};\n";
  pr "\n"

let rec generate_p2v_config_c () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <errno.h>
#include <error.h>

#include \"p2v.h\"
#include \"p2v-config.h\"

/**
 * Allocate a new config struct.
 */
struct config *
new_config (void)
{
  struct config *c;

  c = calloc (1, sizeof *c);
  if (c == NULL)
    error (EXIT_FAILURE, errno, \"calloc\");

";

  generate_field_initialization "c->" fields;

  pr "\

  return c;
}

/**
 * Copy a config struct.
 */
struct config *
copy_config (struct config *old)
{
  struct config *c = new_config ();

  memcpy (c, old, sizeof *c);

  /* Need to deep copy strings and string lists. */
";

  generate_field_copy "c->" fields;

  pr "\

  return c;
}

/**
 * Free a config struct.
 */
void
free_config (struct config *c)
{
  if (c == NULL)
    return;

";

  generate_field_free "c->" fields;

pr "\
}

";

  List.iter (
    fun (name, fields) ->
      pr "static void\n";
      pr "print_%s (enum %s v, FILE *fp)\n" name name;
      pr "{\n";
      pr "  switch (v) {\n";
      List.iter (
        fun (n, comment) ->
          pr "  case %s:\n" n;
          pr "    fprintf (fp, \"%s\");\n" comment;
          pr "    break;\n";
      ) fields;
      pr "  }\n";
      pr "}\n";
      pr "\n";
  ) enums;

 pr "\
/**
 * Print the conversion parameters and other important information.
 */
void
print_config (struct config *c, FILE *fp)
{
  size_t i;

  fprintf (fp, \"%%-20s %%s\\n\", \"local version\", PACKAGE_VERSION_FULL);
  fprintf (fp, \"%%-20s %%s\\n\", \"remote version\",
           v2v_version ? v2v_version : \"unknown\");
";

  generate_field_print None "c->" fields;

pr "\
}
"

and generate_field_initialization v fields =
  List.iter (
    function
    | ConfigInt (_, 0) -> ()
    | ConfigInt (n, i) ->
       pr "  %s%s = %d;\n" v n i

    | ConfigString _
    | ConfigUnsigned _
    | ConfigUInt64 _
    | ConfigEnum _
    | ConfigBool _
    | ConfigStringList _ -> ()

    | ConfigSection (n, fields) ->
       let v = sprintf "%s%s." v n in
       generate_field_initialization v fields
  ) fields

and generate_field_copy v fields =
  List.iter (
    function
    | ConfigString n ->
       pr "  if (%s%s) {\n" v n;
       pr "    %s%s = strdup (%s%s);\n" v n v n;
       pr "    if (%s%s == NULL)\n" v n;
       pr "      error (EXIT_FAILURE, errno, \"strdup: %%s\", \"%s\");\n" n;
       pr "  }\n";
    | ConfigStringList n ->
       pr "  if (%s%s) {\n" v n;
       pr "    %s%s = guestfs_int_copy_string_list (%s%s);\n" v n v n;
       pr "    if (%s%s == NULL)\n" v n;
       pr "      error (EXIT_FAILURE, errno, \"copy string list: %%s\", \"%s\");\n" n;
       pr "  }\n";

    | ConfigInt _
    | ConfigUnsigned _
    | ConfigUInt64 _
    | ConfigEnum _
    | ConfigBool _ -> ()

    | ConfigSection (n, fields) ->
       let v = sprintf "%s%s." v n in
       generate_field_copy v fields
  ) fields

and generate_field_free v fields =
  List.iter (
    function
    | ConfigString n ->
       pr "  free (%s%s);\n" v n
    | ConfigStringList n ->
       pr "  guestfs_int_free_string_list (%s%s);\n" v n

    | ConfigInt _
    | ConfigUnsigned _
    | ConfigUInt64 _
    | ConfigEnum _
    | ConfigBool _ -> ()

    | ConfigSection (n, fields) ->
       let v = sprintf "%s%s." v n in
       generate_field_free v fields
  ) fields

and generate_field_print prefix v fields =
  List.iter (
    fun field ->
      let printable_name =
        match prefix with
        | None -> name_of_config_entry field
        | Some prefix -> prefix ^ "." ^ name_of_config_entry field in

      match field with
      | ConfigString n ->
         pr "  fprintf (fp, \"%%-20s %%s\\n\",\n";
         pr "           \"%s\", %s%s ? %s%s : \"(none)\");\n"
            printable_name v n v n
      | ConfigInt (n, _) ->
         pr "  fprintf (fp, \"%%-20s %%d\\n\",\n";
         pr "           \"%s\", %s%s);\n" printable_name v n
      | ConfigUnsigned n ->
         pr "  fprintf (fp, \"%%-20s %%u\\n\",\n";
         pr "           \"%s\", %s%s);\n" printable_name v n
      | ConfigUInt64 n ->
         pr "  fprintf (fp, \"%%-20s %%\" PRIu64 \"\\n\",\n";
         pr "           \"%s\", %s%s);\n" printable_name v n
      | ConfigEnum (n, enum) ->
         pr "  fprintf (fp, \"%%-20s \", \"%s\");\n" printable_name;
         pr "  print_%s (%s%s, fp);\n" enum v n;
         pr "  fprintf (fp, \"\\n\");\n"
      | ConfigBool n ->
         pr "  fprintf (fp, \"%%-20s %%s\\n\",\n";
         pr "           \"%s\", %s%s ? \"true\" : \"false\");\n"
            printable_name v n
      | ConfigStringList n ->
         pr "  fprintf (fp, \"%%-20s\", \"%s\");\n" printable_name;
         pr "  if (%s%s) {\n" v n;
         pr "    for (i = 0; %s%s[i] != NULL; ++i)\n" v n;
         pr "      fprintf (fp, \" %%s\", %s%s[i]);\n" v n;
         pr "  }\n";
         pr "  else\n";
         pr "    fprintf (fp, \" (none)\\n\");\n";
         pr "  fprintf (fp, \"\\n\");\n"

      | ConfigSection (n, fields) ->
         let v = sprintf "%s%s." v n in
         generate_field_print (Some printable_name) v fields
  ) fields
