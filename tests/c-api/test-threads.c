/* libguestfs
 * Copyright (C) 2015-2023 Red Hat Inc.
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

/* Test that we can make API calls safely from multiple threads. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include <pthread.h>

#include "guestfs.h"
#include "guestfs-utils.h"

static guestfs_h *g;

#define RUN_TIME 60 /* seconds */
#define NR_CONCURRENT_THREADS 4

static void *start_thread (void *nullv);

int
main (int argc, char *argv[])
{
  time_t start_t, t;
  pthread_t threads[NR_CONCURRENT_THREADS];
  void *ret;
  int i, r;

  /* Because we rely on error message content below, force LC_ALL=C. */
  setenv ("LC_ALL", "C", 1);

  g = guestfs_create ();
  if (!g) {
    perror ("guestfs_create");
    exit (EXIT_FAILURE);
  }

  time (&start_t);

  while (time (&t), t - start_t < RUN_TIME) {
    for (i = 0; i < NR_CONCURRENT_THREADS; ++i) {
      r = pthread_create (&threads[i], NULL, start_thread, NULL);
      if (r != 0) {
        fprintf (stderr, "pthread_create: %s\n", strerror (r));
        exit (EXIT_FAILURE);
      }
    }

    for (i = 0; i < NR_CONCURRENT_THREADS; ++i) {
      r = pthread_join (threads[i], &ret);
      if (r != 0) {
        fprintf (stderr, "pthread_join: %s\n", strerror (r));
        exit (EXIT_FAILURE);
      }
      if (ret != NULL) {
        fprintf (stderr, "thread[%d] failed\n", i);
        exit (EXIT_FAILURE);
      }
    }
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void *
start_thread (void *nullv)
{
  char *p;
  const char *err;
  int iterations;

  for (iterations = 0; iterations < 1000; ++iterations) {
    guestfs_set_hv (g, "test");
    p = guestfs_get_hv (g);
    if (!p || STRNEQ (p, "test")) {
      fprintf (stderr, "invalid return from guestfs_get_hv\n");
      pthread_exit ((void *)-1);
    }
    free (p);

    guestfs_push_error_handler (g, NULL, NULL);
    guestfs_set_hv (g, "test");
    p = guestfs_get_hv (g);
    guestfs_pop_error_handler (g);
    if (!p || STRNEQ (p, "test")) {
      fprintf (stderr, "invalid return from guestfs_get_hv\n");
      pthread_exit ((void *)-1);
    }
    free (p);

    guestfs_push_error_handler (g, NULL, NULL);
    guestfs_set_program (g, NULL); /* deliberately cause an error */
    guestfs_pop_error_handler (g);
    err = guestfs_last_error (g);
    if (!err || !STRPREFIX (err, "set_program: program: ")) {
      fprintf (stderr, "invalid error message: %s\n", err ? err : "NULL");
      pthread_exit ((void *)-1);
    }

    guestfs_push_error_handler (g, NULL, NULL);
    guestfs_set_memsize (g, 1); /* deliberately cause an error */
    guestfs_pop_error_handler (g);
    err = guestfs_last_error (g);
    if (!err || strstr (err, "memsize") == NULL) {
      fprintf (stderr, "invalid error message: %s\n", err ? err : "NULL");
      pthread_exit ((void *)-1);
    }
  }

  pthread_exit (NULL);
}
