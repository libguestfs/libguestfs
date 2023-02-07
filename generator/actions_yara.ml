(* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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

open Types

(* Yara APIs. *)

let non_daemon_functions = [
  { defaults with
    name = "yara_scan"; added = (1, 37, 13);
    style = RStructList ("detections", "yara_detection"), [String (Pathname, "path")], [];
    optional = Some "libyara";
    progress = true; cancellable = true;
    shortdesc = "scan a file with the loaded yara rules";
    longdesc = "\
Scan a file with the previously loaded Yara rules.

For each matching rule, a C<yara_detection> structure is returned.

The C<yara_detection> structure contains the following fields.

=over 4

=item C<yara_name>

Path of the file matching a Yara rule.

=item C<yara_rule>

Identifier of the Yara rule which matched against the given file.

=back" };

]

let daemon_functions = [
  { defaults with
      name = "yara_load"; added = (1, 37, 13);
      style = RErr, [String (FileIn, "filename")], [];
      progress = true; cancellable = true;
      optional = Some "libyara";
      shortdesc = "load yara rules within libguestfs";
      longdesc = "\
Upload a set of Yara rules from local file F<filename>.

Yara rules allow to categorize files based on textual or binary patterns
within their content.
See C<guestfs_yara_scan> to see how to scan files with the loaded rules.

Rules can be in binary format, as when compiled with yarac command, or
in source code format. In the latter case, the rules will be first
compiled and then loaded.

Rules in source code format cannot include external files. In such cases,
it is recommended to compile them first.

Previously loaded rules will be destroyed." };

  { defaults with
    name = "yara_destroy"; added = (1, 37, 13);
    style = RErr, [], [];
    optional = Some "libyara";
    shortdesc = "destroy previously loaded yara rules";
    longdesc = "\
Destroy previously loaded Yara rules in order to free libguestfs resources." };

  { defaults with
    name = "internal_yara_scan"; added = (1, 37, 13);
    style = RErr, [String (Pathname, "path"); String (FileOut, "filename")], [];
    visibility = VInternal;
    optional = Some "libyara";
    shortdesc = "scan a file with the loaded yara rules";
    longdesc = "Internal function for yara_scan." };

]
