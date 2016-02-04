(* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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

open Docstrings
open Pr

let generate_header = generate_header ~inputs:["generator/customize.ml"]

(* Command-line arguments used by virt-customize, virt-builder and
 * virt-sysprep.
 *)

type op = {
  op_name : string;          (* argument name, without "--" *)
  op_type : op_type;         (* argument value type *)
  op_discrim : string;       (* argument discriminator in OCaml code *)
  op_shortdesc : string;     (* single-line description *)
  op_pod_longdesc : string;  (* multi-line description *)
}
and op_type =
| Unit                                  (* no argument *)
| String of string                      (* string *)
| StringPair of string                  (* string:string *)
| StringList of string                  (* string,string,... *)
| TargetLinks of string                 (* target:link[:link...] *)
| PasswordSelector of string            (* password selector *)
| UserPasswordSelector of string        (* user:selector *)
| SSHKeySelector of string              (* user:selector *)
| StringFn of (string * string)         (* string, function name *)
| SMPoolSelector of string              (* pool selector *)

let ops = [
  { op_name = "chmod";
    op_type = StringPair "PERMISSIONS:FILE";
    op_discrim = "`Chmod";
    op_shortdesc = "Change the permissions of a file";
    op_pod_longdesc = "\
Change the permissions of C<FILE> to C<PERMISSIONS>.

I<Note>: C<PERMISSIONS> by default would be decimal, unless you prefix
it with C<0> to get octal, ie. use C<0700> not C<700>.";
  };

  { op_name = "commands-from-file";
    op_type = StringFn ("FILENAME", "customize_read_from_file");
    op_discrim = "`CommandsFromFile";
    op_shortdesc = "Read customize commands from file";
    op_pod_longdesc = "\
Read the customize commands from a file, one (and its arguments)
each line.

Each line contains a single customization command and its arguments,
for example:

 delete /some/file
 install some-package
 password some-user:password:its-new-password

Empty lines are ignored, and lines starting with C<#> are comments
and are ignored as well.  Furthermore, arguments can be spread across
multiple lines, by adding a C<\\> (continuation character) at the of
a line, for example

 edit /some/file:\\
   s/^OPT=.*/OPT=ok/

The commands are handled in the same order as they are in the file,
as if they were specified as I<--delete /some/file> on the command
line.";
  };

  { op_name = "copy";
    op_type = StringPair "SOURCE:DEST";
    op_discrim = "`Copy";
    op_shortdesc = "Copy files in disk image";
    op_pod_longdesc = "\
Copy files or directories recursively inside the guest.

Wildcards cannot be used.";
  };

  { op_name = "copy-in";
    op_type = StringPair "LOCALPATH:REMOTEDIR";
    op_discrim = "`CopyIn";
    op_shortdesc = "Copy local files or directories into image";
    op_pod_longdesc = "\
Copy local files or directories recursively into the disk image,
placing them in the directory C<REMOTEDIR> (which must exist).

Wildcards cannot be used.";
  };

  { op_name = "delete";
    op_type = String "PATH";
    op_discrim = "`Delete";
    op_shortdesc = "Delete a file or directory";
    op_pod_longdesc = "\
Delete a file from the guest.  Or delete a directory (and all its
contents, recursively).

You can use shell glob characters in the specified path.  Be careful
to escape glob characters from the host shell, if that is required.
For example:

 virt-customize --delete '/var/log/*.log'.

See also: I<--upload>, I<--scrub>.";
  };

  { op_name = "edit";
    op_type = StringPair "FILE:EXPR";
    op_discrim = "`Edit";
    op_shortdesc = "Edit file using Perl expression";
    op_pod_longdesc = "\
Edit C<FILE> using the Perl expression C<EXPR>.

Be careful to properly quote the expression to prevent it from
being altered by the shell.

Note that this option is only available when Perl 5 is installed.

See L<virt-edit(1)/NON-INTERACTIVE EDITING>.";
  };

  { op_name = "firstboot";
    op_type = String "SCRIPT";
    op_discrim = "`FirstbootScript";
    op_shortdesc = "Run script at first guest boot";
    op_pod_longdesc = "\
Install C<SCRIPT> inside the guest, so that when the guest first boots
up, the script runs (as root, late in the boot process).

The script is automatically chmod +x after installation in the guest.

The alternative version I<--firstboot-command> is the same, but it
conveniently wraps the command up in a single line script for you.

You can have multiple I<--firstboot> options.  They run in the same
order that they appear on the command line.

Please take a look at L<virt-builder(1)/FIRST BOOT SCRIPTS> for more
information and caveats about the first boot scripts.

See also I<--run>.";
  };

  { op_name = "firstboot-command";
    op_type = String "'CMD+ARGS'";
    op_discrim = "`FirstbootCommand";
    op_shortdesc = "Run command at first guest boot";
    op_pod_longdesc = "\
Run command (and arguments) inside the guest when the guest first
boots up (as root, late in the boot process).

You can have multiple I<--firstboot> options.  They run in the same
order that they appear on the command line.

Please take a look at L<virt-builder(1)/FIRST BOOT SCRIPTS> for more
information and caveats about the first boot scripts.

See also I<--run>.";
  };

  { op_name = "firstboot-install";
    op_type = StringList "PKG,PKG..";
    op_discrim = "`FirstbootPackages";
    op_shortdesc = "Add package(s) to install at first boot";
    op_pod_longdesc = "\
Install the named packages (a comma-separated list).  These are
installed when the guest first boots using the guest's package manager
(eg. apt, yum, etc.) and the guest's network connection.

For an overview on the different ways to install packages, see
L<virt-builder(1)/INSTALLING PACKAGES>.";
  };

  { op_name = "hostname";
    op_type = String "HOSTNAME";
    op_discrim = "`Hostname";
    op_shortdesc = "Set the hostname";
    op_pod_longdesc = "\
Set the hostname of the guest to C<HOSTNAME>.  You can use a
dotted hostname.domainname (FQDN) if you want.";
  };

  { op_name = "install";
    op_type = StringList "PKG,PKG..";
    op_discrim = "`InstallPackages";
    op_shortdesc = "Add package(s) to install";
    op_pod_longdesc = "\
Install the named packages (a comma-separated list).  These are
installed during the image build using the guest's package manager
(eg. apt, yum, etc.) and the host's network connection.

For an overview on the different ways to install packages, see
L<virt-builder(1)/INSTALLING PACKAGES>.

See also I<--update>.";
  };

  { op_name = "link";
    op_type = TargetLinks "TARGET:LINK[:LINK..]";
    op_discrim = "`Link";
    op_shortdesc = "Create symbolic links";
    op_pod_longdesc = "\
Create symbolic link(s) in the guest, starting at C<LINK> and
pointing at C<TARGET>.";
  };

  { op_name = "mkdir";
    op_type = String "DIR";
    op_discrim = "`Mkdir";
    op_shortdesc = "Create a directory";
    op_pod_longdesc = "\
Create a directory in the guest.

This uses S<C<mkdir -p>> so any intermediate directories are created,
and it also works if the directory already exists.";
  };

  { op_name = "move";
    op_type = StringPair "SOURCE:DEST";
    op_discrim = "`Move";
    op_shortdesc = "Move files in disk image";
    op_pod_longdesc = "\
Move files or directories inside the guest.

Wildcards cannot be used.";
  };

  { op_name = "password";
    op_type = UserPasswordSelector "USER:SELECTOR";
    op_discrim = "`Password";
    op_shortdesc = "Set user password";
    op_pod_longdesc = "\
Set the password for C<USER>.  (Note this option does I<not>
create the user account).

See L<virt-builder(1)/USERS AND PASSWORDS> for the format of
the C<SELECTOR> field, and also how to set up user accounts.";
  };

  { op_name = "root-password";
    op_type = PasswordSelector "SELECTOR";
    op_discrim = "`RootPassword";
    op_shortdesc = "Set root password";
    op_pod_longdesc = "\
Set the root password.

See L<virt-builder(1)/USERS AND PASSWORDS> for the format of
the C<SELECTOR> field, and also how to set up user accounts.

Note: In virt-builder, if you I<don't> set I<--root-password>
then the guest is given a I<random> root password.";
  };

  { op_name = "run";
    op_type = String "SCRIPT";
    op_discrim = "`Script";
    op_shortdesc = "Run script in disk image";
    op_pod_longdesc = "\
Run the shell script (or any program) called C<SCRIPT> on the disk
image.  The script runs virtualized inside a small appliance, chrooted
into the guest filesystem.

The script is automatically chmod +x.

If libguestfs supports it then a limited network connection is
available but it only allows outgoing network connections.  You can
also attach data disks (eg. ISO files) as another way to provide data
(eg. software packages) to the script without needing a network
connection (I<--attach>).  You can also upload data files (I<--upload>).

You can have multiple I<--run> options.  They run
in the same order that they appear on the command line.

See also: I<--firstboot>, I<--attach>, I<--upload>.";
  };

  { op_name = "run-command";
    op_type = String "'CMD+ARGS'";
    op_discrim = "`Command";
    op_shortdesc = "Run command in disk image";
    op_pod_longdesc = "\
Run the command and arguments on the disk image.  The command runs
virtualized inside a small appliance, chrooted into the guest filesystem.

If libguestfs supports it then a limited network connection is
available but it only allows outgoing network connections.  You can
also attach data disks (eg. ISO files) as another way to provide data
(eg. software packages) to the script without needing a network
connection (I<--attach>).  You can also upload data files (I<--upload>).

You can have multiple I<--run-command> options.  They run
in the same order that they appear on the command line.

See also: I<--firstboot>, I<--attach>, I<--upload>.";
  };

  { op_name = "scrub";
    op_type = String "FILE";
    op_discrim = "`Scrub";
    op_shortdesc = "Scrub a file";
    op_pod_longdesc = "\
Scrub a file from the guest.  This is like I<--delete> except that:

=over 4

=item *

It scrubs the data so a guest could not recover it.

=item *

It cannot delete directories, only regular files.

=back";
  };

  { op_name = "sm-attach";
    op_type = SMPoolSelector "SELECTOR";
    op_discrim = "`SMAttach";
    op_shortdesc = "Attach to a subscription-manager pool";
    op_pod_longdesc = "\
Attach to a pool using C<subscription-manager>.

See L<virt-builder(1)/SUBSCRIPTION-MANAGER> for the format of
the C<SELECTOR> field.";
  };

  { op_name = "sm-register";
    op_type = Unit;
    op_discrim = "`SMRegister";
    op_shortdesc = "Register using subscription-manager";
    op_pod_longdesc = "\
Register the guest using C<subscription-manager>.

This requires credentials being set using I<--sm-credentials>.";
  };

  { op_name = "sm-remove";
    op_type = Unit;
    op_discrim = "`SMRemove";
    op_shortdesc = "Remove all the subscriptions";
    op_pod_longdesc = "\
Remove all the subscriptions from the guest using
C<subscription-manager>.";
  };

  { op_name = "sm-unregister";
    op_type = Unit;
    op_discrim = "`SMUnregister";
    op_shortdesc = "Unregister using subscription-manager";
    op_pod_longdesc = "\
Unregister the guest using C<subscription-manager>.";
  };

  { op_name = "ssh-inject";
    op_type = SSHKeySelector "USER[:SELECTOR]";
    op_discrim = "`SSHInject";
    op_shortdesc = "Inject a public key into the guest";
    op_pod_longdesc = "\
Inject an ssh key so the given C<USER> will be able to log in over
ssh without supplying a password.  The C<USER> must exist already
in the guest.

See L<virt-builder(1)/SSH KEYS> for the format of
the C<SELECTOR> field.

You can have multiple I<--ssh-inject> options, for different users
and also for more keys for each user."
  };

  { op_name = "truncate";
    op_type = String "FILE";
    op_discrim = "`Truncate";
    op_shortdesc = "Truncate a file to zero size";
    op_pod_longdesc = "\
This command truncates C<FILE> to a zero-length file. The file must exist
already.";
  };

  { op_name = "truncate-recursive";
    op_type = String "PATH";
    op_discrim = "`TruncateRecursive";
    op_shortdesc = "Recursively truncate all files in directory";
    op_pod_longdesc = "\
This command recursively truncates all files under C<PATH> to zero-length.";
  };

  { op_name = "timezone";
    op_type = String "TIMEZONE";
    op_discrim = "`Timezone";
    op_shortdesc = "Set the default timezone";
    op_pod_longdesc = "\
Set the default timezone of the guest to C<TIMEZONE>.  Use a location
string like C<Europe/London>";
  };

  { op_name = "touch";
    op_type = String "FILE";
    op_discrim = "`Touch";
    op_shortdesc = "Run touch on a file";
    op_pod_longdesc = "\
This command performs a L<touch(1)>-like operation on C<FILE>.";
  };

  { op_name = "update";
    op_type = Unit;
    op_discrim = "`Update";
    op_shortdesc = "Update packages";
    op_pod_longdesc = "\
Do the equivalent of C<yum update>, C<apt-get upgrade>, or whatever
command is required to update the packages already installed in the
template to their latest versions.

See also I<--install>.";
  };

  { op_name = "upload";
    op_type = StringPair "FILE:DEST";
    op_discrim = "`Upload";
    op_shortdesc = "Upload local file to destination";
    op_pod_longdesc = "\
Upload local file C<FILE> to destination C<DEST> in the disk image.
File owner and permissions from the original are preserved, so you
should set them to what you want them to be in the disk image.

C<DEST> could be the final filename.  This can be used to rename
the file on upload.

If C<DEST> is a directory name (which must already exist in the guest)
then the file is uploaded into that directory, and it keeps the same
name as on the local filesystem.

See also: I<--mkdir>, I<--delete>, I<--scrub>.";
  };

  { op_name = "write";
    op_type = StringPair "FILE:CONTENT";
    op_discrim = "`Write";
    op_shortdesc = "Write file";
    op_pod_longdesc = "\
Write C<CONTENT> to C<FILE>.";
  };
]

(* Flags. *)
type flag = {
  flag_name : string;                (* argument name, without "--" *)
  flag_type : flag_type;             (* argument value type *)
  flag_ml_var : string;              (* variable name in OCaml code *)
  flag_shortdesc : string;           (* single-line description *)
  flag_pod_longdesc : string;        (* multi-line description *)
}
and flag_type =
| FlagBool of bool                  (* boolean is the default value *)
| FlagPasswordCrypto of string
| FlagSMCredentials of string

let flags = [
  { flag_name = "no-logfile";
    flag_type = FlagBool false;
    flag_ml_var = "scrub_logfile";
    flag_shortdesc = "Scrub build log file";
    flag_pod_longdesc = "\
Scrub C<builder.log> (log file from build commands) from the image
after building is complete.  If you don't want to reveal precisely how
the image was built, use this option.

See also: L</LOG FILE>.";
  };

  { flag_name = "password-crypto";
    flag_type = FlagPasswordCrypto "md5|sha256|sha512";
    flag_ml_var = "password_crypto";
    flag_shortdesc = "Set password crypto";
    flag_pod_longdesc = "\
When the virt tools change or set a password in the guest, this
option sets the password encryption of that password to
C<md5>, C<sha256> or C<sha512>.

C<sha256> and C<sha512> require glibc E<ge> 2.7 (check crypt(3) inside
the guest).

C<md5> will work with relatively old Linux guests (eg. RHEL 3), but
is not secure against modern attacks.

The default is C<sha512> unless libguestfs detects an old guest that
didn't have support for SHA-512, in which case it will use C<md5>.
You can override libguestfs by specifying this option.

Note this does not change the default password encryption used
by the guest when you create new user accounts inside the guest.
If you want to do that, then you should use the I<--edit> option
to modify C</etc/sysconfig/authconfig> (Fedora, RHEL) or
C</etc/pam.d/common-password> (Debian, Ubuntu).";
  };

  { flag_name = "selinux-relabel";
    flag_type = FlagBool false (* XXX - the default in virt-builder *);
    flag_ml_var = "selinux_relabel";
    flag_shortdesc = "Relabel files with correct SELinux labels";
    flag_pod_longdesc = "\
Relabel files in the guest so that they have the correct SELinux label.

This will attempt to relabel files immediately, but if the operation fails
this will instead touch F</.autorelabel> on the image to schedule a
relabel operation for the next time the image boots.

You should only use this option for guests which support SELinux.";
  };

  { flag_name = "sm-credentials";
    flag_type = FlagSMCredentials "SELECTOR";
    flag_ml_var = "sm_credentials";
    flag_shortdesc = "Credentials for subscription-manager";
    flag_pod_longdesc = "\
Set the credentials for C<subscription-manager>.

See L<virt-builder(1)/SUBSCRIPTION-MANAGER> for the format of
the C<SELECTOR> field.";
  };

]

let rec generate_customize_cmdline_mli () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
(** Command line argument parsing, both for the virt-customize binary
    and for the other tools that share the same code. *)

";
  generate_ops_struct_decl ();
  pr "\n";

  pr "\
type argspec = Arg.key * Arg.spec * Arg.doc
val argspec : unit -> (argspec * string option * string) list * (unit -> ops)
(** This returns a pair [(list, get_ops)].

    [list] is a list of the command line arguments, plus some extra data.

    [get_ops] is a function you can call {i after} command line parsing
    which will return the actual operations specified by the user on the
    command line. *)"

and generate_customize_cmdline_ml () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
(* Command line argument parsing, both for the virt-customize binary
 * and for the other tools that share the same code.
 *)

open Printf

open Common_utils
open Common_gettext.Gettext

open Customize_utils

";
  generate_ops_struct_decl ();
  pr "\n";

  pr "\
type argspec = Arg.key * Arg.spec * Arg.doc

let rec argspec () =
  let ops = ref [] in
";
  List.iter (
    function
    | { flag_type = FlagBool default; flag_ml_var = var } ->
      pr "  let %s = ref %b in\n" var default
    | { flag_type = FlagPasswordCrypto _; flag_ml_var = var } ->
      pr "  let %s = ref None in\n" var
    | { flag_type = FlagSMCredentials _; flag_ml_var = var } ->
      pr "  let %s = ref None in\n" var
  ) flags;
  pr "\

  let rec get_ops () = {
    ops = List.rev !ops;
    flags = get_flags ();
  }
  and get_flags () = {
";
  List.iter (fun { flag_ml_var = var } -> pr "    %s = !%s;\n" var var) flags;
  pr "  }
  in

  let split_string_pair option_name arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        error (f_\"invalid format for '--%%s' parameter, see the man page\")
          option_name in
    let len = String.length arg in
    String.sub arg 0 i, String.sub arg (i+1) (len-(i+1))
  in
  let split_string_list arg =
    String.nsplit \",\" arg
  in
  let split_links_list option_name arg =
    match String.nsplit \":\" arg with
    | [] | [_] ->
      error (f_\"invalid format for '--%%s' parameter, see the man page\")
        option_name
    | target :: lns -> target, lns
  in

  let rec argspec = [
";

  List.iter (
    function
    | { op_type = Unit; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.Unit (fun () -> push_front %s ops),\n" discrim;
      pr "      \" \" ^ s_\"%s\"\n" shortdesc;
      pr "    ),\n";
      pr "    None, %S;\n" longdesc
    | { op_type = String v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (fun s -> push_front (%s s) ops),\n" discrim;
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = StringPair v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let p = split_string_pair \"%s\" s in\n" name;
      pr "          push_front (%s p) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = StringList v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let ss = split_string_list s in\n";
      pr "          push_front (%s ss) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = TargetLinks v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let ss = split_links_list \"%s\" s in\n" name;
      pr "          push_front (%s ss) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = PasswordSelector v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let sel = Password.parse_selector s in\n";
      pr "          push_front (%s sel) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = UserPasswordSelector v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let user, sel = split_string_pair \"%s\" s in\n" name;
      pr "          let sel = Password.parse_selector sel in\n";
      pr "          push_front (%s (user, sel)) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = SSHKeySelector v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let user, selstr = String.split \":\" s in\n";
      pr "          let sel = Ssh_key.parse_selector selstr in\n";
      pr "          push_front (%s (user, sel)) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = StringFn (v, fn); op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          %s s;\n" fn;
      pr "          push_front (%s s) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { op_type = SMPoolSelector v; op_name = name; op_discrim = discrim;
        op_shortdesc = shortdesc; op_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          let sel = Subscription_manager.parse_pool_selector s in\n";
      pr "          push_front (%s sel) ops\n" discrim;
      pr "      ),\n";
      pr "      s_\"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
  ) ops;

  List.iter (
    function
    | { flag_type = FlagBool default; flag_ml_var = var; flag_name = name;
        flag_shortdesc = shortdesc; flag_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      if default (* is true *) then
        pr "      Arg.Clear %s,\n" var
      else
        pr "      Arg.Set %s,\n" var;
      pr "      \" \" ^ s_\"%s\"\n" shortdesc;
      pr "    ),\n";
      pr "    None, %S;\n" longdesc
    | { flag_type = FlagPasswordCrypto v; flag_ml_var = var;
        flag_name = name; flag_shortdesc = shortdesc;
        flag_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          %s := Some (Password.password_crypto_of_string s)\n" var;
      pr "      ),\n";
      pr "      \"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
    | { flag_type = FlagSMCredentials v; flag_ml_var = var;
        flag_name = name; flag_shortdesc = shortdesc;
        flag_pod_longdesc = longdesc } ->
      pr "    (\n";
      pr "      \"--%s\",\n" name;
      pr "      Arg.String (\n";
      pr "        fun s ->\n";
      pr "          %s := Some (Subscription_manager.parse_credentials_selector s)\n"
        var;
      pr "      ),\n";
      pr "      \"%s\" ^ \" \" ^ s_\"%s\"\n" v shortdesc;
      pr "    ),\n";
      pr "    Some %S, %S;\n" v longdesc
  ) flags;

  pr "  ]
  and customize_read_from_file filename =
    let forbidden_commands = [
";

  List.iter (
    function
    | { op_type = StringFn (_, _); op_name = name; } ->
      pr "      \"%s\";\n" name
    | { op_type = Unit; }
    | { op_type = String _; }
    | { op_type = StringPair _; }
    | { op_type = StringList _; }
    | { op_type = TargetLinks _; }
    | { op_type = PasswordSelector _; }
    | { op_type = UserPasswordSelector _; }
    | { op_type = SSHKeySelector _; }
    | { op_type = SMPoolSelector _; } -> ()
  ) ops;

pr "    ] in
    let lines = read_whole_file filename in
    let lines = String.lines_split lines in
    let lines = List.filter (
      fun line ->
        String.length line > 0 && line.[0] <> '#'
    ) lines in
    let cmds = List.map (fun line -> String.split \" \" line) lines in
    (* Check for commands not allowed in files containing commands. *)
    List.iter (
      fun (cmd, _) ->
        if List.mem cmd forbidden_commands then
          error (f_\"command '%%s' cannot be used in command files, see the man page\")
            cmd
    ) cmds;
    List.iter (
      fun (cmd, arg) ->
        try
          let ((_, spec, _), _, _) = List.find (
            fun ((key, _, _), _, _) ->
              key = \"--\" ^ cmd
          ) argspec in
          (match spec with
          | Arg.Unit fn -> fn ()
          | Arg.String fn -> fn arg
          | Arg.Set varref -> varref := true
          | _ -> error \"INTERNAL error: spec not handled for %%s\" cmd
          )
        with Not_found ->
          error (f_\"command '%%s' not valid, see the man page\")
            cmd
    ) cmds
  in

  argspec, get_ops
"

and generate_ops_struct_decl () =
  pr "\
type ops = {
  ops : op list;
  flags : flags;
}
";

  (* Operations. *)
  pr "and op = [\n";
  List.iter (
    function
    | { op_type = Unit; op_discrim = discrim; op_name = name } ->
      pr "  | %s\n      (* --%s *)\n" discrim name
    | { op_type = String v; op_discrim = discrim; op_name = name } ->
      pr "  | %s of string\n      (* --%s %s *)\n" discrim name v
    | { op_type = StringPair v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of string * string\n      (* --%s %s *)\n" discrim name v
    | { op_type = StringList v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of string list\n      (* --%s %s *)\n" discrim name v
    | { op_type = TargetLinks v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of string * string list\n      (* --%s %s *)\n" discrim name v
    | { op_type = PasswordSelector v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of Password.password_selector\n      (* --%s %s *)\n"
        discrim name v
    | { op_type = UserPasswordSelector v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of string * Password.password_selector\n      (* --%s %s *)\n"
        discrim name v
    | { op_type = SSHKeySelector v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of string * Ssh_key.ssh_key_selector\n      (* --%s %s *)\n"
        discrim name v
    | { op_type = StringFn (v, _); op_discrim = discrim; op_name = name } ->
      pr "  | %s of string\n      (* --%s %s *)\n" discrim name v
    | { op_type = SMPoolSelector v; op_discrim = discrim;
        op_name = name } ->
      pr "  | %s of Subscription_manager.sm_pool\n      (* --%s %s *)\n"
        discrim name v
  ) ops;
  pr "]\n";

  (* Flags. *)
  pr "and flags = {\n";
  List.iter (
    function
    | { flag_type = FlagBool _; flag_ml_var = var; flag_name = name } ->
      pr "  %s : bool;\n      (* --%s *)\n" var name
    | { flag_type = FlagPasswordCrypto v; flag_ml_var = var;
        flag_name = name } ->
      pr "  %s : Password.password_crypto option;\n      (* --%s %s *)\n"
        var name v
    | { flag_type = FlagSMCredentials v; flag_ml_var = var;
        flag_name = name } ->
      pr "  %s : Subscription_manager.sm_credentials option;\n      (* --%s %s *)\n"
        var name v
  ) flags;
  pr "}\n"

let generate_customize_synopsis_pod () =
  (* generate_header PODStyle GPLv2plus; - NOT POSSIBLE *)

  let options =
    List.map (
      function
      | { op_type = Unit; op_name = n } ->
        n, sprintf "[--%s]" n
      | { op_type = String v | StringPair v | StringList v | TargetLinks v
            | PasswordSelector v | UserPasswordSelector v | SSHKeySelector v
            | StringFn (v, _) | SMPoolSelector v;
          op_name = n } ->
        n, sprintf "[--%s %s]" n v
    ) ops @
      List.map (
        function
        | { flag_type = FlagBool _; flag_name = n } ->
          n, sprintf "[--%s]" n
        | { flag_type = FlagPasswordCrypto v; flag_name = n } ->
          n, sprintf "[--%s %s]" n v
        | { flag_type = FlagSMCredentials v; flag_name = n } ->
          n, sprintf "[--%s %s]" n v
      ) flags in

  (* Print the option names in the synopsis, line-wrapped. *)
  let col = ref 4 in
  pr "   ";

  List.iter (
    fun (_, str) ->
      let len = String.length str + 1 in
      col := !col + len;
      if !col >= 72 then (
        col := 4 + len;
        pr "\n   "
      );
      pr " %s" str
  ) options;
  if !col > 4 then
    pr "\n"

let generate_customize_options_pod () =
  generate_header PODStyle GPLv2plus;

  pr "=over 4\n\n";

  let pod =
    List.map (
      function
      | { op_type = Unit; op_name = n; op_pod_longdesc = ld } ->
        n, sprintf "B<--%s>" n, ld
      | { op_type = String v | StringPair v | StringList v | TargetLinks v
            | PasswordSelector v | UserPasswordSelector v | SSHKeySelector v
            | StringFn (v, _) | SMPoolSelector v;
          op_name = n; op_pod_longdesc = ld } ->
        n, sprintf "B<--%s> %s" n v, ld
    ) ops @
      List.map (
        function
        | { flag_type = FlagBool _; flag_name = n; flag_pod_longdesc = ld } ->
          n, sprintf "B<--%s>" n, ld
        | { flag_type = FlagPasswordCrypto v;
            flag_name = n; flag_pod_longdesc = ld } ->
          n, sprintf "B<--%s> %s" n v, ld
        | { flag_type = FlagSMCredentials v;
            flag_name = n; flag_pod_longdesc = ld } ->
          n, sprintf "B<--%s> %s" n v, ld
      ) flags in
  let cmp (arg1, _, _) (arg2, _, _) =
    compare (String.lowercase arg1) (String.lowercase arg2)
  in
  let pod = List.sort cmp pod in

  List.iter (
    fun (_, item, longdesc) ->
      pr "\
=item %s

%s

" item longdesc
  ) pod;

  pr "=back\n\n"
