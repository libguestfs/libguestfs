/* libguestfs-test-tool
 * Copyright (C) 2009 Red Hat Inc.
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
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <guestfs.h>

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
#define N_(str) str
#endif

#define DEFAULT_TIMEOUT 120

static const char *helper = DEFAULT_HELPER;
static int timeout = DEFAULT_TIMEOUT;
static char tmpf[] = "/tmp/libguestfs-test-tool-sda-XXXXXX";
static char isof[] = "/tmp/libguestfs-test-tool-iso-XXXXXX";
static guestfs_h *g;

static void preruncheck (void);
static void make_files (void);
static void set_qemu (const char *path, int use_wrapper);

static void
usage (void)
{
  printf (_("libguestfs-test-tool: interactive test tool\n"
	    "Copyright (C) 2009 Red Hat Inc.\n"
	    "Usage:\n"
	    "  libguestfs-test-tool [--options]\n"
	    "Options:\n"
	    "  --help         Display usage\n"
	    "  --helper libguestfs-test-tool-helper\n"
	    "                 Helper program (default: %s)\n"
	    "  --qemudir dir  Specify QEMU source directory\n"
	    "  --qemu qemu    Specify QEMU binary\n"
	    "  --timeout n\n"
	    "  -t n           Set launch timeout (default: %d seconds)\n"
	    ),
	  DEFAULT_HELPER, DEFAULT_TIMEOUT);
}

int
main (int argc, char *argv[])
{
  static const char *options = "?";
  static struct option long_options[] = {
    { "help", 0, 0, '?' },
    { "helper", 1, 0, 0 },
    { "qemu", 1, 0, 0 },
    { "qemudir", 1, 0, 0 },
    { "timeout", 1, 0, 't' },
    { 0, 0, 0, 0 }
  };
  int c;
  int option_index;
  extern char **environ;
  int i;
  struct guestfs_version *vers;
  char *sfdisk_lines[] = { ",", NULL };
  char *str;
  /* XXX This is wrong if the user renames the helper. */
  char *helper_args[] = { "/iso/libguestfs-test-tool-helper", NULL };

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (strcmp (long_options[option_index].name, "helper") == 0)
	helper = optarg;
      else if (strcmp (long_options[option_index].name, "qemu") == 0)
	set_qemu (optarg, 0);
      else if (strcmp (long_options[option_index].name, "qemudir") == 0)
	set_qemu (optarg, 1);
      else {
	fprintf (stderr,
		 _("libguestfs-test-tool: unknown long option: %s (%d)\n"),
		 long_options[option_index].name, option_index);
	exit (1);
      }
      break;

    case 't':
      if (sscanf (optarg, "%d", &timeout) != 1 || timeout < 0) {
	fprintf (stderr,
		 _("libguestfs-test-tool: invalid timeout: %s\n"),
		 optarg);
	exit (1);
      }
      break;

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr,
	       _("libguestfs-test-tool: unexpected command line option 0x%x\n"),
	       c);
      exit (1);
    }
  }

  preruncheck ();
  make_files ();

  printf ("===== Test starts here =====\n");

  /* Must set LIBGUESTFS_DEBUG=1 */
  setenv ("LIBGUESTFS_DEBUG", "1", 1);

  /* Print out any environment variables which may relate to this test. */
  for (i = 0; environ[i] != NULL; ++i)
    if (strncmp (environ[i], "LIBGUESTFS_", 11) == 0)
      printf ("%s\n", environ[i]);

  /* Create the handle and configure it. */
  g = guestfs_create ();
  if (g == NULL) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to create libguestfs handle\n"));
    exit (1);
  }
  if (guestfs_add_drive (g, tmpf) == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to add drive '%s'\n"),
	     tmpf);
    exit (1);
  }
  if (guestfs_add_drive (g, isof) == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to add drive '%s'\n"),
	     isof);
    exit (1);
  }

  /* Print any version info etc. */
  vers = guestfs_version (g);
  if (vers == NULL) {
    fprintf (stderr, _("libguestfs-test-tool: guestfs_version failed\n"));
    exit (1);
  }
  printf ("library version: %"PRIi64".%"PRIi64".%"PRIi64"%s\n",
	  vers->major, vers->minor, vers->release, vers->extra);
  guestfs_free_version (vers);

  printf ("guestfs_get_append: %s\n", guestfs_get_append (g) ? : "(null)");
  printf ("guestfs_get_autosync: %d\n", guestfs_get_autosync (g));
  printf ("guestfs_get_memsize: %d\n", guestfs_get_memsize (g));
  printf ("guestfs_get_path: %s\n", guestfs_get_path (g));
  printf ("guestfs_get_qemu: %s\n", guestfs_get_qemu (g));
  printf ("guestfs_get_verbose: %d\n", guestfs_get_verbose (g));

  /* Launch the guest handle. */
  if (guestfs_launch (g) == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to launch appliance\n"));
    exit (1);
  }

  printf ("Launching appliance, timeout set to %d seconds.\n", timeout);
  fflush (stdout);

  alarm (timeout);

  if (guestfs_wait_ready (g) == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed or timed out in 'wait_ready'\n"));
    exit (1);
  }

  alarm (0);

  printf ("Guest launched OK.\n");
  fflush (stdout);

  /* Create the filesystem and mount everything. */
  if (guestfs_sfdiskM (g, "/dev/sda", sfdisk_lines) == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to run sfdisk\n"));
    exit (1);
  }

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to mkfs.ext2\n"));
    exit (1);
  }

  if (guestfs_mount (g, "/dev/sda1", "/") == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to mount /dev/sda1 on /\n"));
    exit (1);
  }

  if (guestfs_mkdir (g, "/iso") == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to mkdir /iso\n"));
    exit (1);
  }

  if (guestfs_mount (g, "/dev/sdb", "/iso") == -1) {
    fprintf (stderr,
	     _("libguestfs-test-tool: failed to mount /dev/sdb on /iso\n"));
    exit (1);
  }

  /* Let's now run some simple tests using the helper program. */
  str = guestfs_command (g, helper_args);
  if (str == NULL) {
    fprintf (stderr,
	     _("libguestfs-test-tool: could not run helper program, or helper failed\n"));
    exit (1);
  }
  free (str);

  printf ("===== TEST FINISHED OK =====\n");
  exit (0);
}

static char qemuwrapper[] = "/tmp/libguestfs-test-tool-wrapper-XXXXXX";

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
    exit (1);
  }

  if (!use_wrapper) {
    if (access (path, X_OK) == -1) {
      fprintf (stderr,
	       _("Binary '%s' does not exist or is not executable\n"),
	       path);
      exit (1);
    }

    setenv ("LIBGUESTFS_QEMU", path, 1);
    return;
  }

  /* This should be a source directory, so check it. */
  snprintf (buffer, sizeof buffer, "%s/pc-bios", path);
  if (stat (buffer, &statbuf) == -1 ||
      !S_ISDIR (statbuf.st_mode)) {
    fprintf (stderr,
	     _("%s: does not look like a qemu source directory\n"),
	     path);
    exit (1);
  }

  /* Make a wrapper script. */
  fd = mkstemp (qemuwrapper);
  if (fd == -1) {
    perror (qemuwrapper);
    exit (1);
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

  setenv ("LIBGUESTFS_QEMU", qemuwrapper, 1);
  atexit (cleanup_wrapper);
}

/* After getting the command line args, but before running
 * anything, we check everything is in place to do the tests.
 */
static void
preruncheck (void)
{
  int r;
  FILE *fp;
  char cmd[256];
  char buffer[1024];

  if (access (helper, R_OK) == -1) {
    fprintf (stderr,
    _("Test tool helper program 'libguestfs-test-tool-helper' is not\n"
      "available.  Expected to find it in '%s'\n"
      "\n"
      "Use the --helper option to specify the location of this program.\n"),
	     helper);
    exit (1);
  }

  snprintf (cmd, sizeof cmd, "file '%s'", helper);
  fp = popen (cmd, "r");
  if (fp == NULL) {
    perror (cmd);
    exit (1);
  }
  r = fread (buffer, 1, sizeof buffer - 1, fp);
  if (r == 0) {
    fprintf (stderr, _("command failed: %s"), cmd);
    exit (1);
  }
  pclose (fp);
  buffer[r] = '\0';

  if (strstr (buffer, "statically linked") == NULL) {
    fprintf (stderr,
    _("Test tool helper program %s\n"
      "is not statically linked.  This is a build error when this test tool\n"
      "was built.\n"),
	     helper);
    exit (1);
  }
}

static void
cleanup_tmpfiles (void)
{
  unlink (tmpf);
  unlink (isof);
}

static void
make_files (void)
{
  int fd, r;
  char cmd[256];

  /* Make the ISO which will contain the helper program. */
  fd = mkstemp (isof);
  if (fd == -1) {
    perror (isof);
    exit (1);
  }
  close (fd);

  snprintf (cmd, sizeof cmd, "mkisofs -quiet -rJT -o '%s' '%s'",
	    isof, helper);
  r = system (cmd);
  if (r == -1 || WEXITSTATUS(r) != 0) {
    fprintf (stderr,
	     _("mkisofs command failed: %s\n"), cmd);
    exit (1);
  }

  /* Allocate the sparse file for /dev/sda. */
  fd = mkstemp (tmpf);
  if (fd == -1) {
    perror (tmpf);
    unlink (isof);
    exit (1);
  }

  if (lseek (fd, 100 * 1024 * 1024 - 1, SEEK_SET) == -1) {
    perror ("lseek");
    close (fd);
    unlink (tmpf);
    unlink (isof);
    exit (1);
  }

  if (write (fd, "\0", 1) == -1) {
    perror ("write");
    close (fd);
    unlink (tmpf);
    unlink (isof);
    exit (1);
  }

  close (fd);

  atexit (cleanup_tmpfiles);	/* Removes tmpf and isof. */
}
