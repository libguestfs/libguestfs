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

#include "read-file.h"

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* Redirect errors from the tar command to the error file, then
 * provide functions for reading it in.  We overwrite the file each
 * time, and since it's small and stored on the appliance we don't
 * bother to delete it.
 */
static const char *error_file = "/tmp/error";

static char *
read_error_file (void)
{
  size_t len;
  char *str = read_file (error_file, &len);
  if (str == NULL) {
    str = strdup ("(no error)");
    if (str == NULL) {
      perror ("strdup");
      exit (EXIT_FAILURE);
    }
    len = strlen (str);
  }

  /* Remove trailing \n character if any. */
  if (len > 0 && str[len-1] == '\n')
    str[--len] = '\0';

  return str;                   /* caller frees */
}

static int
write_cb (void *fd_ptr, const void *buf, size_t len)
{
  int fd = *(int *)fd_ptr;
  return xwrite (fd, buf, len);
}

/* Has one FileIn parameter. */
static int
do_tXz_in (const char *dir, const char *filter)
{
  int err, r;
  FILE *fp;
  char *cmd;

  /* "tar -C /sysroot%s -xf -" but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -%sxf - 2> %s",
                       dir, filter, error_file) == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    if (r != -2) reply_with_perror ("asprintf");
    return -1;
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "w");
  if (fp == NULL) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    if (r != -2) reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  /* The semantics of fwrite are too undefined, so write to the
   * file descriptor directly instead.
   */
  int fd = fileno (fp);

  r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    if (cancel_receive () != -2) {
      char *errstr = read_error_file ();
      reply_with_error ("write error on directory: %s: %s", dir, errstr);
      free (errstr);
    }
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    pclose (fp);
    /* Do NOT send any error. */
    return -1;
  }

  if (pclose (fp) != 0) {
    if (r == -1)                /* if r == 0, file transfer ended already */
      r = cancel_receive ();
    if (r != -2) {
      char *errstr = read_error_file ();
      reply_with_error ("tar subcommand failed on directory: %s: %s",
                        dir, errstr);
      free (errstr);
    }
    return -1;
  }

  return 0;
}

/* Has one FileIn parameter. */
int
do_tar_in (const char *dir)
{
  return do_tXz_in (dir, "");
}

/* Has one FileIn parameter. */
int
do_tgz_in (const char *dir)
{
  return do_tXz_in (dir, "z");
}

/* Has one FileIn parameter. */
int
do_txz_in (const char *dir)
{
  return do_tXz_in (dir, "J");
}

/* Has one FileOut parameter. */
static int
do_tXz_out (const char *dir, const char *filter)
{
  int r;
  FILE *fp;
  char *cmd;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  /* "tar -C /sysroot%s -zcf - ." but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -%scf - .", dir, filter) == -1) {
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

/* Has one FileOut parameter. */
int
do_tar_out (const char *dir)
{
  return do_tXz_out (dir, "");
}

/* Has one FileOut parameter. */
int
do_tgz_out (const char *dir)
{
  return do_tXz_out (dir, "z");
}

/* Has one FileOut parameter. */
int
do_txz_out (const char *dir)
{
  return do_tXz_out (dir, "J");
}
