/* virt-format
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

#include "progname.h"
#include "c-ctype.h"

#include "guestfs.h"
#include "options.h"

/* These globals are shared with options.c. */
guestfs_h *g;

int read_only = 0;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
int inspector = 0;
const char *libvirt_uri = NULL;

static const char *filesystem = NULL;
static const char *vg = NULL, *lv = NULL;
static const char *partition = "DEFAULT";
static int wipe = 0;

static void parse_vg_lv (const char *lvm);
static int do_format (void);
static int do_rescan (char **devices);

static inline char *
bad_cast (char const *s)
{
  return (char *) s;
}

static void __attribute__((noreturn))
usage (int status)
{
  char *warning =
    _("IMPORTANT NOTE: This program ERASES ALL DATA on disks.");

  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n%s\n"),
             program_name, warning);
  else {
    fprintf (stdout,
           _("%s: erase and make a blank disk\n"
             "Copyright (C) 2012 Red Hat Inc.\n"
             "\n"
             "%s\n"
             "\n"
             "Usage:\n"
             "  %s [--options] -a disk.img [-a disk.img ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  --filesystem=..      Create empty filesystem\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  --lvm=..             Create Linux LVM2 logical volume\n"
             "  --partition=..       Create / set partition type\n"
             "  -v|--verbose         Verbose messages\n"
             "  -V|--version         Display version and exit\n"
             "  --wipe               Write zeroes over whole disk\n"
             "  -x                   Trace libguestfs API calls\n"
             "For more information, see the manpage %s(1).\n"
             "\n"
             "%s\n\n"),
             program_name, warning, program_name, program_name,
             warning);
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
    { "filesystem", 1, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "lvm", 2, 0, 0 },
    { "partition", 2, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "wipe", 0, 0, 0 },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  int c;
  int option_index;
  int retry, retries;

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
      } else if (STREQ (long_options[option_index].name, "filesystem")) {
        if (STREQ (optarg, "none"))
          filesystem = NULL;
        else if (optarg[0] == '-') { /* eg: --filesystem --lvm */
          fprintf (stderr, _("%s: no filesystem was specified\n"),
                   program_name);
          exit (EXIT_FAILURE);
        } else
          filesystem = optarg;
      } else if (STREQ (long_options[option_index].name, "lvm")) {
        if (vg || lv) {
          fprintf (stderr,
                   _("%s: --lvm option cannot be given multiple times\n"),
                   program_name);
          exit (EXIT_FAILURE);
        }
        if (optarg == NULL) {
          vg = strdup ("VG");
          lv = strdup ("LV");
          if (!vg || !lv) { perror ("strdup"); exit (EXIT_FAILURE); }
        }
        else if (STREQ (optarg, "none"))
          vg = lv = NULL;
        else
          parse_vg_lv (optarg);
      } else if (STREQ (long_options[option_index].name, "partition")) {
        if (optarg == NULL)
          partition = "DEFAULT";
        else if (STREQ (optarg, "none"))
          partition = NULL;
        else
          partition = optarg;
      } else if (STREQ (long_options[option_index].name, "wipe")) {
        wipe = 1;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 program_name, long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      OPTION_a;
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
  assert (read_only == 0);
  assert (inspector == 0);
  assert (live == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  /* The user didn't specify any drives to format. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Because the libguestfs kernel can get stuck rereading the
   * partition table after things have been erased, we sometimes need
   * to completely restart the guest.  Hence this complex retry logic.
   */
  for (retries = 0; retries <= 1; ++retries) {
    /* Add domains/drives from the command line (for a single guest). */
    add_drives (drvs, 'a');

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    /* Perform the format. */
    retry = do_format ();
    if (!retry)
      break;

    if (retries == 0) {
      /* We're going to silently retry, after reopening the connection. */
      guestfs_h *g2;

      g2 = guestfs_create ();
      guestfs_set_verbose (g2, guestfs_get_verbose (g));
      guestfs_set_trace (g2, guestfs_get_trace (g));

      guestfs_close (g);
      g = g2;
    }
    else {
      /* Failed. */
      fprintf (stderr,
               _("%s: failed to rescan the disks after two attempts.  This\n"
                 "may mean there is some sort of partition table or disk\n"
                 "data which we are unable to remove.  If you think this\n"
                 "is a bug, please file a bug at http://libguestfs.org/\n"),
               program_name);
      exit (EXIT_FAILURE);
    }
  }

  /* Free up data structures. */
  free_drives (drvs);

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/* Parse lvm string of the form "/dev/VG/LV" or "VG/LV".
 * This sets the global variables 'vg' and 'lv', or exits on failure.
 */
static void
parse_vg_lv (const char *lvm)
{
  size_t i;

  if (STRPREFIX (lvm, "/dev/"))
    lvm += 5;

  i = strcspn (lvm, "/");
  if (lvm[i]) {
    vg = strndup (lvm, i);
    lv = strdup (lvm + i + 1);

    if (!vg || !lv) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  } else {
  cannot_parse:
    fprintf (stderr, _("%s: cannot parse --lvm option (%s)\n"),
             program_name, lvm);
    exit (EXIT_FAILURE);
  }

  if (strchr (vg, '/') || strchr (lv, '/'))
    goto cannot_parse;
}

/* Returns 0 on success, 1 if we need to retry. */
static int
do_format (void)
{
  char **devices;
  size_t i;
  int ret;

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);

  /* Erase the disks. */
  if (!wipe) {
    for (i = 0; devices[i] != NULL; ++i) {
      /* erase the filesystem signatures on each device */
      if (guestfs_wipefs (g, devices[i]) == -1)
        exit (EXIT_FAILURE);
      /* Then erase the partition table on each device. */
      if (guestfs_zero (g, devices[i]) == -1)
        exit (EXIT_FAILURE);
    }
  }
  else /* wipe */ {
    for (i = 0; devices[i] != NULL; ++i) {
      if (guestfs_zero_device (g, devices[i]) == -1)
        exit (EXIT_FAILURE);
    }
  }

  if (do_rescan (devices)) {
    ret = 1; /* which means, reopen the handle and retry */
    goto out;
  }

  /* Format each disk. */
  for (i = 0; devices[i] != NULL; ++i) {
    char *dev = devices[i];
    int free_dev = 0;

    if (partition) {
      const char *ptype = partition;
      int64_t dev_size;

      /* If partition has the magic value "DEFAULT", choose either MBR or GPT.*/
      if (STREQ (partition, "DEFAULT")) {
        dev_size = guestfs_blockdev_getsize64 (g, devices[i]);
        if (dev_size == -1)
          exit (EXIT_FAILURE);
        ptype = dev_size < INT64_C(2)*1024*1024*1024*1024 ? "mbr" : "gpt";
      }

      if (guestfs_part_disk (g, devices[i], ptype) == -1)
        exit (EXIT_FAILURE);
      if (asprintf (&dev, "%s1", devices[i]) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      free_dev = 1;
    }

    if (vg && lv) {
      char *devs[2] = { dev, NULL };

      if (guestfs_pvcreate (g, dev) == -1)
        exit (EXIT_FAILURE);

      if (guestfs_vgcreate (g, vg, devs) == -1)
        exit (EXIT_FAILURE);

      if (guestfs_lvcreate_free (g, lv, vg, 100) == -1)
        exit (EXIT_FAILURE);

      if (free_dev)
        free (dev);
      if (asprintf (&dev, "/dev/%s/%s", vg, lv) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      free_dev = 1;
    }

    if (filesystem) {
      if (guestfs_mkfs_opts (g, filesystem, dev, -1) == -1)
        exit (EXIT_FAILURE);
    }

    if (free_dev)
      free (dev);
  }

  if (guestfs_sync (g) == -1)
    exit (EXIT_FAILURE);

  ret = 0;

 out:
  /* Free device list. */
  for (i = 0; devices[i] != NULL; ++i)
    free (devices[i]);
  free (devices);

  return ret;
}

/* Rescan everything so the kernel knows that there are no partition
 * tables, VGs etc.  Returns 0 on success, 1 if we need to retry.
 */
static int
do_rescan (char **devices)
{
  size_t i;
  size_t errors = 0;
  guestfs_error_handler_cb old_error_cb;
  void *old_error_data;

  old_error_cb = guestfs_get_error_handler (g, &old_error_data);
  guestfs_set_error_handler (g, NULL, NULL);

  for (i = 0; devices[i] != NULL; ++i) {
    if (guestfs_blockdev_rereadpt (g, devices[i]) == -1)
      errors++;
  }

  if (guestfs_vgscan (g) == -1)
    errors++;

  guestfs_set_error_handler (g, old_error_cb, old_error_data);

  return errors ? 1 : 0;
}
