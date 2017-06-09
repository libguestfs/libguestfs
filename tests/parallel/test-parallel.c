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

/* This test is mainly aimed at libvirt: There appear to be a lot of
 * cases where libvirt is racy when creating transient guests.
 * Therefore this test simply launches lots of handles in parallel for
 * many minutes, hoping to reveal problems in libvirt this way.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <error.h>
#include <sys/types.h>

#include <pthread.h>

#include "guestfs.h"
#include "guestfs-utils.h"

#include "ignore-value.h"
#include "getprogname.h"

#define TOTAL_TIME 600          /* Seconds, excluding launch. */
#define NR_THREADS 5

struct thread_state {
  size_t thread_num;            /* Thread number. */
  pthread_t thread;             /* Thread handle. */
  int exit_status;              /* Thread exit status. */
};
static struct thread_state threads[NR_THREADS];

static void *start_thread (void *) __attribute__((noreturn));

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
  const char *skip, *slow;
  struct sigaction sa;
  int r;
  size_t i, errors = 0;
  void *status;

  srandom (time (NULL) + getpid ());

  /* Only run this test when invoked by check-slow. */
  slow = getenv ("SLOW");
  if (!slow || guestfs_int_is_true (slow) <= 0) {
    fprintf (stderr, "%s: use 'make check-slow' to run this test.\n",
             getprogname ());
    exit (77);
  }

  /* Allow the test to be skipped by setting an environment variable. */
  skip = getenv ("SKIP_TEST_PARALLEL");
  if (skip && guestfs_int_is_true (skip) > 0) {
    fprintf (stderr, "%s: test skipped because environment variable set.\n",
             getprogname ());
    exit (77);
  }

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = catch_sigint;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGINT, &sa, NULL);
  sigaction (SIGQUIT, &sa, NULL);

  for (i = 0; i < NR_THREADS; ++i) {
    threads[i].thread_num = i;
    /* Start the thread. */
    r = pthread_create (&threads[i].thread, NULL, start_thread,
                        &threads[i]);
    if (r != 0)
      error (EXIT_FAILURE, r, "pthread_create");
  }

  /* Wait for the threads to exit. */
  for (i = 0; i < NR_THREADS; ++i) {
    r = pthread_join (threads[i].thread, &status);
    if (r != 0)
      error (EXIT_FAILURE, r, "pthread_join");
    if (*(int *)status != 0) {
      fprintf (stderr, "%zu: thread returned an error\n", i);
      errors++;
    }
  }

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

/* Run the test in a single thread. */
static void *
start_thread (void *statevp)
{
  struct thread_state *state = statevp;
  guestfs_h *g;
  time_t start_t, t;
  char id[64];

  time (&start_t);

  for (;;) {
    /* Keep testing until we run out of time. */
    time (&t);
    if (quit || t - start_t >= TOTAL_TIME)
      break;

    g = guestfs_create ();
    if (g == NULL) {
      perror ("guestfs_create");
      state->exit_status = 1;
      pthread_exit (&state->exit_status);
    }

    snprintf (id, sizeof id, "%zu", state->thread_num);
    guestfs_set_identifier (g, id);

    if (guestfs_add_drive_opts (g, "/dev/null",
                                GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                                GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                                -1) == -1) {
    error:
      guestfs_close (g);
      state->exit_status = 1;
      pthread_exit (&state->exit_status);
    }
    if (guestfs_launch (g) == -1)
      goto error;

    if (guestfs_shutdown (g) == -1)
      goto error;

    guestfs_close (g);
  }

  /* Test finished successfully. */
  state->exit_status = 0;
  pthread_exit (&state->exit_status);
}
