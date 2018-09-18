/* libguestfs - guestfish and guestmount shared option parsing
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
 * This file implements inspecting the guest and mounting the
 * filesystems found in the right places.  It is used by the
 * L<guestfish(1)> I<-i> option and some utilities such as
 * L<virt-cat(1)>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <error.h>
#include <libintl.h>

#include "c-ctype.h"
#include "getprogname.h"

#include "guestfs.h"

/* These definitions ensure we get all extern definitions from the header. */
#include "options.h"

/* Global that saves the root device between inspect_mount and
 * print_inspect_prompt.
 */
static char *root = NULL;

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

static int
compare_keys (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strcasecmp (key1, key2);
}

/**
 * This function implements the I<-i> option.
 */
void
inspect_mount_handle (guestfs_h *g, struct key_store *ks)
{
  if (live)
    error (EXIT_FAILURE, 0, _("don’t use --live and -i options together"));

  inspect_do_decrypt (g, ks);

  char **roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);

  if (roots[0] == NULL) {
    fprintf (stderr,
	     _("%s: no operating system was found on this disk\n"
	       "\n"
	       "If using guestfish ‘-i’ option, remove this option and instead\n"
	       "use the commands ‘run’ followed by ‘list-filesystems’.\n"
	       "You can then mount filesystems you want by hand using the\n"
	       "‘mount’ or ‘mount-ro’ command.\n"
	       "\n"
	       "If using guestmount ‘-i’, remove this option and choose the\n"
	       "filesystem(s) you want to see by manually adding ‘-m’ option(s).\n"
	       "Use ‘virt-filesystems’ to see what filesystems are available.\n"
	       "\n"
	       "If using other virt tools, this disk image won’t work\n"
	       "with these tools.  Use the guestfish equivalent commands\n"
	       "(see the virt tool manual page).\n"),
             getprogname ());
    guestfs_int_free_string_list (roots);
    exit (EXIT_FAILURE);
  }

  if (roots[1] != NULL) {
    fprintf (stderr,
	     _("%s: multi-boot operating systems are not supported\n"
	       "\n"
	       "If using guestfish ‘-i’ option, remove this option and instead\n"
	       "use the commands ‘run’ followed by ‘list-filesystems’.\n"
	       "You can then mount filesystems you want by hand using the\n"
	       "‘mount’ or ‘mount-ro’ command.\n"
	       "\n"
	       "If using guestmount ‘-i’, remove this option and choose the\n"
	       "filesystem(s) you want to see by manually adding ‘-m’ option(s).\n"
	       "Use ‘virt-filesystems’ to see what filesystems are available.\n"
	       "\n"
	       "If using other virt tools, multi-boot operating systems won’t work\n"
	       "with these tools.  Use the guestfish equivalent commands\n"
	       "(see the virt tool manual page).\n"),
             getprogname ());
    guestfs_int_free_string_list (roots);
    exit (EXIT_FAILURE);
  }

  /* Free old global if there is one. */
  free (root);

  root = roots[0];
  free (roots);

  inspect_mount_root (g, root);
}

void
inspect_mount_root (guestfs_h *g, const char *root)
{
  CLEANUP_FREE_STRING_LIST char **mountpoints =
    guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    exit (EXIT_FAILURE);

  /* Sort by key length, shortest key first, so that we end up
   * mounting the filesystems in the correct order.
   */
  qsort (mountpoints, guestfs_int_count_strings (mountpoints) / 2,
         2 * sizeof (char *),
         compare_keys_len);

  size_t i;
  size_t mount_errors = 0;
  for (i = 0; mountpoints[i] != NULL; i += 2) {
    int r;
    if (!read_only)
      r = guestfs_mount (g, mountpoints[i+1], mountpoints[i]);
    else
      r = guestfs_mount_ro (g, mountpoints[i+1], mountpoints[i]);
    if (r == -1) {
      /* If the "/" filesystem could not be mounted, give up, else
       * just count the errors and print a warning.
       */
      if (STREQ (mountpoints[i], "/"))
        exit (EXIT_FAILURE);
      mount_errors++;
    }
  }

  if (mount_errors)
    fprintf (stderr, _("%s: some filesystems could not be mounted (ignored)\n"),
             getprogname ());
}

/**
 * This function is called only if C<inspect_mount_root> was called,
 * and only after we've printed the prompt in interactive mode.
 */
void
print_inspect_prompt (void)
{
  size_t i;
  CLEANUP_FREE char *name = NULL;
  CLEANUP_FREE_STRING_LIST char **mountpoints = NULL;

  name = guestfs_inspect_get_product_name (g, root);
  if (name && STRNEQ (name, "unknown"))
    printf (_("Operating system: %s\n"), name);

  mountpoints = guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    return;

  /* Sort by key. */
  qsort (mountpoints, guestfs_int_count_strings (mountpoints) / 2,
         2 * sizeof (char *),
         compare_keys);

  for (i = 0; mountpoints[i] != NULL; i += 2) {
    /* Try to make the device name canonical for printing, but don't
     * worry if this fails.
     */
    CLEANUP_FREE char *dev =
      guestfs_canonical_device_name (g, mountpoints[i+1]);

    printf (_("%s mounted on %s\n"),
            dev ? dev : mountpoints[i+1], mountpoints[i]);
  }
}
