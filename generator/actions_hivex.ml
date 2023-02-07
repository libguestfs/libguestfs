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

(* Hivex APIs. *)

let daemon_functions = [
  { defaults with
    name = "hivex_open"; added = (1, 19, 35);
    style = RErr, [String (Pathname, "filename")], [OBool "verbose"; OBool "debug"; OBool "write"; OBool "unsafe"];
    optional = Some "hivex";
    tests = [
      InitScratchFS, Always, TestRun (
        [["upload"; "$srcdir/../test-data/files/minimal"; "/hivex_open"];
         ["hivex_open"; "/hivex_open"; ""; ""; "false"; ""];
         ["hivex_root"]; (* in this hive, it returns 0x1020 *)
         ["hivex_node_name"; "0x1020"];
         ["hivex_node_children"; "0x1020"];
         ["hivex_node_values"; "0x1020"]]), [["hivex_close"]]
    ];
    shortdesc = "open a Windows Registry hive file";
    longdesc = "\
Open the Windows Registry hive file named F<filename>.
If there was any previous hivex handle associated with this
guestfs session, then it is closed.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_close"; added = (1, 19, 35);
    style = RErr, [], [];
    optional = Some "hivex";
    shortdesc = "close the current hivex handle";
    longdesc = "\
Close the current hivex handle.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_root"; added = (1, 19, 35);
    style = RInt64 "nodeh", [], [];
    optional = Some "hivex";
    shortdesc = "return the root node of the hive";
    longdesc = "\
Return the root node of the hive.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_name"; added = (1, 19, 35);
    style = RString (RPlainString, "name"), [Int64 "nodeh"], [];
    optional = Some "hivex";
    shortdesc = "return the name of the node";
    longdesc = "\
Return the name of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_children"; added = (1, 19, 35);
    style = RStructList ("nodehs", "hivex_node"), [Int64 "nodeh"], [];
    optional = Some "hivex";
    shortdesc = "return list of nodes which are subkeys of node";
    longdesc = "\
Return the list of nodes which are subkeys of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_get_child"; added = (1, 19, 35);
    style = RInt64 "child", [Int64 "nodeh"; String (PlainString, "name")], [];
    optional = Some "hivex";
    shortdesc = "return the named child of node";
    longdesc = "\
Return the child of C<nodeh> with the name C<name>, if it exists.
This can return C<0> meaning the name was not found.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_parent"; added = (1, 19, 35);
    style = RInt64 "parent", [Int64 "nodeh"], [];
    optional = Some "hivex";
    shortdesc = "return the parent of node";
    longdesc = "\
Return the parent node of C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_values"; added = (1, 19, 35);
    style = RStructList ("valuehs", "hivex_value"), [Int64 "nodeh"], [];
    optional = Some "hivex";
    shortdesc = "return list of values attached to node";
    longdesc = "\
Return the array of (key, datatype, data) tuples attached to C<nodeh>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_get_value"; added = (1, 19, 35);
    style = RInt64 "valueh", [Int64 "nodeh"; String (PlainString, "key")], [];
    optional = Some "hivex";
    shortdesc = "return the named value";
    longdesc = "\
Return the value attached to C<nodeh> which has the
name C<key>, if it exists.  This can return C<0> meaning
the key was not found.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_key"; added = (1, 19, 35);
    style = RString (RPlainString, "key"), [Int64 "valueh"], [];
    optional = Some "hivex";
    shortdesc = "return the key field from the (key, datatype, data) tuple";
    longdesc = "\
Return the key (name) field of a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_type"; added = (1, 19, 35);
    style = RInt64 "datatype", [Int64 "valueh"], [];
    optional = Some "hivex";
    shortdesc = "return the data type from the (key, datatype, data) tuple";
    longdesc = "\
Return the data type field from a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_value_value"; added = (1, 19, 35);
    style = RBufferOut "databuf", [Int64 "valueh"], [];
    optional = Some "hivex";
    shortdesc = "return the data field from the (key, datatype, data) tuple";
    longdesc = "\
Return the data field of a (key, datatype, data) tuple.

This is a wrapper around the L<hivex(3)> call of the same name.

See also: C<guestfs_hivex_value_utf8>." };

  { defaults with
    name = "hivex_value_string"; added = (1, 37, 22);
    style = RString (RPlainString, "databuf"), [Int64 "valueh"], [];
    optional = Some "hivex";
    shortdesc = "return the data field as a UTF-8 string";
    longdesc = "\
This calls C<guestfs_hivex_value_value> (which returns the
data field from a hivex value tuple).  It then assumes that
the field is a UTF-16LE string and converts the result to
UTF-8 (or if this is not possible, it returns an error).

This is useful for reading strings out of the Windows registry.
However it is not foolproof because the registry is not
strongly-typed and fields can contain arbitrary or unexpected
data." };

  { defaults with
    name = "hivex_commit"; added = (1, 19, 35);
    style = RErr, [OptString "filename"], [];
    optional = Some "hivex";
    tests = [
      InitScratchFS, Always, TestRun (
        [["upload"; "$srcdir/../test-data/files/minimal"; "/hivex_commit1"];
         ["hivex_open"; "/hivex_commit1"; ""; ""; "true"; ""];
         ["hivex_commit"; "NULL"]]), [["hivex_close"]];
      InitScratchFS, Always, TestResultTrue (
        [["upload"; "$srcdir/../test-data/files/minimal"; "/hivex_commit2"];
         ["hivex_open"; "/hivex_commit2"; ""; ""; "true"; ""];
         ["hivex_commit"; "/hivex_commit2_copy"];
         ["is_file"; "/hivex_commit2_copy"; "false"]]), [["hivex_close"]]
    ];
    shortdesc = "commit (write) changes back to the hive";
    longdesc = "\
Commit (write) changes to the hive.

If the optional F<filename> parameter is null, then the changes
are written back to the same hive that was opened.  If this is
not null then they are written to the alternate filename given
and the original hive is left untouched.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_add_child"; added = (1, 19, 35);
    style = RInt64 "nodeh", [Int64 "parent"; String (PlainString, "name")], [];
    optional = Some "hivex";
    shortdesc = "add a child node";
    longdesc = "\
Add a child node to C<parent> named C<name>.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_delete_child"; added = (1, 19, 35);
    style = RErr, [Int64 "nodeh"], [];
    optional = Some "hivex";
    shortdesc = "delete a node (recursively)";
    longdesc = "\
Delete C<nodeh>, recursively if necessary.

This is a wrapper around the L<hivex(3)> call of the same name." };

  { defaults with
    name = "hivex_node_set_value"; added = (1, 19, 35);
    style = RErr, [Int64 "nodeh"; String (PlainString, "key"); Int64 "t"; BufferIn "val"], [];
    optional = Some "hivex";
    shortdesc = "set or replace a single value in a node";
    longdesc = "\
Set or replace a single value under the node C<nodeh>.  The
C<key> is the name, C<t> is the type, and C<val> is the data.

This is a wrapper around the L<hivex(3)> call of the same name." };

]
