(* An example using the OCaml bindings. *)

open Printf

let () =
  if Array.length Sys.argv <= 1 || not (Sys.file_exists Sys.argv.(1)) then (
    eprintf "Usage: lvs guest.img\n";
    exit 1
  );

  let h = Guestfs.create () in
  Guestfs.add_drive_opts h ~format:"raw" Sys.argv.(1);
  Guestfs.launch h;

  let pvs = Guestfs.pvs h in
  printf "PVs found: [ %s ]\n" (String.concat "; " (Array.to_list pvs));

  let vgs = Guestfs.vgs h in
  printf "VGs found: [ %s ]\n" (String.concat "; " (Array.to_list vgs));

  let lvs = Guestfs.lvs h in
  printf "LVs found: [ %s ]\n" (String.concat "; " (Array.to_list lvs));

  (* Helps to find any allocation errors. *)
  Gc.compact ()
