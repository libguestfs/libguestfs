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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Regression test for RHBZ#790721.
 *
 * This bug involves locking issues when building the appliance in
 * parallel from multiple threads in the same process.  We use a read
 * lock on the 'checksum' file, and it turns out this causes two
 * problems: (1) locks don't have any effect on threads in the same
 * process, and (2) because the PID is identical in different threads,
 * the file we are trying to overwrite has the same name.
 *
 * To test this we want to create the appliance repeatedly from
 * multiple threads, but we don't really care about launching the full
 * qemu (a waste of time and memory for this test).  Therefore replace
 * qemu with a fake process and just look for the linking error.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include <pthread.h>

#include "guestfs.h"

#define STRNEQ(a,b) (strcmp((a),(b)) != 0)

/* Number of worker threads running the test. */
#define NR_THREADS 20

static pthread_barrier_t barrier;
static void *start_thread (void *);

int
main (int argc, char *argv[])
{
  pthread_t thread[NR_THREADS];
  int data[NR_THREADS];
  int i, r, errors;
  guestfs_h *g;
  char *attach_method;

  /* Test is only meaningful if the attach-method "appliance" is used. */
  g = guestfs_create ();
  if (!g) {
    perror ("guestfs_create");
    exit (EXIT_FAILURE);
  }
  attach_method = guestfs_get_attach_method (g);
  if (attach_method == NULL) {
    guestfs_close (g);
    exit (EXIT_FAILURE);
  }
  if (STRNEQ (attach_method, "appliance")) {
    fprintf (stderr, "%s: test skipped because attach method isn't 'appliance'.\n",
             argv[0]);
    free (attach_method);
    guestfs_close (g);
    exit (77);
  }
  free (attach_method);
  guestfs_close (g);

  /* Ensure error messages are not translated. */
  setenv ("LC_ALL", "C", 1);

  pthread_barrier_init (&barrier, NULL, NR_THREADS);

  /* Create the other threads which will set up their own libguestfs
   * handle then wait at a barrier before launching.
   */
  for (i = 0; i < NR_THREADS; ++i) {
    data[i] = i;
    r = pthread_create (&thread[i], NULL, start_thread, &data[i]);
    if (r != 0) {
      fprintf (stderr, "pthread_create: %s\n", strerror (r));
      exit (EXIT_FAILURE);
    }
  }

  /* Wait for the threads to exit. */
  errors = 0;

  for (i = 0; i < NR_THREADS; ++i) {
    int *ret;

    r = pthread_join (thread[i], (void **) &ret);
    if (r != 0) {
      fprintf (stderr, "pthread_join: %s\n", strerror (r));
      exit (EXIT_FAILURE);
    }
    if (*ret == -1)
      errors++;
  }

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static void *
start_thread (void *vi)
{
  guestfs_h *g;
  int r, thread_id = *(int *)vi;
  guestfs_error_handler_cb old_error_cb;
  void *old_error_data;
  const char *error;

  g = guestfs_create ();
  if (g == NULL) {
    perror ("guestfs_create");
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  if (guestfs_add_drive_opts (g, "/dev/null",
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              GUESTFS_ADD_DRIVE_OPTS_READONLY, 1,
                              -1) == -1) {
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  /* Fake out qemu. */
  if (guestfs_set_qemu (g, "/bin/true") == -1) {
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  /* Wait for the other threads to finish starting up. */
  r = pthread_barrier_wait (&barrier);
  if (r != 0 && r != PTHREAD_BARRIER_SERIAL_THREAD) {
    fprintf (stderr, "pthread_barrier_wait: [thread %d]: %s\n",
             thread_id, strerror (r));
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  /* Launch the handle.  Because of the faked out qemu, we expect this
   * will fail with "child process died unexpectedly".  We are
   * interested in other failures.
   */
  old_error_cb = guestfs_get_error_handler (g, &old_error_data);
  guestfs_set_error_handler (g, NULL, NULL);
  r = guestfs_launch (g);
  error = guestfs_last_error (g);

  if (r == 0) { /* This should NOT happen. */
    fprintf (stderr, "rhbz790721: [thread %d]: "
             "strangeness in test: expected launch to fail, but it didn't!\n",
             thread_id);
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  if (error == NULL) { /* This also should NOT happen. */
    fprintf (stderr, "rhbz790721: [thread %d]: "
             "strangeness in test: no error message!\n",
             thread_id);
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  /* If this happens, it indicates a bug/race in the appliance
   * building code which is what this regression test is designed to
   * spot.
   */
  if (strcmp (error, "child process died unexpectedly") != 0) {
    fprintf (stderr, "rhbz790721: [thread %d]: error: %s\n", thread_id, error);
    *(int *)vi = -1;
    pthread_exit (vi);
  }

  guestfs_set_error_handler (g, old_error_cb, old_error_data);

  /* Close the handle. */
  guestfs_close (g);

  *(int *)vi = 0;
  pthread_exit (vi);
}
