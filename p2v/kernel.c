/* virt-p2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

/**
 * Kernel-driven, non-interactive configuration of virt-p2v.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <assert.h>
#include <locale.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "getprogname.h"

#include "p2v.h"

static void notify_ui_callback (int type, const char *data);
static void run_command (const char *stage, const char *command);

/* Perform conversion using the kernel method. */
void
kernel_conversion (struct config *config, char **cmdline, int cmdline_source)
{
  const char *p;

  /* Pre-conversion command. */
  p = get_cmdline_key (cmdline, "p2v.pre");
  if (p)
    run_command ("p2v.pre", p);

  /* Connect to and interrogate virt-v2v on the conversion server. */
  p = get_cmdline_key (cmdline, "p2v.skip_test_connection");
  if (!p) {
    wait_network_online (config);
    if (test_connection (config) == -1) {
      const char *err = get_ssh_error ();

      error (EXIT_FAILURE, 0,
             "error opening control connection to %s:%d: %s",
             config->remote.server, config->remote.port, err);
    }
  }

  /* Some disks must have been specified for conversion. */
  if (config->disks == NULL || guestfs_int_count_strings (config->disks) == 0)
    error (EXIT_FAILURE, 0,
           "no non-removable disks were discovered on this machine.\n"
           "virt-p2v looked in /sys/block and in p2v.disks on the kernel command line.\n"
           "This is a fatal error and virt-p2v cannot continue.");

  /* Perform the conversion in text mode. */
  if (start_conversion (config, notify_ui_callback) == -1) {
    const char *err = get_conversion_error ();

    fprintf (stderr, "%s: error during conversion: %s\n",
             getprogname (), err);

    p = get_cmdline_key (cmdline, "p2v.fail");
    if (p)
      run_command ("p2v.fail", p);

    exit (EXIT_FAILURE);
  }

  ansi_green (stdout);
  printf ("Conversion finished successfully.");
  ansi_restore (stdout);
  putchar ('\n');

  p = get_cmdline_key (cmdline, "p2v.post");
  if (!p) {
    if (geteuid () == 0 && cmdline_source == CMDLINE_SOURCE_PROC_CMDLINE)
      p = "poweroff";
  }
  if (p)
    run_command ("p2v.post", p);
}

static void
notify_ui_callback (int type, const char *data)
{
  switch (type) {
  case NOTIFY_LOG_DIR:
    ansi_magenta (stdout);
    printf ("%s: remote log directory location: ", getprogname ());
    ansi_red (stdout);
    fputs (data, stdout);
    ansi_restore (stdout);
    putchar ('\n');
    break;

  case NOTIFY_REMOTE_MESSAGE:
    printf ("%s", data);
    break;

  case NOTIFY_STATUS:
    ansi_magenta (stdout);
    printf ("%s: %s", getprogname (), data);
    ansi_restore (stdout);
    putchar ('\n');
    break;

  default:
    ansi_red (stdout);
    printf ("%s: unknown message during conversion: type=%d data=%s",
            getprogname (), type, data);
    ansi_restore (stdout);
    putchar ('\n');
  }

  fflush (stdout);
}

static void
run_command (const char *stage, const char *command)
{
  int r;

  if (STREQ (command, ""))
    return;

#if DEBUG_STDERR
  fprintf (stderr, "%s\n", command);
  fflush (stderr);
#endif

  r = system (command);
  if (r == -1)
    error (EXIT_FAILURE, errno, "system: %s", command);
  if ((WIFEXITED (r) && WEXITSTATUS (r) != 0) || !WIFEXITED (r))
    error (EXIT_FAILURE, 0,
           "%s: unexpected failure of external command", stage);
}
