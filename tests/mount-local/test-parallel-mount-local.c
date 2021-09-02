/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Test mount-local APIs in parallel. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <error.h>

#include <pthread.h>

#include "guestfs.h"
#include "guestfs-utils.h"
#include "estimate-max-threads.h"

#include "ignore-value.h"
#include "getprogname.h"

#define TOTAL_TIME 60           /* Seconds, excluding launch. */
#define DEBUG 1                 /* Print overview debugging messages. */
#define MAX_THREADS 12

struct thread_state {
  pthread_t thread;             /* Thread handle. */
  char *mp;                     /* Mount point. */
  int exit_status;              /* Thread exit status. */
};
static struct thread_state threads[MAX_THREADS];
static size_t nr_threads;

static void *start_thread (void *) __attribute__((noreturn));
static void test_mountpoint (const char *mp);
static void cleanup_thread_state (void);
static int guestunmount (const char *mp, unsigned flags);
#define GUESTUNMOUNT_SILENT 1
#define GUESTUNMOUNT_RMDIR  2

static volatile sig_atomic_t quit = 0;

static void
catch_sigint (int signal)
{
  static char cleaning_up[] = "\ngot signal, cleaning up ...\n";

  if (quit == 0) {
    quit = 1;
    ignore_value (write (2, cleaning_up, sizeof cleaning_up));
  }
}

int
main (int argc, char *argv[])
{
  size_t i;
  char *skip;
  struct sigaction sa;
  int r, errors = 0;
  void *status;

  srandom (time (NULL) + getpid ());

  /* If the --test flag is given, then this is the test subprocess. */
  if (argc == 3 && STREQ (argv[1], "--test")) {
    test_mountpoint (argv[2]);
    exit (EXIT_SUCCESS);
  }

  /* Allow the test to be skipped by setting an environment variable. */
  skip = getenv ("SKIP_TEST_PARALLEL_MOUNT_LOCAL");
  if (skip && guestfs_int_is_true (skip) > 0) {
    fprintf (stderr, "%s: test skipped because environment variable set.\n",
             getprogname ());
    exit (77);
  }

  if (access ("/dev/fuse", W_OK) == -1) {
    fprintf (stderr, "%s: test skipped because /dev/fuse is not writable.\n",
             getprogname ());
    exit (77);
  }

  /* Choose the number of threads based on the amount of free memory. */
  nr_threads = MIN (MAX_THREADS, estimate_max_threads ());

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = catch_sigint;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGINT, &sa, NULL);
  sigaction (SIGQUIT, &sa, NULL);

  if (DEBUG)
    printf ("starting test with %zu threads\n", nr_threads);

  for (i = 0; i < nr_threads; ++i) {
    /* Create a mount point for this thread to use. */
    if (asprintf (&threads[i].mp, "mp%zu", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    rmdir (threads[i].mp);
    if (mkdir (threads[i].mp, 0700) == -1) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, errno, "mkdir: %s", threads[i].mp);
    }

    /* Start the thread. */
    if (DEBUG) {
      printf ("%-8s : starting thread\n", threads[i].mp);
      fflush (stdout);
    }
    r = pthread_create (&threads[i].thread, NULL, start_thread,
                        &threads[i]);
    if (r != 0) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, r, "pthread_create");
    }
  }

  /* Wait for the threads to exit. */
  for (i = 0; i < nr_threads; ++i) {
    r = pthread_join (threads[i].thread, &status);
    if (r != 0) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, r, "pthread_join");
    }
    if (*(int *)status != 0) {
      fprintf (stderr, "%s: thread returned an error\n", threads[i].mp);
      errors++;
    }
  }

  cleanup_thread_state ();

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

/* Run the test in a single thread. */
static void *
start_thread (void *statevp)
{
  struct thread_state *state = statevp;
  guestfs_h *g;
  time_t start_t, t;
  pid_t pid;
  int status, r;

  g = guestfs_create ();
  if (g == NULL) {
    perror ("guestfs_create");
    state->exit_status = 1;
    pthread_exit (&state->exit_status);
  }

  guestfs_set_identifier (g, state->mp);

  if (guestfs_add_drive_scratch (g, 512*1024*1024, -1) == -1)
    goto error;
  if (guestfs_launch (g) == -1)
    goto error;

  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    goto error;
  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    goto error;
  if (guestfs_mount (g, "/dev/sda1", "/") == -1)
    goto error;

  time (&start_t);

  for (;;) {
    /* Keep testing until we run out of time. */
    time (&t);
    if (quit || t - start_t >= TOTAL_TIME)
      break;

    if (DEBUG) {
      printf ("%-8s < mounting filesystem\n", state->mp);
      fflush (stdout);
    }

    if (guestfs_mount_local (g, state->mp, -1) == -1)
      goto error;

    /* Run the test in an exec'd subprocess.  This minimizes the
     * chance of shared file descriptors or other resources [ie.
     * across clone] causing deadlocks in FUSE.
     */
    pid = fork ();
    if (pid == -1) {
      perror ("fork");
      goto error;
    }

    if (pid == 0) { /* child */
      setpgid (0, 0);           /* so we don't get ^C from parent */
      execlp ("mount-local/test-parallel-mount-local",
              "test-parallel-mount-local", "--test", state->mp, NULL);
      perror ("execlp");
      _exit (EXIT_FAILURE);
    }

    /* Run the FUSE main loop.  We don't really want to see libguestfs
     * errors here since these are harmless.
     */
    guestfs_push_error_handler (g, NULL, NULL);
    r = guestfs_mount_local_run (g);
    guestfs_pop_error_handler (g);

    /* Wait for child process to exit and catch any errors from it. */
  again:
    if (waitpid (pid, &status, 0) == -1) {
      if (errno == EINTR)
        goto again;
      perror ("waitpid");
      goto error;
    }
    if (!WIFEXITED (status) || WEXITSTATUS (status) != 0) {
      char status_string[80];

      fprintf (stderr, "%s: %s\n", state->mp,
               guestfs_int_exit_status_to_string (status, "test",
						  status_string,
						  sizeof status_string));
      goto error;
    }

    if (r == -1) /* guestfs_mount_local_run above failed */
      goto error;
  }

  if (DEBUG) {
    printf ("%-8s : shutting down handle and thread\n", state->mp);
    fflush (stdout);
  }

  if (guestfs_shutdown (g) == -1)
    pthread_exit (&state->exit_status);
  guestfs_close (g);

  /* Test finished successfully. */
  state->exit_status = 0;
  pthread_exit (&state->exit_status);

 error:
  guestfs_close (g);
  state->exit_status = 1;
  pthread_exit (&state->exit_status);
}

/* https://gcc.gnu.org/bugzilla/show_bug.cgi?id=99716 */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-double-fclose"
/* This runs as a subprocess and must test the mountpoint at 'mp'. */
static void
test_mountpoint (const char *mp)
{
  const int nr_passes = 5 + (random () & 31);
  int pass;
  int ret = EXIT_FAILURE;

  if (!mp || STREQ (mp, ""))
    error (EXIT_FAILURE, 0, "%s: invalid or empty mountpoint path", __func__);

  if (DEBUG) {
    printf ("%-8s | testing filesystem\n", mp);
    fflush (stdout);
  }

  if (chdir (mp) == -1) {
    perror (mp);
    goto error;
  }

  /* Run through the same set of tests repeatedly a number of times.
   * The aim of this stress test is repeated mount/unmount, not
   * testing the FUSE data path, so we don't do much here.
   */
  for (pass = 0; pass < nr_passes; ++pass) {
    FILE *fp;

    if (mkdir ("tmp.d", 0700) == -1) {
      perror ("mkdir: tmp.d");
      goto error;
    }
    fp = fopen ("file", "w");
    if (fp == NULL) {
      perror ("create: file");
      goto error;
    }
    fprintf (fp, "hello world\n");
    fclose (fp);
    if (rename ("tmp.d", "newdir") == -1) {
      perror ("rename tmp.d newdir");
      goto error;
    }
    if (link ("file", "newfile") == -1) {
      perror ("link: file newfile");
      goto error;
    }
    if (rmdir ("newdir") == -1) {
      perror ("rmdir: newdir");
      goto error;
    }
    if (unlink ("file") == -1) {
      perror ("unlink: file");
      goto error;
    }
    if (unlink ("newfile") == -1) {
      perror ("unlink: newfile");
      goto error;
    }
  }

  if (DEBUG) {
    printf ("%-8s | test finished\n", mp);
    fflush (stdout);
  }

  ret = EXIT_SUCCESS;
 error:
  ignore_value (chdir (".."));
  if (guestunmount (mp, 0) == -1)
    error (EXIT_FAILURE, 0, "guestunmount %s: failed, see earlier errors", mp);

  if (DEBUG) {
    printf ("%-8s > unmounted filesystem\n", mp);
    fflush (stdout);
  }

  exit (ret);
}
#pragma GCC diagnostic pop

static int
guestunmount (const char *mp, unsigned flags)
{
  char cmd[256];
  int status, r;

  if (flags & GUESTUNMOUNT_RMDIR) {
    r = rmdir (mp);
    if (r == 0 || (r == -1 && errno != EBUSY && errno != ENOTCONN))
      return 0;
  }

  snprintf (cmd, sizeof cmd,
            "../fuse/guestunmount%s %s",
            (flags & GUESTUNMOUNT_SILENT) ? " --quiet" : "", mp);

  status = system (cmd);
  if (!WIFEXITED (status) ||
      (WEXITSTATUS (status) != 0 && WEXITSTATUS (status) != 2)) {
    fprintf (stderr, "guestunmount exited with bad status (%d)\n", status);
    return -1;
  }

  if (flags & GUESTUNMOUNT_RMDIR) {
    if (rmdir (mp) == -1) {
      perror ("rmdir");
      return -1;
    }
  }

  return 0;
}

/* Cleanup thread state. */
static void
cleanup_thread_state (void)
{
  size_t i;

  for (i = 0; i < nr_threads; ++i) {
    if (threads[i].mp) {
      guestunmount (threads[i].mp, GUESTUNMOUNT_SILENT|GUESTUNMOUNT_RMDIR);
      free (threads[i].mp);
    }
  }
}
