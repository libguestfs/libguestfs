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

  g = guestfs_create ();
  if (!g) exit (1);

  guestfs_set_verbose (g, 1);
  guestfs_add_drive (g, argv[1]);

  guestfs_launch (g);
  guestfs_wait_ready (g);



  guestfs_close (g);
  return 0;
}
