/* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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
 */

/**
 * Locations of UEFI files.
 */

#include <config.h>

#include <stdio.h>

/* NB: MUST NOT include "guestfs-internal.h". */
#include "guestfs-internal-frontend.h"

/* See src/appliance.c:guestfs_int_get_uefi. */
struct uefi_firmware
guestfs_int_ovmf_i386_firmware[] = {
  /* kraxel's old repository, these will be removed by end of 2016. */
  { "/usr/share/edk2.git/ovmf-ia32/OVMF_CODE-pure-efi.fd",
    NULL,
    "/usr/share/edk2.git/ovmf-ia32/OVMF_VARS-pure-efi.fd" },

  { NULL }
};

struct uefi_firmware
guestfs_int_ovmf_x86_64_firmware[] = {
  { "/usr/share/OVMF/OVMF_CODE.fd",
    NULL,
    "/usr/share/OVMF/OVMF_VARS.fd" },

  { "/usr/share/edk2/ovmf/OVMF_CODE.fd",
    NULL,
    "/usr/share/edk2/ovmf/OVMF_VARS.fd" },

  /* kraxel's old repository, these will be removed by end of 2016. */
  { "/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd",
    NULL,
    "/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd" },

  { "/usr/share/qemu/ovmf-x86_64-code.bin",
    NULL,
    "/usr/share/qemu/ovmf-x86_64-vars.bin" },

  { NULL }
};

struct uefi_firmware
guestfs_int_aavmf_firmware[] = {
  { "/usr/share/AAVMF/AAVMF_CODE.fd",
    "/usr/share/AAVMF/AAVMF_CODE.verbose.fd",
    "/usr/share/AAVMF/AAVMF_VARS.fd" },

  { "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw",
    NULL,
    "/usr/share/edk2/aarch64/vars-template-pflash.raw" },

  /* kraxel's old repository, these will be removed by end of 2016. */
  { "/usr/share/edk2.git/aarch64/QEMU_EFI-pflash.raw",
    NULL,
    "/usr/share/edk2.git/aarch64/vars-template-pflash.raw" },

  { NULL }
};
