/* virt-df
 * Copyright (C) 2010-2011 Red Hat Inc.
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

#include "guestfs.h"
#include "options.h"
#include "virt-df.h"

/* These globals are shared with options.c. */
guestfs_h *g;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;

int csv = 0;                    /* --csv */
int human = 0;                  /* --human-readable|-h */
int inodes = 0;                 /* --inodes */
int one_per_guest = 0;          /* --one-per-guest */
int uuid = 0;                   /* --uuid */

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
           _("%s: display free space on virtual filesystems\n"
             "Copyright (C) 2010 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  --csv                Output as Comma-Separated Values\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  -h|--human-readable  Human-readable sizes in --long output\n"
             "  --help               Display brief help\n"
             "  -i|--inodes          Display inodes\n"
             "  --one-per-guest      Separate appliance per guest\n"
             "  --uuid               Add UUIDs to --long output\n"
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

  static const char *options = "a:c:d:hivVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "csv", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "human-readable", 0, 0, 'h' },
    { "inodes", 0, 0, 'i' },
    { "one-per-guest", 0, 0, 0 },
    { "uuid", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  int c;
  int option_index;

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
      } else if (STREQ (long_options[option_index].name, "csv")) {
        csv = 1;
      } else if (STREQ (long_options[option_index].name, "one-per-guest")) {
        one_per_guest = 1;
      } else if (STREQ (long_options[option_index].name, "uuid")) {
        uuid = 1;
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

    case 'h':
      human = 1;
      break;

    case 'i':
      inodes = 1;
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

  /* Old-style syntax?  There were no -a or -d options in the old
   * virt-df which is how we detect this.
   */
  if (drvs == NULL) {
    while (optind < argc) {
      if (strchr (argv[optind], '/') ||
          access (argv[optind], F_OK) == 0) { /* simulate -a option */
        drv = malloc (sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_a;
        drv->a.filename = argv[optind];
        drv->a.format = NULL;
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = malloc (sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_d;
        drv->d.guest = argv[optind];
        drv->next = drvs;
        drvs = drv;
      }

      optind++;
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

  /* -h and --csv doesn't make sense.  Spreadsheets will corrupt these
   * fields.  (RHBZ#600977).
   */
  if (human && csv) {
    fprintf (stderr, _("%s: you cannot use -h and --csv options together.\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  /* If the user didn't specify any drives, then we ask libvirt for
   * the full list of guests and drives, which we add in batches.
   */
  if (drvs == NULL) {
#ifdef HAVE_LIBVIRT
    get_domains_from_libvirt ();
#else
    fprintf (stderr, _("%s: compiled without support for libvirt.\n"),
             program_name);
    exit (EXIT_FAILURE);
#endif
  }
  else {
    const char *name;

    /* Add domains/drives from the command line (for a single guest). */
    add_drives (drvs, 'a');

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    print_title ();

    /* Synthesize a display name. */
    switch (drvs->type) {
    case drv_a:
      name = strrchr (drvs->a.filename, '/');
      if (name == NULL)
        name = drvs->a.filename;
      else
        name++; /* skip '/' character */
      break;
    case drv_d:
      name = drvs->d.guest;
      break;
    case drv_N:
    default:
      abort ();
    }

    /* XXX regression: in the Perl version we cached the UUID from the
     * libvirt domain handle so it was available to us here.  In this
     * version the libvirt domain handle is hidden inside
     * guestfs_add_domain so the UUID is not available easily for
     * single '-d' command-line options.
     */
    (void) df_on_handle (name, NULL, NULL, 0);

    /* Free up data structures, no longer needed after this point. */
    free_drives (drvs);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}
