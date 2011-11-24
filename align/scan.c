/* virt-alignment-scan
 * Copyright (C) 2011 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "progname.h"
#include "c-ctype.h"

#include "guestfs.h"
#include "options.h"

/* These globals are shared with options.c. */
guestfs_h *g;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;

static int quiet = 0;           /* --quiet */

static int scan (void);

static inline char *
bad_cast (char const *s)
{
  return (char *) s;
}

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             program_name);
  else {
    fprintf (stdout,
           _("%s: check alignment of virtual machine partitions\n"
             "Copyright (C) 2011 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  -q|--quiet           No output, just exit code\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             "  -x                   Trace libguestfs API calls\n"
             "For more information, see the manpage %s(1).\n"),
             program_name, program_name, program_name,
             program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  /* Set global program name that is not polluted with libtool artifacts.  */
  set_program_name (argv[0]);

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:qvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "quiet", 0, 0, 'q' },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  int c;
  int option_index;
  int exit_code;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  argv[0] = bad_cast (program_name);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "format")) {
        if (!optarg || STREQ (optarg, ""))
          format = NULL;
        else
          format = optarg;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 program_name, long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      OPTION_a;
      break;

    case 'c':
      OPTION_c;
      break;

    case 'd':
      OPTION_d;
      break;

    case 'q':
      quiet = 1;
      break;

    case 'v':
      OPTION_v;
      break;

    case 'V':
      OPTION_V;
      break;

    case 'x':
      OPTION_x;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 0);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  /* The user didn't specify any drives to scan. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Add domains/drives from the command line (for a single guest). */
  add_drives (drvs, 'a');

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  /* Perform the scan. */
  exit_code = scan ();

  guestfs_close (g);

  exit (exit_code);
}

static int
scan (void)
{
  int exit_code = 0;
  char **devices;
  size_t i, j;
  size_t alignment;
  uint64_t start;
  struct guestfs_partition_list *parts;

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; devices[i] != NULL; ++i) {
    parts = guestfs_part_list (g, devices[i]);
    if (parts == NULL)
      exit (EXIT_FAILURE);

    /* Canonicalize the name of the device for printing. */
    if (STRPREFIX (devices[i], "/dev/") &&
        (devices[i][5] == 'h' || devices[i][5] == 'v') &&
        devices[i][6] == 'd' &&
        c_isalpha (devices[i][7]))
      devices[i][5] = 's';

    for (j = 0; j < parts->len; ++j) {
      /* Start offset of the partition in bytes. */
      start = parts->val[j].part_start;

      if (!quiet)
        printf ("%s%d %12" PRIu64 " ",
                devices[i], (int) parts->val[j].part_num, start);

      /* What's the alignment? */
      if (start == 0)           /* Probably not possible, but anyway. */
        alignment = 64;
      else
        for (alignment = 0; (start & 1) == 0; alignment++, start /= 2)
          ;

      if (!quiet) {
        if (alignment < 10)
          printf ("%12" PRIu64 "    ", UINT64_C(1) << alignment);
        else if (alignment < 64)
          printf ("%12" PRIu64 "K   ", UINT64_C(1) << (alignment - 10));
        else
          printf ("- ");
      }

      if (alignment < 12) {     /* Bad in general: < 4K alignment */
        exit_code = 3;
        if (!quiet)
          printf ("bad (%s)\n", _("alignment < 4K"));
      } else if (alignment < 16) { /* Bad on NetApps: < 64K alignment */
        if (exit_code < 2)
          exit_code = 2;
        if (!quiet)
          printf ("bad (%s)\n", _("alignment < 64K"));
      } else {
        if (!quiet)
          printf ("ok\n");
      }
    }

    guestfs_free_partition_list (parts);
    free (devices[i]);
  }
  free (devices);

  return exit_code;
}
