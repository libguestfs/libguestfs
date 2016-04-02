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

/* Benchmark the time taken to boot the libguestfs appliance. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <getopt.h>
#include <limits.h>
#include <time.h>
#include <errno.h>
#include <error.h>
#include <assert.h>
#include <math.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "boot-analysis-utils.h"

#define NR_WARMUP_PASSES 3
#define NR_TEST_PASSES   10

static const char *append = NULL;
static int memsize = 0;
static int smp = 1;

static void run_test (void);
static guestfs_h *create_handle (void);
static void add_drive (guestfs_h *g);

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
           "boot-benchmark: Benchmark the time taken to boot the libguestfs appliance.\n"
           "Usage:\n"
           "  boot-benchmark [--options]\n"
           "Options:\n"
           "  --help         Display this usage text and exit.\n"
           "  --append OPTS  Append OPTS to kernel command line.\n"
           "  -m MB\n"
           "  --memsize MB   Set memory size in MB (default: %d).\n"
           "  --smp N        Enable N virtual CPUs (default: 1).\n",
           default_memsize);
  exit (exitcode);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };
  static const char *options = "m:";
  static const struct option long_options[] = {
    { "help", 0, 0, HELP_OPTION },
    { "append", 1, 0, 0 },
    { "memsize", 1, 0, 'm' },
    { "smp", 1, 0, 0 },
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
      else if (STREQ (long_options[option_index].name, "smp")) {
        if (sscanf (optarg, "%d", &smp) != 1) {
          fprintf (stderr, "%s: could not parse smp parameter: %s\n",
                   guestfs_int_program_name, optarg);
          exit (EXIT_FAILURE);
        }
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

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  run_test ();
}

static void
run_test (void)
{
  guestfs_h *g;
  size_t i;
  int64_t ns[NR_TEST_PASSES];
  double mean;
  double variance;
  double sd;

  printf ("Warming up the libguestfs cache ...\n");
  for (i = 0; i < NR_WARMUP_PASSES; ++i) {
    g = create_handle ();
    add_drive (g);
    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);
    guestfs_close (g);
  }

  printf ("Running the tests ...\n");
  for (i = 0; i < NR_TEST_PASSES; ++i) {
    struct timespec start_t, end_t;

    g = create_handle ();
    add_drive (g);
    get_time (&start_t);
    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);
    guestfs_close (g);
    get_time (&end_t);

    ns[i] = timespec_diff (&start_t, &end_t);
  }

  /* Calculate the mean. */
  mean = 0;
  for (i = 0; i < NR_TEST_PASSES; ++i)
    mean += ns[i];
  mean /= NR_TEST_PASSES;

  /* Calculate the variance and standard deviation. */
  variance = 0;
  for (i = 0; i < NR_TEST_PASSES; ++i)
    variance = pow (ns[i] - mean, 2);
  variance /= NR_TEST_PASSES;
  sd = sqrt (variance);

  /* Print the test parameters. */
  printf ("\n");
  g = create_handle ();
  test_info (g, NR_TEST_PASSES);
  guestfs_close (g);

  /* Print the result. */
  printf ("\n");
  printf ("Result: %.1fms ±%.1fms\n", mean / 1000000, sd / 1000000);
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

  if (append != NULL)
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
