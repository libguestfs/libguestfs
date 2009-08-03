/* Create a "/hello" file on chosen partition.
 * eg:
 *   hello guest.img /dev/sda1
 *   hello guest.img /dev/VolGroup00/LogVol00
 */

#include <config.h>
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
    exit (1);
  }

  if (!(g = guestfs_create ())) exit (1);

  if (guestfs_add_drive (g, argv[1]) == -1) exit (1);

  if (guestfs_launch (g) == -1) exit (1);
  if (guestfs_wait_ready (g) == -1) exit (1);

  if (guestfs_mount (g, argv[2], "/") == -1) exit (1);

  if (guestfs_touch (g, "/hello") == -1) exit (1);

  guestfs_sync (g);
  guestfs_close (g);
  return 0;
}
