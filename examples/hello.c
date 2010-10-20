/* Create a "/hello" file on chosen partition.
 * eg:
 *   hello guest.img /dev/sda1
 *   hello guest.img /dev/VolGroup00/LogVol00
 */

#if HAVE_CONFIG_H
# include <config.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <guestfs.h>

int
main (int argc, char *argv[])
{
  guestfs_h *g;

  if (argc != 3 || access (argv[1], F_OK) != 0) {
    fprintf (stderr, "Usage: hello disk-image partition\n");
    exit (EXIT_FAILURE);
  }

  if (!(g = guestfs_create ())) exit (EXIT_FAILURE);

  if (guestfs_add_drive_opts (g, argv[1],
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1) exit (EXIT_FAILURE);

  if (guestfs_mount_options (g, "", argv[2], "/") == -1) exit (EXIT_FAILURE);

  if (guestfs_touch (g, "/hello") == -1) exit (EXIT_FAILURE);

  guestfs_sync (g);
  guestfs_close (g);
  return 0;
}
