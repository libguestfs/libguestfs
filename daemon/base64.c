/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010 Red Hat Inc.
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
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  const int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* Has one FileIn parameter. */
int
do_base64_in (const char *file)
{
  int err, r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  int fd;

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("malloc");
    return -1;
  }
  fprintf (fp, "%s -d -i > ", "base64");
  sysroot_shell_quote (file, fp);
  if (fclose (fp) == EOF)
    goto cmd_error;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", cmd);
    return -1;
  }

  /* The semantics of fwrite are too undefined, so write to the
   * file descriptor directly instead.
   */
  fd = fileno (fp);

  r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    cancel_receive ();
    reply_with_error ("write error on file: %s", file);
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("file upload cancelled");
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    reply_with_error ("base64 subcommand failed on file: %s", file);
    return -1;
  }

  return 0;
}

/* Has one FileOut parameter. */
int
do_base64_out (const char *file)
{
  CLEANUP_FREE char *buf = NULL;
  struct stat statbuf;
  int r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  CLEANUP_FREE char *buffer = NULL;

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  /* Check the filename exists and is not a directory (RHBZ#908322). */
  buf = sysroot_path (file);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (stat (buf, &statbuf) == -1) {
    reply_with_perror ("stat: %s", file);
    return -1;
  }

  if (S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: is a directory", file);
    return -1;
  }

  /* Construct the command. */
  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "base64 ");
  shell_quote (buf, fp);
  if (fclose (fp) == EOF)
    goto cmd_error;

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

  while ((r = fread (buffer, 1, GUESTFS_MAX_CHUNK_SIZE, fp)) > 0) {
    if (send_file_write (buffer, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %s: %m\n", file);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", file);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
