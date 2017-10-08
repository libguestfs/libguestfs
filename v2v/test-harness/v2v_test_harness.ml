(* libguestfs v2v test harness
 * Copyright (C) 2015 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

module G = Guestfs
module C = Libvirt.Connect
module D = Libvirt.Domain

open Unix
open Printf

open Std_utils
open Tools_utils
open Xpath_helpers

type test_plan = {
  guest_clock : float option;
  post_conversion_test : (Guestfs.guestfs -> string -> Xml.doc -> unit) option;
  boot_plan : boot_plan;

  boot_wait_to_write : int;
  boot_max_time : int;
  boot_idle_time : int;
  boot_known_good_screenshots : string list;
  boot_graceful_shutdown : int;

  post_boot_test : (Guestfs.guestfs -> string -> Xml.doc -> unit) option;
}
and boot_plan =
| No_boot
| Boot_to_idle
| Boot_to_screenshot of string

let new_year's_day year =
  let tm = { tm_sec = 0; tm_min = 0; tm_hour = 0;
             tm_mday = 1; tm_mon = 0; tm_year = year - 1900;
             tm_wday = 0; tm_yday = 0; tm_isdst = false } in
  let t, _ = mktime tm in
  Some t

let default_plan = {
  guest_clock = None;
  post_conversion_test = None;
  boot_plan = Boot_to_idle;
  boot_wait_to_write = 120;
  boot_max_time = 600;
  boot_idle_time = 60;
  boot_known_good_screenshots = [];
  boot_graceful_shutdown = 60;
  post_boot_test = None;
}

let failwithf fs = ksprintf failwith fs

let run ~test ?input_disk ?input_xml ?(test_plan = default_plan) () =
  let input_disk =
    match input_disk with
    | None -> test ^ ".img.xz"
    | Some input_disk -> input_disk in

  let inspect_and_mount_disk filename =
    let g = new G.guestfs () in
    g#add_drive filename ~readonly:true ~format:"qcow2";
    g#launch ();

    let roots = g#inspect_os () in
    let roots = Array.to_list roots in
    let root =
      match roots with
      | [] -> failwithf "no roots found in disk image %s" filename
      | [x] -> x
      | _ ->
        failwithf "multiple roots found in disk image %s" filename in

    inspect_mount_root_ro g root;

    g, root
  in

  let test_boot boot_disk boot_xml_doc =
    (* Modify boot XML (in memory). *)
    let xpathctx = Xml.xpath_new_context boot_xml_doc in

    (* Change <name> to something unique. *)
    let domname = "tmpv2v-" ^ test in
    let nodes = xpath_get_nodes xpathctx "/domain/name" in
    List.iter (fun node -> Xml.node_set_content node domname) nodes;

    (* Limit the RAM used by the guest to 2GB. *)
    let nodes = xpath_get_nodes xpathctx "/domain/memory" in
    let nodes = nodes @ xpath_get_nodes xpathctx "/domain/currentMemory" in
    List.iter (
      fun node ->
        let i = int_of_string (Xml.node_as_string node) in
        if i > 2097152 then
          Xml.node_set_content node "2097152"
    ) nodes;

    (* Adjust the <clock/> if requested. *)
    (match test_plan.guest_clock with
     | None -> ()
     | Some t ->
        let adjustment = t -. time () in
        assert (adjustment <= 0.);
        let adjustment = int_of_float adjustment in
        let nodes = xpath_get_nodes xpathctx "/domain/clock" in
        let clock_node =
          match nodes with
          | [] ->
             (* No <clock> element, so insert one. *)
             let root (* the <domain> element *) =
               match Xml.doc_get_root_element boot_xml_doc with
               | None -> assert false
               | Some root -> root in
             Xml.new_text_child root "clock" ""
          | [clock_node] -> clock_node
          | _ ->
             failwith "multiple <clock> elements found" in
        Xml.set_prop clock_node "offset" "variable";
        Xml.set_prop clock_node "basis" "localtime";
        Xml.set_prop clock_node "adjustment" (string_of_int adjustment)
    );

    (* Remove all devices except for a whitelist. *)
    let nodes = xpath_get_nodes xpathctx "/domain/devices/*" in
    List.iter (
      fun node ->
        match Xml.node_name node with
        | "disk" | "graphics" | "video" -> ()
        | _ -> Xml.unlink_node node
    ) nodes;

    (* Remove CDROMs. *)
    let nodes = xpath_get_nodes xpathctx
      "/domain/devices/disk[@device=\"cdrom\"]" in
    List.iter Xml.unlink_node nodes;

    (* Change <on_*> settings to destroy ... *)
    let nodes = xpath_get_nodes xpathctx "/domain/on_poweroff" in
    let nodes = nodes @ xpath_get_nodes xpathctx "/domain/on_crash" in
    List.iter (fun node -> Xml.node_set_content node "destroy") nodes;
    (* ... except for <on_reboot> which is permitted (for SELinux
     * relabelling)
     *)
    let nodes = xpath_get_nodes xpathctx "/domain/on_reboot" in
    List.iter (fun node -> Xml.node_set_content node "restart") nodes;

    (* Get the name of the disk device (eg. "sda"), which is used
     * for getting disk stats.
     *)
    let dev =
      match xpath_get_nodes xpathctx
        "/domain/devices/disk[@device=\"disk\"]/target/@dev" with
      | [node] -> Xml.node_as_string node
      | _ -> assert false in

    let boot_xml = Xml.to_string boot_xml_doc ~format:true in

    (* Dump out the XML as debug information before running the guest. *)
    printf "boot XML:\n%s\n" boot_xml;

    (* Boot the guest. *)
    let conn = C.connect () in
    let dom = D.create_xml conn boot_xml [D.START_AUTODESTROY] in

    let timestamp t =
      let tm = localtime t in
      let y = 1900+tm.tm_year and mo = 1+tm.tm_mon and d = tm.tm_mday
      and h = tm.tm_hour and m = tm.tm_min and s = tm.tm_sec in
      sprintf "%04d%02d%02d-%02d%02d%02d" y mo d h m s
    in

    let display_is_black display =
      let cmd =
        sprintf "convert %s -format '%%[mean]' info:" (quote display) in
      printf "%s\n%!" cmd;
      let chan = open_process_in cmd in
      let lines = ref [] in
      (try while true do List.push_front (input_line chan) lines done
       with End_of_file -> ());
      let lines = List.rev !lines in
      let stat = close_process_in chan in
      match stat with
      | WEXITED 0 ->
         let mean = Scanf.sscanf (List.hd lines) "%f" (fun f -> f) in
         mean < 60.0            (* mostly or completely black *)
      | WEXITED i ->
         failwithf "external command '%s' exited with error %d" cmd 2;
      | WSIGNALED i ->
         failwithf "external command '%s' killed by signal %d" cmd i
      | WSTOPPED i ->
         failwithf "external command '%s' stopped by signal %d" cmd i
    in

    let keys = [| "KEY_LEFTSHIFT"; "KEY_LEFTALT"; "KEY_LEFTCTRL" |] in
    let next_key = ref 0 in

    let take_screenshot t =
      let filename = sprintf "%s-%s.scrn" test (timestamp t) in
      let cmd =
        sprintf "virsh screenshot %s %s" (quote domname) (quote filename) in
      printf "%s\n%!" cmd;

      let do_virsh_screenshot () =
        (* Use 'virsh screenshot' command because our libvirt bindings
         * don't include virDomainScreenshot, and in any case that API
         * is complicated to use.
         *)
      if Sys.command cmd <> 0 then
        failwith "virsh screenshot command failed";
      in

      (* Take a screenshot. *)
      do_virsh_screenshot ();

      (* If the screenshot is completely black, send a key to wake up
       * the screen from blanking.  But don't keep on hitting the shift
       * key as that causes Windows to get in a muddle.  And don't send
       * a key unnecessarily since grub responds to shift keys by going
       * into a menu(!)
       * https://rwmj.wordpress.com/2015/03/30/tip-wake-up-a-guest-from-screen-blank/
       *)
      if display_is_black filename then (
        let key = keys.(!next_key) in
        next_key := !next_key+1;
        if !next_key >= Array.length keys then next_key := 0;

        let cmd = sprintf "virsh send-key %s %s" (quote domname) key in
        printf "%s\n%!" cmd;
        ignore (Sys.command cmd);
        sleep 2;

        do_virsh_screenshot ()
      );

      (* Return the screenshot filename. *)
      filename
    in

    (* Find subimage within display.  There must be a near-exact
     * match.  By editing images (eg. removing dates/times) you can
      ensure this.
     *)
    let display_matches_subimage display subimage =
      (* Grrr compare sends its normal output to stderr. *)
      let cmd =
        sprintf "compare -subimage-search -metric MAE %s %s null: 2>&1"
                (quote display) (quote subimage) in
      printf "%s\n%!" cmd;
      let chan = open_process_in cmd in
      let lines = ref [] in
      (try while true do List.push_front (input_line chan) lines done
       with End_of_file -> ());
      let lines = List.rev !lines in
      let stat = close_process_in chan in
      match stat with
      | WEXITED 0 -> true       (* exact match *)
      | WEXITED 1 ->            (* not exact match *)
         let similarity = Scanf.sscanf (List.hd lines) "%f" (fun f -> f) in
         similarity <= 60.0
      | WEXITED 2 ->            (* error *)
         (* We need to ignore the annoying 'compare: images too dissimilar'
          * message.  Why?
          *)
         let rec loop = function
           | [] ->              (* error *)
              failwithf "external command '%s' exited with error %d" cmd 2;
           | line::lines ->
              if String.is_prefix line "compare: images too dissimilar" then
                false           (* no match *)
              else
                loop lines
         in
         loop lines
      | WEXITED i ->
         failwithf "external command '%s' exited with error %d" cmd i
      | WSIGNALED i ->
         failwithf "external command '%s' killed by signal %d" cmd i
      | WSTOPPED i ->
         failwithf "external command '%s' stopped by signal %d" cmd i
    in

    let dom_is_alive () =
      match (D.get_info dom).D.state with
      | D.InfoRunning | D.InfoBlocked -> true
      | _ -> false
    in

    let get_disk_write_activity stats =
      let stats' = D.block_stats dom dev in
      let writes = Int64.sub stats'.D.wr_req stats.D.wr_req in
      writes > 0L, stats'
    and get_disk_activity stats =
      let stats' = D.block_stats dom dev in
      let writes = Int64.sub stats'.D.wr_req stats.D.wr_req
      and reads = Int64.sub stats'.D.rd_req stats.D.rd_req in
      writes > 0L || reads > 0L, stats'
    in

    let bootfail t fs =
      let screenshot = take_screenshot t in
      eprintf "boot failed: see screenshot in %s\n%!" screenshot;
      ksprintf failwith fs
    in

    (* The guest is booting.  We expect it to write to the disk within
     * the first boot_wait_to_write seconds.
     *)
    let start = time () in
    let stats = D.block_stats dom dev in
    let rec loop stats =
      sleep 10;
      let t = time () in
      if t -. start > float test_plan.boot_wait_to_write then
        bootfail t "guest did not write to disk within %d seconds of boot"
          test_plan.boot_wait_to_write;
      let active, stats = get_disk_write_activity stats in
      if active then
        printf "%s: disk write detected\n" (timestamp t)
      else (
        printf "%s: still waiting for disk write after boot\n" (timestamp t);
        loop stats
      )
    in
    loop stats;

    (* The guest has written something, so it has probably found its
     * own disks, which is a good sign.  Now we wait until it reaches
     * the end condition (eg. Boot_to_idle or Boot_to_screenshot).
     *)
    let start = time () in
    let last_activity = start in
    let stats = D.block_stats dom dev in
    let rec loop start last_activity stats =
      sleep 10;
      let t = time () in
      if t -. start > float test_plan.boot_max_time then
        bootfail t "guest timed out before reaching final state";

      (* Make sure we take a screenshot on every iteration, as they
       * are incredibly useful for debugging.
       *)
      let display = take_screenshot t in

      (* Reached the final screenshot?  Reaching this state
       * terminates the boot immediately.
       *)
      let reached_final_screenshot =
        match test_plan.boot_plan with
        | Boot_to_screenshot final_screenshot ->
           if display_matches_subimage display final_screenshot then (
             printf "%s: guest reached final screenshot\n" (timestamp t);
             true
           ) else false
        | _ -> false in
      if not reached_final_screenshot then (
        (* Is the disk active? *)
        let is_active, stats = get_disk_activity stats in
        let is_idle = t -. last_activity > float test_plan.boot_idle_time in

        if is_active then (
          printf "%s: disk activity detected\n" (timestamp t);
          loop start t stats
        ) else (
          if is_idle then (
            if test_plan.boot_plan <> Boot_to_idle then
              bootfail t "guest timed out with no disk activity before reaching final state"
          (* else Boot_to_idle, so we exit the loop here *)
          ) else (
            (* A screenshot matching one of the screenshots in the set
             * resets the timeouts.
             *)
            let waiting_in_known_good_state =
              List.exists (display_matches_subimage display)
                          test_plan.boot_known_good_screenshots in
            if waiting_in_known_good_state then (
              printf "%s: guest at known-good screenshot\n" (timestamp t);
              loop t t stats
            ) else
              loop start last_activity stats
          )
        )
      )
    in
    loop start last_activity stats;

    (* Shut down the guest.  Eventually kill it if it doesn't shut
     * down gracefully on its own.
     *)
    D.shutdown dom;
    let start = time () in
    let rec loop () =
      sleep 10;
      let t = time () in
      if t -. start > float test_plan.boot_graceful_shutdown then (
        eprintf "warning: guest failed to shut down gracefully, killing it\n";
        D.destroy dom
      )
      else if dom_is_alive () then
        loop ()
    in
    loop ()
  in

  printf "v2v_test_harness: starting test: %s\n%!" test;
  printf "testing: %!"; ignore (Sys.command "which virt-v2v");

  (* Check we are started in the correct directory.
   *)
  if not (Sys.file_exists input_disk) then
    failwith "cannot find input files: you are probably running the test script from the wrong directory";

  (* How we run virt-v2v depends on the extension of the input_disk. *)
  let v2v_method =
    (* Uncompress the input, if the uncompressed file doesn't exist already. *)
    let input_disk =
      if Filename.check_suffix input_disk ".xz" then (
        let input_disk_uncomp = Filename.chop_suffix input_disk ".xz" in
        if not (Sys.file_exists input_disk_uncomp) then (
          let cmd =
            sprintf "xzcat %s > %s"
                    (quote input_disk) (quote input_disk_uncomp) in
          printf "%s\n%!" cmd;
          if Sys.command cmd <> 0 then
            failwith "xzcat command failed"
        );
        input_disk_uncomp
      )
      else input_disk in

    if Filename.check_suffix input_disk ".img" then (
      let input_xml =
        match input_xml with
        | None -> test ^ ".xml"
        | Some input_xml -> input_xml in
      `V2v_method_libvirtxml input_xml
    )
    else if Filename.check_suffix input_disk ".ova" then
      `V2v_method_ova input_disk
    else
      failwithf "don't know what to do with input disk '%s'" input_disk in

  (* Run virt-v2v. *)
  let cmd_input =
    match v2v_method with
    | `V2v_method_libvirtxml input_xml ->
      sprintf "-i libvirtxml %s" (quote input_xml)
    | `V2v_method_ova input_disk ->
      sprintf "-i ova %s" (quote input_disk) in
  let cmd =
    sprintf "virt-v2v %s -o local -of qcow2 -os . -on %s"
      cmd_input (quote (test ^ "-converted")) in
  printf "%s\n%!" cmd;
  if Sys.command cmd <> 0 then
    failwith "virt-v2v command failed";

  (* Check the right output files were created. *)
  let converted_disk = test ^ "-converted-sda" in
  if not (Sys.file_exists converted_disk) then
    failwithf "cannot find virt-v2v output disk: %s" converted_disk;
  let converted_xml = test ^ "-converted.xml" in
  if not (Sys.file_exists converted_xml) then
    failwithf "cannot find virt-v2v output XML: %s" converted_xml;

  (* Check the output XML can be parsed into a document. *)
  let converted_xml_doc = Xml.parse_memory (read_whole_file converted_xml) in

  (* If there's a post-conversion callback, run it now. *)
  (match test_plan.post_conversion_test with
  | None -> ()
  | Some fn ->
    let g, root = inspect_and_mount_disk converted_disk in
    fn g root converted_xml_doc;
    g#close ()
  );

  match test_plan.boot_plan with
  | No_boot -> ()
  | Boot_to_idle | Boot_to_screenshot _ ->
    (* We want to preserve the converted disk (before booting), so
     * make an overlay to store writes during the boot test.  This
     * makes post-mortems a bit easier.
     *)
    let boot_disk = test ^ "-booted-sda" in
    (new G.guestfs ())#disk_create boot_disk "qcow2" (-1L)
      ~backingfile:converted_disk ~backingformat:"qcow2";

    let boot_xml_doc = Xml.copy_doc converted_xml_doc ~recursive:true in

    (* We need to remember to change the XML to point to the boot overlay. *)
    let () =
      let xpathctx = Xml.xpath_new_context boot_xml_doc in
      match xpath_get_nodes xpathctx
        "/domain/devices/disk[@device=\"disk\"]/source" with
      | [node] ->
        (* Libvirt requires that the path is absolute. *)
        let abs_boot_disk = Sys.getcwd () // boot_disk in
        Xml.set_prop node "file" abs_boot_disk
      | _ -> assert false in

    (* Test boot the guest. *)
    (try test_boot boot_disk boot_xml_doc
     with
     | Libvirt.Virterror err ->
       prerr_endline (Libvirt.Virterror.to_string err)
     | exn -> raise exn
    );

    (* If there's a post-boot callback, run it now. *)
    (match test_plan.post_boot_test with
    | None -> ()
    | Some fn ->
      let g, root = inspect_and_mount_disk boot_disk in
      fn g root converted_xml_doc (* or boot_xml_doc? *);
      g#close ()
    )

let skip ~test reason =
  printf "%s: test skipped because: %s\n%!" test reason;
  exit 77
