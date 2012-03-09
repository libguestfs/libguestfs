/* Copy a directory from one libvirt guest to another.
 *
 * This is a more substantial example of using the libguestfs API,
 * demonstrating amongst other things:
 *
 * - using multiple handles with threads
 * - upload and downloading (using a pipe between handles)
 * - inspection
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/time.h>

#include <pthread.h>

#include <guestfs.h>
#include <libvirt/libvirt.h>

struct threaddata {
  const char *src;
  const char *srcdir;
  int fd;
  pthread_t mainthread;
};

static void *start_srcthread (void *);
static int open_guest (guestfs_h *g, const char *dom, int readonly);
static int64_t timeval_diff (const struct timeval *x, const struct timeval *y);
static int compare_keys_len (const void *p1, const void *p2);
static size_t count_strings (char *const *argv);

static void
usage (void)
{
  fprintf (stderr,
    "Usage: copy_over source srcdir dest destdir\n"
    "\n"
    "  source  : the source domain (a libvirt guest name)\n"
    "  srcdir  : the directory to copy from the source guest\n"
    "  dest    : the destination domain (a libvirt guest name)\n"
    "  destdir : the destination directory (must exist at destination)\n"
    "\n"
    "eg: copy_over Src /home/rjones Dest /tmp/dir\n"
    "would copy /home/rjones from Src to /tmp/dir on Dest\n"
    "\n"
    "The destination guest cannot be running.\n");
}

int
main (int argc, char *argv[])
{
  const char *src, *srcdir, *dest, *destdir;
  guestfs_h *destg;
  int fd[2];
  pthread_t srcthread;
  struct threaddata threaddata;
  int err;
  char fdname[128];
  struct timeval start_t, end_t;
  int64_t ms;

  /* This is required when using libvirt from multiple threads. */
  virInitialize ();

  if (argc != 5) {
    usage ();
    exit (EXIT_FAILURE);
  }

  src = argv[1];
  srcdir = argv[2];
  dest = argv[3];
  destdir = argv[4];

  /* Instead of downloading to local disk and uploading, we are going
   * to connect the source download and destination upload using a
   * pipe.  Create that pipe.
   */
  if (pipe (fd) == -1) {
    perror ("pipe");
    exit (EXIT_FAILURE);
  }

  /* We don't want the pipe to be passed to subprocesses. */
  if (fcntl (fd[0], F_SETFD, FD_CLOEXEC) == -1 ||
      fcntl (fd[1], F_SETFD, FD_CLOEXEC) == -1) {
    perror ("fcntl");
    exit (EXIT_FAILURE);
  }

  /* The libguestfs API is synchronous, so if we want to use two
   * handles concurrently, then we have to have two threads.  In this
   * case the main thread (this one) is handling the destination
   * domain (uploading), and we create one more thread to handle the
   * source domain (downloading).
   */
  threaddata.src = src;
  threaddata.srcdir = srcdir;
  threaddata.fd = fd[1];
  threaddata.mainthread = pthread_self ();
  err = pthread_create (&srcthread, NULL, start_srcthread, &threaddata);
  if (err != 0) {
    fprintf (stderr, "pthread_create: %s\n", strerror (err));
    exit (EXIT_FAILURE);
  }

  /* Open the destination domain. */
  destg = guestfs_create ();
  if (!destg) {
    perror ("failed to create libguestfs handle");
    pthread_cancel (srcthread);
    exit (EXIT_FAILURE);
  }
  if (open_guest (destg, dest, 0) == -1) {
    pthread_cancel (srcthread);
    exit (EXIT_FAILURE);
  }

  gettimeofday (&start_t, NULL);

  /* Begin the upload. */
  snprintf (fdname, sizeof fdname, "/dev/fd/%d", fd[0]);
  if (guestfs_tar_in (destg, fdname, destdir) == -1) {
    pthread_cancel (srcthread);
    exit (EXIT_FAILURE);
  }

  /* Close our end of the pipe.  The other thread will close the
   * other side of the pipe.
   */
  close (fd[0]);

  /* Wait for the other thread to finish. */
  err = pthread_join (srcthread, NULL);
  if (err != 0) {
    fprintf (stderr, "pthread_join: %s\n", strerror (err));
    exit (EXIT_FAILURE);
  }

  /* Clean up. */
  if (guestfs_umount_all (destg) == -1)
    exit (EXIT_FAILURE);
  guestfs_close (destg);

  gettimeofday (&end_t, NULL);

  /* Print the elapsed time. */
  ms = timeval_diff (&start_t, &end_t);
  printf ("copy finished, elapsed time (excluding launch) was "
          "%" PRIi64 ".%03" PRIi64 " s\n",
          ms / 1000, ms % 1000);

  exit (EXIT_SUCCESS);
}

static void *
start_srcthread (void *arg)
{
  struct threaddata *threaddata = arg;
  guestfs_h *srcg;
  char fdname[128];

  /* Open the source domain. */
  srcg = guestfs_create ();
  if (!srcg) {
    perror ("failed to create libguestfs handle");
    pthread_cancel (threaddata->mainthread);
    exit (EXIT_FAILURE);
  }
  if (open_guest (srcg, threaddata->src, 1) == -1) {
    pthread_cancel (threaddata->mainthread);
    exit (EXIT_FAILURE);
  }

  /* Begin the download. */
  snprintf (fdname, sizeof fdname, "/dev/fd/%d", threaddata->fd);
  if (guestfs_tar_out (srcg, threaddata->srcdir, fdname) == -1) {
    pthread_cancel (threaddata->mainthread);
    exit (EXIT_FAILURE);
  }

  /* Close the pipe; this will cause the receiver to finish the upload. */
  if (close (threaddata->fd) == -1) {
    pthread_cancel (threaddata->mainthread);
    exit (EXIT_FAILURE);
  }

  /* Clean up. */
  if (guestfs_umount_all (srcg) == -1) {
    pthread_cancel (threaddata->mainthread);
    exit (EXIT_FAILURE);
  }
  guestfs_close (srcg);

  return NULL;
}

/* This function deals with the complexity of adding the domain,
 * launching the handle, and mounting up filesystems.  See
 * 'examples/inspect_vm.c' to understand how this works.
 */
static int
open_guest (guestfs_h *g, const char *dom, int readonly)
{
  char **roots, *root, **mountpoints;
  size_t i;

  /* Use libvirt to find the guest disks and add them to the handle. */
  if (guestfs_add_domain (g, dom,
                          GUESTFS_ADD_DOMAIN_READONLY, readonly,
                          -1) == -1)
    return -1;

  if (guestfs_launch (g) == -1)
    return -1;

  /* Inspect the guest, looking for operating systems. */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    return -1;

  if (roots[0] == NULL || roots[1] != NULL) {
    fprintf (stderr, "copy_over: %s: no operating systems or multiple operating systems found\n", dom);
    return -1;
  }

  root = roots[0];

  /* Mount up the filesystems (like 'guestfish -i'). */
  mountpoints = guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    return -1;

  qsort (mountpoints, count_strings (mountpoints) / 2, 2 * sizeof (char *),
         compare_keys_len);
  for (i = 0; mountpoints[i] != NULL; i += 2) {
    /* Ignore failures from this call, since bogus entries can
     * appear in the guest's /etc/fstab.
     */
    (readonly ? guestfs_mount_ro : guestfs_mount)
      (g, mountpoints[i+1], mountpoints[i]);
    free (mountpoints[i]);
    free (mountpoints[i+1]);
  }

  free (mountpoints);

  free (root);
  free (roots);

  /* Everything ready, no error. */
  return 0;
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
static int64_t
timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

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
