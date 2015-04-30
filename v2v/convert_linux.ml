(* virt-v2v
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(* Convert various RPM-based Linux enterprise distros.  This module
 * handles:
 *
 * - RHEL and derivatives like CentOS and ScientificLinux
 * - SUSE
 * - OpenSUSE and Fedora (not enterprisey, but similar enough to RHEL/SUSE)
 *)

(* < mdbooth> It's all in there for a reason :/ *)

open Printf

open Common_gettext.Gettext
open Common_utils

open Utils
open Types

module G = Guestfs

(* Kernel information. *)
type kernel_info = {
  ki_app : G.application2;         (* The RPM package data. *)
  ki_name : string;                (* eg. "kernel-PAE" *)
  ki_version : string;             (* version-release *)
  ki_arch : string;                (* Kernel architecture. *)
  ki_vmlinuz : string;             (* The path of the vmlinuz file. *)
  ki_vmlinuz_stat : G.statns;      (* stat(2) of vmlinuz *)
  ki_initrd : string option;       (* Path of initramfs, if found. *)
  ki_modpath : string;             (* The module path. *)
  ki_modules : string list;        (* The list of module names. *)
  ki_supports_virtio : bool;       (* Kernel has virtio drivers? *)
  ki_is_xen_kernel : bool;         (* Is a Xen paravirt kernel? *)
  ki_is_debug : bool;              (* Is debug kernel? *)
}

let string_of_kernel_info ki =
  sprintf "(%s, %s, %s, %s, %s, virtio=%b, xen=%b, debug=%b)"
    ki.ki_name ki.ki_version ki.ki_arch ki.ki_vmlinuz
    (match ki.ki_initrd with None -> "None" | Some f -> f)
    ki.ki_supports_virtio ki.ki_is_xen_kernel ki.ki_is_debug

(* The conversion function. *)
let rec convert ~verbose ~keep_serial_console (g : G.guestfs) inspect source =
  (*----------------------------------------------------------------------*)
  (* Inspect the guest first.  We already did some basic inspection in
   * the common v2v.ml code, but that has to deal with generic guests
   * (anything common to Linux and Windows).  Here we do more detailed
   * inspection which can make the assumption that we are dealing with
   * an Enterprise Linux guest using RPM.
   *)

  (* Basic inspection data available as local variables. *)
  assert (inspect.i_type = "linux");

  let family =
    match inspect.i_distro with
    | "fedora"
    | "rhel" | "centos" | "scientificlinux" | "redhat-based" -> `RHEL_family
    | "sles" | "suse-based" | "opensuse" -> `SUSE_family
    | _ -> assert false in

  assert (inspect.i_package_format = "rpm");

  (* We use Augeas for inspection and conversion, so initialize it early. *)
  Linux.augeas_init verbose g;

  (* Clean RPM database.  This must be done early to avoid RHBZ#1143866. *)
  let dbfiles = g#glob_expand "/var/lib/rpm/__db.00?" in
  let dbfiles = Array.to_list dbfiles in
  List.iter g#rm_f dbfiles;

  (* What grub is installed? *)
  let grub_config, grub =
    try
      List.find (
        fun (grub_config, _) -> g#is_file ~followsymlinks:true grub_config
      ) [
        "/boot/grub2/grub.cfg", `Grub2;
        "/boot/grub/menu.lst", `Grub1;
        "/boot/grub/grub.conf", `Grub1;
      ]
    with
      Not_found ->
        error (f_"no grub1/grub-legacy or grub2 configuration file was found") in

  (* Grub prefix?  Usually "/boot". *)
  let grub_prefix =
    match grub with
    | `Grub2 -> ""
    | `Grub1 ->
      let mounts = g#inspect_get_mountpoints inspect.i_root in
      try
        List.find (
          fun path -> List.mem_assoc path mounts
        ) [ "/boot/grub"; "/boot" ]
      with Not_found -> "" in

  (* What kernel/kernel-like packages are installed on the current guest? *)
  let installed_kernels : kernel_info list =
    let rex_ko = Str.regexp ".*\\.k?o\\(\\.xz\\)?$" in
    let rex_ko_extract = Str.regexp ".*/\\([^/]+\\)\\.k?o\\(\\.xz\\)?$" in
    let rex_initrd = Str.regexp "^initr\\(d\\|amfs\\)-.*\\.img$" in
    filter_map (
      function
      | { G.app2_name = name } as app
          when name = "kernel" || string_prefix name "kernel-" ->
        (try
           (* For each kernel, list the files directly owned by the kernel. *)
           let files = Linux.file_list_of_package verbose g inspect app in

           (* Which of these is the kernel itself? *)
           let vmlinuz = List.find (
             fun filename -> string_prefix filename "/boot/vmlinuz-"
           ) files in
           (* Which of these is the modpath? *)
           let modpath = List.find (
             fun filename ->
               String.length filename >= 14 &&
                 string_prefix filename "/lib/modules/"
           ) files in

           (* Check vmlinuz & modpath exist. *)
           if not (g#is_dir ~followsymlinks:true modpath) then
             raise Not_found;
           let vmlinuz_stat =
             try g#statns vmlinuz with G.Error _ -> raise Not_found in

           (* Get/construct the version.  XXX Read this from kernel file. *)
           let version =
             sprintf "%s-%s" app.G.app2_version app.G.app2_release in

           (* Find the initramfs which corresponds to the kernel.
            * Since the initramfs is built at runtime, and doesn't have
            * to be covered by the RPM file list, this is basically
            * guesswork.
            *)
           let initrd =
             let files = g#ls "/boot" in
             let files = Array.to_list files in
             let files =
               List.filter (fun n -> Str.string_match rex_initrd n 0) files in
             let files =
               List.filter (
                 fun n ->
                   string_find n app.G.app2_version >= 0 &&
                   string_find n app.G.app2_release >= 0
               ) files in
             (* Don't consider kdump initramfs images (RHBZ#1138184). *)
             let files =
               List.filter (fun n -> string_find n "kdump.img" == -1) files in
             (* If several files match, take the shortest match.  This
              * handles the case where we have a mix of same-version non-Xen
              * and Xen kernels:
              *   initrd-2.6.18-308.el5.img
              *   initrd-2.6.18-308.el5xen.img
              * and kernel 2.6.18-308.el5 (non-Xen) will match both
              * (RHBZ#1141145).
              *)
             let cmp a b = compare (String.length a) (String.length b) in
             let files = List.sort cmp files in
             match files with
             | [] ->
               warning ~prog (f_"no initrd was found in /boot matching %s %s.")
                 name version;
               None
             | x :: _ -> Some ("/boot/" ^ x) in

           (* Get all modules, which might include custom-installed
            * modules that don't appear in 'files' list above.
            *)
           let modules = g#find modpath in
           let modules = Array.to_list modules in
           let modules =
             List.filter (fun m -> Str.string_match rex_ko m 0) modules in
           assert (List.length modules > 0);

           (* Determine the kernel architecture by looking at the
            * architecture of an arbitrary kernel module.
            *)
           let arch =
             let any_module = modpath ^ List.hd modules in
             g#file_architecture any_module in

           (* Just return the module names, without path or extension. *)
           let modules = filter_map (
             fun m ->
               if Str.string_match rex_ko_extract m 0 then
                 Some (Str.matched_group 1 m)
               else
                 None
           ) modules in
           assert (List.length modules > 0);

           let supports_virtio = List.mem "virtio_net" modules in
           let is_xen_kernel = List.mem "xennet" modules in

           (* If the package name is like "kernel-debug", then it's
            * a debug kernel.
            *)
           let is_debug =
             string_suffix app.G.app2_name "-debug" ||
             string_suffix app.G.app2_name "-dbg" in

           Some {
             ki_app  = app;
             ki_name = name;
             ki_version = version;
             ki_arch = arch;
             ki_vmlinuz = vmlinuz;
             ki_vmlinuz_stat = vmlinuz_stat;
             ki_initrd = initrd;
             ki_modpath = modpath;
             ki_modules = modules;
             ki_supports_virtio = supports_virtio;
             ki_is_xen_kernel = is_xen_kernel;
             ki_is_debug = is_debug;
           }

         with Not_found -> None
        )

      | _ -> None
    ) inspect.i_apps in

  if verbose then (
    printf "installed kernel packages in this guest:\n";
    List.iter (
      fun kernel -> printf "\t%s\n" (string_of_kernel_info kernel)
    ) installed_kernels;
    flush stdout
  );

  if installed_kernels = [] then
    error (f_"no installed kernel packages were found.\n\nThis probably indicates that %s was unable to inspect this guest properly.")
      prog;

  (* Now the difficult bit.  Get the grub kernels.  The first in this
   * list is the default booting kernel.
   *)
  let grub_kernels : kernel_info list =
    (* Helper function for SUSE: remove (hdX,X) prefix from a path. *)
    let remove_hd_prefix  =
      let rex = Str.regexp "^(hd.*)\\(.*\\)" in
      Str.replace_first rex "\\1"
    in

    let vmlinuzes =
      match grub with
      | `Grub1 ->
        let paths =
          let expr = sprintf "/files%s/title/kernel" grub_config in
          let paths = g#aug_match expr in
          let paths = Array.to_list paths in

          (* Remove duplicates. *)
          let paths = remove_duplicates paths in

          (* Get the default kernel from grub if it's set. *)
          let default =
            let expr = sprintf "/files%s/default" grub_config in
            try
              let idx = g#aug_get expr in
              let idx = int_of_string idx in
              (* Grub indices are zero-based, augeas is 1-based. *)
              let expr =
                sprintf "/files%s/title[%d]/kernel" grub_config (idx+1) in
              Some expr
            with Not_found -> None in

          (* If a default kernel was set, put it at the beginning of the paths
           * list.  If not set, assume the first kernel always boots (?)
           *)
          match default with
          | None -> paths
          | Some p -> p :: List.filter ((<>) p) paths in

        (* Resolve the Augeas paths to kernel filenames. *)
        let vmlinuzes = List.map g#aug_get paths in

        (* Make sure kernel does not begin with (hdX,X). *)
        let vmlinuzes = List.map remove_hd_prefix vmlinuzes in

        (* Prepend grub filesystem. *)
        List.map ((^) grub_prefix) vmlinuzes

      | `Grub2 ->
        let get_default_image () =
          let cmd =
            if g#exists "/sbin/grubby" then
              [| "grubby"; "--default-kernel" |]
            else
              [| "/usr/bin/perl"; "-MBootloader::Tools"; "-e"; "
                    InitLibrary();
                    my $default = Bootloader::Tools::GetDefaultSection();
                    print $default->{image};
                 " |] in
          match g#command cmd with
          | "" -> None
          | k ->
            let len = String.length k in
            let k =
              if len > 0 && k.[len-1] = '\n' then
                String.sub k 0 (len-1)
              else k in
            Some (remove_hd_prefix k)
        in

        let vmlinuzes =
          (match get_default_image () with
          | None -> []
          | Some k -> [k]) @
            (* This is how the grub2 config generator enumerates kernels. *)
            Array.to_list (g#glob_expand "/boot/kernel-*") @
            Array.to_list (g#glob_expand "/boot/vmlinuz-*") @
            Array.to_list (g#glob_expand "/vmlinuz-*") in
        let rex = Str.regexp ".*\\.\\(dpkg-.*|rpmsave|rpmnew\\)$" in
        let vmlinuzes = List.filter (
          fun file -> not (Str.string_match rex file 0)
        ) vmlinuzes in
        vmlinuzes in

    (* Map these to installed kernels. *)
    filter_map (
      fun vmlinuz ->
        try
          let statbuf = g#statns vmlinuz in
          let kernel =
            List.find (
              fun { ki_vmlinuz_stat = s } ->
                statbuf.G.st_dev = s.G.st_dev && statbuf.G.st_ino = s.G.st_ino
            ) installed_kernels in
          Some kernel
        with Not_found -> None
    ) vmlinuzes in

  if verbose then (
    printf "grub kernels in this guest (first in list is default):\n";
    List.iter (
      fun kernel -> printf "\t%s\n" (string_of_kernel_info kernel)
    ) grub_kernels;
    flush stdout
  );

  if grub_kernels = [] then
    error (f_"no kernels were found in the grub configuration.\n\nThis probably indicates that %s was unable to parse the grub configuration of this guest.")
      prog;

  (*----------------------------------------------------------------------*)
  (* Conversion step. *)

  let rec augeas_grub_configuration () =
    match grub with
    | `Grub1 ->
      (* Ensure Augeas is reading the grub configuration file, and if not
       * then add it.
       *)
      let incls = g#aug_match "/augeas/load/Grub/incl" in
      let incls = Array.to_list incls in
      let incls_contains_conf =
        List.exists (fun incl -> g#aug_get incl = grub_config) incls in
      if not incls_contains_conf then (
        g#aug_set "/augeas/load/Grub/incl[last()+1]" grub_config;
        Linux.augeas_reload verbose g;
      )

    | `Grub2 -> () (* Not necessary for grub2. *)

  and autorelabel () =
    (* Only do autorelabel if load_policy binary exists.  Actually
     * loading the policy is problematic.
     *)
    if g#is_file ~followsymlinks:true "/usr/sbin/load_policy" then
      g#touch "/.autorelabel";

  and unconfigure_xen () =
    (* Remove kmod-xenpv-* (RHEL 3). *)
    let xenmods =
      filter_map (
        fun { G.app2_name = name } ->
          if name = "kmod-xenpv" || string_prefix name "kmod-xenpv-" then
            Some name
          else
            None
      ) inspect.i_apps in
    Linux.remove verbose g inspect xenmods;

    (* Undo related nastiness if kmod-xenpv was installed. *)
    if xenmods <> [] then (
      (* kmod-xenpv modules may have been manually copied to other kernels.
       * Hunt them down and destroy them.
       *)
      let dirs = g#find "/lib/modules" in
      let dirs = Array.to_list dirs in
      let dirs = List.filter (fun s -> string_find s "/xenpv" >= 0) dirs in
      let dirs = List.map ((^) "/lib/modules/") dirs in
      let dirs = List.filter g#is_dir dirs in

      (* Check it's not owned by an installed application. *)
      let dirs = List.filter (
        fun d -> not (Linux.is_file_owned verbose g inspect d)
      ) dirs in

      (* Remove any unowned xenpv directories. *)
      List.iter g#rm_rf dirs;

      (* rc.local may contain an insmod or modprobe of the xen-vbd driver,
       * added by an installation script.
       *)
      (try
         let lines = g#read_lines "/etc/rc.local" in
         let lines = Array.to_list lines in
         let rex = Str.regexp ".*\\b\\(insmod|modprobe\\)\b.*\\bxen-vbd.*" in
         let lines = List.map (
           fun s ->
             if Str.string_match rex s 0 then
               "#" ^ s
             else
               s
         ) lines in
         let file = String.concat "\n" lines ^ "\n" in
         g#write "/etc/rc.local" file
       with
         G.Error msg -> eprintf "%s: /etc/rc.local: %s (ignored)\n" prog msg
      );
    );

    if family = `SUSE_family then (
      (* Remove xen modules from INITRD_MODULES and DOMU_INITRD_MODULES. *)
      let variables = ["INITRD_MODULES"; "DOMU_INITRD_MODULES"] in
      let xen_modules = ["xennet"; "xen-vnif"; "xenblk"; "xen-vbd"] in
      let modified = ref false in
      List.iter (
        fun var ->
          List.iter (
            fun xen_mod ->
              let expr =
                sprintf "/file/etc/sysconfig/kernel/%s/value[. = '%s']"
                  var xen_mod in
              let entries = g#aug_match expr in
              let entries = Array.to_list entries in
              if entries <> [] then (
                List.iter (fun e -> ignore (g#aug_rm e)) entries;
                modified := true
              )
          ) xen_modules
      ) variables;
      if !modified then g#aug_save ()
    );

  and unconfigure_vbox () =
    (* Uninstall VirtualBox Guest Additions. *)
    let package_name = "virtualbox-guest-additions" in
    let has_guest_additions =
      List.exists (
        fun { G.app2_name = name } -> name = package_name
      ) inspect.i_apps in
    if has_guest_additions then
      Linux.remove verbose g inspect [package_name];

    (* Guest Additions might have been installed from a tarball.  The
     * above code won't detect this case.  Look for the uninstall tool
     * and try running it.
     *
     * Note that it's important we do this early in the conversion
     * process, as this uninstallation script naively overwrites
     * configuration files with versions it cached prior to
     * installation.
     *)
    let vboxconfig = "/var/lib/VBoxGuestAdditions/config" in
    if g#is_file ~followsymlinks:true vboxconfig then (
      let lines = g#read_lines vboxconfig in
      let lines = Array.to_list lines in
      let rex = Str.regexp "^INSTALL_DIR=\\(.*\\)$" in
      let lines = filter_map (
        fun line ->
          if Str.string_match rex line 0 then (
            let vboxuninstall = Str.matched_group 1 line ^ "/uninstall.sh" in
            Some vboxuninstall
          )
          else None
      ) lines in
      let lines = List.filter (g#is_file ~followsymlinks:true) lines in
      match lines with
      | [] -> ()
      | vboxuninstall :: _ ->
        try
          ignore (g#command [| vboxuninstall |]);

          (* Reload Augeas to detect changes made by vbox tools uninst. *)
          Linux.augeas_reload verbose g
        with
          G.Error msg ->
            warning ~prog (f_"VirtualBox Guest Additions were detected, but uninstallation failed.  The error message was: %s (ignored)")
              msg
    )

(* Disabled in RHEL 7.1: see https://bugzilla.redhat.com/show_bug.cgi?id=1155610
  and unconfigure_vmware () =
    (* Look for any configured VMware yum repos and disable them. *)
    let repos =
      g#aug_match "/files/etc/yum.repos.d/*/*[baseurl =~ regexp('https?://([^/]+\\.)?vmware\\.com/.*')]" in
    let repos = Array.to_list repos in
    List.iter (
      fun repo ->
        g#aug_set (repo ^ "/enabled") "0";
        g#aug_save ()
    ) repos;

    (* Uninstall VMware Tools. *)
    let remove = ref [] and libraries = ref [] in
    List.iter (
      fun { G.app2_name = name } ->
        if string_prefix name "vmware-tools-libraries-" then
          libraries := name :: !libraries
        else if string_prefix name "vmware-tools-" then
          remove := name :: !remove
        else if name = "VMwareTools" then
          remove := name :: !remove
        else if string_prefix name "kmod-vmware-tools" then
          remove := name :: !remove
    ) inspect.i_apps;
    let libraries = !libraries in

    (* VMware tools includes 'libraries' packages which provide custom
     * versions of core functionality. We need to install non-custom
     * versions of everything provided by these packages before
     * attempting to uninstall them, or we'll hit dependency
     * issues.
     *)
    if libraries <> [] then (
      (* We only support removal of libraries on systems which use yum. *)
      if inspect.i_package_management = "yum" then (
        List.iter (
          fun library ->
            let provides =
              g#command_lines [| "rpm"; "-q"; "--provides"; library |] in
            let provides = Array.to_list provides in

            (* The packages provide themselves, filter this out. *)
            let provides =
              List.filter (fun s -> string_find s library = -1) provides in

            (* Trim whitespace. *)
            let rex = Str.regexp "^[ \\t]*\\([^ \\t]+\\)[ \\t]*$" in
            let provides = List.map (Str.replace_first rex "\\1") provides in

            (* Install the dependencies with yum.  Use yum explicitly
             * because we don't have package names and local install is
             * impractical.
             *)
            let cmd = ["yum"; "-q"; "resolvedep"] @ provides in
            let cmd = Array.of_list cmd in
            let replacements = g#command_lines cmd in
            let replacements = Array.to_list replacements in

            let cmd = [ "yum"; "install"; "-y" ] @ replacements in
            let cmd = Array.of_list cmd in
            (try
               ignore (g#command cmd);
               remove := library :: !remove
             with G.Error msg ->
               eprintf "%s: could not install replacement for %s.  Error was: %s.  %s was not removed.\n"
                 prog library msg library
            );
        ) libraries
      )
    );

    let remove = !remove in
    Linux.remove verbose g inspect remove;

    (* VMware Tools may have been installed from a tarball, so the
     * above code won't remove it.  Look for the uninstall tool and run
     * if present.
     *)
    let uninstaller = "/usr/bin/vmware-uninstall-tools.pl" in
    if g#is_file ~followsymlinks:true uninstaller then (
      try
        ignore (g#command [| uninstaller |]);

        (* Reload Augeas to detect changes made by vbox tools uninst. *)
        Linux.augeas_reload verbose g
      with
        G.Error msg ->
          warning ~prog (f_"VMware tools was detected, but uninstallation failed.  The error message was: %s (ignored)")
            msg
    )
*)

  and unconfigure_citrix () =
    let pkgs =
      List.filter (
        fun { G.app2_name = name } -> string_prefix name "xe-guest-utilities"
      ) inspect.i_apps in
    let pkgs = List.map (fun { G.app2_name = name } -> name) pkgs in

    if pkgs <> [] then (
      Linux.remove verbose g inspect pkgs;

      (* Installing these guest utilities automatically unconfigures
       * ttys in /etc/inittab if the system uses it. We need to put
       * them back.
       *)
      let rex = Str.regexp "^\\([1-6]\\):\\([2-5]+\\):respawn:\\(.*\\)" in
      let updated = ref false in
      let rec loop () =
        let comments = g#aug_match "/files/etc/inittab/#comment" in
        let comments = Array.to_list comments in
        match comments with
        | [] -> ()
        | commentp :: _ ->
          let comment = g#aug_get commentp in
          if Str.string_match rex comment 0 then (
            let name = Str.matched_group 1 comment in
            let runlevels = Str.matched_group 2 comment in
            let process = Str.matched_group 3 comment in

            if string_find process "getty" >= 0 then (
              updated := true;

              (* Create a new entry immediately after the comment. *)
              g#aug_insert commentp name false;
              g#aug_set ("/files/etc/inittab/" ^ name ^ "/runlevels") runlevels;
              g#aug_set ("/files/etc/inittab/" ^ name ^ "/action") "respawn";
              g#aug_set ("/files/etc/inittab/" ^ name ^ "/process") process;

              (* Delete the comment node. *)
              ignore (g#aug_rm commentp);

              (* As the aug_rm invalidates the output of aug_match, we
               * now have to restart the whole loop.
               *)
              loop ()
            )
          )
      in
      loop ();
      if !updated then g#aug_save ();
    )

  and unconfigure_kudzu () =
    (* Disable kudzu in the guest
     * Kudzu will detect the changed network hardware at boot time and
     * either:
     * - require manual intervention, or
     * - disable the network interface
     * Neither of these behaviours is desirable.
     *)
    if g#is_file ~followsymlinks:true "/etc/init.d/kudzu"
      && g#is_file ~followsymlinks:true "/sbin/chkconfig" then (
        ignore (g#command [| "/sbin/chkconfig"; "kudzu"; "off" |])
      )

  and configure_kernel () =
    (* Previously this function would try to install kernels, but we
     * don't do that any longer.
     *)

    (* Check a non-Xen kernel exists. *)
    let only_xen_kernels = List.for_all (
      fun { ki_is_xen_kernel = is_xen_kernel } -> is_xen_kernel
    ) grub_kernels in
    if only_xen_kernels then
      error (f_"only Xen kernels are installed in this guest.\n\nRead the %s(1) manual, section \"XEN PARAVIRTUALIZED GUESTS\", to see what to do.") prog;

    (* Enable the best non-Xen kernel, where "best" means the one with
     * the highest version which supports virtio.
     *)
    let best_kernel =
      let compare_best_kernels k1 k2 =
        let i = compare k1.ki_supports_virtio k2.ki_supports_virtio in
        if i <> 0 then i
        else (
          let i = compare_app2_versions k1.ki_app k2.ki_app in
          if i <> 0 then i
          (* Favour non-debug kernels over debug kernels (RHBZ#1170073). *)
          else compare k2.ki_is_debug k1.ki_is_debug
        )
      in
      let kernels = grub_kernels in
      let kernels = List.filter (fun { ki_is_xen_kernel = is_xen_kernel } -> not is_xen_kernel) kernels in
      let kernels = List.sort compare_best_kernels kernels in
      let kernels = List.rev kernels (* so best is first *) in
      List.hd kernels in
    if best_kernel <> List.hd grub_kernels then
      grub_set_bootable best_kernel;

    (* Does the best/bootable kernel support virtio? *)
    let virtio = best_kernel.ki_supports_virtio in

    best_kernel, virtio

  and grub_set_bootable kernel =
    match grub with
    | `Grub1 ->
      if not (string_prefix kernel.ki_vmlinuz grub_prefix) then
        error (f_"kernel %s is not under grub tree %s")
          kernel.ki_vmlinuz grub_prefix;
      let kernel_under_grub_prefix =
        let prefix_len = String.length grub_prefix in
        let kernel_len = String.length kernel.ki_vmlinuz in
        String.sub kernel.ki_vmlinuz prefix_len (kernel_len - prefix_len) in

      (* Find the grub entry for the given kernel. *)
      let paths = g#aug_match (sprintf "/files%s/title/kernel[. = '%s']"
                                 grub_config kernel_under_grub_prefix) in
      let paths = Array.to_list paths in
      if paths = [] then
        error (f_"didn't find grub entry for kernel %s") kernel.ki_vmlinuz;
      let path = List.hd paths in
      let rex = Str.regexp ".*/title\\[\\([1-9][0-9]*\\)\\]/kernel" in
      if not (Str.string_match rex path 0) then
        error (f_"internal error: regular expression did not match '%s'")
          path;
      let index = int_of_string (Str.matched_group 1 path) - 1 in
      g#aug_set (sprintf "/files%s/default" grub_config) (string_of_int index);
      g#aug_save ()

    | `Grub2 ->
      let cmd =
        if g#exists "/sbin/grubby" then
          [| "grubby"; "--set-default"; kernel.ki_vmlinuz |]
        else
          [| "/usr/bin/perl"; "-MBootloader::Tools"; "-e"; sprintf "
              InitLibrary();
              my @sections = GetSectionList(type=>image, image=>\"%s\");
              my $section = GetSection(@sections);
              my $newdefault = $section->{name};
              SetGlobals(default, \"$newdefault\");
            " kernel.ki_vmlinuz |] in
      ignore (g#command cmd)

  (* Even though the kernel was already installed (this version of
   * virt-v2v does not install new kernels), it could have an
   * initrd that does not have support virtio.  Therefore rebuild
   * the initrd.
   *)
  and rebuild_initrd kernel =
    match kernel.ki_initrd with
    | None -> ()
    | Some initrd ->
      let virtio = kernel.ki_supports_virtio in
      let modules =
        if virtio then
          (* The order of modules here is deliberately the same as the
           * order specified in the postinstall script of kmod-virtio in
           * RHEL3. The reason is that the probing order determines the
           * major number of vdX block devices. If we change it, RHEL 3
           * KVM guests won't boot.
           *)
          [ "virtio"; "virtio_ring"; "virtio_blk"; "virtio_net";
            "virtio_pci" ]
        else
          [ "sym53c8xx" (* XXX why not "ide"? *) ] in

      (* Move the old initrd file out of the way.  Note that dracut/mkinitrd
       * will refuse to overwrite an old file so we have to do this.
       *)
      g#mv initrd (initrd ^ ".pre-v2v");

      (* dracut and mkinitrd want what they call the "kernel version".  What
       * they actually mean is the last element of the module path
       * (eg. /lib/modules/2.6.32-496.el6.x86_64 -> 2.6.32-496.el6.x86_64)
       * which might include the arch.  Get that here.
       *)
      let mkinitrd_kv =
        let modpath = kernel.ki_modpath in
        let len = String.length modpath in
        try
          let i = String.rindex modpath '/' in
          String.sub modpath (i+1) (len - (i+1))
        with
          Not_found ->
            invalid_arg (sprintf "invalid module path: %s" modpath) in

      if g#is_file ~followsymlinks:true "/sbin/dracut" then (
        (* Dracut. *)
        ignore (
          g#command [| "/sbin/dracut";
                       "--add-drivers"; String.concat " " modules;
                       initrd; mkinitrd_kv |]
        )
      )
      else if family = `SUSE_family
           && g#is_file ~followsymlinks:true "/sbin/mkinitrd" then (
        ignore (
          g#command [| "/sbin/mkinitrd";
                       "-m"; String.concat " " modules;
                       "-i"; initrd;
                       "-k"; kernel.ki_vmlinuz |]
        )
      )
      else if g#is_file ~followsymlinks:true "/sbin/mkinitrd" then (
        let module_args = List.map (sprintf "--with=%s") modules in
        let args =
          [ "/sbin/mkinitrd" ] @ module_args @ [ initrd; mkinitrd_kv ] in

        (* We explicitly modprobe ext2 here. This is required by
         * mkinitrd on RHEL 3, and shouldn't hurt on other OSs. We
         * don't care if this fails.
         *)
        (try g#modprobe "ext2" with G.Error _ -> ());

        (* loop is a module in RHEL 5. Try to load it. Doesn't matter
         * for other OSs if it doesn't exist, but RHEL 5 will complain:
         *   "All of your loopback devices are in use."
         *)
        (try g#modprobe "loop" with G.Error _ -> ());

        (* On RHEL 3 we have to take extra gritty to get a working
         * loopdev.  mkinitrd runs the nash command `findlodev'
         * which does this:
         *
         * for (devNum = 0; devNum < 256; devNum++) {
         *   sprintf(devName, "/dev/loop%s%d", separator, devNum);
         *   if ((fd = open(devName, O_RDONLY)) < 0) return 0;
         *   if (ioctl(fd, LOOP_GET_STATUS, &loopInfo)) {
         *     close(fd);
         *     printf("%s\n", devName);
         *     return 0;
         * // etc
         *
         * In a modern kernel, /dev/loop<N> isn't created until it is
         * used.  But we can create /dev/loop0 manually.  Note we have
         * to do this in the appliance /dev.  (RHBZ#1171130)
         *)
        if family = `RHEL_family && inspect.i_major_version = 3 then
          ignore (g#debug "sh" [| "mknod"; "-m"; "0666";
                                  "/dev/loop0"; "b"; "7"; "0" |]);

        (* RHEL 4 mkinitrd determines if the root filesystem is on LVM
         * by checking if the device name (after following symlinks)
         * starts with /dev/mapper. However, on recent kernels/udevs,
         * /dev/mapper/foo is just a symlink to /dev/dm-X. This means
         * that RHEL 4 mkinitrd running in the appliance fails to
         * detect root on LVM. We check ourselves if root is on LVM,
         * and frig RHEL 4's mkinitrd if it is by setting root_lvm=1 in
         * its environment. This overrides an internal variable in
         * mkinitrd, and is therefore extremely nasty and applicable
         * only to a particular version of mkinitrd.
         *)
        let env =
          if family = `RHEL_family && inspect.i_major_version = 4 then
            Some "root_lvm=1"
          else
            None in

        match env with
        | None -> ignore (g#command (Array.of_list args))
        | Some env ->
          let cmd = sprintf "sh -c '%s %s'" env (String.concat " " args) in
          ignore (g#sh cmd)
      )
      else (
        error (f_"unable to rebuild initrd (%s) because mkinitrd or dracut was not found in the guest")
          initrd
      )

  (* We configure a console on ttyS0. Make sure existing console
   * references use it.  N.B. Note that the RHEL 6 xen guest kernel
   * presents a console device called /dev/hvc0, whereas previous xen
   * guest kernels presented /dev/xvc0. The regular kernel running
   * under KVM also presents a virtio console device called /dev/hvc0,
   * so ideally we would just leave it alone. However, RHEL 6 libvirt
   * doesn't yet support this device so we can't attach to it. We
   * therefore use /dev/ttyS0 for RHEL 6 anyway.
   *)
  and configure_console () =
    (* Look for gettys using xvc0 or hvc0.  RHEL 6 doesn't use inittab
     * but this still works.
     *)
    let paths = g#aug_match "/files/etc/inittab/*/process" in
    let paths = Array.to_list paths in
    let rex = Str.regexp "\\(.*\\)\\b\\([xh]vc0\\)\\b\\(.*\\)" in
    List.iter (
      fun path ->
        let proc = g#aug_get path in
        if Str.string_match rex proc 0 then (
          let proc = Str.global_replace rex "\\1ttyS0\\3" proc in
          g#aug_set path proc
        );
    ) paths;

    let paths = g#aug_match "/files/etc/securetty/*" in
    let paths = Array.to_list paths in
    List.iter (
      fun path ->
        let tty = g#aug_get path in
        if tty = "xvc0" || tty = "hvc0" then
          g#aug_set path "ttyS0"
    ) paths;

    g#aug_save ()

  and grub_configure_console () =
    match grub with
    | `Grub1 ->
      let rex = Str.regexp "\\(.*\\)\\b\\([xh]vc0\\)\\b\\(.*\\)" in
      let expr = sprintf "/files%s/title/kernel/console" grub_config in

      let paths = g#aug_match expr in
      let paths = Array.to_list paths in
      List.iter (
        fun path ->
          let console = g#aug_get path in
          if Str.string_match rex console 0 then (
            let console = Str.global_replace rex "\\1ttyS0\\3" console in
            g#aug_set path console
          )
      ) paths;

      g#aug_save ()

    | `Grub2 ->
      grub2_update_console ~remove:false

  (* If the target doesn't support a serial console, we want to remove
   * all references to it instead.
   *)
  and remove_console () =
    (* Look for gettys using xvc0 or hvc0.  RHEL 6 doesn't use inittab
     * but this still works.
     *)
    let paths = g#aug_match "/files/etc/inittab/*/process" in
    let paths = Array.to_list paths in
    let rex = Str.regexp ".*\\b\\([xh]vc0|ttyS0\\)\\b.*" in
    List.iter (
      fun path ->
        let proc = g#aug_get path in
        if Str.string_match rex proc 0 then
          ignore (g#aug_rm (path ^ "/.."))
    ) paths;

    let paths = g#aug_match "/files/etc/securetty/*" in
    let paths = Array.to_list paths in
    List.iter (
      fun path ->
        let tty = g#aug_get path in
        if tty = "xvc0" || tty = "hvc0" then
          ignore (g#aug_rm path)
    ) paths;

    g#aug_save ()

  and grub_remove_console () =
    match grub with
    | `Grub1 ->
      let rex = Str.regexp "\\(.*\\)\\b\\([xh]vc0\\)\\b\\(.*\\)" in
      let expr = sprintf "/files%s/title/kernel/console" grub_config in

      let rec loop = function
        | [] -> ()
        | path :: paths ->
          let console = g#aug_get path in
          if Str.string_match rex console 0 then (
            ignore (g#aug_rm path);
            (* All the paths are invalid, restart the loop. *)
            let paths = g#aug_match expr in
            let paths = Array.to_list paths in
            loop paths
          )
          else
            loop paths
      in
      let paths = g#aug_match expr in
      let paths = Array.to_list paths in
      loop paths;

      g#aug_save ()

    | `Grub2 ->
      grub2_update_console ~remove:true

  and grub2_update_console ~remove =
    let rex = Str.regexp "\\(.*\\)\\bconsole=[xh]vc0\\b\\(.*\\)" in

    let paths = [
      "/files/etc/sysconfig/grub/GRUB_CMDLINE_LINUX";
      "/files/etc/default/grub/GRUB_CMDLINE_LINUX";
      "/files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT"
    ] in
    let paths = List.map g#aug_match paths in
    let paths = List.map Array.to_list paths in
    let paths = List.flatten paths in
    match paths with
    | [] ->
      if not remove then
        warning ~prog (f_"could not add grub2 serial console (ignored)")
      else
        warning ~prog (f_"could not remove grub2 serial console (ignored)")
    | path :: _ ->
      let grub_cmdline = g#aug_get path in
      if Str.string_match rex grub_cmdline 0 then (
        let new_grub_cmdline =
          if not remove then
            Str.global_replace rex "\\1console=ttyS0\\3" grub_cmdline
          else
            Str.global_replace rex "\\1\\3" grub_cmdline in
        g#aug_set path new_grub_cmdline;
        g#aug_save ();

        try
          ignore (g#command [| "grub2-mkconfig"; "-o"; grub_config |])
        with
          G.Error msg ->
            warning ~prog (f_"could not rebuild grub2 configuration file (%s).  This may mean that grub output will not be sent to the serial port, but otherwise should be harmless.  Original error message: %s")
              grub_config msg
      )

  and supports_acpi () =
    (* ACPI known to cause RHEL 3 to fail. *)
    if family = `RHEL_family && inspect.i_major_version == 3 then
      false
    else
      true

  and get_display_driver () =
    if family = `SUSE_family then Cirrus else QXL

  and configure_display_driver video =
    let video_driver = match video with QXL -> "qxl" | Cirrus -> "cirrus" in

    let updated = ref false in

    let xorg_conf =
      if not (g#is_file ~followsymlinks:true "/etc/X11/xorg.conf") &&
        g#is_file ~followsymlinks:true "/etc/X11/XF86Config"
      then (
        g#aug_set "/augeas/load/Xorg/incl[last()+1]" "/etc/X11/XF86Config";
        g#aug_load ();
        "/etc/X11/XF86Config"
        )
      else
        "/etc/X11/xorg.conf" in

    let paths = g#aug_match ("/files" ^ xorg_conf ^ "/Device/Driver") in
    Array.iter (
      fun path ->
        g#aug_set path video_driver;
        updated := true
    ) paths;

    (* Remove VendorName and BoardName if present. *)
    let paths = g#aug_match ("/files" ^ xorg_conf ^ "/Device/VendorName") in
    Array.iter (fun path -> ignore (g#aug_rm path)) paths;
    let paths = g#aug_match ("/files" ^ xorg_conf ^ "/Device/BoardName") in
    Array.iter (fun path -> ignore (g#aug_rm path)) paths;

    g#aug_save ();

    (* If we updated the X driver, checkthat X itself is installed,
     * and warn if not.  Old virt-v2v used to attempt to install X here
     * but that way lies insanity and ruin.
     *)
    if !updated &&
      not (g#is_file ~followsymlinks:true "/usr/bin/X") &&
      not (g#is_file ~followsymlinks:true "/usr/bin/X11/X") then
      warning ~prog
        (f_"The display driver was updated to '%s', but X11 does not seem to be installed in the guest.  X may not function correctly.")
        video_driver

  and configure_kernel_modules virtio =
    (* This function modifies modules.conf (and its various aliases). *)

    (* Update 'alias eth0 ...'. *)
    let paths = augeas_modprobe ". =~ regexp('eth[0-9]+')" in
    let net_device = if virtio then "virtio_net" else "e1000" in
    List.iter (
      fun path -> g#aug_set (path ^ "/modulename") net_device
    ) paths;

    (* Update 'alias scsi_hostadapter ...' *)
    let paths = augeas_modprobe ". =~ regexp('scsi_hostadapter.*')" in
    if virtio then (
      if paths <> [] then (
        (* There's only 1 scsi controller in the converted guest.
         * Convert only the first scsi_hostadapter entry to virtio
         * and delete other scsi_hostadapter entries.
         *)
        let path, paths_to_delete = List.hd paths, List.tl paths in

        (* Note that we delete paths in reverse order. This means we don't
         * have to worry about alias indices being changed.
         *)
        List.iter (fun path -> ignore (g#aug_rm path))
          (List.rev paths_to_delete);

        g#aug_set (path ^ "/modulename") "virtio_blk"
      ) else (
        (* We have to add a scsi_hostadapter. *)
        let modpath = discover_modpath () in
        g#aug_set (sprintf "/files%s/alias[last()+1]" modpath)
          "scsi_hostadapter";
        g#aug_set (sprintf "/files%s/alias[last()]/modulename" modpath)
          "virtio_blk"
      )
    ) else (* not virtio *) (
      (* There is no scsi controller in an IDE guest. *)
      List.iter (fun path -> ignore (g#aug_rm path)) (List.rev paths)
    );

    (* Display a warning about any leftover Xen modules which we
     * haven't converted.  These are likely to cause an error when
     * we run mkinitrd.
     *)
    let xen_modules = [ "xennet"; "xen-vnif"; "xenblk"; "xen-vbd" ] in
    let query =
      "modulename =~ regexp('" ^ String.concat "|" xen_modules ^ "')" in
    let paths = augeas_modprobe query in
    List.iter (
      fun path ->
        let device = g#aug_get path in
        let module_ = g#aug_get (path ^ "/modulename") in
        warning ~prog (f_"don't know how to update %s which loads the %s module")
          device module_;
    ) paths;

    (* Update files. *)
    g#aug_save ()

  and augeas_modprobe query =
    (* Execute g#aug_match, but against every known location of modules.conf. *)
    let paths = [
      "/files/etc/conf.modules/alias";
      "/files/etc/modules.conf/alias";
      "/files/etc/modprobe.conf/alias";
      "/files/etc/modprobe.d/*/alias";
    ] in
    let paths =
      List.map (
        fun p ->
          let p = sprintf "%s[%s]" p query in
          Array.to_list (g#aug_match p)
      ) paths in
    List.flatten paths

  and discover_modpath () =
    (* Find what /etc/modprobe.conf is called today. *)
    let modpath = ref "" in

    (* Note that we're checking in ascending order of preference so
     * that the last discovered method will be chosen.
     *)
    List.iter (
      fun file ->
        if g#is_file ~followsymlinks:true file then
          modpath := file
    ) [ "/etc/conf.modules"; "/etc/modules.conf" ];

    if g#is_file ~followsymlinks:true "/etc/modprobe.conf" then
      modpath := "modprobe.conf";

    if g#is_dir ~followsymlinks:true "/etc/modprobe.d" then
      (* Create a new file /etc/modprobe.d/virt-v2v-added.conf. *)
      modpath := "modprobe.d/virt-v2v-added.conf";

    if !modpath = "" then
      error (f_"unable to find any valid modprobe configuration file such as /etc/modprobe.conf");

    !modpath

  and remap_block_devices virtio =
    (* This function's job is to iterate over boot configuration
     * files, replacing "hda" with "vda" or whatever is appropriate.
     * This is mostly applicable to old guests, since newer OSes use
     * LABEL or UUID where possible.
     *
     * The original Convert::Linux::_remap_block_devices function was
     * very complex indeed.  This drops most of the complexity.  In
     * particular it assumes all non-removable source disks will be
     * added to the target in the order they appear in the libvirt XML.
     *)
    let ide_block_prefix =
      match family, inspect.i_major_version with
      | `RHEL_family, v when v < 5 ->
        (* RHEL < 5 used old ide driver *) "hd"
      | `RHEL_family, 5 ->
        (* RHEL 5 uses libata, but udev still uses: *) "hd"
      | `SUSE_family, _ ->
        (* SUSE uses libata, but still presents IDE disks as: *) "hd"
      | _, _ ->
        (* All modern distros use libata: *) "sd" in

    let block_prefix_after_conversion =
      if virtio then "vd" else ide_block_prefix in

    let map =
      mapi (
        fun i disk ->
          let block_prefix_before_conversion =
            match disk.s_controller with
            | Some Source_IDE -> ide_block_prefix
            | Some Source_SCSI -> "sd"
            | Some Source_virtio_blk -> "vd"
            | None ->
              (* This is basically a guess.  It assumes the source used IDE. *)
              ide_block_prefix in
          let source_dev = block_prefix_before_conversion ^ drive_name i in
          let target_dev = block_prefix_after_conversion ^ drive_name i in
          source_dev, target_dev
      ) source.s_disks in

    (* If a Xen guest has non-PV devices, Xen also simultaneously
     * presents these as xvd devices. i.e. hdX and xvdX both exist and
     * are the same device.
     *
     * This mapping is also useful for P2V conversion of Citrix
     * Xenserver guests done in HVM mode. Disks are detected as sdX,
     * although the guest uses xvdX natively.
     *)
    let map = map @
      mapi (
        fun i disk ->
          "xvd" ^ drive_name i, block_prefix_after_conversion ^ drive_name i
      ) source.s_disks in

    if verbose then (
      printf "block device map:\n";
      List.iter (
        fun (source_dev, target_dev) ->
          printf "\t%s\t-> %s\n" source_dev target_dev
      ) (List.sort (fun (a,_) (b,_) -> compare a b) map);
      flush stdout
    );

    (* Possible Augeas paths to search for device names. *)
    let paths = [
      (* /etc/fstab *)
      "/files/etc/fstab/*/spec";

      (* grub-legacy config *)
      "/files" ^ grub_config ^ "/*/kernel/root";
      "/files" ^ grub_config ^ "/*/kernel/resume";
      "/files/boot/grub/device.map/*[label() != \"#comment\"]";
      "/files/etc/sysconfig/grub/boot";

      (* grub2 config *)
      "/files/etc/sysconfig/grub/GRUB_CMDLINE_LINUX";
      "/files/etc/default/grub/GRUB_CMDLINE_LINUX";
      "/files/etc/default/grub/GRUB_CMDLINE_LINUX_DEFAULT";
      "/files/boot/grub2/device.map/*[label() != \"#comment\"]";
    ] in

    (* Which of these paths actually exist? *)
    let paths =
      List.flatten (List.map Array.to_list (List.map g#aug_match paths)) in

    (* Map device names for each entry. *)
    let rex_resume = Str.regexp "^\\(.*resume=\\)\\(/dev/[^ ]\\)\\(.*\\)$"
    and rex_device_cciss_p =
      Str.regexp "^/dev/\\(cciss/c[0-9]+d[0-9]+\\)p\\([0-9]+\\)$"
    and rex_device_cciss =
      Str.regexp "^/dev/\\(cciss/c[0-9]+d[0-9]+\\)$"
    and rex_device_p =
      Str.regexp "^/dev/\\([a-z]+\\)\\([0-9]+\\)$"
    and rex_device =
      Str.regexp "^/dev/\\([a-z]+\\)$" in

    let rec replace_if_device path value =
      let replace device =
        try List.assoc device map
        with Not_found ->
          if string_find device "md" = -1 && string_find device "fd" = -1 &&
            device <> "cdrom" then
            warning ~prog (f_"%s references unknown device \"%s\".  You may have to fix this entry manually after conversion.")
              path device;
          device
      in

      if string_find path "GRUB_CMDLINE" >= 0 then (
        (* Handle grub2 resume=<dev> specially. *)
        if Str.string_match rex_resume value 0 then (
          let start = Str.matched_group 1 value
          and device = Str.matched_group 2 value
          and end_ = Str.matched_group 3 value in
          let device = replace_if_device path device in
          start ^ device ^ end_
        )
        else value
      )
      else if Str.string_match rex_device_cciss_p value 0 then (
        let device = Str.matched_group 1 value
        and part = Str.matched_group 2 value in
        "/dev/" ^ replace device ^ part
      )
      else if Str.string_match rex_device_cciss value 0 then (
        let device = Str.matched_group 1 value in
        "/dev/" ^ replace device
      )
      else if Str.string_match rex_device_p value 0 then (
        let device = Str.matched_group 1 value
        and part = Str.matched_group 2 value in
        "/dev/" ^ replace device ^ part
      )
      else if Str.string_match rex_device value 0 then (
        let device = Str.matched_group 1 value in
        "/dev/" ^ replace device
      )
      else (* doesn't look like a known device name *)
        value
    in

    let changed = ref false in
    List.iter (
      fun path ->
        let value = g#aug_get path in
        let new_value = replace_if_device path value in

        if value <> new_value then (
          g#aug_set path new_value;
          changed := true
        )
    ) paths;

    if !changed then (
      g#aug_save ();

      (* If it's grub2, we have to regenerate the config files. *)
      if grub = `Grub2 then
        ignore (g#command [| "grub2-mkconfig"; "-o"; grub_config |]);

      Linux.augeas_reload verbose g
    );

    (* Delete blkid caches if they exist, since they will refer to the old
     * device names.  blkid will rebuild these on demand.
     *
     * Delete the LVM cache since it will contain references to the
     * old devices (RHBZ#1164853).
     *)
    List.iter g#rm_f [
      "/etc/blkid/blkid.tab"; "/etc/blkid.tab";
      "/etc/lvm/cache/.cache"
    ];
  in

  augeas_grub_configuration ();
  autorelabel ();

  unconfigure_xen ();
  unconfigure_vbox ();
  (*unconfigure_vmware ();*)
  unconfigure_citrix ();
  unconfigure_kudzu ();

  let kernel, virtio = configure_kernel () in

  if keep_serial_console then (
    configure_console ();
    grub_configure_console ();
  ) else (
    remove_console ();
    grub_remove_console ();
  );

  let acpi = supports_acpi () in

  let video = get_display_driver () in
  configure_display_driver video;
  remap_block_devices virtio;
  configure_kernel_modules virtio;
  rebuild_initrd kernel;

  let guestcaps = {
    gcaps_block_bus = if virtio then Virtio_blk else IDE;
    gcaps_net_bus = if virtio then Virtio_net else E1000;
    gcaps_video = video;
    gcaps_arch = Utils.kvm_arch inspect.i_arch;
    gcaps_acpi = acpi;
  } in

  guestcaps

let () =
  let matching = function
    | { i_type = "linux";
        i_distro = ("fedora"
                       | "rhel" | "centos" | "scientificlinux" | "redhat-based"
                       | "sles" | "suse-based" | "opensuse") } -> true
    | _ -> false
  in
  Modules_list.register_convert_module matching "enterprise-linux" convert
