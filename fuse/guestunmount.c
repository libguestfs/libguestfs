/* guestunmount
 * Copyright (C) 2013 Red Hat Inc.
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
#include <stdbool.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <libintl.h>
#include <poll.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-utils.h"

#include "ignore-value.h"
#include "getprogname.h"

#include "display-options.h"

static int do_fusermount (const char *mountpoint, char **error_rtn);
static void do_fuser (const char *mountpoint);

static bool quiet = false;
static size_t retries = 5;
static bool verbose = false;

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: clean up a mounted filesystem\n"
              "Copyright (C) 2013 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--fd=FD] mountpoint\n"
              "Options:\n"
              "  --fd=FD              Pipe file descriptor to monitor\n"
              "  --help               Display help message and exit\n"
              "  -q|--quiet           Don't print fusermount errors\n"
              "  --no-retry           Don't retry fusermount\n"
              "  --retry=N            Retry fusermount N times (default: 5)\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              ),
            getprogname (), getprogname ());
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char options[] = "qvV";
  static const struct option long_options[] = {
    { "fd", 1, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "quiet", 0, 0, 'q' },
    { "long-options", 0, 0, 0 },
    { "no-retry", 0, 0, 0 },
    { "retry", 1, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };

  int c, fd = -1;
  int option_index;
  const char *mountpoint;
  struct sigaction sa;
  struct pollfd pollfd;
  char *error_str = NULL;
  size_t i;

  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "fd")) {
        if (sscanf (optarg, "%d", &fd) != 1 || fd < 0)
          error (EXIT_FAILURE, 0, _("cannot parse fd option ‘%s’"), optarg);
      } else if (STREQ (long_options[option_index].name, "no-retry")) {
        retries = 0;
      } else if (STREQ (long_options[option_index].name, "retry")) {
        if (sscanf (optarg, "%zu", &retries) != 1 || retries >= 64)
          error (EXIT_FAILURE, 0,
                 _("cannot parse retries option or value is too large ‘%s’"),
                 optarg);
      } else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
      break;

    case 'q':
      quiet = true;
      break;

    case 'v':
      verbose = true;
      break;

    case 'V':
      printf ("guestunmount %s %s\n", PACKAGE_NAME, PACKAGE_VERSION);
      exit (EXIT_SUCCESS);

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  /* We'd better have a mountpoint. */
  if (optind+1 != argc)
    error (EXIT_FAILURE, 0,
           _("you must specify a mountpoint in the host filesystem\n"));

  mountpoint = argv[optind];

  /* Monitor the pipe until we get POLLHUP. */
  if (fd >= 0) {
    ignore_value (chdir ("/"));

    /* Ignore keyboard signals. */
    memset (&sa, 0, sizeof sa);
    sa.sa_handler = SIG_IGN;
    sa.sa_flags = SA_RESTART;
    sigaction (SIGINT, &sa, NULL);
    sigaction (SIGQUIT, &sa, NULL);

    while (1) {
      pollfd.fd = fd;
      pollfd.events = POLLIN;
      pollfd.revents = 0;
      if (poll (&pollfd, 1, -1) == -1) {
        if (errno != EAGAIN && errno != EINTR)
          error (EXIT_FAILURE, errno, "poll");
      }
      else {
        if ((pollfd.revents & POLLHUP) != 0)
          break;
      }
    }
  }

  /* Unmount the filesystem.  We may have to try a few times. */
  for (i = 0; i <= retries; ++i) {
    if (i > 0)
      sleep (1 << (i-1));

    free (error_str);
    error_str = NULL;

    if (do_fusermount (mountpoint, &error_str) == 0)
      goto done;

    /* Did fusermount fail because the mountpoint is not mounted? */
    if (error_str &&
        strstr (error_str, "fusermount: entry for") != NULL) {
      goto not_mounted;
    }
  }

  /* fusermount failed after N retries */
  if (!quiet) {
    fprintf (stderr, _("%s: failed to unmount %s: %s\n"),
             getprogname (), mountpoint, error_str);
    do_fuser (mountpoint);
  }
  free (error_str);

  exit (2);

  /* not mounted */
 not_mounted:
  if (!quiet)
    fprintf (stderr, _("%s: %s is not mounted: %s\n"),
             getprogname (), mountpoint, error_str);

  free (error_str);

  exit (3);

  /* success */
 done:
  exit (EXIT_SUCCESS);
}

static int
do_fusermount (const char *mountpoint, char **error_rtn)
{
  int fd[2];
  pid_t pid;
  int r;
  char *buf = NULL;
  size_t allocsize = 0, len = 0;

  if (pipe (fd) == -1)
    error (EXIT_FAILURE, errno, "pipe");

  if (verbose)
    fprintf (stderr, "%s: running: fusermount -u %s\n",
             getprogname (), mountpoint);

  pid = fork ();
  if (pid == -1)
    error (EXIT_FAILURE, errno, "fork");

  if (pid == 0) {               /* Child - run fusermount. */
    close (fd[0]);
    dup2 (fd[1], 1);
    dup2 (fd[1], 2);
    close (fd[1]);

    /* We have to parse error messages from fusermount, so ... */
    setenv ("LC_ALL", "C", 1);

#ifdef __linux__
    execlp ("fusermount", "fusermount", "-u", mountpoint, NULL);
#else
    /* use umount where fusermount is not available */
    execlp ("umount", "umount", mountpoint, NULL);
#endif
    perror ("exec");
    _exit (EXIT_FAILURE);
  }

  /* Parent - read from the pipe any errors etc. */
  close (fd[1]);

  while (1) {
    if (len >= allocsize) {
      allocsize += 256;
      buf = realloc (buf, allocsize);
      if (buf == NULL)
        error (EXIT_FAILURE, errno, "realloc");
    }

    /* Leave space in the buffer for a terminating \0 character. */
    r = read (fd[0], &buf[len], allocsize - len - 1);
    if (r == -1)
      error (EXIT_FAILURE, errno, "read");

    if (r == 0)
      break;

    len += r;
  }

  if (close (fd[0]) == -1)
    error (EXIT_FAILURE, errno, "close");

  if (buf) {
    /* Remove any trailing \n from the error message. */
    while (len > 0 && buf[len-1] == '\n') {
      buf[len-1] = '\0';
      len--;
    }

    /* Make sure the error message is \0 terminated. */
    if (len < allocsize)
      buf[len] = '\0';
  }

  if (waitpid (pid, &r, 0) == -1)
    error (EXIT_FAILURE, errno, "waitpid");

  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    if (verbose)
      fprintf (stderr, "%s\n", buf);

    *error_rtn = buf;
    return 1;                   /* fusermount or exec failed */
  }

  if (verbose)
    fprintf (stderr, "%s: fusermount successful\n",
             getprogname ());

  free (buf);
  return 0;                     /* fusermount successful */
}

/* Try running 'fuser' on the mountpoint.  This is for information
 * only so don't fail if we can't run it.
 */
static void
do_fuser (const char *mountpoint)
{
  pid_t pid;

  pid = fork ();
  if (pid == -1)
    error (EXIT_FAILURE, errno, "fork");

  if (pid == 0) {               /* Child - run fuser. */
#ifdef __linux__
    execlp (FUSER, "fuser", "-v", "-m", mountpoint, NULL);
#else
    execlp (FUSER, "fuser", "-c", mountpoint, NULL);
#endif
    _exit (EXIT_FAILURE);
  }

  waitpid (pid, NULL, 0);
}
