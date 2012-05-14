/* Demonstrate the use of the 'mount-local' API.
 *
 * Run this program as (eg) mount_local /tmp/test.img.  Note that
 * '/tmp/test.img' is created or overwritten.  Follow the instructions
 * on screen.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

#include <guestfs.h>

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

static void
usage (void)
{
  fprintf (stderr,
           "Usage: mount_local disk.img\n"
           "\n"
           "NOTE: disk.img will be created or overwritten.\n"
           "\n");
}

int
main (int argc, char *argv[])
{
  guestfs_h *g;
  int fd;
  char tempdir[] = "/tmp/mlXXXXXX";
  pid_t pid;
  char *shell;

  if (argc != 2) {
    usage ();
    exit (EXIT_FAILURE);
  }

  printf ("\n"
          "This is the 'mount-local' demonstration program.  Follow the\n"
          "instructions on screen.\n"
          "\n"
          "Creating and formatting the disk image, please wait a moment ...\n");
  fflush (stdout);

  /* Create the output disk image: 512 MB raw sparse. */
  fd = open (argv[1], O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
  if (fd == -1) {
    perror (argv[1]);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, 512 * 1024 * 1024) == -1) {
    perror ("truncate");
    close (fd);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror ("close");
    exit (EXIT_FAILURE);
  }

  /* Open the disk image and format it with a partition and a filesystem. */
  g = guestfs_create ();
  if (g == NULL) {
    perror ("could not create libguestfs handle");
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_opts (g, argv[1],
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    exit (EXIT_FAILURE);

  /* Mount the empty filesystem. */
  if (guestfs_mount_options (g, "acl,user_xattr", "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  /* Create a temporary mount directory. */
  if (mkdtemp (tempdir) == NULL) {
    perror ("mkdtemp");
    exit (EXIT_FAILURE);
  }

  /* Mount the filesystem. */
  if (guestfs_mount_local (g, tempdir, -1) == -1)
    exit (EXIT_FAILURE);

  /* Fork the shell for the user. */
  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    exit (EXIT_FAILURE);
  }

  if (pid == 0) {               /* Child. */
    if (chdir (tempdir) == -1) {
      perror (tempdir);
      _exit (EXIT_FAILURE);
    }

    printf ("\n"
            "The _current directory_ is a FUSE filesystem backed by the disk\n"
            "image which is managed by libguestfs.  Any files or directories\n"
            "you copy into here (up to 512 MB) will be saved into the disk\n"
            "image.  You can also delete files, create certain special files\n"
            "and so on.\n"
            "\n"
            "When you have finished adding files, hit ^D or exit to exit the\n"
            "shell and return to the mount-local program.\n"
            "\n");

    shell = getenv ("SHELL");
    system (shell ? : "/bin/sh");

    chdir ("/");
    guestfs_umount_local (g, GUESTFS_UMOUNT_LOCAL_RETRY, 1, -1);
    _exit (EXIT_SUCCESS);
  }

  /* Note that we are *not* waiting for the child yet.  We want to
   * run the FUSE code in parallel with the subshell.
   */
  if (guestfs_mount_local_run (g) == -1)
    exit (EXIT_FAILURE);

  waitpid (pid, NULL, 0);

  /* Unmount and close. */
  if (guestfs_umount (g, "/") == -1)
    exit (EXIT_FAILURE);

  guestfs_close (g);

  printf ("\n"
          "Any files or directories that you copied in have been saved into\n"
          "the disk image called '%s'.\n"
          "\n"
          "Try opening the disk image with guestfish to see those files:\n"
          "\n"
          "  guestfish -a %s -m /dev/sda1\n"
          "\n",
          argv[1], argv[1]);

  exit (EXIT_SUCCESS);
}
