/* virt-tail
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
#include <signal.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "getprogname.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "options.h"
#include "display-options.h"
#include "windows.h"

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 1;
int live = 0;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 1;
int in_guestfish = 0;
int in_virt_rescue = 0;

static int do_tail (int argc, char *argv[], struct drv *drvs, struct mp *mps);
static time_t disk_mtime (struct drv *drvs);
static int reopen_handle (void);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try `%s --help' for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: follow (tail) files in a virtual machine\n"
              "Copyright (C) 2016 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domname file [file ...]\n"
              "  %s [--options] -a disk.img [-a disk.img ...] file [file ...]\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --echo-keys          Don't turn off echo for passphrases\n"
              "  -f|--follow          Ignored for compatibility with tail\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  --help               Display brief help\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  -m|--mount dev[:mnt[:opts[:fstype]]]\n"
              "                       Mount dev on mnt (if omitted, /)\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -x                   Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"),
            getprogname (), getprogname (),
            getprogname (), getprogname ());
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

  static const char options[] = "a:c:d:fm:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "follow", 0, 0, 'f' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "keys-from-stdin", 0, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "short-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct mp *mps = NULL;
  struct mp *mp;
  char *p;
  const char *format = NULL;
  bool format_consumed = true;
  int c;
  int r;
  int option_index;

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
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

    case 'f':
      /* ignored */
      break;

    case 'm':
      OPTION_m;
      inspector = 0;
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
  assert (inspector == 1 || mps != NULL);
  assert (live == 0);

  /* User must specify at least one filename on the command line. */
  if (optind >= argc || argc - optind < 1) {
    fprintf (stderr, _("%s: error: missing filenames on command line.\n"
                       "Please specify at least one file to follow.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  CHECK_OPTION_format_consumed;

  /* User must have specified some drives. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  r = do_tail (argc - optind, &argv[optind], drvs, mps);

  free_drives (drvs);
  free_mps (mps);

  guestfs_close (g);

  exit (r == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

struct follow {
  int64_t mtime;                /* For each file, last mtime. */
  int64_t size;                 /* For each file, last size. */
};

static sig_atomic_t quit = 0;

static void
user_cancel (int sig)
{
  quit = 1;
  ignore_value (guestfs_user_cancel (g));
}

static int
do_tail (int argc, char *argv[], /* list of files in the guest */
         struct drv *drvs, struct mp *mps)
{
  struct sigaction sa;
  time_t drvt;
  int first_iteration = 1;
  int prev_file_displayed = -1;
  CLEANUP_FREE struct follow *file = NULL;

  /* Allocate storage to track each file. */
  file = calloc (argc, sizeof (struct follow));

  /* We loop until the user hits ^C. */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = user_cancel;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGINT, &sa, NULL);
  sigaction (SIGQUIT, &sa, NULL);

  if (guestfs_set_pgroup (g, 1) == -1)
    exit (EXIT_FAILURE);

  drvt = disk_mtime (drvs);
  if (drvt == (time_t)-1)
    return -1;

  while (!quit) {
    time_t t;
    int i;
    int windows = 0;
    char *root;
    CLEANUP_FREE_STRING_LIST char **roots = NULL;
    int processed;

    /* Add drives, inspect and mount. */
    add_drives (drvs, 'a');

    if (guestfs_launch (g) == -1)
      return -1;

    if (mps != NULL)
      mount_mps (mps);
    else
      inspect_mount ();

    if (inspector) {
      /* Get root mountpoint.  See: fish/inspect.c:inspect_mount */
      roots = guestfs_inspect_get_roots (g);

      assert (roots);
      assert (roots[0] != NULL);
      assert (roots[1] == NULL);
      root = roots[0];

      /* Windows?  Special handling is required. */
      windows = is_windows (g, root);
    }

    /* Check files here. */
    processed = 0;
    for (i = 0; i < argc; ++i) {
      CLEANUP_FREE char *filename = NULL;
      CLEANUP_FREE_STATNS struct guestfs_statns *stat = NULL;

      if (windows) {
        filename = windows_path (g, root, filename, 1 /* readonly */);
        if (filename == NULL)
          return -1; /* windows_path printed an error */
      }
      else {
        filename = strdup (argv[i]);
        if (filename == NULL) {
          perror ("malloc");
          return -1;
        }
      }

      guestfs_push_error_handler (g, NULL, NULL);
      stat = guestfs_statns (g, filename);
      guestfs_pop_error_handler (g);
      if (stat == NULL) {
        /* There's an error.  Treat ENOENT as if the file was empty size. */
        if (guestfs_last_errno (g) == ENOENT) {
          time (&t);
          file[i].mtime = t;
          file[i].size = 0;
        }
        else {
          fprintf (stderr, "%s: %s: %s\n",
                   getprogname (), filename, guestfs_last_error (g));
          return -1;
        }
      }
      else {
        CLEANUP_FREE_STRING_LIST char **lines = NULL;
        CLEANUP_FREE char *content = NULL;

        processed++;

        /* We believe the guest mtime to mean the file changed.  This
         * can include the file changing but the size staying the same,
         * so be careful.
         */
        if (file[i].mtime != stat->st_mtime_sec ||
            file[i].size != stat->st_size) {
          /* If we get here, the file changed and we're going to display
           * something.  If there is more than one file, and the file
           * displayed is different from previously, then display the
           * filename banner.
           */
          if (i != prev_file_displayed)
            printf ("\n\n--- %s ---\n\n", filename);
          prev_file_displayed = i;

          /* If the file grew, display all the new content unless
           * it's a lot, in which case display the last few lines.
           * If the file shrank, display the last few lines.
           * If the file stayed the same size [note that the file
           * has changed -- see above], redisplay the last few lines.
           */
          if (stat->st_size > file[i].size + 10000) { /* grew a lot */
            goto show_tail;
          }
          else if (stat->st_size > file[i].size) { /* grew a bit */
            int count = stat->st_size - file[i].size;
            size_t r;
            guestfs_push_error_handler (g, NULL, NULL);
            content = guestfs_pread (g, filename, count, file[i].size, &r);
            guestfs_pop_error_handler (g);
            if (content) {
              size_t j;
              for (j = 0; j < r; ++j)
                putchar (content[j]);
            }
          }
          else if (stat->st_size <= file[i].size) { /* shrank or same size */
          show_tail:
            guestfs_push_error_handler (g, NULL, NULL);
            lines = guestfs_tail (g, filename);
            guestfs_pop_error_handler (g);
            if (lines) {
              size_t j;
              for (j = 0; lines[j] != NULL; ++j)
                puts (lines[j]);
            }
          }

          fflush (stdout);

          file[i].mtime = stat->st_mtime_sec;
          file[i].size = stat->st_size;
        }
      }
    }

    /* If no files were found, exit.  If this is the first iteration
     * of the loop, then this is an error, otherwise it's an ordinary
     * exit when all files get deleted (see man page).
     */
    if (processed == 0) {
      if (first_iteration) {
        fprintf (stderr,
                 _("%s: error: none of the files were found in the disk image\n"),
                 getprogname ());
        return -1;
      }
      else {
        printf (_("%s: all files deleted, exiting\n"), getprogname ());
        return 0;
      }
    }

    /* Do nothing until something happens on the disk image.  Even if
     * the drive changes, always wait min. 30 seconds.  For libvirt
     * (-d) and remote sources we cannot check this so we have to use
     * a fixed (5 minute) delay instead.  Also we recheck every so
     * often even if nothing seems to have changed.  (XXX Can we do
     * better?)
     */
    for (i = 0; i < 10 /* 30 seconds * 10 = 5 mins */; ++i) {
      time (&t);
      sleep (30);
      drvt = disk_mtime (drvs);
      if (drvt == (time_t)-1)
        return -1;
      if (drvt-t < 30) break;
    }

    if (reopen_handle () == -1)
      return -1;

    first_iteration = 0;
  }

  return 0;
}

/* Return the latest (highest) mtime of any local drive in the list of
 * drives passed on the command line.  If there are no such drives
 * (eg. the guest is libvirt or remote) then this returns 0.  If there
 * is an error it returns (time_t)-1.
 */
static time_t
disk_mtime (struct drv *drvs)
{
  time_t ret;

  if (drvs == NULL)
    return 0;

  ret = disk_mtime (drvs->next);
  if (ret == (time_t)-1)
    return -1;

  if (drvs->type == drv_a) {
    struct stat statbuf;

    if (stat (drvs->a.filename, &statbuf) == -1) {
      error (0, errno, "stat: %s", drvs->a.filename);
      return -1;
    }

    if (statbuf.st_mtime > ret)
      ret = statbuf.st_mtime;
  }
  /* XXX "look into" libvirt guests for local drives. */

  return ret;
}

/* Reopen the handle.  Open the new handle first and copy some
 * settings across.  We only need to copy settings which are set
 * somewhere in the code above, eg by OPTION_v.  Settings from
 * environment variables will be recreated by guestfs_create.
 *
 * The global 'g' must never be unset or NULL (visible to code outside
 * this function).
 */
static int
reopen_handle (void)
{
  guestfs_h *g2;

  g2 = guestfs_create ();
  if (g2 == NULL) {
    perror ("guestfs_create");
    return -1;
  }

  guestfs_set_verbose (g2, guestfs_get_verbose (g));
  guestfs_set_trace (g2, guestfs_get_trace (g));
  guestfs_set_pgroup (g2, guestfs_get_pgroup (g));

  guestfs_close (g);
  g = g2;

  return 0;
}
