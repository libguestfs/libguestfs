/* virt-cat
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
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

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 1;

static int is_windows (guestfs_h *g, const char *root);
static char *windows_path (guestfs_h *g, const char *root, const char *filename);

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
           _("%s: display files in a virtual machine\n"
             "Copyright (C) 2010 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname file [file ...]\n"
             "  %s [--options] -a disk.img [-a disk.img ...] file [file ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --echo-keys          Don't turn off echo for passphrases\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  --keys-from-stdin    Read passphrases from stdin\n"
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

  static const char *options = "a:c:d:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "keys-from-stdin", 0, 0, 0 },
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
      if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
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

    case 'h':
      usage (EXIT_SUCCESS);

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
   * virt-cat which is how we detect this.
   */
  if (drvs == NULL) {
    /* argc - 1 because last parameter is the single filename. */
    while (optind < argc - 1) {
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
  assert (inspector == 1);
  assert (live == 0);

  /* User must specify at least one filename on the command line. */
  if (optind >= argc || argc - optind < 1)
    usage (EXIT_FAILURE);

  /* User must have specified some drives. */
  if (drvs == NULL)
    usage (EXIT_FAILURE);

  /* Add drives, inspect and mount.  Note that inspector is always true,
   * and there is no -m option.
   */
  add_drives (drvs, 'a');

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  inspect_mount ();

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  unsigned errors = 0;
  int windows;
  char *root, **roots;

  /* Get root mountpoint.  See: fish/inspect.c:inspect_mount */
  roots = guestfs_inspect_get_roots (g);
  assert (roots);
  assert (roots[0] != NULL);
  assert (roots[1] == NULL);
  root = roots[0];
  free (roots);

  /* Windows?  Special handling is required. */
  windows = is_windows (g, root);

  for (; optind < argc; optind++) {
    char *filename_to_free = NULL;
    const char *filename = argv[optind];

    if (windows) {
      filename = filename_to_free = windows_path (g, root, filename);
      if (filename == NULL) {
        errors++;
        continue;
      }
    }

    if (guestfs_download (g, filename, "/dev/stdout") == -1)
      errors++;

    free (filename_to_free);
  }

  free (root);

  guestfs_close (g);

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static int
is_windows (guestfs_h *g, const char *root)
{
  char *type;
  int w;

  type = guestfs_inspect_get_type (g, root);
  if (!type)
    return 0;

  w = STREQ (type, "windows");
  free (type);
  return w;
}

static void mount_drive_letter_ro (char drive_letter, const char *root);

static char *
windows_path (guestfs_h *g, const char *root, const char *path)
{
  char *ret;
  size_t i;

  /* If there is a drive letter, rewrite the path. */
  if (c_isalpha (path[0]) && path[1] == ':') {
    char drive_letter = c_tolower (path[0]);
    /* This returns the newly allocated string. */
    mount_drive_letter_ro (drive_letter, root);
    ret = strdup (path + 2);
    if (ret == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  }
  else if (!*path) {
    ret = strdup ("/");
    if (ret == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  }
  else {
    ret = strdup (path);
    if (ret == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
  }

  /* Blindly convert any backslashes into forward slashes.  Is this good? */
  for (i = 0; i < strlen (ret); ++i)
    if (ret[i] == '\\')
      ret[i] = '/';

  /* If this fails, we want to return NULL. */
  char *t = guestfs_case_sensitive_path (g, ret);
  free (ret);
  ret = t;

  return ret;
}

static void
mount_drive_letter_ro (char drive_letter, const char *root)
{
  char **drives;
  char *device;
  size_t i;

  /* Resolve the drive letter using the drive mappings table. */
  drives = guestfs_inspect_get_drive_mappings (g, root);
  if (drives == NULL || drives[0] == NULL) {
    fprintf (stderr, _("%s: to use Windows drive letters, this must be a Windows guest\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  device = NULL;
  for (i = 0; drives[i] != NULL; i += 2) {
    if (c_tolower (drives[i][0]) == drive_letter && drives[i][1] == '\0') {
      device = drives[i+1];
      break;
    }
  }

  if (device == NULL) {
    fprintf (stderr, _("%s: drive '%c:' not found.\n"),
             program_name, drive_letter);
    exit (EXIT_FAILURE);
  }

  /* Unmount current disk and remount device. */
  if (guestfs_umount_all (g) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mount_ro (g, device, "/") == -1)
    exit (EXIT_FAILURE);

  for (i = 0; drives[i] != NULL; ++i)
    free (drives[i]);
  free (drives);
  /* Don't need to free (device) because that string was in the
   * drives array.
   */
}
