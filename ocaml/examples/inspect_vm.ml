(* Example showing how to inspect a virtual machine disk. *)

open Printf

let disk =
  if Array.length Sys.argv = 2 then
    Sys.argv.(1)
  else
    failwith "usage: inspect_vm disk.img"

let () =
  let g = new Guestfs.guestfs () in

  (* Attach the disk image read-only to libguestfs. *)
  g#add_drive_opts (*~format:"raw"*) ~readonly:true disk;

  (* Run the libguestfs back-end. *)
  g#launch ();

  (* Ask libguestfs to inspect for operating systems. *)
  let roots = g#inspect_os () in
  if Array.length roots = 0 then
    failwith "inspect_vm: no operating systems found";

  Array.iter (
    fun root ->
      printf "Root device: %s\n" root;

      (* Print basic information about the operating system. *)
      printf "  Product name: %s\n" (g#inspect_get_product_name root);
      printf "  Version:      %d.%d\n"
        (g#inspect_get_major_version root)
        (g#inspect_get_minor_version root);
      printf "  Type:         %s\n" (g#inspect_get_type root);
      printf "  Distro:       %s\n" (g#inspect_get_distro root);

      (* Mount up the disks, like guestfish -i.
       *
       * Sort keys by length, shortest first, so that we end up
       * mounting the filesystems in the correct order.
       *)
      let mps = g#inspect_get_mountpoints root in
      let cmp (a,_) (b,_) =
        compare (String.length a) (String.length b) in
      let mps = List.sort cmp mps in
      List.iter (
        fun (mp, dev) ->
          try g#mount_ro dev mp
          with Guestfs.Error msg -> eprintf "%s (ignored)\n" msg
      ) mps;

      (* If /etc/issue.net file exists, print up to 3 lines. *)
      let filename = "/etc/issue.net" in
      if g#is_file filename then (
        printf "--- %s ---\n" filename;
        let lines = g#head_n 3 filename in
        Array.iter print_endline lines
      );

      (* Unmount everything. *)
      g#umount_all ()
  ) roots
