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
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include <pthread.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "guestfs.h"
#include "options.h"
#include "parallel.h"
#include "domains.h"

/* This just needs to be larger than any alignment we care about. */
static size_t worst_alignment = UINT_MAX;
static pthread_mutex_t worst_alignment_mutex = PTHREAD_MUTEX_INITIALIZER;

static int scan (guestfs_h *g, const char *prefix, FILE *fp);

#ifdef HAVE_LIBVIRT
static int scan_work (guestfs_h *g, size_t i, FILE *fp);
#endif

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
static int uuid = 0;            /* --uuid */

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    printf (_("%s: check alignment of virtual machine partitions\n"
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
              "  -P nr_threads        Use at most nr_threads\n"
              "  -q|--quiet           No output, just exit code\n"
              "  --uuid               Print UUIDs instead of names\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -x                   Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"),
            guestfs_int_program_name, guestfs_int_program_name,
            guestfs_int_program_name, guestfs_int_program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:P:qvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "long-options", 0, 0, 0 },
    { "quiet", 0, 0, 'q' },
    { "short-options", 0, 0, 0 },
    { "uuid", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int option_index;
  int exit_code;
  size_t max_threads = 0;
  int r;

  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr, _("guestfs_create: failed to create handle\n"));
    exit (EXIT_FAILURE);
  }

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "uuid")) {
        uuid = 1;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name,
                 long_options[option_index].name, option_index);
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

    case 'P':
      if (sscanf (optarg, "%zu", &max_threads) != 1) {
        fprintf (stderr, _("%s: -P option is not numeric\n"),
                 guestfs_int_program_name);
        exit (EXIT_FAILURE);
      }
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

  CHECK_OPTION_format_consumed;

  /* virt-alignment-scan has two modes.  If the user didn't specify
   * any drives, then we do the scan on every libvirt guest.  That's
   * the if-clause below.  If the user specified domains/drives, then
   * we assume they belong to a single guest.  That's the else-clause
   * below.
   */
  if (drvs == NULL) {
#if defined(HAVE_LIBVIRT)
    get_all_libvirt_domains (libvirt_uri);
    r = start_threads (max_threads, g, scan_work);
    free_domains ();
    if (r == -1)
      exit (EXIT_FAILURE);
#else
    fprintf (stderr, _("%s: compiled without support for libvirt.\n"),
             guestfs_int_program_name);
    exit (EXIT_FAILURE);
#endif
  } else {                      /* Single guest. */
    if (uuid) {
      fprintf (stderr, _("%s: --uuid option cannot be used with -a or -d\n"),
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }

    /* Add domains/drives from the command line (for a single guest). */
    add_drives (drvs, 'a');

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    /* Free up data structures, no longer needed after this point. */
    free_drives (drvs);

    /* Perform the scan. */
    r = scan (g, NULL, stdout);

    guestfs_close (g);

    if (r == -1)
      exit (EXIT_FAILURE);
  }

  /* Decide on an appropriate exit code. */
  if (worst_alignment < 10) /* 2^10 = 4096 */
    exit_code = 3;
  else if (worst_alignment < 16) /* 2^16 = 65536 */
    exit_code = 2;
  else
    exit_code = 0;

  exit (exit_code);
}

static int
scan (guestfs_h *g, const char *prefix, FILE *fp)
{
  size_t i, j;
  size_t alignment;
  uint64_t start;
  int err;

  CLEANUP_FREE_STRING_LIST char **devices = guestfs_list_devices (g);
  if (devices == NULL)
    return -1;

  for (i = 0; devices[i] != NULL; ++i) {
    CLEANUP_FREE char *name = NULL;
    CLEANUP_FREE_PARTITION_LIST struct guestfs_partition_list *parts = NULL;

    guestfs_push_error_handler (g, NULL, NULL);
    parts = guestfs_part_list (g, devices[i]);
    guestfs_pop_error_handler (g);
    if (parts == NULL) {
      if (guestfs_last_errno (g) == EINVAL) /* unrecognised disk label */
        continue;
      else
        return -1;
    }

    /* Canonicalize the name of the device for printing. */
    name = guestfs_canonical_device_name (g, devices[i]);
    if (name == NULL)
      return -1;

    for (j = 0; j < parts->len; ++j) {
      /* Start offset of the partition in bytes. */
      start = parts->val[j].part_start;

      if (!quiet) {
        if (prefix)
          fprintf (fp, "%s:", prefix);

        fprintf (fp, "%s%d %12" PRIu64 " ",
                 name, (int) parts->val[j].part_num, start);
      }

      /* What's the alignment? */
      if (start == 0)           /* Probably not possible, but anyway. */
        alignment = 64;
      else
        for (alignment = 0; (start & 1) == 0; alignment++, start /= 2)
          ;

      if (!quiet) {
        if (alignment < 10)
          fprintf (fp, "%12" PRIu64 "    ", UINT64_C(1) << alignment);
        else if (alignment < 64)
          fprintf (fp, "%12" PRIu64 "K   ", UINT64_C(1) << (alignment - 10));
        else
          fprintf (fp, "- ");
      }

      err = pthread_mutex_lock (&worst_alignment_mutex);
      assert (err == 0);
      if (alignment < worst_alignment)
        worst_alignment = alignment;
      err = pthread_mutex_unlock (&worst_alignment_mutex);
      assert (err == 0);

      if (alignment < 12) {     /* Bad in general: < 4K alignment */
        if (!quiet)
          fprintf (fp, "bad (%s)\n", _("alignment < 4K"));
      } else if (alignment < 16) { /* Bad on NetApps: < 64K alignment */
        if (!quiet)
          fprintf (fp, "bad (%s)\n", _("alignment < 64K"));
      } else {
        if (!quiet)
          fprintf (fp, "ok\n");
      }
    }
  }

  return 0;
}

#if defined(HAVE_LIBVIRT)

/* The multi-threaded version.  This callback is called from the code
 * in "parallel.c".
 */

static int
scan_work (guestfs_h *g, size_t i, FILE *fp)
{
  struct guestfs_add_libvirt_dom_argv optargs;

  optargs.bitmask =
    GUESTFS_ADD_LIBVIRT_DOM_READONLY_BITMASK |
    GUESTFS_ADD_LIBVIRT_DOM_READONLYDISK_BITMASK;
  optargs.readonly = 1;
  optargs.readonlydisk = "read";

  if (guestfs_add_libvirt_dom_argv (g, domains[i].dom, &optargs) == -1)
    return -1;

  if (guestfs_launch (g) == -1)
    return -1;

  return scan (g, !uuid ? domains[i].name : domains[i].uuid, fp);
}

#endif /* HAVE_LIBVIRT */
