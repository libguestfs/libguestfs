/* virt-rescue
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include "ignore-value.h"
#include "xvasprintf.h"

#include "guestfs.h"
#include "options.h"

static void add_scratch_disks (int n, struct drv **drvs);
static void do_suggestion (struct drv *drvs);

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 0;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             guestfs_int_program_name);
  else {
    fprintf (stdout,
           _("%s: Run a rescue shell on a virtual machine\n"
             "Copyright (C) 2009-2014 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  --append kernelopts  Append kernel options\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  -m|--memsize MB      Set memory size in megabytes\n"
             "  --network            Enable network\n"
             "  -r|--ro              Access read-only\n"
             "  --scratch[=N]        Add scratch disk(s)\n"
             "  --selinux            Enable SELinux\n"
             "  --smp N              Enable SMP with N >= 2 virtual CPUs\n"
             "  --suggest            Suggest mount commands for this guest\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             "  -w|--rw              Mount read-write\n"
             "  -x                   Trace libguestfs API calls\n"
             "For more information, see the manpage %s(1).\n"),
             guestfs_int_program_name, guestfs_int_program_name, guestfs_int_program_name,
             guestfs_int_program_name);
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  parse_config ();

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char *options = "a:c:d:m:rvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "append", 1, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "long-options", 0, 0, 0 },
    { "memsize", 1, 0, 'm' },
    { "network", 0, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "scratch", 2, 0, 0 },
    { "selinux", 0, 0, 0 },
    { "smp", 1, 0, 0 },
    { "suggest", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int option_index;
  int network = 0;
  const char *append = NULL;
  int memsize = 0;
  int smp = 0;
  int suggest = 0;

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
      else if (STREQ (long_options[option_index].name, "selinux")) {
        if (guestfs_set_selinux (g, 1) == -1)
          exit (EXIT_FAILURE);
      } else if (STREQ (long_options[option_index].name, "append")) {
        append = optarg;
      } else if (STREQ (long_options[option_index].name, "network")) {
        network = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "smp")) {
        if (sscanf (optarg, "%d", &smp) != 1) {
          fprintf (stderr, _("%s: could not parse --smp parameter '%s'\n"),
                   guestfs_int_program_name, optarg);
          exit (EXIT_FAILURE);
        }
        if (smp < 1) {
          fprintf (stderr, _("%s: --smp parameter '%s' should be >= 1\n"),
                   guestfs_int_program_name, optarg);
          exit (EXIT_FAILURE);
        }
      } else if (STREQ (long_options[option_index].name, "suggest")) {
        suggest = 1;
      } else if (STREQ (long_options[option_index].name, "scratch")) {
        if (!optarg || STREQ (optarg, ""))
          add_scratch_disks (1, &drvs);
        else {
          int n;
          if (sscanf (optarg, "%d", &n) != 1) {
            fprintf (stderr,
                     _("%s: could not parse --scratch parameter '%s'\n"),
                     guestfs_int_program_name, optarg);
            exit (EXIT_FAILURE);
          }
          if (n < 1) {
            fprintf (stderr,
                     _("%s: --scratch parameter '%s' should be >= 1\n"),
                     guestfs_int_program_name, optarg);
            exit (EXIT_FAILURE);
          }
          add_scratch_disks (n, &drvs);
        }
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name, long_options[option_index].name, option_index);
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

    case 'm':
      if (sscanf (optarg, "%d", &memsize) != 1) {
        fprintf (stderr, _("%s: could not parse memory size '%s'\n"),
                 guestfs_int_program_name, optarg);
        exit (EXIT_FAILURE);
      }
      break;

    case 'r':
      OPTION_r;
      break;

    case 'v':
      OPTION_v;
      break;

    case 'V':
      OPTION_V;
      break;

    case 'w':
      OPTION_w;
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
   * virt-rescue which is how we detect this.
   */
  if (drvs == NULL) {
    while (optind < argc) {
      if (strchr (argv[optind], '/') ||
          access (argv[optind], F_OK) == 0) { /* simulate -a option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv) {
          perror ("malloc");
          exit (EXIT_FAILURE);
        }
        drv->type = drv_a;
        drv->a.filename = strdup (argv[optind]);
        if (!drv->a.filename) {
          perror ("strdup");
          exit (EXIT_FAILURE);
        }
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = calloc (1, sizeof (struct drv));
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

  /* --suggest flag */
  if (suggest) {
    do_suggestion (drvs);
    exit (EXIT_SUCCESS);
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (inspector == 0);
  assert (keys_from_stdin == 0);
  assert (echo_keys == 0);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  CHECK_OPTION_format_consumed;

  /* User must have specified some drives. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Setting "direct mode" is required for the rescue appliance. */
  if (guestfs_set_direct (g, 1) == -1)
    exit (EXIT_FAILURE);

  {
    /* The libvirt backend doesn't support direct mode.  As a temporary
     * workaround, force the appliance backend, but warn about it.
     */
    CLEANUP_FREE char *backend = guestfs_get_backend (g);
    if (backend) {
      if (STREQ (backend, "libvirt") ||
          STRPREFIX (backend, "libvirt:")) {
        fprintf (stderr, _("%s: warning: virt-rescue doesn't work with the libvirt backend\n"
                           "at the moment.  As a workaround, forcing backend = 'direct'.\n"),
                 guestfs_int_program_name);
        if (guestfs_set_backend (g, "direct") == -1)
          exit (EXIT_FAILURE);
      }
    }
  }

  /* Set other features. */
  if (memsize > 0)
    if (guestfs_set_memsize (g, memsize) == -1)
      exit (EXIT_FAILURE);
  if (network)
    if (guestfs_set_network (g, 1) == -1)
      exit (EXIT_FAILURE);
  if (smp >= 1)
    if (guestfs_set_smp (g, smp) == -1)
      exit (EXIT_FAILURE);

  {
    /* Kernel command line must include guestfs_rescue=1 (see
     * appliance/init) as well as other options.
     */
    CLEANUP_FREE char *append_full = xasprintf ("guestfs_rescue=1%s%s",
                                                append ? " " : "",
                                                append ? append : "");
    if (guestfs_set_append (g, append_full) == -1)
      exit (EXIT_FAILURE);
  }

  /* Add drives. */
  add_drives (drvs, 'a');

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  /* Run the appliance.  This won't return until the user quits the
   * appliance.
   */
  if (!verbose)
    guestfs_set_error_handler (g, NULL, NULL);

  /* We expect launch to fail, so ignore the return value, and don't
   * bother with explicit guestfs_shutdown either.
   */
  ignore_value (guestfs_launch (g));

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void suggest_filesystems (void);

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  return strlen (key1) - strlen (key2);
}

/* virt-rescue --suggest flag does a kind of inspection on the
 * drives and suggests mount commands that you should use.
 */
static void
do_suggestion (struct drv *drvs)
{
  CLEANUP_FREE_STRING_LIST char **roots = NULL;
  size_t i;

  /* For inspection, force add_drives to add the drives read-only. */
  read_only = 1;

  /* Add drives. */
  add_drives (drvs, 'a');

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  printf (_("Inspecting the virtual machine or disk image ...\n\n"));
  fflush (stdout);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Don't use inspect_mount, since for virt-rescue we should allow
   * arbitrary disks and disks with more than one OS on them.  Let's
   * do this using the basic API instead.
   */
  roots = guestfs_inspect_os (g);
  if (roots == NULL)
    exit (EXIT_FAILURE);

  if (roots[0] == NULL) {
    suggest_filesystems ();
    return;
  }

  printf (_("This disk contains one or more operating systems.  You can use these mount\n"
            "commands in virt-rescue (at the ><rescue> prompt) to mount the filesystems.\n\n"));

  for (i = 0; roots[i] != NULL; ++i) {
    CLEANUP_FREE_STRING_LIST char **mps = NULL;
    CLEANUP_FREE char *type = NULL, *distro = NULL, *product_name = NULL;
    int major, minor;
    size_t j;

    type = guestfs_inspect_get_type (g, roots[i]);
    distro = guestfs_inspect_get_distro (g, roots[i]);
    product_name = guestfs_inspect_get_product_name (g, roots[i]);
    major = guestfs_inspect_get_major_version (g, roots[i]);
    minor = guestfs_inspect_get_minor_version (g, roots[i]);

    printf (_("# %s is the root of a %s operating system\n"
              "# type: %s, distro: %s, version: %d.%d\n"
              "# %s\n\n"),
            roots[i], type ? : "unknown",
            type ? : "unknown", distro ? : "unknown", major, minor,
            product_name ? : "");

    mps = guestfs_inspect_get_mountpoints (g, roots[i]);
    if (mps == NULL)
      exit (EXIT_FAILURE);

    /* Sort by key length, shortest key first, so that we end up
     * mounting the filesystems in the correct order.
     */
    qsort (mps, guestfs_int_count_strings (mps) / 2, 2 * sizeof (char *),
           compare_keys_len);

    for (j = 0; mps[j] != NULL; j += 2)
      printf ("mount %s /sysroot%s\n", mps[j+1], mps[j]);

    /* If it's Linux, print the bind-mounts. */
    if (type && STREQ (type, "linux")) {
      printf ("mount --bind /dev /sysroot/dev\n");
      printf ("mount --bind /dev/pts /sysroot/dev/pts\n");
      printf ("mount --bind /proc /sysroot/proc\n");
      printf ("mount --bind /sys /sysroot/sys\n");
    }

    printf ("\n");
  }
}

/* Inspection failed, so it doesn't contain any OS that we recognise.
 * However there might still be filesystems so print some suggestions
 * for those.
 */
static void
suggest_filesystems (void)
{
  size_t i, count;

  CLEANUP_FREE_STRING_LIST char **fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    exit (EXIT_FAILURE);

  /* Count how many are not swap or unknown.  Possibly we should try
   * mounting to see which are mountable, but that has a high
   * probability of breaking.
   */
#define TEST_MOUNTABLE(fs) STRNEQ ((fs), "swap") && STRNEQ ((fs), "unknown")
  count = 0;
  for (i = 0; fses[i] != NULL; i += 2) {
    if (TEST_MOUNTABLE (fses[i+1]))
      count++;
  }

  if (count == 0) {
    printf (_("This disk contains no mountable filesystems that we recognize.\n\n"
              "However you can still use virt-rescue on the disk image, to try to mount\n"
              "filesystems that are not recognized by libguestfs, or to create partitions,\n"
              "logical volumes and filesystems on a blank disk.\n"));
    return;
  }

  printf (_("This disk contains one or more filesystems, but we don't recognize any\n"
            "operating system.  You can use these mount commands in virt-rescue (at the\n"
            "><rescue> prompt) to mount these filesystems.\n\n"));

  for (i = 0; fses[i] != NULL; i += 2) {
    printf (_("# %s has type '%s'\n"), fses[i], fses[i+1]);

    if (TEST_MOUNTABLE (fses[i+1]))
      printf ("mount %s /sysroot\n", fses[i]);

    printf ("\n");
  }
#undef TEST_MOUNTABLE
}

static void add_scratch_disk (struct drv **drvs);

static void
add_scratch_disks (int n, struct drv **drvs)
{
  while (n > 0) {
    add_scratch_disk (drvs);
    n--;
  }
}

static void
add_scratch_disk (struct drv **drvs)
{
  struct drv *drv;

  /* Add the scratch disk to the drives list. */
  drv = calloc (1, sizeof (struct drv));
  if (!drv) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  drv->type = drv_scratch;
  drv->nr_drives = -1;
  drv->scratch.size = INT64_C (10737418240);
  drv->next = *drvs;
  *drvs = drv;
}
