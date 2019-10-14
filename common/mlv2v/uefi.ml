(* libguestfs generated file
 * WARNING: THIS FILE IS GENERATED
 *          from the code in the generator/ subdirectory.
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

type uefi_firmware = {
  code : string;
  code_debug : string option;
  vars : string;
  flags : uefi_flags;
}
and uefi_flags = uefi_flag list
and uefi_flag = UEFI_FLAG_SECURE_BOOT_REQUIRED

let uefi_aarch64_firmware = [
  { code = "/usr/share/AAVMF/AAVMF_CODE.fd";
    code_debug = Some "/usr/share/AAVMF/AAVMF_CODE.verbose.fd";
    vars = "/usr/share/AAVMF/AAVMF_VARS.fd";
    flags = [];
  };
  { code = "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw";
    code_debug = None;
    vars = "/usr/share/edk2/aarch64/vars-template-pflash.raw";
    flags = [];
  };
]

let uefi_x86_64_firmware = [
  { code = "/usr/share/OVMF/OVMF_CODE.fd";
    code_debug = None;
    vars = "/usr/share/OVMF/OVMF_VARS.fd";
    flags = [];
  };
  { code = "/usr/share/OVMF/OVMF_CODE.secboot.fd";
    code_debug = None;
    vars = "/usr/share/OVMF/OVMF_VARS.fd";
    flags = [UEFI_FLAG_SECURE_BOOT_REQUIRED];
  };
  { code = "/usr/share/edk2/ovmf/OVMF_CODE.fd";
    code_debug = None;
    vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd";
    flags = [];
  };
  { code = "/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd";
    code_debug = None;
    vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd";
    flags = [UEFI_FLAG_SECURE_BOOT_REQUIRED];
  };
  { code = "/usr/share/qemu/ovmf-x86_64-code.bin";
    code_debug = None;
    vars = "/usr/share/qemu/ovmf-x86_64-vars.bin";
    flags = [];
  };
]
