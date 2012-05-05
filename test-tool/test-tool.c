/* libguestfs-test-tool
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <locale.h>
#include <limits.h>
#include <libintl.h>

#include <guestfs.h>

#define _(str) dgettext(PACKAGE, (str))
//#define N_(str) dgettext(PACKAGE, (str))

#define STREQ(a,b) (strcmp((a),(b)) == 0)
//#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
//#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
//#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
//#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
//#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
//#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
//#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

#ifndef P_tmpdir
#define P_tmpdir "/tmp"
#endif

#define DEFAULT_TIMEOUT 600

static int timeout = DEFAULT_TIMEOUT;
static char tmpf[] = P_tmpdir "/libguestfs-test-tool-sda-XXXXXX";
static guestfs_h *g;

static void make_files (void);
static void set_qemu (const char *path, int use_wrapper);

static void
usage (void)
{
  printf (_("libguestfs-test-tool: interactive test tool\n"
            "Copyright (C) 2009-2012 Red Hat Inc.\n"
            "Usage:\n"
            "  libguestfs-test-tool [--options]\n"
            "Options:\n"
            "  --help         Display usage\n"
            "  --qemudir dir  Specify QEMU source directory\n"
            "  --qemu qemu    Specify QEMU binary\n"
            "  --timeout n\n"
            "  -t n           Set launch timeout (default: %d seconds)\n"
            "  --version\n"
            "  -V             Display libguestfs version and exit\n"
            ),
          DEFAULT_TIMEOUT);
}

extern char **environ;

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  static const char *options = "t:V?";
  static const struct option long_options[] = {
    { "help", 0, 0, '?' },
    { "qemu", 1, 0, 0 },
    { "qemudir", 1, 0, 0 },
    { "timeout", 1, 0, 't' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  int c;
  int option_index;
  int i;
  struct guestfs_version *vers;
  char *p;

  /* Create the handle. */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to create libguestfs handle\n"));
    exit (EXIT_FAILURE);
  }
  guestfs_set_verbose (g, 1);
  vers = guestfs_version (g);
  if (vers == NULL) {
    fprintf (stderr, _("libguestfs-test-tool: guestfs_version failed\n"));
    exit (EXIT_FAILURE);
  }

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "qemu"))
        set_qemu (optarg, 0);
      else if (STREQ (long_options[option_index].name, "qemudir"))
        set_qemu (optarg, 1);
      else {
        fprintf (stderr,
                 _("libguestfs-test-tool: unknown long option: %s (%d)\n"),
                 long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 't':
      if (sscanf (optarg, "%d", &timeout) != 1 || timeout < 0) {
        fprintf (stderr,
                 _("libguestfs-test-tool: invalid timeout: %s\n"),
                 optarg);
        exit (EXIT_FAILURE);
      }
      break;

    case 'V':
      printf ("%s %"PRIi64".%"PRIi64".%"PRIi64"%s\n",
              "libguestfs-test-tool",
              vers->major, vers->minor, vers->release, vers->extra);
      guestfs_set_verbose (g, 0);
      exit (EXIT_SUCCESS);

    case '?':
      usage ();
      exit (EXIT_SUCCESS);

    default:
      fprintf (stderr,
               _("libguestfs-test-tool: unexpected command line option 0x%x\n"),
               c);
      exit (EXIT_FAILURE);
    }
  }

  make_files ();

  printf ("===== Test starts here =====\n");

  /* Print out any environment variables which may relate to this test. */
  for (i = 0; environ[i] != NULL; ++i)
    if (STREQLEN (environ[i], "LIBGUESTFS_", 11))
      printf ("%s\n", environ[i]);
  for (i = 0; environ[i] != NULL; ++i)
    if (STREQLEN (environ[i], "FEBOOTSTRAP_", 12))
      printf ("%s\n", environ[i]);
  printf ("TMPDIR=%s\n", getenv ("TMPDIR") ? : "(not set)");

  /* Configure the handle. */
  if (guestfs_add_drive_opts (g, tmpf,
                              GUESTFS_ADD_DRIVE_OPTS_FORMAT, "raw",
                              -1) == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to add drive '%s'\n"),
             tmpf);
    exit (EXIT_FAILURE);
  }

  /* Print any version info etc. */
  printf ("library version: %"PRIi64".%"PRIi64".%"PRIi64"%s\n",
          vers->major, vers->minor, vers->release, vers->extra);
  guestfs_free_version (vers);

  printf ("guestfs_get_append: %s\n", guestfs_get_append (g) ? : "(null)");
  p = guestfs_get_attach_method (g);
  printf ("guestfs_get_attach_method: %s\n", p ? : "(null)");
  free (p);
  printf ("guestfs_get_autosync: %d\n", guestfs_get_autosync (g));
  printf ("guestfs_get_direct: %d\n", guestfs_get_direct (g));
  printf ("guestfs_get_memsize: %d\n", guestfs_get_memsize (g));
  printf ("guestfs_get_network: %d\n", guestfs_get_network (g));
  printf ("guestfs_get_path: %s\n", guestfs_get_path (g));
  printf ("guestfs_get_pgroup: %d\n", guestfs_get_pgroup (g));
  printf ("guestfs_get_qemu: %s\n", guestfs_get_qemu (g));
  printf ("guestfs_get_recovery_proc: %d\n", guestfs_get_recovery_proc (g));
  printf ("guestfs_get_selinux: %d\n", guestfs_get_selinux (g));
  printf ("guestfs_get_smp: %d\n", guestfs_get_smp (g));
  printf ("guestfs_get_trace: %d\n", guestfs_get_trace (g));
  printf ("guestfs_get_verbose: %d\n", guestfs_get_verbose (g));

  printf ("host_cpu: %s\n", host_cpu);

  /* Launch the guest handle. */
  printf ("Launching appliance, timeout set to %d seconds.\n", timeout);
  fflush (stdout);

  alarm (timeout);

  if (guestfs_launch (g) == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to launch appliance\n"));
    exit (EXIT_FAILURE);
  }

  alarm (0);

  printf ("Guest launched OK.\n");
  fflush (stdout);

  /* Create the filesystem and mount everything. */
  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to run part-disk\n"));
    exit (EXIT_FAILURE);
  }

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to mkfs.ext2\n"));
    exit (EXIT_FAILURE);
  }

  if (guestfs_mount_options (g, "", "/dev/sda1", "/") == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to mount /dev/sda1 on /\n"));
    exit (EXIT_FAILURE);
  }

  /* Touch a file. */
  if (guestfs_touch (g, "/hello") == -1) {
    fprintf (stderr,
             _("libguestfs-test-tool: failed to touch file\n"));
    exit (EXIT_FAILURE);
  }

  /* Close the handle. */
  guestfs_close (g);

  /* Booted and performed some simple operations -- success! */
  printf ("===== TEST FINISHED OK =====\n");
  exit (EXIT_SUCCESS);
}

static char qemuwrapper[] = P_tmpdir "/libguestfs-test-tool-wrapper-XXXXXX";

static void
cleanup_wrapper (void)
{
  unlink (qemuwrapper);
}

/* Handle the --qemu and --qemudir parameters.  use_wrapper is true
 * in the --qemudir (source directory) case, where we have to create
 * a wrapper shell script.
 */
static void
set_qemu (const char *path, int use_wrapper)
{
  char buffer[PATH_MAX];
  struct stat statbuf;
  int fd;
  FILE *fp;

  if (getenv ("LIBGUESTFS_QEMU")) {
    fprintf (stderr,
    _("LIBGUESTFS_QEMU environment variable is already set, so\n"
      "--qemu/--qemudir options cannot be used.\n"));
    exit (EXIT_FAILURE);
  }

  if (!use_wrapper) {
    if (access (path, X_OK) == -1) {
      fprintf (stderr,
               _("Binary '%s' does not exist or is not executable\n"),
               path);
      exit (EXIT_FAILURE);
    }

    guestfs_set_qemu (g, path);
    return;
  }

  /* This should be a source directory, so check it. */
  snprintf (buffer, sizeof buffer, "%s/pc-bios", path);
  if (stat (buffer, &statbuf) == -1 ||
      !S_ISDIR (statbuf.st_mode)) {
    fprintf (stderr,
             _("%s: does not look like a qemu source directory\n"),
             path);
    exit (EXIT_FAILURE);
  }

  /* Make a wrapper script. */
  fd = mkstemp (qemuwrapper);
  if (fd == -1) {
    perror (qemuwrapper);
    exit (EXIT_FAILURE);
  }

  fchmod (fd, 0700);

  fp = fdopen (fd, "w");
  fprintf (fp,
           "#!/bin/sh -\n"
           "qemudir='%s'\n"
           "\"$qemudir\"/",
           path);

  /* Select the right qemu binary for the wrapper script. */
#ifdef __i386__
  fprintf (fp, "i386-softmmu/qemu");
#else
  fprintf (fp, host_cpu "-softmmu/qemu-system-" host_cpu);
#endif

  fprintf (fp, " -L \"$qemudir\"/pc-bios \"$@\"\n");

  fclose (fp);

  guestfs_set_qemu (g, qemuwrapper);
  atexit (cleanup_wrapper);
}

static void
cleanup_tmpfiles (void)
{
  unlink (tmpf);
}

static void
make_files (void)
{
  int fd;

  /* Allocate the sparse file for /dev/sda. */
  fd = mkstemp (tmpf);
  if (fd == -1) {
    perror (tmpf);
    exit (EXIT_FAILURE);
  }

  if (lseek (fd, 100 * 1024 * 1024 - 1, SEEK_SET) == -1) {
    perror ("lseek");
    close (fd);
    unlink (tmpf);
    exit (EXIT_FAILURE);
  }

  if (write (fd, "\0", 1) == -1) {
    perror ("write");
    close (fd);
    unlink (tmpf);
    exit (EXIT_FAILURE);
  }

  close (fd);

  atexit (cleanup_tmpfiles);	/* Removes tmpf. */
}
