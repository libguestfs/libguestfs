/* libguestfs - the guestfsd daemon
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

static int send_command_output (const char *cmd);

GUESTFSD_EXT_CMD(str_icat, icat);

int
do_download_inode (const mountable_t *mountable, int64_t inode)
{
  int ret;
  CLEANUP_FREE char *cmd = NULL;

  /* Inode must be greater than 0 */
  if (inode < 0) {
    reply_with_error ("inode must be >= 0");
    return -1;
  }

  /* Construct the command. */
  ret = asprintf(&cmd, "%s -r %s %" PRIi64, str_icat, mountable->device, inode);
  if (ret < 0) {
    reply_with_perror ("asprintf");
    return -1;
  }

  return send_command_output (cmd);
}

/* Run the given command, collect the output and send it to the appliance.
 * Return 0 on success, -1 on error.
 */
static int
send_command_output (const char *cmd)
{
  int ret;
  FILE *fp;
  CLEANUP_FREE char *buffer = NULL;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    return -1;
  }

  /* Send reply message before the file content. */
  reply (NULL, NULL);

  while ((ret = fread (buffer, 1, sizeof buffer, fp)) > 0) {
    ret = send_file_write (buffer, ret);
    if (ret < 0) {
      pclose (fp);
      return -1;
    }
  }

  ret = ferror (fp);
  if (ret != 0) {
    fprintf (stderr, "fread: %m");
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  ret = pclose (fp);
  if (ret != 0) {
    fprintf (stderr, "pclose: %m");
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  ret = send_file_end (0);      /* Normal end of file. */
  if (ret != 0)
    return -1;

  return 0;
}

int
optgroup_sleuthkit_available (void)
{
  return prog_exists (str_icat);
}
