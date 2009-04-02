/* A simple "df" command for guests. */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <guestfs.h>

int
main (int argc, char *argv[])
{
  guestfs_h *g;

  if (argc != 2 || access (argv[1], F_OK) != 0) {
    fprintf (stderr, "Usage: df disk-image\n");
    exit (1);
  }

  if (!(g = guestfs_create ())) exit (1);

  guestfs_set_verbose (g, 1);
  if (guestfs_add_drive (g, argv[1]) == -1) exit (1);

  if (guestfs_launch (g) == -1) exit (1);
  if (guestfs_wait_ready (g) == -1) exit (1);



  guestfs_close (g);
  return 0;
}
