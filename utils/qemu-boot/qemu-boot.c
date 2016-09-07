/* libguestfs
 * Copyright (C) 2014-2016 Red Hat Inc.
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
#include <error.h>
#include <pthread.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"
#include "estimate-max-threads.h"

#include "getprogname.h"

#define MIN(a,b) ((a)<(b)?(a):(b))

/* Maximum number of threads we would ever run.  Note this should not
 * be > 20, unless libvirt is modified to increase the maximum number
 * of clients.  User can override this limit using -P.
 */
#define MAX_THREADS 12

static size_t n;       /* Number of qemu processes to run in total. */
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

static int ignore_errors = 0;
static const char *log_template = NULL;
static size_t log_file_size;
static int trace = 0;
static int verbose = 0;

/* Events captured by the --log option. */
static const uint64_t event_bitmask =
  GUESTFS_EVENT_LIBRARY |
  GUESTFS_EVENT_WARNING |
  GUESTFS_EVENT_APPLIANCE |
  GUESTFS_EVENT_TRACE;

struct thread_data {
  int thread_num;
  int r;
};

static void run_test (size_t P);
static void *start_thread (void *thread_data_vp);
static void message_callback (guestfs_h *g, void *opaque, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

static void
usage (int exitcode)
{
  fprintf (stderr,
           "qemu-boot: A program for repeatedly running the libguestfs appliance.\n"
           "qemu-boot [-i] [--log output.%%] [-P <nr-threads>] -n <nr-appliances>\n"
           "  -i     Ignore errors\n"
           "  --log <file.%%>\n"
           "         Write per-appliance logs to file (%% in name replaced by boot number)\n"
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
  static const char options[] = "in:P:vx";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "ignore", 0, 0, 'i' },
    { "log", 1, 0, 0 },
    { "number", 1, 0, 'n' },
    { "processes", 1, 0, 'P' },
    { "trace", 0, 0, 'x' },
    { "verbose", 0, 0, 'v' },
    { 0, 0, 0, 0 }
  };
  size_t P = 0, i;
  int c, option_index;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:
      /* Options which are long only. */
      if (STREQ (long_options[option_index].name, "log")) {
        log_template = optarg;
        log_file_size = strlen (log_template);
        for (i = 0; i < strlen (log_template); ++i) {
          if (log_template[i] == '%')
            log_file_size += 64;
        }
      }
      else
        error (EXIT_FAILURE, 0,
               "unknown long option: %s (%d)",
               long_options[option_index].name, option_index);
      break;

    case 'i':
      ignore_errors = 1;
      break;

    case 'n':
      if (sscanf (optarg, "%zu", &n) != 1 || n == 0)
        error (EXIT_FAILURE, 0, "-n option not numeric and greater than 0");
      break;

    case 'P':
      if (sscanf (optarg, "%zu", &P) != 1)
        error (EXIT_FAILURE, 0, "-P option not numeric");
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

  if (n == 0)
    error (EXIT_FAILURE, 0,
           "must specify number of processes to run (-n option)");

  if (optind != argc)
    error (EXIT_FAILURE, 0,
           "extra arguments found on the command line");

  /* Calculate the number of threads to use. */
  if (P > 0)
    P = MIN (n, P);
  else
    P = MIN (n, MIN (MAX_THREADS, estimate_max_threads ()));

  run_test (P);
  exit (EXIT_SUCCESS);
}

static void
run_test (size_t P)
{
  void *status;
  int err;
  size_t i, errors;
  CLEANUP_FREE struct thread_data *thread_data = NULL;
  CLEANUP_FREE pthread_t *threads = NULL;

  thread_data = malloc (sizeof (struct thread_data) * P);
  threads = malloc (sizeof (pthread_t) * P);
  if (thread_data == NULL || threads == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  /* Start the worker threads. */
  for (i = 0; i < P; ++i) {
    thread_data[i].thread_num = i;
    err = pthread_create (&threads[i], NULL, start_thread, &thread_data[i]);
    if (err != 0)
      error (EXIT_FAILURE, err, "pthread_create[%zu]\n", i);
  }

  /* Wait for the threads to exit. */
  errors = 0;
  for (i = 0; i < P; ++i) {
    err = pthread_join (threads[i], &status);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_join[%zu]: %s\n",
               getprogname (), i, strerror (err));
      errors++;
    }
    if (*(int *)status == -1)
      errors++;
  }

  if (errors > 0)
    exit (EXIT_FAILURE);
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
  char id[64];

  for (;;) {
    CLEANUP_FREE char *log_file = NULL;
    CLEANUP_FCLOSE FILE *log_fp = NULL;

    /* Take the next process. */
    err = pthread_mutex_lock (&mutex);
    if (err != 0) {
      fprintf (stderr, "%s: pthread_mutex_lock: %s",
               getprogname (), strerror (err));
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
               getprogname (), strerror (err));
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

    /* Only if using --log, set up a callback.  See examples/debug-logging.c */
    if (log_template != NULL) {
      size_t j, k;

      log_file = malloc (log_file_size + 1);
      if (log_file == NULL) abort ();
      for (j = 0, k = 0; j < strlen (log_template); ++j) {
        if (log_template[j] == '%') {
          snprintf (&log_file[k], log_file_size - k, "%zu", i);
          k += strlen (&log_file[k]);
        }
        else
          log_file[k++] = log_template[j];
      }
      log_file[k] = '\0';
      log_fp = fopen (log_file, "w");
      if (log_fp == NULL) {
        perror (log_file);
        abort ();
      }
      guestfs_set_event_callback (g, message_callback,
                                  event_bitmask, 0, log_fp);
    }

    snprintf (id, sizeof id, "%zu", i);
    guestfs_set_identifier (g, id);

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
             getprogname (), thread_data->thread_num, errors);
    goto error;
  }

  thread_data->r = 0;
  return &thread_data->r;

 error:
  thread_data->r = -1;
  return &thread_data->r;
}

/* If using --log, this is called to write messages to the log file. */
static void
message_callback (guestfs_h *g, void *opaque,
                  uint64_t event, int event_handle,
                  int flags,
                  const char *buf, size_t buf_len,
                  const uint64_t *array, size_t array_len)
{
  FILE *fp = opaque;

  if (buf_len > 0) {
    CLEANUP_FREE char *msg = strndup (buf, buf_len);

    switch (event) {
    case GUESTFS_EVENT_APPLIANCE:
      fprintf (fp, "%s", msg);
      break;
    case GUESTFS_EVENT_LIBRARY:
      fprintf (fp, "libguestfs: %s\n", msg);
      break;
    case GUESTFS_EVENT_WARNING:
      fprintf (fp, "libguestfs: warning: %s\n", msg);
      break;
    case GUESTFS_EVENT_TRACE:
      fprintf (fp, "libguestfs: trace: %s\n", msg);
      break;
    }
    fflush (fp);
  }
}
