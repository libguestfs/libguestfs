/* libguestfs
 * Copyright (C) 2014 Red Hat Inc.
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

/* Ancient libguestfs had a script called test-bootbootboot which just
 * booted up the appliance in a loop.  This was necessary back in the
 * bad old days when qemu was not very reliable.  This is the
 * spiritual successor of that script, designed to find bugs in
 * aarch64 KVM.  You can control the number of boots that are done and
 * the amount of parallelism.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <limits.h>
#include <errno.h>
#include <pthread.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "estimate-max-threads.h"

#define MIN(a,b) ((a)<(b)?(a):(b))

/* Maximum number of threads we would ever run.  Note this should not
 * be > 20, unless libvirt is modified to increase the maximum number
 * of clients.  User can override this limit using -P.
 */
#define MAX_THREADS 12

static size_t n;       /* Number of qemu processes to run in total. */
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

static int ignore_errors = 0;
static int trace = 0;
static int verbose = 0;

struct thread_data {
  int thread_num;
  int r;
};

static void *start_thread (void *thread_data_vp);

static void
usage (int exitcode)
{
  fprintf (stderr,
           "qemu-boot: A program for repeatedly running the libguestfs appliance.\n"
           "qemu-boot [-i] [-P <nr-threads>] -n <nr-appliances>\n"
           "  -i     Ignore errors\n"
           "  -P <n> Set number of parallel threads\n"
           "           (default is based on the amount of free memory)\n"
           "  -n <n> Set number of appliances to run before exiting\n"
           "  -v     Verbose appliance\n"
           "  -x     Enable libguestfs tracing\n");
  exit (exitcode);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char *options = "in:P:vx";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "ignore", 0, 0, 'i' },
    { "number", 1, 0, 'n' },
    { "processes", 1, 0, 'P' },
    { "trace", 0, 0, 'x' },
    { "verbose", 0, 0, 'v' },
    { 0, 0, 0, 0 }
  };
  size_t P = 0, i, errors;
  int c, option_index;
  int err;
  void *status;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:
      /* Options which are long only. */
      fprintf (stderr, "%s: unknown long option: %s (%d)\n",
               guestfs___program_name, long_options[option_index].name, option_index);
      exit (EXIT_FAILURE);

    case 'i':
      ignore_errors = 1;
      break;

    case 'n':
      if (sscanf (optarg, "%zu", &n) != 1 || n == 0) {
        fprintf (stderr, "%s: -n option not numeric and greater than 0\n",
                 guestfs___program_name);
        exit (EXIT_FAILURE);
      }
      break;

    case 'P':
      if (sscanf (optarg, "%zu", &P) != 1) {
        fprintf (stderr, "%s: -P option not numeric\n", guestfs___program_name);
        exit (EXIT_FAILURE);
      }
      break;

    case 'v':
      verbose = 1;
      break;

    case 'x':
      trace = 1;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  if (n == 0) {
    fprintf (stderr,
             "%s: must specify number of processes to run (-n option)\n",
             guestfs___program_name);
    exit (EXIT_FAILURE);
  }

  if (optind != argc) {
    fprintf (stderr, "%s: extra arguments found on the command line\n",
             guestfs___program_name);
    exit (EXIT_FAILURE);
  }

  /* Calculate the number of threads to use. */
  if (P > 0)
    P = MIN (n, P);
  else
    P = MIN (n, MIN (MAX_THREADS, estimate_max_threads ()));

  /* Start the worker threads. */
  struct thread_data thread_data[P];
  pthread_t threads[P];

  for (i = 0; i < P; ++i) {
    thread_data[i].thread_num = i;
    err = pthread_create (&threads[i], NULL, start_thread, &thread_data[i]);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_create[%zu]: %s\n",
               guestfs___program_name, i, strerror (err));
      exit (EXIT_FAILURE);
    }
  }

  /* Wait for the threads to exit. */
  errors = 0;
  for (i = 0; i < P; ++i) {
    err = pthread_join (threads[i], &status);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_join[%zu]: %s\n",
               guestfs___program_name, i, strerror (err));
      errors++;
    }
    if (*(int *)status == -1)
      errors++;
  }

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

/* Worker thread. */
static void *
start_thread (void *thread_data_vp)
{
  struct thread_data *thread_data = thread_data_vp;
  int quit = 0;
  int err;
  size_t i;
  guestfs_h *g;
  unsigned errors = 0;

  for (;;) {
    /* Take the next process. */
    err = pthread_mutex_lock (&mutex);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_mutex_lock: %s",
               guestfs___program_name, strerror (err));
      goto error;
    }

    i = n;
    if (i > 0) {
      printf ("%zu to go ...          \r", n);
      fflush (stdout);

      n--;
    }
    else
      quit = 1;

    err = pthread_mutex_unlock (&mutex);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_mutex_unlock: %s",
               guestfs___program_name, strerror (err));
      goto error;
    }

    if (quit)                   /* Work finished. */
      break;

    g = guestfs_create ();
    if (g == NULL) {
      perror ("guestfs_create");
      errors++;
      if (!ignore_errors)
        goto error;
    }

    guestfs_set_trace (g, trace);
    guestfs_set_verbose (g, verbose);

    if (guestfs_add_drive_ro (g, "/dev/null") == -1) {
      errors++;
      if (!ignore_errors)
        goto error;
    }

    if (guestfs_launch (g) == -1) {
      errors++;
      if (!ignore_errors)
        goto error;
    }

    if (guestfs_shutdown (g) == -1) {
      errors++;
      if (!ignore_errors)
        goto error;
    }

    guestfs_close (g);
  }

  if (errors > 0) {
    fprintf (stderr, "%s: thread %d: %u errors were ignored\n",
             guestfs___program_name, thread_data->thread_num, errors);
    goto error;
  }

  thread_data->r = 0;
  return &thread_data->r;

 error:
  thread_data->r = -1;
  return &thread_data->r;
}
