/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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

/* Trace and analyze the appliance boot process to find out which
 * steps are taking the most time.  It is not part of the standard
 * tests.
 *
 * This needs to be run on a quiet machine, so that other processes
 * disturb the timing as little as possible.  The program is
 * completely safe to run at any time.  It doesn't read or write any
 * external files, and it doesn't require root.
 *
 * You can run it from the build directory like this:
 *
 *   make
 *   make -C tests/qemu boot-analysis
 *   ./run tests/qemu/boot-analysis
 *
 * The way it works is roughly like this:
 *
 * We create a libguestfs handle and register callback handlers so we
 * can see appliance messages, trace events and so on.
 *
 * We then launch the handle and shut it down as quickly as possible.
 *
 * While the handle is running, events (seen by the callback handlers)
 * are written verbatim into an in-memory buffer, with timestamps.
 *
 * Afterwards we analyze the result using regular expressions to try
 * to identify a "timeline" for the handle (eg. at what time did the
 * BIOS hand control to the kernel).  This analysis is done in
 * 'boot-analysis-timeline.c'.
 *
 * The whole process is repeated across a few runs, and the final
 * timeline (including statistical analysis of the variation between
 * runs) gets printed.
 *
 * The program is very sensitive to the specific messages printed by
 * BIOS/kernel/supermin/userspace, so it won't work on non-x86, and it
 * will require periodic adjustment of the regular expressions in
 * order to keep things up to date.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <time.h>
#include <errno.h>
#include <error.h>
#include <ctype.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <math.h>
#include <pthread.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "boot-analysis.h"
#include "boot-analysis-utils.h"

/* Activities taking longer than this % of the total time, except
 * those flagged as LONG_ACTIVITY, are highlighted in red.
 */
#define WARNING_THRESHOLD 1.0

static const char *append = NULL;
static int force_colour = 0;
static int memsize = 0;
static int smp = 1;
static int verbose = 0;

static int libvirt_pipe[2] = { -1, -1 };
static ssize_t libvirt_pass = -1;

/* Because there is a separate thread which collects libvirt log data,
 * we must protect the pass_data struct with a mutex.  This only
 * applies during the data collection passes.
 */
static pthread_mutex_t pass_data_lock = PTHREAD_MUTEX_INITIALIZER;
struct pass_data pass_data[NR_TEST_PASSES];

size_t nr_activities;
struct activity *activities;

static void run_test (void);
static struct event *add_event (struct pass_data *, uint64_t source);
static guestfs_h *create_handle (void);
static void set_up_event_handlers (guestfs_h *g, size_t pass);
static void libvirt_log_hack (int argc, char **argv);
static void start_libvirt_thread (size_t pass);
static void stop_libvirt_thread (void);
static void add_drive (guestfs_h *g);
static void check_pass_data (void);
static void dump_pass_data (void);
static void analyze_timeline (void);
static void dump_timeline (void);
static void print_analysis (void);
static void print_longest_to_shortest (void);
static void free_pass_data (void);
static void free_final_timeline (void);
static void ansi_green (void);
static void ansi_red (void);
static void ansi_blue (void);
static void ansi_magenta (void);
static void ansi_restore (void);

static void
usage (int exitcode)
{
  guestfs_h *g;
  int default_memsize = -1;

  g = guestfs_create ();
  if (g) {
    default_memsize = guestfs_get_memsize (g);
    guestfs_close (g);
  }

  fprintf (stderr,
           "boot-analysis: Trace and analyze the appliance boot process.\n"
           "Usage:\n"
           "  boot-analysis [--options]\n"
           "Options:\n"
           "  --help         Display this usage text and exit.\n"
           "  --append OPTS  Append OPTS to kernel command line.\n"
           "  --colour       Output colours, even if not a terminal.\n"
           "  -m MB\n"
           "  --memsize MB   Set memory size in MB (default: %d).\n"
           "  --smp N        Enable N virtual CPUs (default: 1).\n"
           "  -v|--verbose   Verbose output, useful for debugging.\n",
           default_memsize);
  exit (exitcode);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char *options = "m:v";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "append", 1, 0, 0 },
    { "color", 0, 0, 0 },
    { "colour", 0, 0, 0 },
    { "memsize", 1, 0, 'm' },
    { "libvirt-pipe-0", 1, 0, 0 }, /* see libvirt_log_hack */
    { "libvirt-pipe-1", 1, 0, 0 },
    { "smp", 1, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { 0, 0, 0, 0 }
  };
  int c, option_index;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:                     /* Options which are long only. */
      if (STREQ (long_options[option_index].name, "append")) {
        append = optarg;
        break;
      }
      else if (STREQ (long_options[option_index].name, "color") ||
               STREQ (long_options[option_index].name, "colour")) {
        force_colour = 1;
        break;
      }
      else if (STREQ (long_options[option_index].name, "libvirt-pipe-0")) {
        if (sscanf (optarg, "%d", &libvirt_pipe[0]) != 1)
          error (EXIT_FAILURE, 0,
                 "could not parse libvirt-pipe-0 parameter: %s", optarg);
        break;
      }
      else if (STREQ (long_options[option_index].name, "libvirt-pipe-1")) {
        if (sscanf (optarg, "%d", &libvirt_pipe[1]) != 1)
          error (EXIT_FAILURE, 0,
                 "could not parse libvirt-pipe-1 parameter: %s", optarg);
        break;
      }
      else if (STREQ (long_options[option_index].name, "smp")) {
        if (sscanf (optarg, "%d", &smp) != 1)
          error (EXIT_FAILURE, 0,
                 "could not parse smp parameter: %s", optarg);
        break;
      }
      fprintf (stderr, "%s: unknown long option: %s (%d)\n",
               guestfs_int_program_name, long_options[option_index].name, option_index);
      exit (EXIT_FAILURE);

    case 'm':
      if (sscanf (optarg, "%d", &memsize) != 1) {
        fprintf (stderr, "%s: could not parse memsize parameter: %s\n",
                 guestfs_int_program_name, optarg);
        exit (EXIT_FAILURE);
      }
      break;

    case 'v':
      verbose = 1;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  libvirt_log_hack (argc, argv);

  if (STRNEQ (host_cpu, "x86_64") && STRNEQ (host_cpu, "aarch64"))
    fprintf (stderr, "WARNING: host_cpu != x86_64|aarch64: This program may not work or give bogus results.\n");

  run_test ();
}

static void
run_test (void)
{
  guestfs_h *g;
  size_t i;

  printf ("Warming up the libguestfs cache ...\n");
  for (i = 0; i < NR_WARMUP_PASSES; ++i) {
    g = create_handle ();
    add_drive (g);
    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);
    guestfs_close (g);
  }

  printf ("Running the tests in %d passes ...\n", NR_TEST_PASSES);
  for (i = 0; i < NR_TEST_PASSES; ++i) {
    g = create_handle ();
    set_up_event_handlers (g, i);
    start_libvirt_thread (i);
    add_drive (g);
    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);
    guestfs_close (g);
    stop_libvirt_thread ();

    printf ("    pass %zu: %zu events collected in %" PRIi64 " ns\n",
            i+1, pass_data[i].nr_events, pass_data[i].elapsed_ns);
  }

  if (verbose)
    dump_pass_data ();

  printf ("Analyzing the results ...\n");
  check_pass_data ();
  construct_timeline ();
  analyze_timeline ();

  if (verbose)
    dump_timeline ();

  printf ("\n");
  g = create_handle ();
  test_info (g, NR_TEST_PASSES);
  guestfs_close (g);
  printf ("\n");
  print_analysis ();
  printf ("\n");
  printf ("Longest activities:\n");
  printf ("\n");
  print_longest_to_shortest ();

  free_pass_data ();
  free_final_timeline ();
}

static struct event *
add_event_unlocked (struct pass_data *data, uint64_t source)
{
  struct event *ret;

  data->nr_events++;
  data->events = realloc (data->events,
                          sizeof (struct event) * data->nr_events);
  if (data->events == NULL)
    error (EXIT_FAILURE, errno, "realloc");
  ret = &data->events[data->nr_events-1];
  get_time (&ret->t);
  ret->source = source;
  ret->message = NULL;
  return ret;
}

static struct event *
add_event (struct pass_data *data, uint64_t source)
{
  struct event *ret;

  pthread_mutex_lock (&pass_data_lock);
  ret = add_event_unlocked (data, source);
  pthread_mutex_unlock (&pass_data_lock);
  return ret;
}

/* Common function to create the handle and set various defaults. */
static guestfs_h *
create_handle (void)
{
  guestfs_h *g;
  CLEANUP_FREE char *full_append = NULL;

  g = guestfs_create ();
  if (!g) error (EXIT_FAILURE, errno, "guestfs_create");

  if (memsize != 0)
    if (guestfs_set_memsize (g, memsize) == -1)
      exit (EXIT_FAILURE);

  if (smp >= 2)
    if (guestfs_set_smp (g, smp) == -1)
      exit (EXIT_FAILURE);

  /* This changes some details in appliance/init and enables a
   * detailed trace of calls to initcall functions in the kernel.
   */
  if (asprintf (&full_append,
                "guestfs_boot_analysis=1 "
                "ignore_loglevel initcall_debug "
                "%s",
                append != NULL ? append : "") == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  if (guestfs_set_append (g, full_append) == -1)
    exit (EXIT_FAILURE);

  return g;
}

/* Common function to add the /dev/null drive. */
static void
add_drive (guestfs_h *g)
{
  if (guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1) == -1)
    exit (EXIT_FAILURE);
}

/* Called when the handle is closed.  Perform any cleanups required in
 * the pass_data here.
 */
static void
close_callback (guestfs_h *g, void *datavp, uint64_t source,
                int eh, int flags,
                const char *buf, size_t buf_len,
                const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;

  if (!data->seen_launch)
    return;

  event = add_event (data, source);
  event->message = strdup ("close callback");
  if (event->message == NULL)
    error (EXIT_FAILURE, errno, "strdup");

  get_time (&data->end_t);
  data->elapsed_ns = timespec_diff (&data->start_t, &data->end_t);
}

/* Called when the qemu subprocess exits.
 * XXX This is never called - why?
 */
static void
subprocess_quit_callback (guestfs_h *g, void *datavp, uint64_t source,
                          int eh, int flags,
                          const char *buf, size_t buf_len,
                          const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;

  if (!data->seen_launch)
    return;

  event = add_event (data, source);
  event->message = strdup ("subprocess quit callback");
  if (event->message == NULL)
    error (EXIT_FAILURE, errno, "strdup");
}

/* Called when the launch operation is complete (the library and the
 * guestfs daemon and talking to each other).
 */
static void
launch_done_callback (guestfs_h *g, void *datavp, uint64_t source,
                      int eh, int flags,
                      const char *buf, size_t buf_len,
                      const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;

  if (!data->seen_launch)
    return;

  event = add_event (data, source);
  event->message = strdup ("launch done callback");
  if (event->message == NULL)
    error (EXIT_FAILURE, errno, "strdup");
}

/* Trim \r (multiple) from the end of a string. */
static void
trim_r (char *message)
{
  size_t len = strlen (message);

  while (len > 0 && message[len-1] == '\r') {
    message[len-1] = '\0';
    len--;
  }
}

/* Called when we get (possibly part of) a log message (or more than
 * one log message) from the appliance (which may include qemu, the
 * BIOS, kernel, etc).
 */
static void
appliance_callback (guestfs_h *g, void *datavp, uint64_t source,
                    int eh, int flags,
                    const char *buf, size_t buf_len,
                    const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;
  size_t i, len, slen;

  if (!data->seen_launch)
    return;

  /* If the previous log message was incomplete, but time has moved on
   * a lot, record a new log message anyway, so it gets a new
   * timestamp.
   */
  if (data->incomplete_log_message >= 0) {
    struct timespec ts;
    get_time (&ts);
    if (timespec_diff (&data->events[data->incomplete_log_message].t,
                       &ts) >= 10000000 /* 10ms */)
      data->incomplete_log_message = -1;
  }

  /* If the previous log message was incomplete then we may need to
   * append part of the current log message to a previous one.
   */
  if (data->incomplete_log_message >= 0) {
    len = buf_len;
    for (i = 0; i < buf_len; ++i) {
      if (buf[i] == '\n') {
        len = i;
        break;
      }
    }

    event = &data->events[data->incomplete_log_message];
    slen = strlen (event->message);
    event->message = realloc (event->message, slen + len + 1);
    if (event->message == NULL)
      error (EXIT_FAILURE, errno, "realloc");
    memcpy (event->message + slen, buf, len);
    event->message[slen + len] = '\0';
    trim_r (event->message);

    /* Skip what we just added to the previous incomplete message. */
    buf += len;
    buf_len -= len;

    if (buf_len == 0)          /* still not complete, more to come! */
      return;

    /* Skip the \n in the buffer. */
    buf++;
    buf_len--;
    data->incomplete_log_message = -1;
  }

  /* Add the event, or perhaps multiple events if the message
   * contains \n characters.
   */
  while (buf_len > 0) {
    len = buf_len;
    for (i = 0; i < buf_len; ++i) {
      if (buf[i] == '\n') {
        len = i;
        break;
      }
    }

    event = add_event (data, source);
    event->message = strndup (buf, len);
    if (event->message == NULL)
      error (EXIT_FAILURE, errno, "strndup");
    trim_r (event->message);

    /* Skip what we just added to the event. */
    buf += len;
    buf_len -= len;

    if (buf_len == 0) {
      /* Event is incomplete (doesn't end with \n).  We'll finish it
       * in the next callback.
       */
      data->incomplete_log_message = event - data->events;
      return;
    }

    /* Skip the \n in the buffer. */
    buf++;
    buf_len--;
  }
}

/* Called when we get a debug message from the library side.  These
 * are always delivered as complete messages.
 */
static void
library_callback (guestfs_h *g, void *datavp, uint64_t source,
                  int eh, int flags,
                  const char *buf, size_t buf_len,
                  const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;

  if (!data->seen_launch)
    return;

  event = add_event (data, source);
  event->message = strndup (buf, buf_len);
  if (event->message == NULL)
    error (EXIT_FAILURE, errno, "strndup");
}

/* Called when we get a call trace message (a libguestfs API function
 * has been called or is returning).  These are always delivered as
 * complete messages.
 */
static void
trace_callback (guestfs_h *g, void *datavp, uint64_t source,
                int eh, int flags,
                const char *buf, size_t buf_len,
                const uint64_t *array, size_t array_len)
{
  struct pass_data *data = datavp;
  struct event *event;
  char *message;

  message = strndup (buf, buf_len);
  if (message == NULL)
    error (EXIT_FAILURE, errno, "strndup");

  if (STREQ (message, "launch"))
    data->seen_launch = 1;

  if (!data->seen_launch) {
    free (message);
    return;
  }

  event = add_event (data, source);
  event->message = message;
}

/* Common function to set up event callbacks and record data in memory
 * for a particular pass (0 <= pass < NR_TEST_PASSES).
 */
static void
set_up_event_handlers (guestfs_h *g, size_t pass)
{
  struct pass_data *data;

  assert (/* 0 <= pass && */ pass < NR_TEST_PASSES);

  data = &pass_data[pass];
  data->pass = pass;
  data->nr_events = 0;
  data->events = NULL;
  get_time (&data->start_t);
  data->incomplete_log_message = -1;
  data->seen_launch = 0;

  guestfs_set_event_callback (g, close_callback,
                              GUESTFS_EVENT_CLOSE, 0, data);
  guestfs_set_event_callback (g, subprocess_quit_callback,
                              GUESTFS_EVENT_SUBPROCESS_QUIT, 0, data);
  guestfs_set_event_callback (g, launch_done_callback,
                              GUESTFS_EVENT_LAUNCH_DONE, 0, data);
  guestfs_set_event_callback (g, appliance_callback,
                              GUESTFS_EVENT_APPLIANCE, 0, data);
  guestfs_set_event_callback (g, library_callback,
                              GUESTFS_EVENT_LIBRARY, 0, data);
  guestfs_set_event_callback (g, trace_callback,
                              GUESTFS_EVENT_TRACE, 0, data);

  guestfs_set_verbose (g, 1);
  guestfs_set_trace (g, 1);
}

/* libvirt debugging sucks in a number of concrete ways:
 *
 * - you can't get a synchronous callback from a log message
 * - you can't enable logging per handle (only globally
 *   by setting environment variables)
 * - you can't debug the daemon easily
 * - it's very complex
 * - it's very complex but not in ways that are practical or useful
 *
 * To get log messages at all, we need to create a pipe connected to a
 * second thread, and when libvirt prints something to the pipe we log
 * that.
 *
 * However that's not sufficient.  Because logging is only enabled
 * when libvirt examines environment variables at the start of the
 * program, we need to create the pipe and then fork+exec a new
 * instance of the whole program with the pipe and environment
 * variables set up.
 */
static int is_libvirt_backend (guestfs_h *g);
static void *libvirt_log_thread (void *datavp);

static void
libvirt_log_hack (int argc, char **argv)
{
  guestfs_h *g;

  g = guestfs_create ();
  if (!is_libvirt_backend (g)) {
    guestfs_close (g);
    return;
  }
  guestfs_close (g);

  /* Have we set up the pipes and environment and forked yet?  If not,
   * do that first.
   */
  if (libvirt_pipe[0] == -1 || libvirt_pipe[1] == -1) {
    char log_outputs[64];
    char **new_argv;
    char param1[64], param2[64];
    size_t i;
    pid_t pid;
    int status;

    /* Create the pipe.  NB: do NOT use O_CLOEXEC since we want to pass
     * this pipe into a child process.
     */
    if (pipe (libvirt_pipe) == -1)
      error (EXIT_FAILURE, 0, "pipe2");

    /* Create the environment variables to enable logging in libvirt. */
    setenv ("LIBVIRT_DEBUG", "1", 1);
    //setenv ("LIBVIRT_LOG_FILTERS",
    //        "1:qemu 1:securit 3:file 3:event 3:object 1:util", 1);
    snprintf (log_outputs, sizeof log_outputs,
              "1:file:/dev/fd/%d", libvirt_pipe[1]);
    setenv ("LIBVIRT_LOG_OUTPUTS", log_outputs, 1);

    /* Run self again. */
    new_argv = malloc ((argc+3) * sizeof (char *));
    if (new_argv == NULL)
      error (EXIT_FAILURE, errno, "malloc");

    for (i = 0; i < (size_t) argc; ++i)
      new_argv[i] = argv[i];

    snprintf (param1, sizeof param1, "--libvirt-pipe-0=%d", libvirt_pipe[0]);
    new_argv[argc] = param1;
    snprintf (param2, sizeof param2, "--libvirt-pipe-1=%d", libvirt_pipe[1]);
    new_argv[argc+1] = param2;
    new_argv[argc+2] = NULL;

    pid = fork ();
    if (pid == -1)
      error (EXIT_FAILURE, errno, "fork");
    if (pid == 0) {             /* Child process. */
      execvp (argv[0], new_argv);
      perror ("execvp");
      _exit (EXIT_FAILURE);
    }

    if (waitpid (pid, &status, 0) == -1)
      error (EXIT_FAILURE, errno, "waitpid");
    if (WIFEXITED (status))
      exit (WEXITSTATUS (status));
    error (EXIT_FAILURE, 0, "unexpected exit status from process: %d", status);
  }

  /* If we reach this else clause, then we have forked.  Now we must
   * create a thread to read events from the pipe.  This must be
   * constantly reading from the pipe, otherwise we will deadlock.
   * During the warm-up phase we end up throwing away messages.
   */
  else {
    pthread_t thread;
    pthread_attr_t attr;
    int r;

    r = pthread_attr_init (&attr);
    if (r != 0)
      error (EXIT_FAILURE, r, "pthread_attr_init");
    r = pthread_attr_setdetachstate (&attr, PTHREAD_CREATE_DETACHED);
    if (r != 0)
      error (EXIT_FAILURE, r, "pthread_attr_setdetachstate");
    r = pthread_create (&thread, &attr, libvirt_log_thread, NULL);
    if (r != 0)
      error (EXIT_FAILURE, r, "pthread_create");
    pthread_attr_destroy (&attr);
  }
}

static void
start_libvirt_thread (size_t pass)
{
  /* In the non-libvirt case, this variable is ignored. */
  pthread_mutex_lock (&pass_data_lock);
  libvirt_pass = pass;
  pthread_mutex_unlock (&pass_data_lock);
}

static void
stop_libvirt_thread (void)
{
  /* In the non-libvirt case, this variable is ignored. */
  pthread_mutex_lock (&pass_data_lock);
  libvirt_pass = -1;
  pthread_mutex_unlock (&pass_data_lock);
}

/* The separate "libvirt thread".  It loops reading debug messages
 * printed by libvirt and adds them to the pass_data.
 */
static void *
libvirt_log_thread (void *arg)
{
  struct event *event;
  CLEANUP_FREE char *buf = NULL;
  ssize_t r;

  buf = malloc (BUFSIZ);
  if (buf == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  while ((r = read (libvirt_pipe[0], buf, BUFSIZ)) > 0) {
    pthread_mutex_lock (&pass_data_lock);
    if (libvirt_pass == -1) goto discard;
    event =
      add_event_unlocked (&pass_data[libvirt_pass], SOURCE_LIBVIRT);
    event->message = strndup (buf, r);
    if (event->message == NULL)
      error (EXIT_FAILURE, errno, "strndup");
  discard:
    pthread_mutex_unlock (&pass_data_lock);
  }

  if (r == -1)
    error (EXIT_FAILURE, errno, "libvirt_log_thread: read");

  /* It's possible for the pipe to be closed (r == 0) if thread
   * cancellation is delayed after the main thread exits, so just
   * ignore that case and exit.
   */
  pthread_exit (NULL);
}

static int
is_libvirt_backend (guestfs_h *g)
{
  CLEANUP_FREE char *backend = guestfs_get_backend (g);

  return backend &&
    (STREQ (backend, "libvirt") || STRPREFIX (backend, "libvirt:"));
}

/* Sanity check the collected events. */
static void
check_pass_data (void)
{
  size_t i, j, len;
  int64_t ns;
  const char *message;

  for (i = 0; i < NR_TEST_PASSES; ++i) {
    assert (pass_data[i].pass == i);
    assert (pass_data[i].elapsed_ns > 1000);
    assert (pass_data[i].nr_events > 0);
    assert (pass_data[i].events != NULL);

    for (j = 0; j < pass_data[i].nr_events; ++j) {
      assert (pass_data[i].events[j].t.tv_sec > 0);
      if (j > 0) {
        ns = timespec_diff (&pass_data[i].events[j-1].t,
                            &pass_data[i].events[j].t);
        assert (ns >= 0);
      }
      assert (pass_data[i].events[j].source != 0);
      message = pass_data[i].events[j].message;
      assert (message != NULL);
      assert (pass_data[i].events[j].source != GUESTFS_EVENT_APPLIANCE ||
              strchr (message, '\n') == NULL);
      len = strlen (message);
      assert (len == 0 || message[len-1] != '\r');
    }
  }
}

static void
print_escaped_string (const char *message)
{
  while (*message) {
    if (isprint (*message))
      putchar (*message);
    else
      printf ("\\x%02x", (unsigned int) *message);
    message++;
  }
}

/* Dump the events to stdout, if verbose is set. */
static void
dump_pass_data (void)
{
  size_t i, j;

  for (i = 0; i < NR_TEST_PASSES; ++i) {
    printf ("pass %zu\n", pass_data[i].pass);
    printf ("    number of events collected %zu\n", pass_data[i].nr_events);
    printf ("    elapsed time %" PRIi64 " ns\n", pass_data[i].elapsed_ns);
    for (j = 0; j < pass_data[i].nr_events; ++j) {
      int64_t ns, diff_ns;
      CLEANUP_FREE char *source_str = NULL;

      ns = timespec_diff (&pass_data[i].start_t, &pass_data[i].events[j].t);
      source_str = source_to_string (pass_data[i].events[j].source);
      printf ("    %.1fms ", ns / 1000000.0);
      if (j > 0) {
	diff_ns = timespec_diff (&pass_data[i].events[j-1].t,
				 &pass_data[i].events[j].t);
	printf ("(+%.1f) ", diff_ns / 1000000.0);
      }
      printf ("[%s] \"", source_str);
      print_escaped_string (pass_data[i].events[j].message);
      printf ("\"\n");
    }
  }
}

/* Convert source to a printable string.  The caller must free the
 * returned string.
 */
char *
source_to_string (uint64_t source)
{
  char *ret;

  if (source == SOURCE_LIBVIRT) {
    ret = strdup ("libvirt");
    if (ret == NULL)
      error (EXIT_FAILURE, errno, "strdup");
  }
  else
    ret = guestfs_event_to_string (source);

  return ret;                   /* caller frees */
}

int
activity_exists (const char *name)
{
  size_t i;

  for (i = 0; i < nr_activities; ++i)
    if (STREQ (activities[i].name, name))
      return 1;
  return 0;
}

/* Add an activity to the global list. */
struct activity *
add_activity (const char *name, int flags)
{
  struct activity *ret;
  size_t i;

  /* You shouldn't have two activities with the same name. */
  assert (!activity_exists (name));

  nr_activities++;
  activities = realloc (activities, sizeof (struct activity) * nr_activities);
  if (activities == NULL)
    error (EXIT_FAILURE, errno, "realloc");
  ret = &activities[nr_activities-1];
  ret->name = strdup (name);
  if (ret->name == NULL)
    error (EXIT_FAILURE, errno, "strdup");
  ret->flags = flags;

  for (i = 0; i < NR_TEST_PASSES; ++i)
    ret->start_event[i] = ret->end_event[i] = 0;

  return ret;
}

struct activity *
find_activity (const char *name)
{
  size_t i;

  for (i = 0; i < nr_activities; ++i)
    if (STREQ (activities[i].name, name))
      return &activities[i];
  error (EXIT_FAILURE, 0,
         "internal error: could not find activity '%s'", name);
  /*NOTREACHED*/
  abort ();
}

int
activity_exists_with_no_data (const char *name, size_t pass)
{
  size_t i;

  for (i = 0; i < nr_activities; ++i)
    if (STREQ (activities[i].name, name) &&
        activities[i].start_event[pass] == 0 &&
        activities[i].end_event[pass] == 0)
      return 1;
  return 0;
}

static int
compare_activities_by_t (const void *av, const void *bv)
{
  const struct activity *a = av;
  const struct activity *b = bv;

  return a->t - b->t;
}

/* Go through the activities, computing the start and elapsed time. */
static void
analyze_timeline (void)
{
  struct activity *activity;
  size_t i, j;
  int64_t delta_ns;

  for (j = 0; j < nr_activities; ++j) {
    activity = &activities[j];

    activity->t = 0;
    activity->mean = 0;
    for (i = 0; i < NR_TEST_PASSES; ++i) {
      delta_ns =
        timespec_diff (&pass_data[i].events[0].t,
                       &pass_data[i].events[activity->start_event[i]].t);
      activity->t += delta_ns;

      delta_ns =
        timespec_diff (&pass_data[i].events[activity->start_event[i]].t,
                       &pass_data[i].events[activity->end_event[i]].t);
      activity->mean += delta_ns;
    }

    /* Divide through to get real start time and mean of each activity. */
    activity->t /= NR_TEST_PASSES;
    activity->mean /= NR_TEST_PASSES;

    /* Calculate the end time of this activity.  It's convenient when
     * drawing the timeline for one activity to finish just before the
     * next activity starts, rather than having them end and start at
     * the same time, hence ``- 1'' here.
     */
    activity->end_t = activity->t + activity->mean - 1;

    /* The above only calculated mean.  Now we are able to
     * calculate from the mean the variance and the standard
     * deviation.
     */
    activity->variance = 0;
    for (i = 0; i < NR_TEST_PASSES; ++i) {
      delta_ns =
        timespec_diff (&pass_data[i].events[activity->start_event[i]].t,
                       &pass_data[i].events[activity->end_event[i]].t);
      activity->variance += pow (delta_ns - activity->mean, 2);
    }
    activity->variance /= NR_TEST_PASSES;

    activity->sd = sqrt (activity->variance);
  }

  /* Get the total mean elapsed time from the special "run" activity. */
  activity = find_activity ("run");
  for (j = 0; j < nr_activities; ++j) {
    activities[j].percent = 100.0 * activities[j].mean / activity->mean;

    activities[j].warning =
      !(activities[j].flags & LONG_ACTIVITY) &&
      activities[j].percent >= WARNING_THRESHOLD;
  }

  /* Sort the activities by start time. */
  qsort (activities, nr_activities, sizeof (struct activity),
         compare_activities_by_t);
}

/* Dump the timeline to stdout, if verbose is set. */
static void
dump_timeline (void)
{
  size_t i;

  for (i = 0; i < nr_activities; ++i) {
    printf ("activity %zu:\n", i);
    printf ("    name = %s\n", activities[i].name);
    printf ("    start - end = %.1f - %.1f\n",
            activities[i].t, activities[i].end_t);
    printf ("    mean elapsed = %.1f\n", activities[i].mean);
    printf ("    variance = %.1f\n", activities[i].variance);
    printf ("    s.d = %.1f\n", activities[i].sd);
    printf ("    percent = %.1f\n", activities[i].percent);
  }
}

static void
print_activity (struct activity *activity)
{
  if (activity->warning) ansi_red (); else ansi_green ();
  print_escaped_string (activity->name);
  ansi_restore ();
  printf (" %.1fms ±%.1fms ",
          activity->mean / 1000000, activity->sd / 1000000);
  if (activity->warning) ansi_red (); else ansi_green ();
  printf ("(%.1f%%) ", activity->percent);
  ansi_restore ();
}

static void
print_analysis (void)
{
  double t = -1;                /* Current time. */
  /* Which columns contain activities that we are displaying now?
   * -1 == unused column, else index of an activity
   */
  CLEANUP_FREE ssize_t *columns = NULL;
  const size_t nr_columns = nr_activities;
  size_t last_free_column = 0;

  size_t i, j;
  double last_t, smallest_next_t;
  const double MAX_T = 1e20;

  columns = malloc (nr_columns * sizeof (ssize_t));
  if (columns == NULL) error (EXIT_FAILURE, errno, "malloc");
  for (j = 0; j < nr_columns; ++j)
    columns[j] = -1;

  for (;;) {
    /* Find the next significant time to display, which is a time when
     * some activity started or ended.
     */
    smallest_next_t = MAX_T;
    for (i = 0; i < nr_activities; ++i) {
      if (t < activities[i].t && activities[i].t < smallest_next_t)
        smallest_next_t = activities[i].t;
      else if (t < activities[i].end_t && activities[i].end_t < smallest_next_t)
        smallest_next_t = activities[i].end_t;
    }
    if (smallest_next_t == MAX_T)
      break;                    /* Finished. */

    last_t = t;
    t = smallest_next_t;

    /* Draw a spacer line, but only if last_t -> t is a large jump. */
    if (t - last_t >= 1000000 /* ns */) {
      printf ("          ");
      ansi_magenta ();
      for (j = 0; j < last_free_column; ++j) {
        if (columns[j] >= 0 &&
            activities[columns[j]].end_t != last_t /* !▼ */)
          printf ("│ ");
        else
          printf ("  ");
      }
      ansi_restore ();
      printf ("\n");
    }

    /* If there are any activities that ended before this time, drop
     * them from the columns list.
     */
    for (i = 0; i < nr_activities; ++i) {
      if (activities[i].end_t < t) {
        for (j = 0; j < nr_columns; ++j)
          if (columns[j] == (ssize_t) i) {
            columns[j] = -1;
            break;
          }
      }
    }

    /* May need to adjust last_free_column after previous operation. */
    while (last_free_column > 0 && columns[last_free_column-1] == -1)
      last_free_column--;

    /* If there are any activities starting at this time, add them to
     * the right hand end of the columns list.
     */
    for (i = 0; i < nr_activities; ++i) {
      if (activities[i].t == t)
        columns[last_free_column++] = i;
    }

    /* Draw the line. */
    ansi_blue ();
    printf ("%6.1fms: ", t / 1000000);

    ansi_magenta ();
    for (j = 0; j < last_free_column; ++j) {
      if (columns[j] >= 0) {
        if (activities[columns[j]].t == t)
          printf ("▲ ");
        else if (activities[columns[j]].end_t == t)
          printf ("▼ ");
        else
          printf ("│ ");
      }
      else
        printf ("  ");
    }
    ansi_restore ();

    for (j = 0; j < last_free_column; ++j) {
      if (columns[j] >= 0 && activities[columns[j]].t == t) /* ▲ */
        print_activity (&activities[columns[j]]);
    }

    printf ("\n");
  }
}

static int
compare_activities_pointers_by_mean (const void *av, const void *bv)
{
  const struct activity * const *a = av;
  const struct activity * const *b = bv;

  return (*b)->mean - (*a)->mean;
}

static void
print_longest_to_shortest (void)
{
  size_t i;
  CLEANUP_FREE struct activity **longest;

  /* Sort the activities longest first.  In order not to affect the
   * global activities array, sort an array of pointers to the
   * activities instead.
   */
  longest = malloc (sizeof (struct activity *) * nr_activities);
  for (i = 0; i < nr_activities; ++i)
    longest[i] = &activities[i];

  qsort (longest, nr_activities, sizeof (struct activity *),
         compare_activities_pointers_by_mean);

  /* Display the activities, longest first. */
  for (i = 0; i < nr_activities; ++i) {
    print_activity (longest[i]);
    printf ("\n");
  }
}

/* Free the non-static part of the pass_data structures. */
static void
free_pass_data (void)
{
  size_t i, j;

  for (i = 0; i < NR_TEST_PASSES; ++i) {
    for (j = 0; j < pass_data[i].nr_events; ++j)
      free (pass_data[i].events[j].message);
    free (pass_data[i].events);
  }
}

static void
free_final_timeline (void)
{
  size_t i;

  for (i = 0; i < nr_activities; ++i)
    free (activities[i].name);
  free (activities);
}

/* Colours. */
static void
ansi_green (void)
{
  if (force_colour || isatty (1))
    fputs ("\033[0;32m", stdout);
}

static void
ansi_red (void)
{
  if (force_colour || isatty (1))
    fputs ("\033[1;31m", stdout);
}

static void
ansi_blue (void)
{
  if (force_colour || isatty (1))
    fputs ("\033[1;34m", stdout);
}

static void
ansi_magenta (void)
{
  if (force_colour || isatty (1))
    fputs ("\033[1;35m", stdout);
}

static void
ansi_restore (void)
{
  if (force_colour || isatty (1))
    fputs ("\033[0m", stdout);
}
