/* libguestfs - the guestfsd daemon
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
#include <string.h>
#include <fcntl.h>

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static int
fwrite_cb (void *fp_ptr, const void *buf, int len)
{
  FILE *fp = *(FILE **)fp_ptr;
  return fwrite (buf, len, 1, fp) == 1 ? 0 : -1;
}

/* Has one FileIn parameter. */
int
do_tar_in (const char *dir)
{
  int err, r;
  FILE *fp;
  char *cmd;

  if (!root_mounted || dir[0] != '/') {
    cancel_receive ();
    reply_with_error ("root must be mounted and path must be absolute");
    return -1;
  }

  /* "tar -C /sysroot%s -xf -" but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -xf -", dir) == -1) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  r = receive_file (fwrite_cb, &fp);
  if (r == -1) {		/* write error */
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("write: %s", dir);
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    pclose (fp);
    /* Do NOT send any error. */
    return -1;
  }

  if (pclose (fp) != 0) {
    err = errno;
    if (r == -1)                /* if r == 0, file transfer ended already */
      cancel_receive ();
    errno = err;
    reply_with_perror ("pclose: %s", dir);
    return -1;
  }

  return 0;
}

/* Has one FileOut parameter. */
int
do_tar_out (const char *dir)
{
  int r;
  FILE *fp;
  char *cmd;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  /* "tar -C /sysroot%s -cf - ." but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -cf - .", dir) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buf, 1, sizeof buf, fp)) > 0) {
    if (send_file_write (buf, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    perror (dir);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    perror (dir);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}

/* Has one FileIn parameter. */
int
do_tgz_in (const char *dir)
{
  int err, r;
  FILE *fp;
  char *cmd;

  if (!root_mounted || dir[0] != '/') {
    cancel_receive ();
    reply_with_error ("root must be mounted and path must be absolute");
    return -1;
  }

  /* "tar -C /sysroot%s -zxf -" but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -zxf -", dir) == -1) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  r = receive_file (fwrite_cb, &fp);
  if (r == -1) {		/* write error */
    err = errno;
    cancel_receive ();
    errno = err;
    reply_with_perror ("write: %s", dir);
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    pclose (fp);
    /* Do NOT send any error. */
    return -1;
  }

  if (pclose (fp) != 0) {
    err = errno;
    if (r == -1)                /* if r == 0, file transfer ended already */
      cancel_receive ();
    errno = err;
    reply_with_perror ("pclose: %s", dir);
    return -1;
  }

  return 0;
}

/* Has one FileOut parameter. */
int
do_tgz_out (const char *dir)
{
  int r;
  FILE *fp;
  char *cmd;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  /* "tar -C /sysroot%s -zcf - ." but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -zcf - .", dir) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buf, 1, sizeof buf, fp)) > 0) {
    if (send_file_write (buf, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    perror (dir);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    perror (dir);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}
