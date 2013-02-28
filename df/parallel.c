/* virt-df
 * Copyright (C) 2013 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>
#include <error.h>
#include <assert.h>

#include <pthread.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "progname.h"

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "options.h"
#include "domains.h"
#include "estimate-max-threads.h"
#include "parallel.h"

#define DEBUG_PARALLEL 0

#if defined(HAVE_LIBVIRT)

/* Maximum number of threads we would ever run.  Note this should not
 * be > 20, unless libvirt is modified to increase the maximum number
 * of clients.
 */
#define MAX_THREADS 12

/* The worker threads take domains off the 'domains' global list until
 * 'next_domain_to_take' is 'nr_threads'.
 *
 * The worker threads retire domains in numerical order, using the
 * 'next_domain_to_retire' number.
 *
 * 'next_domain_to_take' is protected just by a mutex.
 * 'next_domain_to_retire' is protected by a mutex and condition.
 */
static size_t next_domain_to_take = 0;
static pthread_mutex_t take_mutex = PTHREAD_MUTEX_INITIALIZER;

static size_t next_domain_to_retire = 0;
static pthread_mutex_t retire_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t retire_cond = PTHREAD_COND_INITIALIZER;

static void thread_failure (const char *fn, int err) __attribute__((noreturn));
static void *worker_thread (void *arg);

struct thread_data {
  int trace, verbose;           /* Flags from the options_handle. */
  work_fn work;
};

/* Start threads. */
void
start_threads (size_t option_P, guestfs_h *options_handle, work_fn work)
{
  struct thread_data thread_data = { .trace = 0, .verbose = 0, .work = work };
  size_t i, nr_threads;
  int err;
  void *status;

  if (nr_domains == 0)          /* Nothing to do. */
    return;

  if (options_handle) {
    thread_data.trace = guestfs_get_trace (options_handle);
    thread_data.verbose = guestfs_get_verbose (options_handle);
  }

  /* If the user selected the -P option, then we use up to that many threads. */
  if (option_P > 0)
    nr_threads = MIN (nr_domains, option_P);
  else
    nr_threads = MIN (nr_domains, MIN (MAX_THREADS, estimate_max_threads ()));

  pthread_t threads[nr_threads];

  /* Start the worker threads. */
  for (i = 0; i < nr_threads; ++i) {
    err = pthread_create (&threads[i], NULL, worker_thread, &thread_data);
    if (err != 0)
      error (EXIT_FAILURE, err, "pthread_create [%zu]", i);
  }

  /* Wait for the threads to exit. */
  for (i = 0; i < nr_threads; ++i) {
    err = pthread_join (threads[i], &status);
    if (err != 0)
      error (EXIT_FAILURE, err, "pthread_join [%zu]", i);
  }
}

/* Worker thread. */
static void *
worker_thread (void *thread_data_vp)
{
  struct thread_data *thread_data = thread_data_vp;

  while (1) {
    size_t i;               /* The current domain we're working on. */
    FILE *fp;
    CLEANUP_FREE char *output = NULL;
    size_t output_len = 0;
    guestfs_h *g;
    int err;

    /* Take the next domain from the list. */
    err = pthread_mutex_lock (&take_mutex);
    if (err != 0) thread_failure ("pthread_mutex_lock", err);
    i = next_domain_to_take++;
    err = pthread_mutex_unlock (&take_mutex);
    if (err != 0) thread_failure ("pthread_mutex_unlock", err);

    if (i >= nr_domains)        /* Work finished. */
      break;

    if (DEBUG_PARALLEL)
      printf ("thread taking domain %zu\n", i);

    fp = open_memstream (&output, &output_len);
    if (fp == NULL) {
      perror ("open_memstream");
      _exit (EXIT_FAILURE);
    }

    /* Create a guestfs handle. */
    g = guestfs_create ();
    if (g == NULL) {
      perror ("guestfs_create");
      _exit (EXIT_FAILURE);
    }

    /* Copy some settings from the options guestfs handle. */
    guestfs_set_trace (g, thread_data->trace);
    guestfs_set_verbose (g, thread_data->verbose);

    /* Do work. */
    thread_data->work (g, i, fp);

    fclose (fp);
    guestfs_close (g);

    /* Retire this domain.  We have to retire domains in order, which
     * may mean waiting for another thread to finish here.
     */
    err = pthread_mutex_lock (&retire_mutex);
    if (err != 0) thread_failure ("pthread_mutex_lock", err);
    while (next_domain_to_retire != i) {
      err = pthread_cond_wait (&retire_cond, &retire_mutex);
      if (err != 0) thread_failure ("pthread_cond_wait", err);
    }

    if (DEBUG_PARALLEL)
      printf ("thread retiring domain %zu\n", i);

    /* Retire domain. */
    printf ("%s", output);

    /* Update next_domain_to_retire and tell other threads. */
    next_domain_to_retire = i+1;
    pthread_cond_broadcast (&retire_cond);
    err = pthread_mutex_unlock (&retire_mutex);
    if (err != 0) thread_failure ("pthread_mutex_unlock", err);
  }

  if (DEBUG_PARALLEL)
    printf ("thread exiting\n");

  return NULL;
}

static void
thread_failure (const char *fn, int err)
{
  fprintf (stderr, "%s: %s: %s\n", program_name, fn, strerror (err));
  _exit (EXIT_FAILURE);
}

#endif /* HAVE_LIBVIRT */
