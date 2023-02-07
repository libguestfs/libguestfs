/* guestmount - mount guests using libguestfs and FUSE
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

#define FUSE_USE_VERSION 26

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <getopt.h>
#include <signal.h>
#include <limits.h>
#include <locale.h>
#include <libintl.h>

/* We're still using some of FUSE to handle command line options. */
#include <fuse.h>

#include "guestfs.h"

#include "ignore-value.h"
#include "getprogname.h"

#include "options.h"
#include "display-options.h"

static int write_pipe_fd (int fd);
static int write_pid_file (const char *pid_file, pid_t pid);

#ifndef HAVE_FUSE_OPT_ADD_OPT_ESCAPED
/* Copied from lib/fuse_opt.c and modified.
 * Copyright (C) 2001-2007  Miklos Szeredi <miklos@szeredi.hu>
 * This [function] can be distributed under the terms of the GNU LGPLv2.
 */
static void
fuse_opt_add_opt_escaped (char **opts, const char *opt)
{
  const unsigned oldlen = *opts ? strlen(*opts) : 0;
  char *d = realloc (*opts, oldlen + 1 + strlen(opt) * 2 + 1);

  if (!d)
    error (EXIT_FAILURE, errno, "realloc");

  *opts = d;
  if (oldlen) {
    d += oldlen;
    *d++ = ',';
  }

  for (; *opt; opt++) {
    if (*opt == ',' || *opt == '\\')
      *d++ = '\\';
    *d++ = *opt;
  }
  *d = '\0';
}
#endif

guestfs_h *g = NULL;
int read_only = 0;
int verbose = 0;
int inspector = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri;
int in_guestfish = 0;
int in_virt_rescue = 0;

static void __attribute__((noreturn))
fuse_help (void)
{
  static struct fuse_operations null_operations;
  const char *tmp_argv[] = { getprogname (), "--help", NULL };
  fuse_main (2, (char **) tmp_argv, &null_operations, NULL);
  exit (EXIT_SUCCESS);
}

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: FUSE module for libguestfs\n"
              "%s lets you mount a virtual machine filesystem\n"
              "Copyright (C) 2009-2023 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] mountpoint\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  --dir-cache-timeout  Set readdir cache timeout (default 5 sec)\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --echo-keys          Don't turn off echo for passphrases\n"
              "  --fd=FD              Write to pipe FD when mountpoint is ready\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  --fuse-help          Display extra FUSE options\n"
              "  -i|--inspector       Automatically mount filesystems\n"
              "  --help               Display help message and exit\n"
              "  --key selector       Specify a LUKS key\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  -m|--mount dev[:mnt[:opts[:fstype]] Mount dev on mnt (if omitted, /)\n"
              "  --no-fork            Don't daemonize\n"
              "  -n|--no-sync         Don't autosync\n"
              "  -o|--option opt      Pass extra option to FUSE\n"
              "  --pid-file filename  Write PID to filename\n"
              "  -r|--ro              Mount read-only\n"
              "  --selinux            For backwards compat only, does nothing\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -w|--rw              Mount read-write\n"
              "  -x|--trace           Trace guestfs API calls\n"
              ),
            getprogname (), getprogname (),
            getprogname ());
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

  /* The command line arguments are broadly compatible with (a subset
   * of) guestfish.  Thus we have to deal mainly with -a, -m and --ro.
   */
  static const char options[] = "a:c:d:im:no:rvVwx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "blocksize", 2, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "dir-cache-timeout", 1, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "fd", 1, 0, 0 },
    { "format", 2, 0, 0 },
    { "fuse-help", 0, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "inspector", 0, 0, 'i' },
    { "key", 1, 0, 0 },
    { "keys-from-stdin", 0, 0, 0 },
    { "live", 0, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "mount", 1, 0, 'm' },
    { "no-fork", 0, 0, 0 },
    { "no-sync", 0, 0, 'n' },
    { "option", 1, 0, 'o' },
    { "pid-file", 1, 0, 0 },
    { "ro", 0, 0, 'r' },
    { "rw", 0, 0, 'w' },
    { "selinux", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "trace", 0, 0, 'x' },
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
  int blocksize = 0;
  bool blocksize_consumed = true;
  int c, r;
  int option_index;
  struct sigaction sa;
  struct key_store *ks = NULL;

  int debug_calls = 0;
  int dir_cache_timeout = -1;
  int do_fork = 1;
  char *fuse_options = NULL;
  char *pid_file = NULL;
  int pipe_fd = -1;

  struct guestfs_mount_local_argv optargs;

  /* LC_ALL=C is required so we can parse error messages. */
  setenv ("LC_ALL", "C", 1);

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_RESTART;
  sigaction (SIGPIPE, &sa, NULL);

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
      else if (STREQ (long_options[option_index].name, "dir-cache-timeout"))
        dir_cache_timeout = atoi (optarg);
      else if (STREQ (long_options[option_index].name, "fuse-help"))
        fuse_help ();
      else if (STREQ (long_options[option_index].name, "selinux")) {
        /* nothing */
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "blocksize")) {
        OPTION_blocksize;
      } else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "live")) {
        error (EXIT_FAILURE, 0,
               _("libguestfs live support was removed in libguestfs 1.48"));
      } else if (STREQ (long_options[option_index].name, "pid-file")) {
        pid_file = optarg;
      } else if (STREQ (long_options[option_index].name, "no-fork")) {
        do_fork = 0;
      } else if (STREQ (long_options[option_index].name, "fd")) {
        if (sscanf (optarg, "%d", &pipe_fd) != 1 || pipe_fd < 0)
          error (EXIT_FAILURE, 0,
                 _("unable to parse --fd option value: %s"), optarg);
      } else if (STREQ (long_options[option_index].name, "key")) {
        OPTION_key;
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

    case 'i':
      OPTION_i;
      break;

    case 'm':
      OPTION_m;
      break;

    case 'n':
      OPTION_n;
      break;

    case 'o':
      fuse_opt_add_opt_escaped (&fuse_options, optarg);
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
      debug_calls = 1;
      do_fork = 0;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  CHECK_OPTION_format_consumed;
  CHECK_OPTION_blocksize_consumed;

  /* Check we have the right options. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }
  if (!(mps || inspector)) {
    fprintf (stderr, _("%s: error: you must specify either -i at least one -m option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  /* We'd better have a mountpoint. */
  if (optind+1 != argc)
    error (EXIT_FAILURE, 0,
           _("you must specify a mountpoint in the host filesystem"));

  /* If we're forking, we can't use the recovery process. */
  if (guestfs_set_recovery_proc (g, !do_fork) == -1)
    exit (EXIT_FAILURE);

  /* Do the guest drives and mountpoints. */
  add_drives (drvs);

  if (key_store_requires_network (ks) && guestfs_set_network (g, 1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);
  if (inspector)
    inspect_mount ();
  mount_mps (mps);

  free_drives (drvs);
  free_mps (mps);
  free_key_store (ks);

  /* FUSE example does this, not clear if it's necessary, but ... */
  if (guestfs_umask (g, 0) == -1)
    exit (EXIT_FAILURE);

  optargs.bitmask = 0;
  if (read_only) {
    optargs.bitmask |= GUESTFS_MOUNT_LOCAL_READONLY_BITMASK;
    optargs.readonly = 1;
  }
  if (debug_calls) {
    optargs.bitmask |= GUESTFS_MOUNT_LOCAL_DEBUGCALLS_BITMASK;
    optargs.debugcalls = 1;
  }
  if (dir_cache_timeout > 0) {
    optargs.bitmask |= GUESTFS_MOUNT_LOCAL_CACHETIMEOUT_BITMASK;
    optargs.cachetimeout = dir_cache_timeout;
  }
  if (fuse_options != NULL) {
    optargs.bitmask |= GUESTFS_MOUNT_LOCAL_OPTIONS_BITMASK;
    optargs.options = fuse_options;
  }

  if (guestfs_mount_local_argv (g, argv[optind], &optargs) == -1)
    exit (EXIT_FAILURE);

  /* Daemonize. */
  if (do_fork) {
    pid_t pid;
    int fd;

    pid = fork ();
    if (pid == -1)
      error (EXIT_FAILURE, errno, "fork");

    if (pid != 0) {             /* parent */
      if (write_pid_file (pid_file, pid) == -1)
        _exit (EXIT_FAILURE);
      if (write_pipe_fd (pipe_fd) == -1)
        _exit (EXIT_FAILURE);

      _exit (EXIT_SUCCESS);
    }

    /* Emulate what old fuse_daemonize used to do. */
    if (setsid () == -1)
      error (EXIT_FAILURE, errno, "setsid");

    ignore_value (chdir ("/"));

    fd = open ("/dev/null", O_RDWR);
    if (fd >= 0) {
      dup2 (fd, 0);
      dup2 (fd, 1);
      dup2 (fd, 2);
      if (fd > 2)
        close (fd);
    }
  }
  else {
    /* not forking, write PID file and pipe FD anyway */
    if (write_pid_file (pid_file, getpid ()) == -1)
      exit (EXIT_FAILURE);
    if (write_pipe_fd (pipe_fd) == -1)
      exit (EXIT_FAILURE);
  }

  /* At the last minute, remove the libguestfs error handler.  In code
   * above this point, the default error handler has been used which
   * sends all errors to stderr.  From now on, the FUSE code will
   * convert errors into error codes (errnos) when appropriate.
   */
  guestfs_push_error_handler (g, NULL, NULL);

  /* Main loop. */
  r = guestfs_mount_local_run (g);

  guestfs_pop_error_handler (g);

  /* Cleanup. */
  if (guestfs_shutdown (g) == -1)
    r = -1;
  guestfs_close (g);

  /* Don't delete PID file until the cleanup has been completed. */
  if (pid_file)
    unlink (pid_file);

  exit (r == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

static int
write_pid_file (const char *pid_file, pid_t pid)
{
  FILE *fp;

  if (pid_file == NULL)
    return 0;

  fp = fopen (pid_file, "w");
  if (fp == NULL) {
  error:
    perror (pid_file);
    return -1;
  }

  if (fprintf (fp, "%d\n", pid) == -1) {
    fclose (fp);
    goto error;
  }

  if (fclose (fp) == -1)
    goto error;

  return 0;
}

static int
write_pipe_fd (int fd)
{
  char c = 0;

  if (fd < 0)
    return 0;

  if (write (fd, &c, 1) != 1) {
    perror ("write (--fd option)");
    return -1;
  }

  if (close (fd) == -1) {
    perror ("close (--fd option)");
    return -1;
  }

  return 0;
}
