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
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

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
static const char *label = NULL;
static int wipe = 0;
static int have_wipefs;

static void parse_vg_lv (const char *lvm);
static int do_format (void);
static int do_rescan (char **devices);

static void __attribute__((noreturn))
usage (int status)
{
  char *warning =
    _("IMPORTANT NOTE: This program ERASES ALL DATA on disks.");

  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n%s\n"),
             guestfs_int_program_name, warning);
  else {
    printf (_("%s: erase and make a blank disk\n"
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
              "  --label=..           Set filesystem label\n"
              "  --lvm=..             Create Linux LVM2 logical volume\n"
              "  --partition=..       Create / set partition type\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  --wipe               Write zeroes over whole disk\n"
              "  -x                   Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"
              "\n"
              "%s\n\n"),
            guestfs_int_program_name, warning,
            guestfs_int_program_name, guestfs_int_program_name,
            warning);
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

  static const char *options = "a:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "filesystem", 1, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "label", 1, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "lvm", 2, 0, 0 },
    { "partition", 2, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "wipe", 0, 0, 0 },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int option_index;
  int retry, retries;

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
      } else if (STREQ (long_options[option_index].name, "filesystem")) {
        if (STREQ (optarg, "none"))
          filesystem = NULL;
        else if (optarg[0] == '-') { /* eg: --filesystem --lvm */
          fprintf (stderr, _("%s: no filesystem was specified\n"),
                   guestfs_int_program_name);
          exit (EXIT_FAILURE);
        } else
          filesystem = optarg;
      } else if (STREQ (long_options[option_index].name, "lvm")) {
        if (vg || lv) {
          fprintf (stderr,
                   _("%s: --lvm option cannot be given multiple times\n"),
                   guestfs_int_program_name);
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
      } else if (STREQ (long_options[option_index].name, "label")) {
        label = optarg;
      } else {
        fprintf (stderr, _("%s: unknown long option: %s (%d)\n"),
                 guestfs_int_program_name,
                 long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'a':
      OPTION_a;

      /* Enable discard on all drives added on the command line. */
      assert (drvs != NULL);
      assert (drvs->type == drv_a);
      drvs->a.discard = "besteffort";
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
  if (optind != argc) {
    fprintf (stderr, _("%s: error: extra argument '%s' on command line.\n"
             "Make sure to specify the argument for --format, --lvm "
             "or --partition like '--format=%s'.\n"),
             guestfs_int_program_name, argv[optind], argv[optind]);
    usage (EXIT_FAILURE);
  }

  CHECK_OPTION_format_consumed;

  /* The user didn't specify any drives to format. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a option.\n"),
             guestfs_int_program_name);
    usage (EXIT_FAILURE);
  }

  /* Because the libguestfs kernel can get stuck rereading the
   * partition table after things have been erased, we sometimes need
   * to completely restart the guest.  Hence this complex retry logic.
   */
  for (retries = 0; retries <= 1; ++retries) {
    const char *wipefs[] = { "wipefs", NULL };

    /* Add domains/drives from the command line (for a single guest). */
    add_drives (drvs, 'a');

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    /* Test if the wipefs API is available. */
    have_wipefs = guestfs_feature_available (g, (char **) wipefs);

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

      if (guestfs_shutdown (g) == -1)
        exit (EXIT_FAILURE);
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
               guestfs_int_program_name);
      exit (EXIT_FAILURE);
    }
  }

  /* Free up data structures. */
  free_drives (drvs);

  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);
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
             guestfs_int_program_name, lvm);
    exit (EXIT_FAILURE);
  }

  if (strchr (vg, '/') || strchr (lv, '/'))
    goto cannot_parse;
}

/* Returns 0 on success, 1 if we need to retry. */
static int
do_format (void)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **devices =
    guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);

  /* Erase the disks. */
  if (!wipe) {
    for (i = 0; devices[i] != NULL; ++i) {
      /* erase the filesystem signatures on each device */
      if (have_wipefs && guestfs_wipefs (g, devices[i]) == -1)
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

  /* Send TRIM/UNMAP to all block devices, to give back the space to
   * the host.  However don't fail if this doesn't work.
   */
  guestfs_push_error_handler (g, NULL, NULL);
  for (i = 0; devices[i] != NULL; ++i)
    guestfs_blkdiscard (g, devices[i]);
  guestfs_pop_error_handler (g);

  if (do_rescan (devices))
    return 1; /* which means, reopen the handle and retry */

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

      /* Set the partition type byte appropriately, otherwise Windows
       * won't see the filesystem (RHBZ#1000428).
       */
      if (STREQ (ptype, "mbr") || STREQ (ptype, "msdos")) {
        int mbr_id = 0;

        if (vg && lv)
          mbr_id = 0x8e;
        else if (filesystem) {
          if (STREQ (filesystem, "msdos"))
            mbr_id = 0x01;
          else if (STREQ (filesystem, "fat") || STREQ (filesystem, "vfat"))
            mbr_id = 0x0b;
          else if (STREQ (filesystem, "ntfs"))
            mbr_id = 0x07;
          else if (STRPREFIX (filesystem, "ext"))
            mbr_id = 0x83;
          else if (STREQ (filesystem, "minix"))
            mbr_id = 0x81;
        }

        if (mbr_id > 0)
          guestfs_part_set_mbr_id (g, devices[i], 1, mbr_id);
      }
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
      struct guestfs_mkfs_opts_argv optargs = { .bitmask = 0 };

      if (label) {
        optargs.label = label;
        optargs.bitmask |= GUESTFS_MKFS_OPTS_LABEL_BITMASK;
      }

      if (guestfs_mkfs_opts_argv (g, filesystem, dev, &optargs) == -1)
        exit (EXIT_FAILURE);
    }

    if (free_dev)
      free (dev);
  }

  if (guestfs_sync (g) == -1)
    exit (EXIT_FAILURE);

  return 0;
}

/* Rescan everything so the kernel knows that there are no partition
 * tables, VGs etc.  Returns 0 on success, 1 if we need to retry.
 */
static int
do_rescan (char **devices)
{
  size_t i;
  size_t errors = 0;

  guestfs_push_error_handler (g, NULL, NULL);

  for (i = 0; devices[i] != NULL; ++i) {
    if (guestfs_blockdev_rereadpt (g, devices[i]) == -1)
      errors++;
  }

  if (guestfs_vgscan (g) == -1)
    errors++;

  guestfs_pop_error_handler (g);

  return errors ? 1 : 0;
}
