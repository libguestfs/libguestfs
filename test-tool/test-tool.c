/* libguestfs-test-tool
 * Copyright (C) 2009-2023 Red Hat Inc.
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
#include <errno.h>
#include <error.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <locale.h>
#include <limits.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-utils.h"
#include "display-options.h"

#include "ignore-value.h"

#ifndef P_tmpdir
#define P_tmpdir "/tmp"
#endif

#define DEFAULT_TIMEOUT 600

static int timeout = DEFAULT_TIMEOUT;

static void set_qemu (guestfs_h *g, const char *path, int use_wrapper);

static void
usage (void)
{
  printf (_("libguestfs-test-tool: interactive test tool\n"
            "Copyright (C) 2009-2023 Red Hat Inc.\n"
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

  static const char options[] = "t:V?";
  static const struct option long_options[] = {
    { "help", 0, 0, '?' },
    { "long-options", 0, 0, 0 },
    { "qemu", 1, 0, 0 },
    { "qemudir", 1, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "timeout", 1, 0, 't' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  int c;
  int option_index;
  size_t i;
  struct guestfs_version *vers;
  char *p;
  char **pp;
  guestfs_h *g;
  char *qemu = NULL;
  int qemu_use_wrapper = 0;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "qemu")) {
        qemu = optarg;
        qemu_use_wrapper = 0;
      }
      else if (STREQ (long_options[option_index].name, "qemudir")) {
        qemu = optarg;
        qemu_use_wrapper = 1;
      }
      else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
      break;

    case 't':
      if (sscanf (optarg, "%d", &timeout) != 1 || timeout < 0)
        error (EXIT_FAILURE, 0, _("invalid timeout: %s"), optarg);
      break;

    case 'V':
      g = guestfs_create ();
      if (g == NULL)
        error (EXIT_FAILURE, errno, "guestfs_create");
      vers = guestfs_version (g);
      if (vers == NULL)
        exit (EXIT_FAILURE);
      printf ("%s %"PRIi64".%"PRIi64".%"PRIi64"%s\n",
              "libguestfs-test-tool",
              vers->major, vers->minor, vers->release, vers->extra);
      guestfs_free_version (vers);
      guestfs_close (g);
      exit (EXIT_SUCCESS);

    case '?':
      usage ();
      exit (EXIT_SUCCESS);

    default:
      error (EXIT_FAILURE, 0, _("unexpected command line option %d"), c);
    }
  }

  if (optind < argc)
    error (EXIT_FAILURE, 0, _("extra arguments on the command line"));

  /* Everyone ignores the documentation, so ... */
  printf ("     ************************************************************\n"
          "     *                    IMPORTANT NOTICE\n"
          "     *\n"
          "     * When reporting bugs, include the COMPLETE, UNEDITED\n"
          "     * output below in your bug report.\n"
          "     *\n"
          "     ************************************************************\n"
          );
  sleep (3);

  /* Create the handle. */
  g = guestfs_create_flags (GUESTFS_CREATE_NO_ENVIRONMENT);
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create_flags");
  if (guestfs_parse_environment (g) == -1)
    error (EXIT_FAILURE, 0,
           _("failed parsing environment variables.\n"
             "Check earlier messages, and the output of the ‘printenv’ command."));
  guestfs_set_verbose (g, 1);

  if (qemu)
    set_qemu (g, qemu, qemu_use_wrapper);

  /* Print out any environment variables which may relate to this test. */
  for (i = 0; environ[i] != NULL; ++i) {
    if (STRPREFIX (environ[i], "LIBGUESTFS_"))
      printf ("%s\n", environ[i]);
    if (STRPREFIX (environ[i], "SUPERMIN_"))
      printf ("%s\n", environ[i]);
    if (STRPREFIX (environ[i], "LIBVIRT_"))
      printf ("%s\n", environ[i]);
    if (STRPREFIX (environ[i], "LIBVIRTD_"))
      printf ("%s\n", environ[i]);
    if (STRPREFIX (environ[i], "LD_"))
      printf ("%s\n", environ[i]);
  }
  p = getenv ("TMPDIR");
  if (p)
    printf ("TMPDIR=%s\n", p);
  p = getenv ("PATH");
  if (p)
    printf ("PATH=%s\n", p);
  p = getenv ("XDG_RUNTIME_DIR");
  if (p)
    printf ("XDG_RUNTIME_DIR=%s\n", p);

  /* Print SELinux mode (don't worry if this fails, or if the command
   * doesn't even exist).
   */
  printf ("SELinux: ");
  fflush (stdout); /* because getenforce prints output on stderr :-( */
  ignore_value (system ("getenforce"));

  /* Configure the handle. */
  if (guestfs_add_drive_scratch (g, 100*1024*1024, -1) == -1)
    exit (EXIT_FAILURE);

  printf ("guestfs_get_append: %s\n", guestfs_get_append (g) ? : "(null)");
  printf ("guestfs_get_autosync: %d\n", guestfs_get_autosync (g));
  p = guestfs_get_backend (g);
  printf ("guestfs_get_backend: %s\n", p ? : "(null)");
  free (p);
  pp = guestfs_get_backend_settings (g);
  printf ("guestfs_get_backend_settings: [");
  for (i = 0; pp[i] != NULL; ++i) {
    if (i > 0)
      printf (", ");
    printf ("%s", pp[i]);
    free (pp[i]);
  }
  printf ("]\n");
  free (pp);
  p = guestfs_get_cachedir (g);
  printf ("guestfs_get_cachedir: %s\n", p ? : "(null)");
  free (p);
  p = guestfs_get_hv (g);
  printf ("guestfs_get_hv: %s\n", p);
  free (p);
  printf ("guestfs_get_memsize: %d\n", guestfs_get_memsize (g));
  printf ("guestfs_get_network: %d\n", guestfs_get_network (g));
  printf ("guestfs_get_path: %s\n", guestfs_get_path (g) ? : "(null)");
  printf ("guestfs_get_pgroup: %d\n", guestfs_get_pgroup (g));
  printf ("guestfs_get_program: %s\n", guestfs_get_program (g));
  printf ("guestfs_get_recovery_proc: %d\n", guestfs_get_recovery_proc (g));
  printf ("guestfs_get_smp: %d\n", guestfs_get_smp (g));
  p = guestfs_get_sockdir (g);
  printf ("guestfs_get_sockdir: %s\n", p ? : "(null)");
  free (p);
  p = guestfs_get_tmpdir (g);
  printf ("guestfs_get_tmpdir: %s\n", p ? : "(null)");
  free (p);
  printf ("guestfs_get_trace: %d\n", guestfs_get_trace (g));
  printf ("guestfs_get_verbose: %d\n", guestfs_get_verbose (g));

  printf ("host_cpu: %s\n", host_cpu);

  /* Launch the guest handle. */
  printf ("Launching appliance, timeout set to %d seconds.\n", timeout);
  fflush (stdout);

  alarm (timeout);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  alarm (0);

  printf ("Guest launched OK.\n");
  fflush (stdout);

  /* Create the filesystem and mount everything. */
  if (guestfs_part_disk (g, "/dev/sda", "mbr") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mkfs (g, "ext2", "/dev/sda1") == -1)
    exit (EXIT_FAILURE);

  if (guestfs_mount (g, "/dev/sda1", "/") == -1)
    exit (EXIT_FAILURE);

  /* Touch a file. */
  if (guestfs_touch (g, "/hello") == -1)
    exit (EXIT_FAILURE);

  /* Close the handle. */
  if (guestfs_shutdown (g) == -1)
    exit (EXIT_FAILURE);

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
set_qemu (guestfs_h *g, const char *path, int use_wrapper)
{
  CLEANUP_FREE char *buffer = NULL;
  struct stat statbuf;
  int fd;
  FILE *fp;

  if (getenv ("LIBGUESTFS_QEMU") != NULL ||
      getenv ("LIBGUESTFS_HV") != NULL)
    error (EXIT_FAILURE, 0,
           _("LIBGUESTFS_HV/LIBGUESTFS_QEMU environment variable is already set, so\n"
             "--qemu/--qemudir options cannot be used."));

  if (!use_wrapper) {
    if (access (path, X_OK) == -1)
      error (EXIT_FAILURE, errno,
             _("binary ‘%s’ does not exist or is not executable"), path);

    guestfs_set_hv (g, path);
    return;
  }

  /* This should be a source directory, so check it. */
  if (asprintf (&buffer, "%s/pc-bios", path) == -1)
    error (EXIT_FAILURE, errno, "asprintf");
  if (stat (buffer, &statbuf) == -1 ||
      !S_ISDIR (statbuf.st_mode))
    error (EXIT_FAILURE, errno,
           _("path does not look like a qemu source directory: %s"), path);

  /* Make a wrapper script. */
  fd = mkstemp (qemuwrapper);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "mkstemp: %s", qemuwrapper);

  fchmod (fd, 0700);

  fp = fdopen (fd, "w");
  fprintf (fp,
           "#!/bin/sh -\n"
           "host_cpu=%s\n"
           "qemudir='%s'\n"
           "case $host_cpu in\n"
           "    amd64*)\n"
           "          qemu=\"$qemudir/$host_cpu-softmmu/qemu-system-x86_64\"\n"
           "          ;;\n"
           "    arm*) qemu=\"$qemudir/$host_cpu-softmmu/qemu-system-arm\"\n"
           "          ;;\n"
           "    powerpc64|ppc64le|powerpc64le)\n"
           "          qemu=\"$qemudir/$host_cpu-softmmu/qemu-system-ppc64\"\n"
           "          ;;\n"
           "    *)    qemu=\"$qemudir/$host_cpu-softmmu/qemu-system-$host_cpu\"\n"
           "          ;;\n"
           "esac\n"
           "exec \"$qemu\" -L \"$qemudir/pc-bios\" \"$@\"\n",
           host_cpu, path);
  fclose (fp);

  guestfs_set_hv (g, qemuwrapper);
  atexit (cleanup_wrapper);
}
