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
#include "guestfs-internal-frontend.h"

#include "ignore-value.h"

#define TOTAL_TIME 60           /* Seconds, excluding launch. */
#define DEBUG 1                 /* Print overview debugging messages. */
#define MIN_THREADS 2
#define MAX_THREADS 12
#define MBYTES_PER_THREAD 900

struct thread_state {
  pthread_t thread;             /* Thread handle. */
  char *filename;               /* Disk image. */
  char *mp;                     /* Mount point. */
  int exit_status;              /* Thread exit status. */
};
static struct thread_state threads[MAX_THREADS];
static size_t nr_threads;

static void *start_thread (void *) __attribute__((noreturn));
static void test_mountpoint (const char *mp);
static void cleanup_thread_state (void);
static char *read_line_from (const char *cmd);
static int unmount (const char *mp, unsigned flags);
#define UNMOUNT_SILENT 1
#define UNMOUNT_RMDIR  2

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
  size_t i, mbytes;
  char *skip, *mbytes_s;
  struct sigaction sa;
  int fd, r, errors = 0;
  void *status;

  srandom (time (NULL));

  /* If the --test flag is given, then this is the test subprocess. */
  if (argc == 3 && STREQ (argv[1], "--test")) {
    test_mountpoint (argv[2]);
    exit (EXIT_SUCCESS);
  }

  /* Allow the test to be skipped by setting an environment variable. */
  skip = getenv ("SKIP_TEST_PARALLEL_MOUNT_LOCAL");
  if (skip && STREQ (skip, "1")) {
    fprintf (stderr, "%s: test skipped because environment variable set.\n",
             argv[0]);
    exit (77);
  }

  if (access ("/dev/fuse", W_OK) == -1) {
    fprintf (stderr, "%s: test skipped because /dev/fuse is not writable.\n",
             argv[0]);
    exit (77);
  }

  /* Choose the number of threads based on the amount of free memory. */
  mbytes_s = read_line_from ("LANG=C free -m | "
                             "grep 'buffers/cache' | awk '{print $NF}'");
  if (!mbytes_s)
    nr_threads = MIN_THREADS; /* default */
  else {
    if (sscanf (mbytes_s, "%zu", &mbytes) != 1)
      error (EXIT_FAILURE, 0, "expecting integer but got \"%s\"", mbytes_s);
    free (mbytes_s);
    nr_threads = mbytes / MBYTES_PER_THREAD;
    if (nr_threads < MIN_THREADS)
      nr_threads = MIN_THREADS;
    else if (nr_threads > MAX_THREADS)
      nr_threads = MAX_THREADS;
  }

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = catch_sigint;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGINT, &sa, NULL);
  sigaction (SIGQUIT, &sa, NULL);

  if (DEBUG)
    printf ("starting test with %zu threads\n", nr_threads);

  for (i = 0; i < nr_threads; ++i) {
    /* Create an image file and a mount point for this thread to use. */
    if (asprintf (&threads[i].filename, "test%zu.img", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
    if (asprintf (&threads[i].mp, "mp%zu", i) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    fd = open (threads[i].filename, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0600);
    if (fd == -1) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, errno, "open: %s", threads[i].filename);
    }

    if (ftruncate (fd, 512*1024*1024) == -1) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, errno, "truncate: %s", threads[i].filename);
    }

    if (close (fd) == -1) {
      cleanup_thread_state ();
      error (EXIT_FAILURE, errno, "close: %s", threads[i].filename);
    }

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

  if (guestfs_add_drive_opts (g, state->filename,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw", -1) == -1)
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
      execlp ("./test-parallel-mount-local",
              "test-parallel-mount-local", "--test", state->mp, NULL);
      perror ("execlp");
      goto error;
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
    if (WIFEXITED (status)) {
      if (WEXITSTATUS (status) != 0) {
        fprintf (stderr, "%s: test exited with non-zero status %d\n",
                 state->mp, WEXITSTATUS (status));
        goto error;
      }
    } else if (WIFSIGNALED (status)) {
      fprintf (stderr, "%s: subprocess killed by signal %d\n",
               state->mp, WTERMSIG (status));
      goto error;
    } else if (WIFSTOPPED (status)) {
      fprintf (stderr, "%s: subprocess stopped by signal %d\n",
               state->mp, WSTOPSIG (status));
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

/* This runs as a subprocess and must test the mountpoint at 'mp'. */
static void
test_mountpoint (const char *mp)
{
  int nr_passes = 5 + (random () & 31);
  int pass;
  int ret = EXIT_FAILURE;
  FILE *fp;

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
  if (unmount (mp, 0) == -1)
    error (EXIT_FAILURE, 0, "fusermount -u %s: failed, see earlier errors", mp);

  if (DEBUG) {
    printf ("%-8s > unmounted filesystem\n", mp);
    fflush (stdout);
  }

  exit (ret);
}

/* We may need to retry this a few times because of processes which
 * run in the background jumping into mountpoints.  Only display
 * errors if it still fails after many retries.
 */
static int
unmount (const char *mp, unsigned flags)
{
  char logfile[256];
  char cmd[256];
  int tries = 5, status, r;

  if (flags & UNMOUNT_RMDIR) {
    r = rmdir (mp);
    if (r == 0 || (r == -1 && errno != EBUSY && errno != ENOTCONN))
      return 0;
  }

  snprintf (logfile, sizeof logfile, "%s.fusermount.tmp", mp);
  unlink (logfile);

  snprintf (cmd, sizeof cmd, "fusermount -u %s >> %s 2>&1", mp, logfile);

  while (tries > 0) {
    status = system (cmd);
    if (WIFEXITED (status) && WEXITSTATUS (status) == 0)
      break;
    sleep (1);
    tries--;
  }

  if (tries == 0) {             /* Failed. */
    if (!(flags & UNMOUNT_SILENT)) {
      fprintf (stderr, "fusermount -u %s: command failed:\n", mp);
      snprintf (cmd, sizeof cmd, "cat %s", logfile);
      ignore_value (system (cmd));
    }
    unlink (logfile);
    return -1;
  }

  unlink (logfile);

  if (flags & UNMOUNT_RMDIR) {
    if (rmdir (mp) == -1)
      return -1;
  }

  return 0;
}

/* Cleanup thread state. */
static void
cleanup_thread_state (void)
{
  size_t i;

  for (i = 0; i < nr_threads; ++i) {
    if (threads[i].filename) {
      unlink (threads[i].filename);
      free (threads[i].filename);
    }

    if (threads[i].mp) {
      unmount (threads[i].mp, UNMOUNT_SILENT|UNMOUNT_RMDIR);
      free (threads[i].mp);
    }
  }
}

/* Run external command and read the first line of output. */
static char *
read_line_from (const char *cmd)
{
  FILE *pp;
  char *ret = NULL;
  size_t allocsize;

  pp = popen (cmd, "r");
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "%s: external command failed", cmd);

  if (getline (&ret, &allocsize, pp) == -1)
    error (EXIT_FAILURE, errno, "could not read line from external command");

  if (pclose (pp) == -1)
    error (EXIT_FAILURE, errno, "pclose");

  return ret;
}
