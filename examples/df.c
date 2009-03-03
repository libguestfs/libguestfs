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
  if (!g) {
    perror ("guestfs_create");
    exit (1);
  }

  guestfs_set_exit_on_error (g, 1);
  guestfs_set_verbose (g, 1);

  guestfs_add_drive (g, argv[1]);

  guestfs_wait_ready (g);




  guestfs_free (g);
  return 0;
}
