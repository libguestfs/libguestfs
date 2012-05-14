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

/* Define a list of filesystem mount options (used on the libguestfs
 * side, nothing to do with FUSE).  An empty string may be used here
 * instead.
 */
#define MOUNT_OPTIONS "acl,user_xattr"

/* Size of the disk (megabytes). */
#define SIZE_MB 512

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
  int fd, r;
  char tempdir[] = "/tmp/mlXXXXXX";
  pid_t pid;
  char *shell, *p;
  guestfs_error_handler_cb old_error_cb;
  void *old_error_data;

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

  /* Create the output disk image: raw sparse. */
  fd = open (argv[1], O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
  if (fd == -1) {
    perror (argv[1]);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, SIZE_MB * 1024 * 1024) == -1) {
    perror ("truncate");
    close (fd);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror ("close");
    exit (EXIT_FAILURE);
  }

  /* Guestfs handle. */
  g = guestfs_create ();
  if (g == NULL) {
    perror ("could not create libguestfs handle");
    exit (EXIT_FAILURE);
  }

  /* Create the disk image and format it with a partition and a filesystem. */
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
  if (guestfs_mount_options (g, MOUNT_OPTIONS, "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  /* Create a file in the new filesystem. */
  if (guestfs_touch (g, "/PUT_FILES_AND_DIRECTORIES_HERE") == -1)
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
            "you copy into here (up to %d MB) will be saved into the disk\n"
            "image.  You can also delete files, create certain special files\n"
            "and so on.\n"
            "\n"
            "When you have finished adding files, hit ^D or exit to exit the\n"
            "shell and return to the mount-local program.\n"
            "\n",
            SIZE_MB);

    shell = getenv ("SHELL");
    if (!shell)
      r = system ("/bin/sh");
    else {
      /* Set a magic prompt.  We only know how to do this for bash. */
      p = strrchr (shell, '/');
      if (p && strcmp (p+1, "bash") == 0) {
        size_t len = 64 + strlen (shell);
        char buf[len];

        snprintf (buf, len, "PS1='mount-local-shell> ' %s --norc -i", shell);
        r = system (buf);
      } else
        r = system (shell);
    }
    if (r == -1) {
      fprintf (stderr, "error: failed to run sub-shell (%s) "
               "(is $SHELL set correctly?)\n",
               shell);
      //FALLTHROUGH
    }

    chdir ("/");
    guestfs_umount_local (g, GUESTFS_UMOUNT_LOCAL_RETRY, 1, -1);
    _exit (EXIT_SUCCESS);
  }

  /* Note that we are *not* waiting for the child yet.  We want to
   * run the FUSE code in parallel with the subshell.
   */

  /* We're going to hide libguestfs errors here, but in a real program
   * you would probably want to log them somewhere.
   */
  old_error_cb = guestfs_get_error_handler (g, &old_error_data);
  guestfs_set_error_handler (g, NULL, NULL);

  /* Now run the FUSE thread. */
  if (guestfs_mount_local_run (g) == -1)
    exit (EXIT_FAILURE);

  guestfs_set_error_handler (g, old_error_cb, old_error_data);

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
