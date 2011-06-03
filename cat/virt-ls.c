/* virt-ls
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
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include <locale.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>

#include "progname.h"

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

static int do_ls (const char *dir);
static int do_ls_l (const char *dir);
static int do_ls_R (const char *dir);

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
           _("%s: list files in a virtual machine\n"
             "Copyright (C) 2010-2011 Red Hat Inc.\n"
             "Usage:\n"
             "  %s [--options] -d domname dir [dir ...]\n"
             "  %s [--options] -a disk.img [-a disk.img ...] dir [dir ...]\n"
             "Options:\n"
             "  -a|--add image       Add image\n"
             "  -c|--connect uri     Specify libvirt URI for -d option\n"
             "  -d|--domain guest    Add disks from libvirt guest\n"
             "  --echo-keys          Don't turn off echo for passphrases\n"
             "  --format[=raw|..]    Force disk format for -a option\n"
             "  --help               Display brief help\n"
             "  --keys-from-stdin    Read passphrases from stdin\n"
             "  -l|--long            Long listing\n"
             "  -R|--recursive       Recursive listing\n"
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

  static const char *options = "a:c:d:lRvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "keys-from-stdin", 0, 0, 0 },
    { "long", 0, 0, 'l' },
    { "recursive", 0, 0, 'R' },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  int c;
  int option_index;
#define MODE_LS_L  1
#define MODE_LS_R  2
#define MODE_LS_LR (MODE_LS_L|MODE_LS_R)
  int mode = 0;

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

    case 'l':
      mode |= MODE_LS_L;
      break;

    case 'R':
      mode |= MODE_LS_R;
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
   * virt-ls which is how we detect this.
   */
  if (drvs == NULL) {
    /* argc - 1 because last parameter is the single directory name. */
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

  if (mode == MODE_LS_LR) {
    fprintf (stderr, _("%s: cannot combine -l and -R options\n"),
             program_name);
    exit (EXIT_FAILURE);
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 1);
  assert (live == 0);

  /* User must specify at least one directory name on the command line. */
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

  while (optind < argc) {
    const char *dir = argv[optind];

    switch (mode) {
    case 0:                     /* no -l or -R option */
      if (do_ls (dir) == -1)
        errors++;
      break;

    case MODE_LS_L:             /* virt-ls -l */
      if (do_ls_l (dir) == -1)
        errors++;
      break;

    case MODE_LS_R:             /* virt-ls -R */
      if (do_ls_R (dir) == -1)
        errors++;
      break;

    default:
      abort ();                 /* can't happen */
    }

    optind++;
  }

  guestfs_close (g);

  exit (errors == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static int
do_ls (const char *dir)
{
  char **lines;
  size_t i;

  if ((lines = guestfs_ls (g, dir)) == NULL) {
    return -1;
  }

  for (i = 0; lines[i] != NULL; ++i) {
    printf ("%s\n", lines[i]);
    free (lines[i]);
  }
  free (lines);

  return 0;
}

static int
do_ls_l (const char *dir)
{
  char *out;

  if ((out = guestfs_ll (g, dir)) == NULL)
    return -1;

  printf ("%s", out);
  free (out);

  return 0;
}

static int
do_ls_R (const char *dir)
{
  /* This is TMP_TEMPLATE_ON_STACK expanded from fish.h. */
  const char *tmpdir = guestfs_tmpdir ();
  char tmpfile[strlen (tmpdir) + 32];
  sprintf (tmpfile, "%s/virtlsXXXXXX", tmpdir);

  int fd = mkstemp (tmpfile);
  if (fd == -1) {
    perror ("mkstemp");
    exit (EXIT_FAILURE);
  }

  char buf[BUFSIZ]; /* also used below */
  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_find0 (g, dir, buf) == -1)
    return -1;

  if (close (fd) == -1) {
    perror (tmpfile);
    exit (EXIT_FAILURE);
  }

  /* The output of find0 is a \0-separated file.  Turn each \0 into
   * a \n character.
   */
  fd = open (tmpfile, O_RDONLY);
  if (fd == -1) {
    perror (tmpfile);
    exit (EXIT_FAILURE);
  }

  ssize_t r;
  while ((r = read (fd, buf, sizeof buf)) > 0) {
    size_t i;
    for (i = 0; i < (size_t) r; ++i)
      if (buf[i] == '\0')
        buf[i] = '\n';

    size_t n = r;
    while (n > 0) {
      r = write (1, buf, n);
      if (r == -1) {
        perror ("write");
        exit (EXIT_FAILURE);
      }
      n -= r;
    }
  }

  if (r == -1 || close (fd) == -1) {
    perror (tmpfile);
    exit (EXIT_FAILURE);
  }

 unlink (tmpfile);

 return 0;
}
