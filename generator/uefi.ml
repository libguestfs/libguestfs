(* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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

open Utils
open Pr
open Docstrings

(* danpb is proposing that libvirt supports E<lt>loader type="efi"/E<gt>
 * (L<https://bugzilla.redhat.com/1217444#c6>).  If that happens we can
 * simplify or even remove this code.
 *)

(* Order is significant *within architectures only*. *)
let firmware = [
    "i386",
    "/usr/share/edk2.git/ovmf-ia32/OVMF_CODE-pure-efi.fd",
    None,
    "/usr/share/edk2.git/ovmf-ia32/OVMF_VARS-pure-efi.fd",
    [];

    "x86_64",
    "/usr/share/OVMF/OVMF_CODE.fd",
    None,
    "/usr/share/OVMF/OVMF_VARS.fd",
    [];

    "x86_64",
    "/usr/share/edk2/ovmf/OVMF_CODE.fd",
    None,
    "/usr/share/edk2/ovmf/OVMF_VARS.fd",
    [];

    (* kraxel's old repository, these will be removed by end of 2016. *)
    "x86_64",
    "/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd",
    None,
    "/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",
    [];

    "x86_64",
    "/usr/share/qemu/ovmf-x86_64-code.bin",
    None,
    "/usr/share/qemu/ovmf-x86_64-vars.bin",
    [];

    "aarch64",
    "/usr/share/AAVMF/AAVMF_CODE.fd",
    Some "/usr/share/AAVMF/AAVMF_CODE.verbose.fd",
    "/usr/share/AAVMF/AAVMF_VARS.fd",
    [];

    "aarch64",
    "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw",
    None,
    "/usr/share/edk2/aarch64/vars-template-pflash.raw",
    [];

    (* kraxel's old repository, these will be removed by end of 2016. *)
    "aarch64",
    "/usr/share/edk2.git/aarch64/QEMU_EFI-pflash.raw",
    None,
    "/usr/share/edk2.git/aarch64/vars-template-pflash.raw",
    [];
]

let arches = sort_uniq (List.map (fun (arch, _, _, _, _) -> arch) firmware)

let generate_uefi_c () =
  generate_header CStyle LGPLv2plus;

  pr "#include <config.h>\n";
  pr "\n";
  pr "#include <stdio.h>\n";
  pr "\n";
  pr "#include \"guestfs-internal-frontend.h\"\n";

  List.iter (
    fun arch ->
      let firmware =
        List.filter (fun (arch', _, _, _, _) -> arch = arch') firmware in
      pr "\n";
      pr "struct uefi_firmware\n";
      pr "guestfs_int_uefi_%s_firmware[] = {\n" arch;
      List.iter (
        fun (_, code, code_debug, vars, flags) ->
          assert (flags = []);
          pr "  { \"%s\",\n" (c_quote code);
          (match code_debug with
           | None -> pr "    NULL,\n"
           | Some code_debug -> pr "    \"%s\",\n" (c_quote code_debug)
          );
          pr "    \"%s\",\n" (c_quote vars);
          pr "    0\n";
          pr "  },\n";
      ) firmware;
      pr "};\n";
  ) arches

let generate_uefi_ml () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
type uefi_firmware = {
  code : string;
  code_debug : string option;
  vars : string;
  flags : unit list;
}
";
  List.iter (
    fun arch ->
      let firmware =
        List.filter (fun (arch', _, _, _, _) -> arch = arch') firmware in
      pr "\n";
      pr "let uefi_%s_firmware = [\n" arch;
      List.iter (
        fun (_, code, code_debug, vars, flags) ->
          assert (flags = []);
          pr "  { code = %S;\n" code;
          (match code_debug with
           | None -> pr "    code_debug = None;\n"
           | Some code_debug -> pr "    code_debug = Some %S;\n" code_debug
          );
          pr "    vars = %S;\n" vars;
          pr "    flags = [];\n";
          pr "  };\n";
      ) firmware;
      pr "]\n";
  ) arches

let generate_uefi_mli () =
  generate_header OCamlStyle GPLv2plus;

  pr "\
(** UEFI paths. *)

type uefi_firmware = {
  code : string;                (** code file *)
  code_debug : string option;   (** code debug file *)
  vars : string;                (** vars template file *)
  flags : unit list;            (** flags *)
}

";

  List.iter (pr "val uefi_%s_firmware : uefi_firmware list\n") arches
