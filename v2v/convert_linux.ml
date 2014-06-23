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

open Printf

open Common_gettext.Gettext
open Common_utils

open Utils
open Types

module G = Guestfs

let rec convert ?(keep_serial_console = true) verbose (g : G.guestfs)
    ({ i_root = root; i_apps = apps; i_apps_map = apps_map }
        as inspect) source =
  let typ = g#inspect_get_type root
  and distro = g#inspect_get_distro root
  and arch = g#inspect_get_arch root
  and major_version = g#inspect_get_major_version root
  and minor_version = g#inspect_get_minor_version root
  and package_format = g#inspect_get_package_format root
  and package_management = g#inspect_get_package_management root in

  assert (typ = "linux");

  let is_rhel_family =
    (distro = "rhel" || distro = "centos"
            || distro = "scientificlinux" || distro = "redhat-based")

  and is_suse_family =
    (distro = "sles" || distro = "suse-based" || distro = "opensuse") in

  let rec clean_rpmdb () =
    (* Clean RPM database. *)
    assert (package_format = "rpm");
    let dbfiles = g#glob_expand "/var/lib/rpm/__db.00?" in
    let dbfiles = Array.to_list dbfiles in
    List.iter g#rm_f dbfiles

  and autorelabel () =
    (* Only do autorelabel if load_policy binary exists.  Actually
     * loading the policy is problematic.
     *)
    if g#is_file ~followsymlinks:true "/usr/sbin/load_policy" then
      g#touch "/.autorelabel";

  and get_grub () =
    (* Detect if grub2 or grub1 is installed by trying to create
     * an object of each sort.
     *)
    try Convert_linux_grub.grub2 verbose g inspect
    with Failure grub2_error ->
      try Convert_linux_grub.grub1 verbose g inspect
      with Failure grub1_error ->
        error (f_"no grub configuration found in this guest.
Grub2 error was: %s
Grub1/grub-legacy error was: %s")
          grub2_error grub1_error

  and unconfigure_xen () =
    (* Remove kmod-xenpv-* (RHEL 3). *)
    let xenmods =
      filter_map (
        fun { G.app2_name = name } ->
          if name = "kmod-xenpv" || string_prefix name "kmod-xenpv-" then
            Some name
          else
            None
      ) apps in
    Lib_linux.remove verbose g inspect xenmods;

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
        fun d -> not (Lib_linux.is_file_owned verbose g inspect d)
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

    if is_suse_family then (
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
      ) apps in
    if has_guest_additions then
      Lib_linux.remove verbose g inspect [package_name];

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
          Lib_linux.augeas_reload verbose g
        with
          G.Error msg ->
            warning ~prog (f_"VirtualBox Guest Additions were detected, but uninstallation failed.  The error message was: %s (ignored)")
              msg
    )

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
        if name = "open-vm-tools" then
          remove := name :: !remove
        else if string_prefix name "vmware-tools-libraries-" then
          libraries := name :: !libraries
        else if string_prefix name "vmware-tools-" then
          remove := name :: !remove
    ) apps;
    let libraries = !libraries in

    (* VMware tools includes 'libraries' packages which provide custom
     * versions of core functionality. We need to install non-custom
     * versions of everything provided by these packages before
     * attempting to uninstall them, or we'll hit dependency
     * issues.
     *)
    if libraries <> [] then (
      (* We only support removal of libraries on systems which use yum. *)
      if package_management = "yum" then (
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
             * impractical.  - RWMJ: Not convinced the original Perl code
             * would work, so I'm just installing the dependencies.
             *)
            let cmd = [ "yum"; "install"; "-y" ] @ provides in
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
    Lib_linux.remove verbose g inspect remove;

    (* VMware Tools may have been installed from a tarball, so the
     * above code won't remove it.  Look for the uninstall tool and run
     * if present.
     *)
    let uninstaller = "/usr/bin/vmware-uninstall-tools.pl" in
    if g#is_file ~followsymlinks:true uninstaller then (
      try
        ignore (g#command [| uninstaller |]);

        (* Reload Augeas to detect changes made by vbox tools uninst. *)
        Lib_linux.augeas_reload verbose g
      with
        G.Error msg ->
          warning ~prog (f_"VMware tools was detected, but uninstallation failed.  The error message was: %s (ignored)")
            msg
    )

  and unconfigure_citrix () =
    let pkgs =
      List.filter (
        fun { G.app2_name = name } -> string_prefix name "xe-guest-utilities"
      ) apps in
    let pkgs = List.map (fun { G.app2_name = name } -> name) pkgs in

    if pkgs <> [] then (
      Lib_linux.remove verbose g inspect pkgs;

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

  and can_do_virtio () =
    (* In the previous virt-v2v, this was a function that installed
     * virtio, eg. by updating the kernel.  However that function
     * (which only applied to RHEL <= 5) was very difficult to write
     * and maintain.  Instead what we do here is to check if the kernel
     * supports virtio, warn if it doesn't (and give some hint about
     * what to do) and return false.  Note that all recent Linux comes
     * with virtio drivers.
     *)
    match distro, major_version, minor_version with
    (* RHEL 6+ has always supported virtio. *)
    | ("rhel"|"centos"|"scientificlinux"|"redhat-based"), v, _ when v >= 6 ->
      true
    | ("rhel"|"centos"|"scientificlinux"|"redhat-based"), 5, _ ->
      let kernel = check_kernel_package (0_l, "2.6.18", "128.el5") in
      let lvm2 = check_package "lvm2" (0_l, "2.02.40", "6.el5") in
      let selinux =
        check_package ~ifinstalled:true
          "selinux-policy-targeted" (0_l, "2.4.6", "203.el5") in
      kernel && lvm2 && selinux
    | ("rhel"|"centos"|"scientificlinux"|"redhat-based"), 4, _ ->
      check_kernel_package (0_l, "2.6.9", "89.EL")

    (* All supported Fedora versions support virtio. *)
    | "fedora", _, _ -> true

    (* SLES 11 supports virtio in the kernel. *)
    | ("sles"|"suse-based"), v, _ when v >= 11 -> true
    | ("sles"|"suse-based"), 10, _ ->
      check_kernel_package (0_l, "2.6.16.60", "0.85.1")

    (* OpenSUSE. *)
    | "opensuse", v, _ when v >= 11 -> true
    | "opensuse", 10, _ ->
      check_kernel_package (0_l, "2.6.25.5", "1.1")

    | _ ->
      warning ~prog (f_"don't know how to install virtio drivers for %s %d\n%!")
        distro major_version;
      false

  and check_kernel_package minversion =
    let names = ["kernel"; "kernel-PAE"; "kernel-hugemem"; "kernel-smp";
                 "kernel-largesmp"; "kernel-pae"; "kernel-default"] in
    let found = List.exists (
      fun name -> check_package ~warn:false name minversion
    ) names in
    if not found then (
      let _, minversion, minrelease = minversion in
      warning ~prog (f_"cannot enable virtio in this guest.\nTo enable virtio you need to install a kernel >= %s-%s and run %s again.")
        minversion minrelease prog
    );
    found

  and check_package ?(ifinstalled = false) ?(warn = true) name minversion =
    let installed =
      let apps = try StringMap.find name apps_map with Not_found -> [] in
      List.rev (List.sort compare_app2_versions apps) in

    match ifinstalled, installed with
    (* If the package is not installed, ignore the request. *)
    | true, [] -> true
    (* Is the package already installed at the minimum version? *)
    | _, (installed::_)
      when compare_app2_version_min installed minversion >= 0 -> true
    (* User will need to install the package to get virtio. *)
    | _ ->
      if warn then (
        let _, minversion, minrelease = minversion in
        warning ~prog (f_"cannot enable virtio in this guest.\nTo enable virtio you need to upgrade %s >= %s-%s and run %s again.")
          name minversion minrelease prog
      );
      false

  and configure_kernel virtio grub =
    let kernels = grub#list_kernels () in

    let bootable_kernel =
      let rec loop =
        function
        | [] -> None
        | path :: paths ->
          let kernel =
            Lib_linux.inspect_linux_kernel verbose g inspect path in
          match kernel with
          | None -> loop paths
          | Some kernel when is_hv_kernel kernel -> loop paths
          | Some kernel when virtio && not (supports_virtio kernel) ->
            loop paths
          | Some kernel -> Some kernel
      in
      loop kernels in

    (* If virtio == true, then a virtio kernel should have been
     * installed.  If we didn't find one, it indicates a bug in
     * virt-v2v.
     *)
    if virtio && bootable_kernel = None then
      error (f_"virtio configured, but no virtio kernel found");

    (* No bootable kernel was found.  Install one. *)
    let bootable_kernel =
      match bootable_kernel with
      | Some k -> k
      | None ->
        (* Find which kernel is currently used by the guest. *)
        let current_kernel =
          let rec loop = function
            | [] -> "kernel"
            | path :: paths ->
              let kernel =
                Lib_linux.inspect_linux_kernel verbose g inspect
                  path in
              match kernel with
              | None -> loop paths
              | Some kernel -> kernel.Lib_linux.base_package
          in
          loop kernels in

        (* Replace kernel-xen with a suitable kernel. *)
        let current_kernel =
          if string_find current_kernel "kernel-xen" >= 0 then
            xen_replacement_kernel ()
          else
            current_kernel in

        (* Install the kernel.  However we need a way to detect the
         * version of the kernel that has just been installed.  A quick
         * way is to compare /lib/modules before and after.
         *)
        let files1 = g#ls "/lib/modules" in
        let files1 = Array.to_list files1 in
        Lib_linux.install verbose g inspect [current_kernel];
        let files2 = g#ls "/lib/modules" in
        let files2 = Array.to_list files2 in

        (* Note that g#ls is guaranteed to return the strings in order. *)
        let rec loop files1 files2 =
          match files1, files2 with
          | [], [] ->
            error (f_"tried to install '%s', but no kernel package was installed") current_kernel
          | (v1 :: _), [] ->
            error (f_"tried to install '%s', but there are now fewer directories under /lib/modules!") current_kernel
          | [], (v2 :: _) -> v2
          | (v1 :: _), (v2 :: _) when v1 <> v2 -> v2
          | (_ :: v1s), (_ :: v2s) -> loop v1s v2s
        in
        let version = loop files1 files2 in

        { Lib_linux.base_package = current_kernel;
          version = version; modules = []; arch = "" } in

    (* Set /etc/sysconfig/kernel DEFAULTKERNEL to point to the new
     * kernel package name.
     *)
    if g#is_file ~followsymlinks:true "/etc/sysconfig/kernel" then (
      let base_package = bootable_kernel.Lib_linux.base_package in
      let paths =
        g#aug_match "/files/etc/sysconfig/kernel/DEFAULTKERNEL/value" in
      let paths = Array.to_list paths in
      List.iter (fun path -> g#aug_set path base_package) paths;
      g#aug_save ()
    );

    (* Return the installed kernel version. *)
    bootable_kernel.Lib_linux.version

  and supports_virtio { Lib_linux.modules = modules } =
    List.mem "virtio_blk" modules && List.mem "virtio_net" modules

  (* Is it a hypervisor-specific kernel? *)
  and is_hv_kernel { Lib_linux.modules = modules } =
    List.mem "xennet" modules           (* Xen PV kernel. *)

  (* Find a suitable replacement for kernel-xen. *)
  and xen_replacement_kernel () =
    if is_rhel_family then (
      match major_version, arch with
      | 5, ("i386"|"i486"|"i586"|"i686") -> "kernel-PAE"
      | 5, _ -> "kernel"
      | 4, ("i386"|"i486"|"i586"|"i686") ->
        (* If guest has >= 10GB of RAM, give it a hugemem kernel. *)
        if source.s_memory >= 10L *^ 1024L *^ 1024L *^ 1024L then
          "kernel-hugemem"
        (* SMP kernel for guests with > 1 vCPU. *)
        else if source.s_vcpu > 1 then
          "kernel-smp"
        else
          "kernel"
      | 4, _ ->
        if source.s_vcpu > 8 then "kernel-largesmp"
        else if source.s_vcpu > 1 then "kernel-smp"
        else "kernel"
      | _, _ -> "kernel"
    )
    else if is_suse_family then (
      match distro, major_version, arch with
      | "opensuse", _, _ -> "kernel-default"
      | _, v, ("i386"|"i486"|"i586"|"i686") when v >= 11 ->
        if source.s_memory >= 10L *^ 1024L *^ 1024L *^ 1024L then
          "kernel-pae"
        else
          "kernel"
      | _, v, _ when v >= 11 -> "kernel-default"
      | _, 10, ("i386"|"i486"|"i586"|"i686") ->
        if source.s_memory >= 10L *^ 1024L *^ 1024L *^ 1024L then
          "kernel-bigsmp"
        else if source.s_vcpu > 1 then
          "kernel-smp"
        else
          "kernel-default"
      | _, 10, _ ->
        if source.s_vcpu > 1 then
          "kernel-smp"
        else
          "kernel-default"
      | _ -> "kernel-default"
    )
    else
      "kernel" (* conservative default *)

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

  in

  clean_rpmdb ();
  autorelabel ();
  Lib_linux.augeas_init verbose g;
  let grub = get_grub () in

  unconfigure_xen ();
  unconfigure_vbox ();
  unconfigure_vmware ();
  unconfigure_citrix ();

  let virtio = can_do_virtio () in
  let kernel_version = configure_kernel virtio grub in (*XXX*) ignore kernel_version;
  if keep_serial_console then (
    configure_console ();
    grub#configure_console ()
  ) else (
    remove_console ();
    grub#remove_console ()
  );









  let guestcaps = {
    gcaps_block_bus = if virtio then "virtio" else "ide";
    gcaps_net_bus = if virtio then "virtio" else "e1000";
  (* XXX display *)
  } in

  guestcaps
