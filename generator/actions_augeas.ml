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

(* Augeas APIs. *)

let daemon_functions = [
  { defaults with
    name = "aug_init"; added = (0, 0, 7);
    style = RErr, [String (Pathname, "root"); Int "flags"], [];
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hostname"; "test.example.org"];
         ["aug_init"; "/"; "0"];
         ["aug_get"; "/files/etc/hostname/hostname"]], "test.example.org"), [["aug_close"]]
    ];
    shortdesc = "create a new Augeas handle";
    longdesc = "\
Create a new Augeas handle for editing configuration files.
If there was any previous Augeas handle associated with this
guestfs session, then it is closed.

You must call this before using any other C<guestfs_aug_*>
commands.

C<root> is the filesystem root.  C<root> must not be NULL,
use F</> instead.

The flags are the same as the flags defined in
E<lt>augeas.hE<gt>, the logical I<or> of the following
integers:

=over 4

=item C<AUG_SAVE_BACKUP> = 1

Keep the original file with a C<.augsave> extension.

=item C<AUG_SAVE_NEWFILE> = 2

Save changes into a file with extension C<.augnew>, and
do not overwrite original.  Overrides C<AUG_SAVE_BACKUP>.

=item C<AUG_TYPE_CHECK> = 4

Typecheck lenses.

This option is only useful when debugging Augeas lenses.  Use
of this option may require additional memory for the libguestfs
appliance.  You may need to set the C<LIBGUESTFS_MEMSIZE>
environment variable or call C<guestfs_set_memsize>.

=item C<AUG_NO_STDINC> = 8

Do not use standard load path for modules.

=item C<AUG_SAVE_NOOP> = 16

Make save a no-op, just record what would have been changed.

=item C<AUG_NO_LOAD> = 32

Do not load the tree in C<guestfs_aug_init>.

=back

To close the handle, you can call C<guestfs_aug_close>.

To find out more about Augeas, see L<http://augeas.net/>." };

  { defaults with
    name = "aug_close"; added = (0, 0, 7);
    style = RErr, [], [];
    shortdesc = "close the current Augeas handle";
    longdesc = "\
Close the current Augeas handle and free up any resources
used by it.  After calling this, you have to call
C<guestfs_aug_init> again before you can use any other
Augeas functions." };

  { defaults with
    name = "aug_defvar"; added = (0, 0, 7);
    style = RInt "nrnodes", [String (PlainString, "name"); OptString "expr"], [];
    shortdesc = "define an Augeas variable";
    longdesc = "\
Defines an Augeas variable C<name> whose value is the result
of evaluating C<expr>.  If C<expr> is NULL, then C<name> is
undefined.

On success this returns the number of nodes in C<expr>, or
C<0> if C<expr> evaluates to something which is not a nodeset." };

  { defaults with
    name = "aug_defnode"; added = (0, 0, 7);
    style = RStruct ("nrnodescreated", "int_bool"), [String (PlainString, "name"); String (PlainString, "expr"); String (PlainString, "val")], [];
    shortdesc = "define an Augeas node";
    longdesc = "\
Defines a variable C<name> whose value is the result of
evaluating C<expr>.

If C<expr> evaluates to an empty nodeset, a node is created,
equivalent to calling C<guestfs_aug_set> C<expr>, C<val>.
C<name> will be the nodeset containing that single node.

On success this returns a pair containing the
number of nodes in the nodeset, and a boolean flag
if a node was created." };

  { defaults with
    name = "aug_get"; added = (0, 0, 7);
    style = RString (RPlainString, "val"), [String (PlainString, "augpath")], [];
    shortdesc = "look up the value of an Augeas path";
    longdesc = "\
Look up the value associated with C<path>.  If C<path>
matches exactly one node, the C<value> is returned." };

  { defaults with
    name = "aug_set"; added = (0, 0, 7);
    style = RErr, [String (PlainString, "augpath"); String (PlainString, "val")], [];
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hostname"; "test.example.org"];
         ["aug_init"; "/"; "0"];
         ["aug_set"; "/files/etc/hostname/hostname"; "replace.example.com"];
         ["aug_get"; "/files/etc/hostname/hostname"]], "replace.example.com"), [["aug_close"]]
    ];
    shortdesc = "set Augeas path to value";
    longdesc = "\
Set the value associated with C<augpath> to C<val>.

In the Augeas API, it is possible to clear a node by setting
the value to NULL.  Due to an oversight in the libguestfs API
you cannot do that with this call.  Instead you must use the
C<guestfs_aug_clear> call." };

  { defaults with
    name = "aug_insert"; added = (0, 0, 7);
    style = RErr, [String (PlainString, "augpath"); String (PlainString, "label"); Bool "before"], [];
    tests = [
      InitBasicFS, Always, TestResultString (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hosts"; ""];
         ["aug_init"; "/"; "0"];
         ["aug_insert"; "/files/etc/hosts"; "1"; "false"];
         ["aug_set"; "/files/etc/hosts/1/ipaddr"; "127.0.0.1"];
         ["aug_set"; "/files/etc/hosts/1/canonical"; "foobar"];
         ["aug_clear"; "/files/etc/hosts/1/canonical"];
         ["aug_set"; "/files/etc/hosts/1/canonical"; "localhost"];
         ["aug_save"];
         ["cat"; "/etc/hosts"]], "\n127.0.0.1\tlocalhost\n"), [["aug_close"]]
    ];
    shortdesc = "insert a sibling Augeas node";
    longdesc = "\
Create a new sibling C<label> for C<path>, inserting it into
the tree before or after C<path> (depending on the boolean
flag C<before>).

C<path> must match exactly one existing node in the tree, and
C<label> must be a label, ie. not contain F</>, C<*> or end
with a bracketed index C<[N]>." };

  { defaults with
    name = "aug_rm"; added = (0, 0, 7);
    style = RInt "nrnodes", [String (PlainString, "augpath")], [];
    shortdesc = "remove an Augeas path";
    longdesc = "\
Remove C<path> and all of its children.

On success this returns the number of entries which were removed." };

  { defaults with
    name = "aug_mv"; added = (0, 0, 7);
    style = RErr, [String (PlainString, "src"); String (PlainString, "dest")], [];
    shortdesc = "move Augeas node";
    longdesc = "\
Move the node C<src> to C<dest>.  C<src> must match exactly
one node.  C<dest> is overwritten if it exists." };

  { defaults with
    name = "aug_match"; added = (0, 0, 7);
    style = RStringList (RPlainString, "matches"), [String (PlainString, "augpath")], [];
    shortdesc = "return Augeas nodes which match augpath";
    longdesc = "\
Returns a list of paths which match the path expression C<path>.
The returned paths are sufficiently qualified so that they match
exactly one node in the current tree." };

  { defaults with
    name = "aug_save"; added = (0, 0, 7);
    style = RErr, [], [];
    shortdesc = "write all pending Augeas changes to disk";
    longdesc = "\
This writes all pending changes to disk.

The flags which were passed to C<guestfs_aug_init> affect exactly
how files are saved." };

  { defaults with
    name = "aug_load"; added = (0, 0, 7);
    style = RErr, [], [];
    shortdesc = "load files into the tree";
    longdesc = "\
Load files into the tree.

See C<aug_load> in the Augeas documentation for the full gory
details." };

  { defaults with
    name = "aug_ls"; added = (0, 0, 8);
    style = RStringList (RPlainString, "matches"), [String (PlainString, "augpath")], [];
    tests = [
      InitBasicFS, Always, TestResult (
        [["mkdir"; "/etc"];
         ["write"; "/etc/hosts"; "127.0.0.1 localhost"];
         ["aug_init"; "/"; "0"];
         ["aug_ls"; "/files/etc/hosts/1"]],
        "is_string_list (ret, 2, \"/files/etc/hosts/1/canonical\", \"/files/etc/hosts/1/ipaddr\")"), [["aug_close"]]
    ];
    shortdesc = "list Augeas nodes under augpath";
    longdesc = "\
This is just a shortcut for listing C<guestfs_aug_match>
C<path/*> and sorting the resulting nodes into alphabetical order." };

  { defaults with
    name = "aug_clear"; added = (1, 3, 4);
    style = RErr, [String (PlainString, "augpath")], [];
    shortdesc = "clear Augeas path";
    longdesc = "\
Set the value associated with C<path> to C<NULL>.  This
is the same as the L<augtool(1)> C<clear> command." };

  { defaults with
    name = "aug_transform"; added = (1, 35, 2);
    style = RErr, [String (PlainString, "lens"); String (PlainString, "file")], [ OBool "remove"];
    shortdesc = "add/remove an Augeas lens transformation";
    longdesc = "\
Add an Augeas transformation for the specified C<lens> so it can
handle C<file>.

If C<remove> is true (C<false> by default), then the transformation
is removed." };

]
