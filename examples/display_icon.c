#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <guestfs.h>

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

static size_t
count_strings (char *const *argv)
{
  size_t c;

  for (c = 0; argv[c]; ++c)
    ;
  return c;
}

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  const char *disk;
  char **roots, *root, **mountpoints, *icon;
  size_t i, j, icon_size;
  FILE *fp;

  if (argc != 2) {
    fprintf (stderr, "usage: display_icon disk.img\n");
    exit (EXIT_FAILURE);
  }
  disk = argv[1];

  g = guestfs_create ();
  if (g == NULL) {
    perror ("failed to create libguestfs handle");
    exit (EXIT_FAILURE);
  }

  /* Attach the disk image read-only to libguestfs. */
  if (guestfs_add_drive_opts (g, disk,
     /* GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw", */
        GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
        -1) /* this marks end of optional arguments */
      == -1)
    exit (EXIT_FAILURE);

  /* Run the libguestfs back-end. */
  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Ask libguestfs to inspect for operating systems. */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);
  if (roots[0] == NULL) {
    fprintf (stderr, "display_icon: no operating systems found\n");
    exit (EXIT_FAILURE);
  }

  for (j = 0; roots[j] != NULL; ++j) {
    root = roots[j];

    /* Mount up the disks, like guestfish -i.
     *
     * Sort keys by length, shortest first, so that we end up
     * mounting the filesystems in the correct order.
     */
    mountpoints = guestfs_inspect_get_mountpoints (g, root);
    if (mountpoints == NULL)
      exit (EXIT_FAILURE);

    qsort (mountpoints, count_strings (mountpoints) / 2, 2 * sizeof (char *),
           compare_keys_len);
    for (i = 0; mountpoints[i] != NULL; i += 2) {
      /* Ignore failures from this call, since bogus entries can
       * appear in the guest's /etc/fstab.
       */
      guestfs_mount_ro (g, mountpoints[i+1], mountpoints[i]);
      free (mountpoints[i]);
      free (mountpoints[i+1]);
    }
    free (mountpoints);

    /* Get the icon.
     * This function returns a buffer ('icon').  Normally it is a png
     * file, returned as a string, but it can also be a zero length
     * buffer which has a special meaning, or NULL which means there
     * was an error.
     */
    icon = guestfs_inspect_get_icon (g, root, &icon_size, -1);
    if (!icon)                  /* actual libguestfs error */
      exit (EXIT_FAILURE);
    if (icon_size == 0)         /* no icon available */
      fprintf (stderr, "%s: %s: no icon available for this operating system\n",
               disk, root);
    else {
      /* Display the icon. */
      fp = popen ("display -", "w");
      if (fp == NULL) {
        perror ("display");
        exit (EXIT_FAILURE);
      }
      if (fwrite (icon, 1, icon_size, fp) != icon_size) {
        perror ("write");
        exit (EXIT_FAILURE);
      }
      if (pclose (fp) == -1) {
        perror ("pclose");
        exit (EXIT_FAILURE);
      }
    }
    free (icon);

    /* Unmount everything. */
    if (guestfs_umount_all (g) == -1)
      exit (EXIT_FAILURE);

    free (root);
  }
  free (roots);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
