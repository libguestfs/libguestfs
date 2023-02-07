/* libguestfs - the guestfsd daemon
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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-null-argument"
/* Read the error file.  Returns a string that the caller must free. */
static char *
read_error_file (char *error_file)
{
  size_t len;
  char *str;

  str = read_whole_file (error_file, &len);
  if (str == NULL) {
    str = strdup ("(no error)");
    if (str == NULL)
      error (EXIT_FAILURE, errno, "strdup"); /* XXX */
    len = strlen (str);
  }

  /* Remove trailing \n character if any. */
  if (len > 0 && str[len-1] == '\n')
    str[--len] = '\0';

  return str;                   /* caller frees */
}
#pragma GCC diagnostic pop

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  const int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* Has one FileIn parameter. */
int
do_ntfsclone_in (const char *device)
{
  int err, r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  char error_file[] = "/tmp/ntfscloneXXXXXX";
  int fd;

  fd = mkstemp (error_file);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return -1;
  }

  close (fd);

  /* Construct the command. */
  if (asprintf (&cmd, "%s -O %s --restore-image - 2> %s",
                "ntfsclone", device, error_file) == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("asprintf");
    unlink (error_file);
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("%s", cmd);
    unlink (error_file);
    return -1;
  }

  /* The semantics of fwrite are too undefined, so write to the
   * file descriptor directly instead.
   */
  fd = fileno (fp);

  r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    cancel_receive ();
    CLEANUP_FREE char *errstr = read_error_file (error_file);
    reply_with_error ("write error on device: %s: %s", device, errstr);
    unlink (error_file);
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("ntfsclone cancelled");
    pclose (fp);
    unlink (error_file);
    return -1;
  }

  if (pclose (fp) != 0) {
    CLEANUP_FREE char *errstr = read_error_file (error_file);
    reply_with_error ("ntfsclone subcommand failed on device: %s: %s",
                      device, errstr);
    unlink (error_file);
    return -1;
  }

  unlink (error_file);

  return 0;
}

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_ntfsclone_out (const char *device,
                  int metadataonly, int rescue, int ignorefscheck,
                  int preservetimestamps, int force)
{
  int r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  CLEANUP_FREE char *buf = NULL;

  buf = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Construct the ntfsclone command. */
  if (asprintf (&cmd, "ntfsclone -o - --save-image%s%s%s%s%s %s",
                (optargs_bitmask & GUESTFS_NTFSCLONE_OUT_METADATAONLY_BITMASK) && metadataonly ? " --metadata" : "",
                (optargs_bitmask & GUESTFS_NTFSCLONE_OUT_RESCUE_BITMASK) && rescue ? " --rescue" : "",
                (optargs_bitmask & GUESTFS_NTFSCLONE_OUT_IGNOREFSCHECK_BITMASK) && ignorefscheck ? " --ignore-fs-check" : "",
                (optargs_bitmask & GUESTFS_NTFSCLONE_OUT_PRESERVETIMESTAMPS_BITMASK) && preservetimestamps ? " --preserve-timestamps" : "",
                (optargs_bitmask & GUESTFS_NTFSCLONE_OUT_FORCE_BITMASK) && force ? " --force" : "",
                device) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    return -1;
  }

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buf, 1, GUESTFS_MAX_CHUNK_SIZE, fp)) > 0) {
    if (send_file_write (buf, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %s: %m\n", device);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", device);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
