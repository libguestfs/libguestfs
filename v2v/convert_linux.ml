(* virt-v2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

(* Convert a Linux guest to run on KVM. *)

(* < mdbooth> It's all in there for a reason :/ *)

open Printf

open C_utils
open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Utils
open Types
open Linux_kernels

module G = Guestfs

(* The conversion function. *)
let convert (g : G.guestfs) inspect source output rcaps =
  (*----------------------------------------------------------------------*)
  (* Inspect the guest first.  We already did some basic inspection in
   * the common v2v.ml code, but that has to deal with generic guests
   * (anything common to Linux and Windows).  Here we do more detailed
   * inspection which can make the assumption that we are dealing with
   * a Linux guest using RPM or Debian packages.
   *)

  (* Basic inspection data available as local variables. *)
  assert (inspect.i_type = "linux");

  let family =
    match inspect.i_distro with
    | "fedora"
    | "rhel" | "centos" | "scientificlinux" | "redhat-based"
    | "oraclelinux" -> `RHEL_family
    | "sles" | "suse-based" | "opensuse" -> `SUSE_family
    | "debian" | "ubuntu" | "linuxmint" -> `Debian_family
    | _ -> assert false in

  assert (inspect.i_package_format = "rpm" || inspect.i_package_format = "deb");

  (* We use Augeas for inspection and conversion, so initialize it early.
   * Calling debug_augeas_errors will display any //error nodes in
   * debugging output if verbose (but otherwise it does nothing).
   *)
  g#aug_init "/" 1;
  debug_augeas_errors g;

  (* Clean RPM database.  This must be done early to avoid RHBZ#1143866. *)
  Array.iter g#rm_f (g#glob_expand "/var/lib/rpm/__db.00?");

  (* Detect the installed bootloader. *)
  let bootloader = Linux_bootloaders.detect_bootloader g inspect in
  Linux.augeas_reload g;

  (* Detect which kernels are installed and offered by the bootloader. *)
  let bootloader_kernels =
    Linux_kernels.detect_kernels g inspect family bootloader in

  (*----------------------------------------------------------------------*)
  (* Conversion step. *)

  let rec do_convert () =
    augeas_grub_configuration ();

    unconfigure_xen ();
    unconfigure_vbox ();
    unconfigure_vmware ();
    unconfigure_citrix ();
    unconfigure_kudzu ();
    unconfigure_prltools ();

    let kernel = configure_kernel () in

    if output#keep_serial_console then (
      configure_console ();
      bootloader#configure_console ();
    ) else (
      remove_console ();
      bootloader#remove_console ();
    );

    let acpi = supports_acpi () in

    let video =
      match rcaps.rcaps_video with
      | None -> get_display_driver ()
      | Some video -> video in

    let block_type =
      match rcaps.rcaps_block_bus with
      | None -> if kernel.ki_supports_virtio_blk then Virtio_blk else IDE
      | Some block_type -> block_type in

    let net_type =
      match rcaps.rcaps_net_bus with
      | None -> if kernel.ki_supports_virtio_net then Virtio_net else E1000
      | Some net_type -> net_type in

    configure_display_driver video;
    remap_block_devices block_type;
    configure_kernel_modules block_type net_type;
    rebuild_initrd kernel;

    SELinux_relabel.relabel g;

    (* Return guest capabilities from the convert () function. *)
    let guestcaps = {
      gcaps_block_bus = block_type;
      gcaps_net_bus = net_type;
      gcaps_video = video;
      gcaps_virtio_rng = kernel.ki_supports_virtio_rng;
      gcaps_virtio_balloon = kernel.ki_supports_virtio_balloon;
      gcaps_isa_pvpanic = kernel.ki_supports_isa_pvpanic;
      gcaps_arch = Utils.kvm_arch inspect.i_arch;
      gcaps_acpi = acpi;
    } in

    guestcaps

  and augeas_grub_configuration () =
    if bootloader#set_augeas_configuration () then
      Linux.augeas_reload g

  and unconfigure_xen () =
    (* Remove kmod-xenpv-* (RHEL 3). *)
    let xenmods =
      List.filter_map (
        fun { G.app2_name = name } ->
          if name = "kmod-xenpv" || String.is_prefix name "kmod-xenpv-" then
            Some name
          else
            None
      ) inspect.i_apps in
    Linux.remove g inspect xenmods;

    (* Undo related nastiness if kmod-xenpv was installed. *)
    if xenmods <> [] then (
      (* kmod-xenpv modules may have been manually copied to other kernels.
       * Hunt them down and destroy them.
       *)
      let dirs = g#find "/lib/modules" in
      let dirs = Array.to_list dirs in
      let dirs = List.filter (fun s -> String.find s "/xenpv" >= 0) dirs in
      let dirs = List.map ((^) "/lib/modules/") dirs in
      let dirs = List.filter g#is_dir dirs in

      (* Check it's not owned by an installed application. *)
      let dirs = List.filter (
        fun d -> not (Linux.is_file_owned g inspect d)
      ) dirs in

      (* Remove any unowned xenpv directories. *)
      List.iter g#rm_rf dirs;

      (* rc.local may contain an insmod or modprobe of the xen-vbd driver,
       * added by an installation script.
       *)
      (try
         let lines = g#read_lines "/etc/rc.local" in
         let lines = Array.to_list lines in
         let rex = PCRE.compile "\\b(insmod|modprobe)\\b.*\\bxen-vbd" in
         let lines = List.map (
           fun s ->
             if PCRE.matches rex s then
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
      Linux.remove g inspect [package_name];

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
      let rex = PCRE.compile "^INSTALL_DIR=(.*)$" in
      let lines = List.filter_map (
        fun line ->
          if PCRE.matches rex line then (
            let path = PCRE.sub 1 in
            let path = shell_unquote path in
            if String.length path >= 1 && path.[0] = '/' then (
              let vboxuninstall = path ^ "/uninstall.sh" in
              Some vboxuninstall
            )
            else None
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
          Linux.augeas_reload g
        with
          G.Error msg ->
            warning (f_"VirtualBox Guest Additions were detected, but uninstallation failed.  The error message was: %s (ignored)")
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
        if String.is_prefix name "vmware-tools-libraries-" then
          List.push_front name libraries
        else if String.is_prefix name "vmware-tools-" then
          List.push_front name remove
        else if name = "VMwareTools" then
          List.push_front name remove
        else if String.is_prefix name "kmod-vmware-tools" then
          List.push_front name remove
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
              List.filter (
                fun s ->
                  not (library = s || String.is_prefix s (library ^ " = "))
              ) provides in

            (* If the package provides something other than itself, then
             * proceed installing the replacements; in the other case,
             * just mark the package for removal, as it means no other
             * package can depend on something provided.
             *)
            if provides <> [] then (
              (* Trim whitespace. *)
              let provides = List.map String.trim provides in

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
                 List.push_front library remove
               with G.Error msg ->
                 eprintf "%s: could not install replacement for %s.  Error was: %s.  %s was not removed.\n"
                   prog library msg library
              );
            ) else (
              List.push_front library remove;
            );
        ) libraries
      )
    );

    let remove = !remove in
    Linux.remove g inspect remove;

    (* VMware Tools may have been installed from a tarball, so the
     * above code won't remove it.  Look for the uninstall tool and run
     * if present.
     *)
    let uninstaller = "/usr/bin/vmware-uninstall-tools.pl" in
    if g#is_file ~followsymlinks:true uninstaller then (
      try
        if family = `SUSE_family then
          ignore (g#command [| "/usr/bin/env";
                               "rootdev=" ^ inspect.i_root;
                               uninstaller |])
        else
          ignore (g#command [| uninstaller |]);

        (* Reload Augeas to detect changes made by vbox tools uninst. *)
        Linux.augeas_reload g
      with
        G.Error msg ->
          warning (f_"VMware tools was detected, but uninstallation failed.  The error message was: %s (ignored)")
            msg
    )

  and unconfigure_citrix () =
    let pkgs =
      List.filter (
        fun { G.app2_name = name } -> String.is_prefix name "xe-guest-utilities"
      ) inspect.i_apps in
    let pkgs = List.map (fun { G.app2_name = name } -> name) pkgs in

    if pkgs <> [] then (
      Linux.remove g inspect pkgs;

      (* Installing these guest utilities automatically unconfigures
       * ttys in /etc/inittab if the system uses it. We need to put
       * them back.
       *)
      let rex = PCRE.compile "^([1-6]):([2-5]+):respawn:(.*)" in
      let updated = ref false in
      let rec loop () =
        let comments = g#aug_match "/files/etc/inittab/#comment" in
        let comments = Array.to_list comments in
        match comments with
        | [] -> ()
        | commentp :: _ ->
          let comment = g#aug_get commentp in
          if PCRE.matches rex comment then (
            let name = PCRE.sub 1
            and runlevels = PCRE.sub 2
            and process = PCRE.sub 3 in

            if String.find process "getty" >= 0 then (
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

  and unconfigure_prltools () =
    let prltools_path = "/usr/lib/parallels-tools/install" in
    if g#is_file ~followsymlinks:true prltools_path then (
      try
        ignore (g#command [| prltools_path; "-r" |]);

        (* Reload Augeas to detect changes made by prltools uninst. *)
        Linux.augeas_reload g
      with
        G.Error msg ->
          warning (f_"Parallels tools was detected, but uninstallation failed. The error message was: %s (ignored)")
            msg
    )

  and configure_kernel () =
    (* Previously this function would try to install kernels, but we
     * don't do that any longer.
     *)

    (* Check a non-Xen kernel exists. *)
    let only_xen_kernels = List.for_all (
      fun { ki_is_xen_pv_only_kernel = pv_only } -> pv_only
    ) bootloader_kernels in
    if only_xen_kernels then
      error (f_"only Xen kernels are installed in this guest.\n\nRead the %s(1) manual, section \"XEN PARAVIRTUALIZED GUESTS\", to see what to do.") prog;

    (* Enable the best non-Xen kernel, where "best" means the one with
     * the highest version, preferring non-debug kernels which support
     * virtio.
     *)
    let best_kernel =
      let compare_best_kernels k1 k2 =
        let i = compare k1.ki_supports_virtio_net k2.ki_supports_virtio_net in
        if i <> 0 then i
        else (
          let i = compare_app2_versions k1.ki_app k2.ki_app in
          if i <> 0 then i
          (* Favour non-debug kernels over debug kernels (RHBZ#1170073). *)
          else compare k2.ki_is_debug k1.ki_is_debug
        )
      in
      let kernels = bootloader_kernels in
      let kernels =
        List.filter (fun { ki_is_xen_pv_only_kernel = pv_only } -> not pv_only)
                    kernels in
      let kernels = List.sort compare_best_kernels kernels in
      let kernels = List.rev kernels (* so best is first *) in
      List.hd kernels in
    if verbose () then (
      eprintf "best kernel for this guest:\n";
      print_kernel_info stderr "\t" best_kernel
    );
    if best_kernel <> List.hd bootloader_kernels then (
      debug "best kernel is not the bootloader default, setting bootloader default ...";
      bootloader#set_default_kernel best_kernel.ki_vmlinuz
    );

    (* Update /etc/sysconfig/kernel DEFAULTKERNEL (RHBZ#1176801). *)
    if g#is_file ~followsymlinks:true "/etc/sysconfig/kernel" then (
      let entries =
        g#aug_match "/files/etc/sysconfig/kernel/DEFAULTKERNEL/value" in
      let entries = Array.to_list entries in
      if entries <> [] then (
        List.iter (fun path -> g#aug_set path best_kernel.ki_name) entries;
        g#aug_save ()
      )
    );

    best_kernel

  (* Even though the kernel was already installed (this version of
   * virt-v2v does not install new kernels), it could have an
   * initrd that does not have support virtio.  Therefore rebuild
   * the initrd.
   *)
  and rebuild_initrd kernel =
    match kernel.ki_initrd with
    | None -> ()
    | Some initrd ->
      (* Enable the basic virtio modules in the kernel. *)
      let modules =
        let modules =
          (* The order of modules here is deliberately the same as the
           * order specified in the postinstall script of kmod-virtio in
           * RHEL3. The reason is that the probing order determines the
           * major number of vdX block devices. If we change it, RHEL 3
           * KVM guests won't boot.
           *)
          List.filter (fun m -> List.mem m kernel.ki_modules)
                      [ "virtio"; "virtio_ring"; "virtio_blk";
                        "virtio_scsi"; "virtio_net"; "virtio_pci" ] in
        if modules <> [] then modules
        else
          (* Fallback copied from old virt-v2v.  XXX Why not "ide"? *)
          [ "sym53c8xx" ] in

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
        match last_part_of modpath '/' with
        | Some x -> x
        | None -> invalid_arg (sprintf "invalid module path: %s" modpath) in

      let run_dracut_command dracut_path =
        (* Dracut. *)
        let args =
          dracut_path ::
            (if verbose () then [ "--verbose" ] else [])
          @ [ "--add-drivers"; String.concat " " modules; initrd; mkinitrd_kv ]
        in
        ignore (g#command (Array.of_list args))
      in

      let run_update_initramfs_command () =
        let args =
          "/usr/sbin/update-initramfs"  ::
            (if verbose () then [ "-v" ] else [])
          @ [ "-c"; "-k"; mkinitrd_kv ]
        in
        ignore (g#command (Array.of_list args))
      in

      if g#is_file ~followsymlinks:true "/sbin/dracut" then
        run_dracut_command "/sbin/dracut"
      else if g#is_file ~followsymlinks:true "/usr/bin/dracut" then
        run_dracut_command "/usr/bin/dracut"
      else if family = `SUSE_family
           && g#is_file ~followsymlinks:true "/sbin/mkinitrd" then (
        ignore (
          g#command [| "/usr/bin/env";
                       "rootdev=" ^ inspect.i_root;
                       "/sbin/mkinitrd";
                       "-m"; String.concat " " modules;
                       "-i"; initrd;
                       "-k"; kernel.ki_vmlinuz;
                       "-d"; inspect.i_root |]
        )
      )
      else if family = `Debian_family then (
        if not (g#is_file ~followsymlinks:true "/usr/sbin/update-initramfs") then
          error (f_"unable to rebuild initrd (%s) because update-initramfs was not found in the guest")
            initrd;

        if List.length modules > 0 then (
          (* The modules to add to initrd are defined in:
          *     /etc/initramfs-tools/modules
          * File format is same as modules(5).
          *)
          let path = "/files/etc/initramfs-tools/modules" in
          g#aug_transform "modules" "/etc/initramfs-tools/modules";
          Linux.augeas_reload g;
          g#aug_set (sprintf "%s/#comment[last()+1]" path)
            "The following modules were added by virt-v2v";
          List.iter (
            fun m -> g#aug_clear (sprintf "%s/%s" path m)
          ) modules;
          g#aug_save ();
        );

        run_update_initramfs_command ()
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
    let rex = PCRE.compile "\\b([xh]vc0)\\b" in
    List.iter (
      fun path ->
        let proc = g#aug_get path in
        let proc' = PCRE.replace ~global:true rex "ttyS0" proc in
        if proc <> proc' then g#aug_set path proc'
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
    let rex = PCRE.compile "\\b([xh]vc0|ttyS0)\\b" in
    List.iter (
      fun path ->
        let proc = g#aug_get path in
        if PCRE.matches rex proc then
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

    (* If we updated the X driver, check that X itself is installed,
     * and warn if not.  Old virt-v2v used to attempt to install X here
     * but that way lies insanity and ruin.
     *)
    if !updated &&
      not (g#is_file ~followsymlinks:true "/usr/bin/X") &&
      not (g#is_file ~followsymlinks:true "/usr/bin/X11/X") then
      warning (f_"The display driver was updated to ‘%s’, but X11 does not seem to be installed in the guest.  X may not function correctly.")
        video_driver

  and configure_kernel_modules block_type net_type =
    (* This function modifies modules.conf (and its various aliases). *)

    let augeas_modprobe query =
      (* Execute g#aug_match, but against every known location of
         modules.conf. *)
      let paths = [
        "/files/etc/conf.modules/alias";        (* modules_conf.aug *)
        "/files/etc/modules.conf/alias";
        "/files/etc/modprobe.conf/alias";       (* modprobe.aug *)
        "/files/etc/modprobe.conf.local/alias";
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
      if g#is_dir ~followsymlinks:true "/etc/modprobe.d" then (
        (* Create a new file /etc/modprobe.d/virt-v2v-added.conf. *)
        "/etc/modprobe.d/virt-v2v-added.conf"
      ) else (
        (* List of methods, in order of preference. *)
        let paths = [
          "/etc/modprobe.conf.local";
          "/etc/modprobe.conf";
          "/etc/modules.conf";
          "/etc/conf.modules"
        ] in
        try List.find (g#is_file ~followsymlinks:true) paths
        with Not_found ->
          error (f_"unable to find any valid modprobe configuration file such as /etc/modprobe.conf");
      )
    in

    (* Update 'alias eth0 ...'. *)
    let paths = augeas_modprobe ". =~ regexp('eth[0-9]+')" in
    let net_device =
      match net_type with
      | Virtio_net -> "virtio_net"
      | E1000 -> "e1000"
      | RTL8139 -> "rtl8139cp"
    in

    List.iter (
      fun path -> g#aug_set (path ^ "/modulename") net_device
    ) paths;

    (* Update 'alias scsi_hostadapter ...' *)
    let paths = augeas_modprobe ". =~ regexp('scsi_hostadapter.*')" in
    (match block_type with
    | Virtio_blk | Virtio_SCSI ->
      let block_module =
        match block_type with
        | Virtio_blk -> "virtio_blk"
        | Virtio_SCSI -> "virtio_scsi"
        | IDE -> assert false in

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

        g#aug_set (path ^ "/modulename") block_module
      ) else (
        (* We have to add a scsi_hostadapter. *)
        let modpath = discover_modpath () in
        g#aug_set (sprintf "/files%s/alias[last()+1]" modpath)
          "scsi_hostadapter";
        g#aug_set (sprintf "/files%s/alias[last()]/modulename" modpath)
          block_module
      )
    | IDE ->
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
        warning (f_"don’t know how to update %s which loads the %s module")
          device module_;
    ) paths;

    (* Update files. *)
    g#aug_save ()

  and remap_block_devices block_type =
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
      match block_type with
      | Virtio_blk -> "vd"
      | Virtio_SCSI -> "sd"
      | IDE -> ide_block_prefix in

    let map =
      List.mapi (
        fun i disk ->
          let block_prefix_before_conversion =
            match disk.s_controller with
            | Some Source_IDE -> ide_block_prefix
            | Some (Source_virtio_SCSI | Source_SCSI | Source_SATA) -> "sd"
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
      List.mapi (
        fun i disk ->
          "xvd" ^ drive_name i, block_prefix_after_conversion ^ drive_name i
      ) source.s_disks in

    if verbose () then (
      eprintf "block device map:\n";
      List.iter (
        fun (source_dev, target_dev) ->
          eprintf "\t%s\t-> %s\n" source_dev target_dev
      ) (List.sort (fun (a,_) (b,_) -> compare a b) map);
      flush stderr
    );

    (* Possible Augeas paths to search for device names. *)
    let paths = [
      (* /etc/fstab *)
      "/files/etc/fstab/*/spec";
    ] in
    (* Bootloader config *)
    let paths = paths @ bootloader#augeas_device_patterns in

    (* Which of these paths actually exist? *)
    let paths =
      List.flatten (List.map Array.to_list (List.map g#aug_match paths)) in

    (* Map device names for each entry. *)
    let rex_resume = PCRE.compile "^(.*resume=)(/dev/\\S+)(.*)$"
    and rex_device_cciss = PCRE.compile "^/dev/(cciss/c\\d+d\\d+)(?:p(\\d+))?$"
    and rex_device = PCRE.compile "^/dev/([a-z]+)(\\d*)?$" in

    let rec replace_if_device path value =
      let replace device =
        try List.assoc device map
        with Not_found ->
          if not (String.is_prefix device "md") &&
             not (String.is_prefix device "fd") &&
             not (String.is_prefix device "sr") &&
             not (String.is_prefix device "scd") &&
             device <> "cdrom" then
            warning (f_"%s references unknown device \"%s\".  You may have to fix this entry manually after conversion.")
              path device;
          device
      in

      if String.find path "GRUB_CMDLINE" >= 0 then (
        (* Handle grub2 resume=<dev> specially. *)
        if PCRE.matches rex_resume value then (
          let start = PCRE.sub 1
          and device = PCRE.sub 2
          and end_ = PCRE.sub 3 in
          let device = replace_if_device path device in
          start ^ device ^ end_
        )
        else value
      )
      else if PCRE.matches rex_device_cciss value then (
        let device = PCRE.sub 1
        and part = try PCRE.sub 2 with Not_found -> "" in
        "/dev/" ^ replace device ^ part
      )
      else if PCRE.matches rex_device value then (
        let device = PCRE.sub 1
        and part = try PCRE.sub 2 with Not_found -> "" in
        "/dev/" ^ replace device ^ part
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

      (* Make sure the bootloader is up-to-date. *)
      bootloader#update ();

      Linux.augeas_reload g
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

  do_convert ()

(* Register this conversion module. *)
let () =
  let matching = function
    | { i_type = "linux";
        i_distro = ("fedora"
                    | "rhel" | "centos" | "scientificlinux" | "redhat-based"
                    | "oraclelinux"
                    | "sles" | "suse-based" | "opensuse"
                    | "debian" | "ubuntu" | "linuxmint") } -> true
    | _ -> false
  in
  Modules_list.register_convert_module matching "linux" convert
