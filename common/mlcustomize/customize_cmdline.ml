(* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED FROM THE FOLLOWING FILES:
 *          generator/customize.ml
 *          and from the code in the generator/ subdirectory.
 * ANY CHANGES YOU MAKE TO THIS FILE WILL BE LOST.
 *
 * Copyright (C) 2009-2019 Red Hat Inc.
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

(* Command line argument parsing, both for the virt-customize binary
 * and for the other tools that share the same code.
 *)

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext
open Getopt.OptionName

type ops = {
  ops : op list;
  flags : flags;
}
and op = [
  | `AppendLine of string * string
      (* --append-line FILE:LINE *)
  | `Chmod of string * string
      (* --chmod PERMISSIONS:FILE *)
  | `CommandsFromFile of string
      (* --commands-from-file FILENAME *)
  | `Copy of string * string
      (* --copy SOURCE:DEST *)
  | `CopyIn of string * string
      (* --copy-in LOCALPATH:REMOTEDIR *)
  | `Delete of string
      (* --delete PATH *)
  | `Edit of string * string
      (* --edit FILE:EXPR *)
  | `FirstbootScript of string
      (* --firstboot SCRIPT *)
  | `FirstbootCommand of string
      (* --firstboot-command 'CMD+ARGS' *)
  | `FirstbootPackages of string list
      (* --firstboot-install PKG,PKG.. *)
  | `Hostname of string
      (* --hostname HOSTNAME *)
  | `InstallPackages of string list
      (* --install PKG,PKG.. *)
  | `Link of string * string list
      (* --link TARGET:LINK[:LINK..] *)
  | `Mkdir of string
      (* --mkdir DIR *)
  | `Move of string * string
      (* --move SOURCE:DEST *)
  | `Password of string * Password.password_selector
      (* --password USER:SELECTOR *)
  | `RootPassword of Password.password_selector
      (* --root-password SELECTOR *)
  | `Script of string
      (* --run SCRIPT *)
  | `Command of string
      (* --run-command 'CMD+ARGS' *)
  | `Scrub of string
      (* --scrub FILE *)
  | `SMAttach of Subscription_manager.sm_pool
      (* --sm-attach SELECTOR *)
  | `SMRegister
      (* --sm-register *)
  | `SMRemove
      (* --sm-remove *)
  | `SMUnregister
      (* --sm-unregister *)
  | `SSHInject of string * Ssh_key.ssh_key_selector
      (* --ssh-inject USER[:SELECTOR] *)
  | `Truncate of string
      (* --truncate FILE *)
  | `TruncateRecursive of string
      (* --truncate-recursive PATH *)
  | `Timezone of string
      (* --timezone TIMEZONE *)
  | `Touch of string
      (* --touch FILE *)
  | `UninstallPackages of string list
      (* --uninstall PKG,PKG.. *)
  | `Update
      (* --update *)
  | `Upload of string * string
      (* --upload FILE:DEST *)
  | `Write of string * string
      (* --write FILE:CONTENT *)
]
and flags = {
  scrub_logfile : bool;
      (* --no-logfile *)
  password_crypto : Password.password_crypto option;
      (* --password-crypto md5|sha256|sha512 *)
  selinux_relabel : bool;
      (* --selinux-relabel *)
  sm_credentials : Subscription_manager.sm_credentials option;
      (* --sm-credentials SELECTOR *)
}

type argspec = Getopt.keys * Getopt.spec * Getopt.doc

let rec argspec () =
  let ops = ref [] in
  let scrub_logfile = ref false in
  let password_crypto = ref None in
  let selinux_relabel = ref false in
  let sm_credentials = ref None in

  let rec get_ops () = {
    ops = List.rev !ops;
    flags = get_flags ();
  }
  and get_flags () = {
    scrub_logfile = !scrub_logfile;
    password_crypto = !password_crypto;
    selinux_relabel = !selinux_relabel;
    sm_credentials = !sm_credentials;
  }
  in

  let split_string_pair option_name arg =
    let i =
      try String.index arg ':'
      with Not_found ->
        error (f_"invalid format for '--%s' parameter, see the man page")
          option_name in
    let len = String.length arg in
    String.sub arg 0 i, String.sub arg (i+1) (len-(i+1))
  in
  let split_string_list arg =
    String.nsplit "," arg
  in
  let split_links_list option_name arg =
    match String.nsplit ":" arg with
    | [] | [_] ->
      error (f_"invalid format for '--%s' parameter, see the man page")
        option_name
    | target :: lns -> target, lns
  in

  let rec argspec = [
    (
      [ L"append-line" ],
      Getopt.String (
        s_"FILE:LINE",
        fun s ->
          let p = split_string_pair "append-line" s in
          List.push_front (`AppendLine p) ops
      ),
      s_"Append line(s) to the file"
    ),
    Some "FILE:LINE", "Append a single line of text to the C<FILE>.  If the file does not already\nend with a newline, then one is added before the appended\nline.  Also a newline is added to the end of the C<LINE> string\nautomatically.\n\nFor example (assuming ordinary shell quoting) this command:\n\n --append-line '/etc/hosts:10.0.0.1 foo'\n\nwill add either C<10.0.0.1 foo\226\143\142> or C<\226\143\14210.0.0.1 foo\226\143\142> to\nthe file, the latter only if the existing file does not\nalready end with a newline.\n\nC<\226\143\142> represents a newline character, which is guessed by\nlooking at the existing content of the file, so this command\ndoes the right thing for files using Unix or Windows line endings.\nIt also works for empty or non-existent files.\n\nTo insert several lines, use the same option several times:\n\n --append-line '/etc/hosts:10.0.0.1 foo'\n --append-line '/etc/hosts:10.0.0.2 bar'\n\nTo insert a blank line before the appended line, do:\n\n --append-line '/etc/hosts:'\n --append-line '/etc/hosts:10.0.0.1 foo'";
    (
      [ L"chmod" ],
      Getopt.String (
        s_"PERMISSIONS:FILE",
        fun s ->
          let p = split_string_pair "chmod" s in
          List.push_front (`Chmod p) ops
      ),
      s_"Change the permissions of a file"
    ),
    Some "PERMISSIONS:FILE", "Change the permissions of C<FILE> to C<PERMISSIONS>.\n\nI<Note>: C<PERMISSIONS> by default would be decimal, unless you prefix\nit with C<0> to get octal, ie. use C<0700> not C<700>.";
    (
      [ L"commands-from-file" ],
      Getopt.String (
        s_"FILENAME",
        fun s ->
          customize_read_from_file s;
          List.push_front (`CommandsFromFile s) ops
      ),
      s_"Read customize commands from file"
    ),
    Some "FILENAME", "Read the customize commands from a file, one (and its arguments)\neach line.\n\nEach line contains a single customization command and its arguments,\nfor example:\n\n delete /some/file\n install some-package\n password some-user:password:its-new-password\n\nEmpty lines are ignored, and lines starting with C<#> are comments\nand are ignored as well.  Furthermore, arguments can be spread across\nmultiple lines, by adding a C<\\> (continuation character) at the of\na line, for example\n\n edit /some/file:\\\n   s/^OPT=.*/OPT=ok/\n\nThe commands are handled in the same order as they are in the file,\nas if they were specified as I<--delete /some/file> on the command\nline.";
    (
      [ L"copy" ],
      Getopt.String (
        s_"SOURCE:DEST",
        fun s ->
          let p = split_string_pair "copy" s in
          List.push_front (`Copy p) ops
      ),
      s_"Copy files in disk image"
    ),
    Some "SOURCE:DEST", "Copy files or directories recursively inside the guest.\n\nWildcards cannot be used.";
    (
      [ L"copy-in" ],
      Getopt.String (
        s_"LOCALPATH:REMOTEDIR",
        fun s ->
          let p = split_string_pair "copy-in" s in
          List.push_front (`CopyIn p) ops
      ),
      s_"Copy local files or directories into image"
    ),
    Some "LOCALPATH:REMOTEDIR", "Copy local files or directories recursively into the disk image,\nplacing them in the directory C<REMOTEDIR> (which must exist).\n\nWildcards cannot be used.";
    (
      [ L"delete" ],
      Getopt.String (s_"PATH", fun s -> List.push_front (`Delete s) ops),
      s_"Delete a file or directory"
    ),
    Some "PATH", "Delete a file from the guest.  Or delete a directory (and all its\ncontents, recursively).\n\nYou can use shell glob characters in the specified path.  Be careful\nto escape glob characters from the host shell, if that is required.\nFor example:\n\n virt-customize --delete '/var/log/*.log'.\n\nSee also: I<--upload>, I<--scrub>.";
    (
      [ L"edit" ],
      Getopt.String (
        s_"FILE:EXPR",
        fun s ->
          let p = split_string_pair "edit" s in
          List.push_front (`Edit p) ops
      ),
      s_"Edit file using Perl expression"
    ),
    Some "FILE:EXPR", "Edit C<FILE> using the Perl expression C<EXPR>.\n\nBe careful to properly quote the expression to prevent it from\nbeing altered by the shell.\n\nNote that this option is only available when Perl 5 is installed.\n\nSee L<virt-edit(1)/NON-INTERACTIVE EDITING>.";
    (
      [ L"firstboot" ],
      Getopt.String (s_"SCRIPT", fun s -> List.push_front (`FirstbootScript s) ops),
      s_"Run script at first guest boot"
    ),
    Some "SCRIPT", "Install C<SCRIPT> inside the guest, so that when the guest first boots\nup, the script runs (as root, late in the boot process).\n\nThe script is automatically chmod +x after installation in the guest.\n\nThe alternative version I<--firstboot-command> is the same, but it\nconveniently wraps the command up in a single line script for you.\n\nYou can have multiple I<--firstboot> options.  They run in the same\norder that they appear on the command line.\n\nPlease take a look at L<virt-builder(1)/FIRST BOOT SCRIPTS> for more\ninformation and caveats about the first boot scripts.\n\nSee also I<--run>.";
    (
      [ L"firstboot-command" ],
      Getopt.String (s_"'CMD+ARGS'", fun s -> List.push_front (`FirstbootCommand s) ops),
      s_"Run command at first guest boot"
    ),
    Some "'CMD+ARGS'", "Run command (and arguments) inside the guest when the guest first\nboots up (as root, late in the boot process).\n\nYou can have multiple I<--firstboot> options.  They run in the same\norder that they appear on the command line.\n\nPlease take a look at L<virt-builder(1)/FIRST BOOT SCRIPTS> for more\ninformation and caveats about the first boot scripts.\n\nSee also I<--run>.";
    (
      [ L"firstboot-install" ],
      Getopt.String (
        s_"PKG,PKG..",
        fun s ->
          let ss = split_string_list s in
          List.push_front (`FirstbootPackages ss) ops
      ),
      s_"Add package(s) to install at first boot"
    ),
    Some "PKG,PKG..", "Install the named packages (a comma-separated list).  These are\ninstalled when the guest first boots using the guest\226\128\153s package manager\n(eg. apt, yum, etc.) and the guest\226\128\153s network connection.\n\nFor an overview on the different ways to install packages, see\nL<virt-builder(1)/INSTALLING PACKAGES>.";
    (
      [ L"hostname" ],
      Getopt.String (s_"HOSTNAME", fun s -> List.push_front (`Hostname s) ops),
      s_"Set the hostname"
    ),
    Some "HOSTNAME", "Set the hostname of the guest to C<HOSTNAME>.  You can use a\ndotted hostname.domainname (FQDN) if you want.";
    (
      [ L"install" ],
      Getopt.String (
        s_"PKG,PKG..",
        fun s ->
          let ss = split_string_list s in
          List.push_front (`InstallPackages ss) ops
      ),
      s_"Add package(s) to install"
    ),
    Some "PKG,PKG..", "Install the named packages (a comma-separated list).  These are\ninstalled during the image build using the guest\226\128\153s package manager\n(eg. apt, yum, etc.) and the host\226\128\153s network connection.\n\nFor an overview on the different ways to install packages, see\nL<virt-builder(1)/INSTALLING PACKAGES>.\n\nSee also I<--update>, I<--uninstall>.";
    (
      [ L"link" ],
      Getopt.String (
        s_"TARGET:LINK[:LINK..]",
        fun s ->
          let ss = split_links_list "link" s in
          List.push_front (`Link ss) ops
      ),
      s_"Create symbolic links"
    ),
    Some "TARGET:LINK[:LINK..]", "Create symbolic link(s) in the guest, starting at C<LINK> and\npointing at C<TARGET>.";
    (
      [ L"mkdir" ],
      Getopt.String (s_"DIR", fun s -> List.push_front (`Mkdir s) ops),
      s_"Create a directory"
    ),
    Some "DIR", "Create a directory in the guest.\n\nThis uses S<C<mkdir -p>> so any intermediate directories are created,\nand it also works if the directory already exists.";
    (
      [ L"move" ],
      Getopt.String (
        s_"SOURCE:DEST",
        fun s ->
          let p = split_string_pair "move" s in
          List.push_front (`Move p) ops
      ),
      s_"Move files in disk image"
    ),
    Some "SOURCE:DEST", "Move files or directories inside the guest.\n\nWildcards cannot be used.";
    (
      [ L"password" ],
      Getopt.String (
        s_"USER:SELECTOR",
        fun s ->
          let user, sel = split_string_pair "password" s in
          let sel = Password.parse_selector sel in
          List.push_front (`Password (user, sel)) ops
      ),
      s_"Set user password"
    ),
    Some "USER:SELECTOR", "Set the password for C<USER>.  (Note this option does I<not>\ncreate the user account).\n\nSee L<virt-builder(1)/USERS AND PASSWORDS> for the format of\nthe C<SELECTOR> field, and also how to set up user accounts.";
    (
      [ L"root-password" ],
      Getopt.String (
        s_"SELECTOR",
        fun s ->
          let sel = Password.parse_selector s in
          List.push_front (`RootPassword sel) ops
      ),
      s_"Set root password"
    ),
    Some "SELECTOR", "Set the root password.\n\nSee L<virt-builder(1)/USERS AND PASSWORDS> for the format of\nthe C<SELECTOR> field, and also how to set up user accounts.\n\nNote: In virt-builder, if you I<don't> set I<--root-password>\nthen the guest is given a I<random> root password.";
    (
      [ L"run" ],
      Getopt.String (s_"SCRIPT", fun s -> List.push_front (`Script s) ops),
      s_"Run script in disk image"
    ),
    Some "SCRIPT", "Run the shell script (or any program) called C<SCRIPT> on the disk\nimage.  The script runs virtualized inside a small appliance, chrooted\ninto the guest filesystem.\n\nThe script is automatically chmod +x.\n\nIf libguestfs supports it then a limited network connection is\navailable but it only allows outgoing network connections.  You can\nalso attach data disks (eg. ISO files) as another way to provide data\n(eg. software packages) to the script without needing a network\nconnection (I<--attach>).  You can also upload data files (I<--upload>).\n\nYou can have multiple I<--run> options.  They run\nin the same order that they appear on the command line.\n\nSee also: I<--firstboot>, I<--attach>, I<--upload>.";
    (
      [ L"run-command" ],
      Getopt.String (s_"'CMD+ARGS'", fun s -> List.push_front (`Command s) ops),
      s_"Run command in disk image"
    ),
    Some "'CMD+ARGS'", "Run the command and arguments on the disk image.  The command runs\nvirtualized inside a small appliance, chrooted into the guest filesystem.\n\nIf libguestfs supports it then a limited network connection is\navailable but it only allows outgoing network connections.  You can\nalso attach data disks (eg. ISO files) as another way to provide data\n(eg. software packages) to the script without needing a network\nconnection (I<--attach>).  You can also upload data files (I<--upload>).\n\nYou can have multiple I<--run-command> options.  They run\nin the same order that they appear on the command line.\n\nSee also: I<--firstboot>, I<--attach>, I<--upload>.";
    (
      [ L"scrub" ],
      Getopt.String (s_"FILE", fun s -> List.push_front (`Scrub s) ops),
      s_"Scrub a file"
    ),
    Some "FILE", "Scrub a file from the guest.  This is like I<--delete> except that:\n\n=over 4\n\n=item *\n\nIt scrubs the data so a guest could not recover it.\n\n=item *\n\nIt cannot delete directories, only regular files.\n\n=back";
    (
      [ L"sm-attach" ],
      Getopt.String (
        s_"SELECTOR",
        fun s ->
          let sel = Subscription_manager.parse_pool_selector s in
          List.push_front (`SMAttach sel) ops
      ),
      s_"Attach to a subscription-manager pool"
    ),
    Some "SELECTOR", "Attach to a pool using C<subscription-manager>.\n\nSee L<virt-builder(1)/SUBSCRIPTION-MANAGER> for the format of\nthe C<SELECTOR> field.";
    (
      [ L"sm-register" ],
      Getopt.Unit (fun () -> List.push_front `SMRegister ops),
      s_"Register using subscription-manager"
    ),
    None, "Register the guest using C<subscription-manager>.\n\nThis requires credentials being set using I<--sm-credentials>.";
    (
      [ L"sm-remove" ],
      Getopt.Unit (fun () -> List.push_front `SMRemove ops),
      s_"Remove all the subscriptions"
    ),
    None, "Remove all the subscriptions from the guest using\nC<subscription-manager>.";
    (
      [ L"sm-unregister" ],
      Getopt.Unit (fun () -> List.push_front `SMUnregister ops),
      s_"Unregister using subscription-manager"
    ),
    None, "Unregister the guest using C<subscription-manager>.";
    (
      [ L"ssh-inject" ],
      Getopt.String (
        s_"USER[:SELECTOR]",
        fun s ->
          let user, selstr = String.split ":" s in
          let sel = Ssh_key.parse_selector selstr in
          List.push_front (`SSHInject (user, sel)) ops
      ),
      s_"Inject a public key into the guest"
    ),
    Some "USER[:SELECTOR]", "Inject an ssh key so the given C<USER> will be able to log in over\nssh without supplying a password.  The C<USER> must exist already\nin the guest.\n\nSee L<virt-builder(1)/SSH KEYS> for the format of\nthe C<SELECTOR> field.\n\nYou can have multiple I<--ssh-inject> options, for different users\nand also for more keys for each user.";
    (
      [ L"truncate" ],
      Getopt.String (s_"FILE", fun s -> List.push_front (`Truncate s) ops),
      s_"Truncate a file to zero size"
    ),
    Some "FILE", "This command truncates C<FILE> to a zero-length file. The file must exist\nalready.";
    (
      [ L"truncate-recursive" ],
      Getopt.String (s_"PATH", fun s -> List.push_front (`TruncateRecursive s) ops),
      s_"Recursively truncate all files in directory"
    ),
    Some "PATH", "This command recursively truncates all files under C<PATH> to zero-length.";
    (
      [ L"timezone" ],
      Getopt.String (s_"TIMEZONE", fun s -> List.push_front (`Timezone s) ops),
      s_"Set the default timezone"
    ),
    Some "TIMEZONE", "Set the default timezone of the guest to C<TIMEZONE>.  Use a location\nstring like C<Europe/London>";
    (
      [ L"touch" ],
      Getopt.String (s_"FILE", fun s -> List.push_front (`Touch s) ops),
      s_"Run touch on a file"
    ),
    Some "FILE", "This command performs a L<touch(1)>-like operation on C<FILE>.";
    (
      [ L"uninstall" ],
      Getopt.String (
        s_"PKG,PKG..",
        fun s ->
          let ss = split_string_list s in
          List.push_front (`UninstallPackages ss) ops
      ),
      s_"Uninstall package(s)"
    ),
    Some "PKG,PKG..", "Uninstall the named packages (a comma-separated list).  These are\nremoved during the image build using the guest\226\128\153s package manager\n(eg. apt, yum, etc.).  Dependent packages may also need to be\nuninstalled to satisfy the request.\n\nSee also I<--install>, I<--update>.";
    (
      [ L"update" ],
      Getopt.Unit (fun () -> List.push_front `Update ops),
      s_"Update packages"
    ),
    None, "Do the equivalent of C<yum update>, C<apt-get upgrade>, or whatever\ncommand is required to update the packages already installed in the\ntemplate to their latest versions.\n\nSee also I<--install>, I<--uninstall>.";
    (
      [ L"upload" ],
      Getopt.String (
        s_"FILE:DEST",
        fun s ->
          let p = split_string_pair "upload" s in
          List.push_front (`Upload p) ops
      ),
      s_"Upload local file to destination"
    ),
    Some "FILE:DEST", "Upload local file C<FILE> to destination C<DEST> in the disk image.\nFile owner and permissions from the original are preserved, so you\nshould set them to what you want them to be in the disk image.\n\nC<DEST> could be the final filename.  This can be used to rename\nthe file on upload.\n\nIf C<DEST> is a directory name (which must already exist in the guest)\nthen the file is uploaded into that directory, and it keeps the same\nname as on the local filesystem.\n\nSee also: I<--mkdir>, I<--delete>, I<--scrub>.";
    (
      [ L"write" ],
      Getopt.String (
        s_"FILE:CONTENT",
        fun s ->
          let p = split_string_pair "write" s in
          List.push_front (`Write p) ops
      ),
      s_"Write file"
    ),
    Some "FILE:CONTENT", "Write C<CONTENT> to C<FILE>.";
    (
      [ L"no-logfile" ],
      Getopt.Set scrub_logfile,
      s_"Scrub build log file"
    ),
    None, "Scrub C<builder.log> (log file from build commands) from the image\nafter building is complete.  If you don't want to reveal precisely how\nthe image was built, use this option.\n\nSee also: L</LOG FILE>.";
    (
      [ L"password-crypto" ],
      Getopt.String (
        s_"md5|sha256|sha512",
        fun s ->
          password_crypto := Some (Password.password_crypto_of_string s)
      ),
      s_"Set password crypto"
    ),
    Some "md5|sha256|sha512", "When the virt tools change or set a password in the guest, this\noption sets the password encryption of that password to\nC<md5>, C<sha256> or C<sha512>.\n\nC<sha256> and C<sha512> require glibc E<ge> 2.7 (check crypt(3) inside\nthe guest).\n\nC<md5> will work with relatively old Linux guests (eg. RHEL 3), but\nis not secure against modern attacks.\n\nThe default is C<sha512> unless libguestfs detects an old guest that\ndidn't have support for SHA-512, in which case it will use C<md5>.\nYou can override libguestfs by specifying this option.\n\nNote this does not change the default password encryption used\nby the guest when you create new user accounts inside the guest.\nIf you want to do that, then you should use the I<--edit> option\nto modify C</etc/sysconfig/authconfig> (Fedora, RHEL) or\nC</etc/pam.d/common-password> (Debian, Ubuntu).";
    (
      [ L"selinux-relabel" ],
      Getopt.Set selinux_relabel,
      s_"Relabel files with correct SELinux labels"
    ),
    None, "Relabel files in the guest so that they have the correct SELinux label.\n\nThis will attempt to relabel files immediately, but if the operation fails\nthis will instead touch F</.autorelabel> on the image to schedule a\nrelabel operation for the next time the image boots.\n\nYou should only use this option for guests which support SELinux.";
    (
      [ L"sm-credentials" ],
      Getopt.String (
        s_"SELECTOR",
        fun s ->
          sm_credentials := Some (Subscription_manager.parse_credentials_selector s)
      ),
      s_"Credentials for subscription-manager"
    ),
    Some "SELECTOR", "Set the credentials for C<subscription-manager>.\n\nSee L<virt-builder(1)/SUBSCRIPTION-MANAGER> for the format of\nthe C<SELECTOR> field.";
  ]
  and customize_read_from_file filename =
    let forbidden_commands = [
      "commands-from-file";
    ] in
    let lines = read_whole_file filename in
    let lines = String.lines_split lines in
    let lines = List.filter (
      fun line ->
        String.length line > 0 && line.[0] <> '#'
    ) lines in
    let cmds = List.map (fun line -> String.split " " line) lines in
    (* Check for commands not allowed in files containing commands. *)
    List.iter (
      fun (cmd, _) ->
        if List.mem cmd forbidden_commands then
          error (f_"command '%s' cannot be used in command files, see the man page")
            cmd
    ) cmds;
    List.iter (
      fun (cmd, arg) ->
        try
          let ((_, spec, _), _, _) = List.find (
            fun ((keys, _, _), _, _) ->
              List.mem (L cmd) keys
          ) argspec in
          (match spec with
          | Getopt.Unit fn -> fn ()
          | Getopt.String (_, fn) -> fn arg
          | Getopt.Set varref -> varref := true
          | _ -> error "INTERNAL error: spec not handled for %s" cmd
          )
        with Not_found ->
          error (f_"command '%s' not valid, see the man page")
            cmd
    ) cmds
  in

  argspec, get_ops
