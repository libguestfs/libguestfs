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

type enum_choice = string * string * string (* name, cmdline, comment *)
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

type manual_entry = {
  shortopt : string;
  description : string;
}

(* Enums. *)
let enums = [
  "basis", [
    "BASIS_UNKNOWN",   "unknown",   "RTC could not be read";
    "BASIS_UTC",       "utc",       "RTC is either UTC or an offset from UTC";
    "BASIS_LOCALTIME", "localtime", "RTC is localtime";
  ];
  "output_allocation", [
    "OUTPUT_ALLOCATION_NONE",         "none", "output allocation not set";
    "OUTPUT_ALLOCATION_SPARSE",       "sparse",       "sparse";
    "OUTPUT_ALLOCATION_PREALLOCATED", "preallocated", "preallocated";
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

(* Some /proc/cmdline p2v.* options were renamed when we introduced
 * the generator.  This map creates backwards compatibility mappings
 * for these.
 *)
let cmdline_aliases = [
  "p2v.remote.server",     ["p2v.server"];
  "p2v.remote.port",       ["p2v.port"];
  "p2v.auth.username",     ["p2v.username"];
  "p2v.auth.password",     ["p2v.password"];
  "p2v.auth.identity.url", ["p2v.identity"];
  "p2v.auth.sudo",         ["p2v.sudo"];
  "p2v.guestname",         ["p2v.name"];
  "p2v.network_map",       ["p2v.network"];
  "p2v.output.type",       ["p2v.o"];
  "p2v.output.allocation", ["p2v.oa"];
  "p2v.output.connection", ["p2v.oc"];
  "p2v.output.format",     ["p2v.of"];
  "p2v.output.storage",    ["p2v.os"];
]

(* Some config entries are not exposed on the kernel command line. *)
let cmdline_ignore = [
  "p2v.auth.identity.file";
  "p2v.auth.identity.file_needs_update";
]

(* Man page snippets for each kernel command line setting. *)
let cmdline_manual = [
  "p2v.remote.server", {
    shortopt = "SERVER";
    description = "
The name or IP address of the conversion server.

This is always required if you are using the kernel configuration
method.  If virt-p2v does not find this on the kernel command line
then it switches to the GUI (interactive) configuration method.";
  };
  "p2v.remote.port", {
    shortopt = "PORT";
    description = "
The SSH port number on the conversion server (default: C<22>).";
  };
  "p2v.auth.username", {
    shortopt = "USERNAME";
    description = "
The SSH username that we log in as on the conversion server
(default: C<root>).";
  };
  "p2v.auth.password", {
    shortopt = "PASSWORD";
    description = "
The SSH password that we use to log in to the conversion server.

The default is to try with no password.  If this fails then virt-p2v
will ask the user to type the password (probably several times during
conversion).

This setting is ignored if C<p2v.auth.identity.url> is present.";
  };
  "p2v.auth.identity.url", {
    shortopt = "URL";
    description = "
Provide a URL pointing to an SSH identity (private key) file.  The URL
is interpreted by L<curl(1)> so any URL that curl supports can be used
here, including C<https://> and C<file://>.  For more information on
using SSH identities, see L</SSH IDENTITIES> below.

If C<p2v.auth.identity.url> is present, it overrides C<p2v.auth.password>.
There is no fallback.";
  };
  "p2v.auth.sudo", {
    shortopt = ""; (* ignored for booleans *)
    description = "
Use C<p2v.sudo> to tell virt-p2v to use L<sudo(8)> to gain root
privileges on the conversion server after logging in as a non-root
user (default: do not use sudo).";
  };
  "p2v.guestname", {
    shortopt = "GUESTNAME";
    description = "
The name of the guest that is created.  The default is to try to
derive a name from the physical machine’s hostname (if possible) else
use a randomly generated name.";
  };
  "p2v.vcpus", {
    shortopt = "N";
    description = "
The number of virtual CPUs to give to the guest.  The default is to
use the same as the number of physical CPUs.";
  };
  "p2v.memory", {
    shortopt = "n(M|G)";
    description = "
The size of the guest memory.  You must specify the unit such as
megabytes or gigabytes by using for example C<p2v.memory=1024M> or
C<p2v.memory=1G>.

The default is to use the same amount of RAM as on the physical
machine.";
  };
  "p2v.cpu.vendor", {
    shortopt = "VENDOR";
    description = "
The vCPU vendor, eg. \"Intel\" or \"AMD\".  The default is to use
the same CPU vendor as the physical machine.";
  };
  "p2v.cpu.model", {
    shortopt = "MODEL";
    description = "
The vCPU model, eg. \"IvyBridge\".  The default is to use the same
CPU model as the physical machine.";
  };
  "p2v.cpu.sockets", {
    shortopt = "N";
    description = "
Number of vCPU sockets to use.  The default is to use the same as the
physical machine.";
  };
  "p2v.cpu.cores", {
    shortopt = "N";
    description = "
Number of vCPU cores to use.  The default is to use the same as the
physical machine.";
  };
  "p2v.cpu.threads", {
    shortopt = "N";
    description = "
Number of vCPU hyperthreads to use.  The default is to use the same
as the physical machine.";
  };
  "p2v.cpu.acpi", {
    shortopt = ""; (* ignored for booleans *)
    description = "
Whether to enable ACPI in the remote virtual machine.  The default is
to use the same as the physical machine.";
  };
  "p2v.cpu.apic", {
    shortopt = ""; (* ignored for booleans *)
    description = "
Whether to enable APIC in the remote virtual machine.  The default is
to use the same as the physical machine.";
  };
  "p2v.cpu.pae", {
    shortopt = ""; (* ignored for booleans *)
    description = "
Whether to enable PAE in the remote virtual machine.  The default is
to use the same as the physical machine.";
  };
  "p2v.rtc.basis", {
    shortopt = ""; (* ignored for enums. *)
    description = "
Set the basis of the Real Time Clock in the virtual machine.  The
default is to try to detect this setting from the physical machine.";
  };
  "p2v.rtc.offset", {
    shortopt = "[+|-]HOURS";
    description = "
The offset of the Real Time Clock from UTC.  The default is to try
to detect this setting from the physical machine.";
  };
  "p2v.disks", {
    shortopt = "sda,sdb,...";
    description = "
A list of physical hard disks to convert, for example:

 p2v.disks=sda,sdc

The default is to convert all local hard disks that are found.";
  };
  "p2v.removable", {
    shortopt = "sra,srb,...";
    description = "
A list of removable media to convert.  The default is to create
virtual removable devices for every physical removable device found.
Note that the content of removable media is never copied over.";
  };
  "p2v.interfaces", {
    shortopt = "em1,...";
    description = "
A list of network interfaces to convert.  The default is to create
virtual network interfaces for every physical network interface found.";
  };
  "p2v.network_map", {
    shortopt = "interface:target,...";
    description = "
Controls how network interfaces are connected to virtual networks on
the target hypervisor.  The default is to connect all network
interfaces to the target C<default> network.

You give a comma-separated list of C<interface:target> pairs, plus
optionally a default target.  For example:

 p2v.network=em1:ovirtmgmt

maps interface C<em1> to target network C<ovirtmgmt>.

 p2v.network=em1:ovirtmgmt,em2:management,other

maps interface C<em1> to C<ovirtmgmt>, and C<em2> to C<management>,
and any other interface that is found to C<other>.";
  };
  "p2v.output.type", {
    shortopt = "(libvirt|local|...)";
    description = "
Set the output mode.  This is the same as the virt-v2v I<-o> option.
See L<virt-v2v(1)/OPTIONS>.

If not specified, the default is C<local>, and the converted guest is
written to F</var/tmp>.";
  };
  "p2v.output.allocation", {
    shortopt = ""; (* ignored for enums *)
    description = "
Set the output allocation mode.  This is the same as the virt-v2v
I<-oa> option.  See L<virt-v2v(1)/OPTIONS>.";
  };
  "p2v.output.connection", {
    shortopt = "URI";
    description = "
Set the output connection libvirt URI.  This is the same as the
virt-v2v I<-oc> option.  See L<virt-v2v(1)/OPTIONS> and
L<http://libvirt.org/uri.html>";
  };
  "p2v.output.format", {
    shortopt = "(raw|qcow2|...)";
    description = "
Set the output format.  This is the same as the virt-v2v I<-of>
option.  See L<virt-v2v(1)/OPTIONS>.";
  };
  "p2v.output.storage", {
    shortopt = "STORAGE";
    description = "
Set the output storage.  This is the same as the virt-v2v I<-os>
option.  See L<virt-v2v(1)/OPTIONS>.

If not specified, the default is F</var/tmp> (on the conversion server).";
  };
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
        fun (n, _, comment) ->
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
        fun (n, cmdline, _) ->
          pr "  case %s:\n" n;
          pr "    fprintf (fp, \"%s\");\n" cmdline;
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

let rec generate_p2v_kernel_config_c () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include \"xstrtol.h\"

#include \"p2v.h\"
#include \"p2v-config.h\"

/**
 * Read the kernel command line and parse out any C<p2v.*> fields that
 * we understand into the config struct.
 */
void
update_config_from_kernel_cmdline (struct config *c, char **cmdline)
{
  const char *p;
  strtol_error xerr;
  unsigned long long ull;

";

  generate_field_config "p2v" "c->" fields;

  pr "  if (c->auth.identity.url != NULL)
    c->auth.identity.file_needs_update = 1;

  /* Undocumented command line parameter used for testing command line
   * parsing.
   */
  p = get_cmdline_key (cmdline, \"p2v.dump_config_and_exit\");
  if (p) {
    print_config (c, stdout);
    exit (EXIT_SUCCESS);
  }
}
"

and generate_field_config prefix v fields =
  List.iter (
    function
    | ConfigSection (n, fields) ->
       let prefix = sprintf "%s.%s" prefix n in
       let v = sprintf "%s%s." v n in
       generate_field_config prefix v fields

    | field ->
      let n = name_of_config_entry field in
      let key = sprintf "%s.%s" prefix n in

      if not (List.mem key cmdline_ignore) then (
        (* Is there an alias for this field? *)
        let aliases =
          try List.assoc key cmdline_aliases
          with Not_found -> [] in

        pr "  if ((p = get_cmdline_key (cmdline, \"%s\")) != NULL" key;
        List.iter (
          fun alias ->
            pr " ||\n";
            pr "      (p = get_cmdline_key (cmdline, \"%s\")) != NULL" alias;
        ) aliases;
        pr ") {\n";

        (* Parse the field. *)
        (match field with
         | ConfigString n ->
            pr "    free (%s%s);\n" v n;
            pr "    %s%s = strdup (p);\n" v n;
            pr "    if (%s%s == NULL)\n" v n;
            pr "      error (EXIT_FAILURE, errno, \"strdup\");\n"
         | ConfigStringList n ->
            pr "    guestfs_int_free_string_list (%s%s);\n" v n;
            pr "    %s%s = guestfs_int_split_string (',', p);\n" v n;
            pr "    if (%s%s == NULL)\n" v n;
            pr "      error (EXIT_FAILURE, errno, \"strdup\");\n"
         | ConfigInt (n, _) ->
            pr "    if (sscanf (p, \"%%d\", &%s%s) != 1)\n" v n;
            pr "      error (EXIT_FAILURE, errno,\n";
            pr "             \"cannot parse %%s=%%s from the kernel command line\",\n";
            pr "             %S, p);\n" key
         | ConfigUnsigned n ->
            pr "    if (sscanf (p, \"%%u\", &%s%s) != 1)\n" v n;
            pr "      error (EXIT_FAILURE, errno,\n";
            pr "             \"cannot parse %%s=%%s from the kernel command line\",\n";
            pr "             %S, p);\n" key
         | ConfigUInt64 n ->
            pr "    xerr = xstrtoull (p, NULL, 0, &ull, \"0kKMGTPEZY\");\n";
            pr "    if (xerr != LONGINT_OK)\n";
            pr "      error (EXIT_FAILURE, 0,\n";
            pr "             \"cannot parse %%s=%%s from the kernel command line\",\n";
            pr "             %S, p);\n" key;
            pr "    %s%s = ull;\n" v n
         | ConfigEnum (n, enum) ->
            let enum_choices =
              try List.assoc enum enums
              with Not_found -> failwithf "cannot find ConfigEnum %s" enum in
            pr "    ";
            List.iter (
              fun (name, cmdline, _) ->
                pr "if (STREQ (p, \"%s\"))\n" cmdline;
                pr "      %s%s = %s;\n" v n name;
                pr "    else ";
            ) enum_choices;
            pr "{\n";
            pr "      error (EXIT_FAILURE, 0,\n";
            pr "             \"invalid value %%s=%%s from the kernel command line\",\n";
            pr "             %S, p);\n" key;
            pr "    }\n"
         | ConfigBool n ->
            pr "    %s%s = guestfs_int_is_true (p) || STREQ (p, \"\");\n" v n

         | ConfigSection _ -> assert false (* see above *)
        );

        pr "  }\n";
        pr "\n";
      )
  ) fields

let rec generate_p2v_kernel_config_pod () =
  generate_field_config_pod "p2v" fields

and generate_field_config_pod prefix fields =
  List.iter (
    function
    | ConfigSection (n, fields) ->
       let prefix = sprintf "%s.%s" prefix n in
       generate_field_config_pod prefix fields

    | field ->
      let n = name_of_config_entry field in
      let key = sprintf "%s.%s" prefix n in

      if not (List.mem key cmdline_ignore) then (
        let manual_entry =
          try List.assoc key cmdline_manual
          with Not_found ->
            failwithf "generator/p2v_config.ml: missing manual entry for %s"
                      key in

        (* For booleans there is no shortopt field.  For enums
         * we generate it.
         *)
        let shortopt =
          match field with
          | ConfigBool _ ->
             assert (manual_entry.shortopt = "");
             ""
          | ConfigEnum (_, enum) ->
             assert (manual_entry.shortopt = "");

             let enum_choices =
              try List.assoc enum enums
              with Not_found -> failwithf "cannot find ConfigEnum %s" enum in
             "=(" ^
               String.concat "|"
                             (List.map (fun (_, cmdline, _) -> cmdline)
                                       enum_choices) ^
             ")"
          | ConfigString _
          | ConfigInt _
          | ConfigUnsigned _
          | ConfigUInt64 _
          | ConfigStringList _
          | ConfigSection _ -> "=" ^ manual_entry.shortopt in

        (* The description must not end with \n *)
        if String.is_suffix manual_entry.description "\n" then
          failwithf "generator/p2v_config.ml: description of %s must not end with \\n"
                    key;

        (* Is there an alias for this field? *)
        let aliases =
          try List.assoc key cmdline_aliases
          with Not_found -> [] in
        List.iter (
          fun k -> pr "=item B<%s%s>\n\n" k shortopt
        ) (key :: aliases);

        pr "%s\n\n" manual_entry.description
      )
  ) fields
