/* libguestfs - shared disk decryption
 * Copyright (C) 2010 Red Hat Inc.
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/**
 * This file implements the decryption of disk images, usually done
 * before mounting their partitions.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>
#include <error.h>
#include <assert.h>

#include "c-ctype.h"

#include "guestfs.h"

#include "options.h"

/**
 * Make a LUKS map name from the partition name,
 * eg. C<"/dev/vda2" =E<gt> "luksvda2">
 */
static void
make_mapname (const char *device, char *mapname, size_t len)
{
  size_t i = 0;

  if (len < 5)
    abort ();
  strcpy (mapname, "luks");
  mapname += 4;
  len -= 4;

  if (STRPREFIX (device, "/dev/"))
    i = 5;

  for (; device[i] != '\0' && len >= 1; ++i) {
    if (c_isalnum (device[i])) {
      *mapname++ = device[i];
      len--;
    }
  }

  *mapname = '\0';
}

/**
 * Simple implementation of decryption: look for any C<crypto_LUKS>
 * partitions and decrypt them, then rescan for VGs.  This only works
 * for Fedora whole-disk encryption.  WIP to make this work for other
 * encryption schemes.
 */
void
inspect_do_decrypt (guestfs_h *g, struct key_store *ks)
{
  CLEANUP_FREE_STRING_LIST char **partitions = guestfs_list_partitions (g);
  if (partitions == NULL)
    exit (EXIT_FAILURE);

  int need_rescan = 0, r;
  size_t i, j;

  for (i = 0; partitions[i] != NULL; ++i) {
    CLEANUP_FREE char *type = guestfs_vfs_type (g, partitions[i]);
    if (type && STREQ (type, "crypto_LUKS")) {
      char mapname[32];
      make_mapname (partitions[i], mapname, sizeof mapname);

      CLEANUP_FREE_STRING_LIST char **keys = get_keys (ks, partitions[i]);
      assert (guestfs_int_count_strings (keys) > 0);

      /* Try each key in turn. */
      for (j = 0; keys[j] != NULL; ++j) {
        /* XXX Should we call guestfs_luks_open_ro if readonly flag
         * is set?  This might break 'mount_ro'.
         */
        guestfs_push_error_handler (g, NULL, NULL);
        r = guestfs_luks_open (g, partitions[i], keys[j], mapname);
        guestfs_pop_error_handler (g);
        if (r == 0)
          goto opened;
      }
      error (EXIT_FAILURE, 0,
             _("could not find key to open LUKS encrypted %s.\n\n"
               "Try using --key on the command line.\n\n"
               "Original error: %s (%d)"),
             partitions[i], guestfs_last_error (g),
             guestfs_last_errno (g));

    opened:
      need_rescan = 1;
    }
  }

  if (need_rescan) {
    if (guestfs_lvm_scan (g, 1) == -1)
      exit (EXIT_FAILURE);
  }
}
