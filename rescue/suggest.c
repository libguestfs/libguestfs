/* virt-rescue
 * Copyright (C) 2010-2023 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <locale.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-utils.h"

#include "options.h"

#include "rescue.h"

static void suggest_filesystems (void);

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

/* virt-rescue --suggest flag does a kind of inspection on the
 * drives and suggests mount commands that you should use.
 */
void
do_suggestion (struct drv *drvs)
{
  CLEANUP_FREE_STRING_LIST char **roots = NULL;
  size_t i;

  /* For inspection, force add_drives to add the drives read-only. */
  read_only = 1;

  /* Add drives. */
  add_drives (drvs);

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  printf (_("Inspecting the virtual machine or disk image ...\n\n"));
  fflush (stdout);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Don't use inspect_mount, since for virt-rescue we should allow
   * arbitrary disks and disks with more than one OS on them.  Let's
   * do this using the basic API instead.
   */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);

  if (roots[0] == NULL) {
    suggest_filesystems ();
    return;
  }

  printf (_("This disk contains one or more operating systems.  You can use these mount\n"
            "commands in virt-rescue (at the ><rescue> prompt) to mount the filesystems.\n\n"));

  for (i = 0; roots[i] != NULL; ++i) {
    CLEANUP_FREE_STRING_LIST char **mps = NULL;
    CLEANUP_FREE char *type = NULL, *distro = NULL, *product_name = NULL;
    int major, minor;
    size_t j;

    type = guestfs_inspect_get_type (g, roots[i]);
    distro = guestfs_inspect_get_distro (g, roots[i]);
    product_name = guestfs_inspect_get_product_name (g, roots[i]);
    major = guestfs_inspect_get_major_version (g, roots[i]);
    minor = guestfs_inspect_get_minor_version (g, roots[i]);

    printf (_("# %s is the root of a %s operating system\n"
              "# type: %s, distro: %s, version: %d.%d\n"
              "# %s\n\n"),
            roots[i], type ? : "unknown",
            type ? : "unknown", distro ? : "unknown", major, minor,
            product_name ? : "");

    mps = guestfs_inspect_get_mountpoints (g, roots[i]);
    if (mps == NULL)
      exit (EXIT_FAILURE);

    /* Sort by key length, shortest key first, so that we end up
     * mounting the filesystems in the correct order.
     */
    qsort (mps, guestfs_int_count_strings (mps) / 2, 2 * sizeof (char *),
           compare_keys_len);

    for (j = 0; mps[j] != NULL; j += 2)
      printf ("mount %s /sysroot%s\n", mps[j+1], mps[j]);

    /* If it's Linux, print the bind-mounts and a chroot command. */
    if (type && STREQ (type, "linux")) {
      printf ("mount --rbind /dev /sysroot/dev\n");
      printf ("mount --rbind /proc /sysroot/proc\n");
      printf ("mount --rbind /sys /sysroot/sys\n");
      printf ("\n");
      printf ("cd /sysroot\n");
      printf ("chroot /sysroot\n");
    }

    printf ("\n");
  }
}

/* Inspection failed, so it doesn't contain any OS that we recognise.
 * However there might still be filesystems so print some suggestions
 * for those.
 */
static void
suggest_filesystems (void)
{
  size_t i, count;

  CLEANUP_FREE_STRING_LIST char **fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    exit (EXIT_FAILURE);

  /* Count how many are not swap or unknown.  Possibly we should try
   * mounting to see which are mountable, but that has a high
   * probability of breaking.
   */
#define TEST_MOUNTABLE(fs) STRNEQ ((fs), "swap") && STRNEQ ((fs), "unknown")
  count = 0;
  for (i = 0; fses[i] != NULL; i += 2) {
    if (TEST_MOUNTABLE (fses[i+1]))
      count++;
  }

  if (count == 0) {
    printf (_("This disk contains no mountable filesystems that we recognize.\n\n"
              "However you can still use virt-rescue on the disk image, to try to mount\n"
              "filesystems that are not recognized by libguestfs, or to create partitions,\n"
              "logical volumes and filesystems on a blank disk.\n"));
    return;
  }

  printf (_("This disk contains one or more filesystems, but we don’t recognize any\n"
            "operating system.  You can use these mount commands in virt-rescue (at the\n"
            "><rescue> prompt) to mount these filesystems.\n\n"));

  for (i = 0; fses[i] != NULL; i += 2) {
    printf (_("# %s has type ‘%s’\n"), fses[i], fses[i+1]);

    if (TEST_MOUNTABLE (fses[i+1]))
      printf ("mount %s /sysroot\n", fses[i]);

    printf ("\n");
  }
#undef TEST_MOUNTABLE
}
