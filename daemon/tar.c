/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#include "read-file.h"

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_xz_available (void)
{
  return prog_exists ("xz");
}

/* Detect if chown(2) is supported on the target directory. */
static int
is_chown_supported (const char *dir)
{
  size_t len = sysroot_len + strlen (dir) + 64;
  char buf[len];
  int fd, r, saved_errno;

  /* Create a randomly named file. */
  snprintf (buf, len, "%s%s/XXXXXXXX.XXX", sysroot, dir);
  if (random_name (buf) == -1) {
    reply_with_perror ("random_name");
    return -1;
  }

  /* Maybe 'dir' is not a directory or filesystem not writable? */
  fd = open (buf, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    reply_with_perror ("%s", dir);
    return -1;
  }

  /* This is the test. */
  r = fchown (fd, 1000, 1000);
  saved_errno = errno;

  /* Make sure the test file is removed. */
  close (fd);
  unlink (buf);

  if (r == -1 && saved_errno == EPERM) {
    /* This means chown is not supported by the filesystem. */
    return 0;
  }

  if (r == -1) {
    /* Some other error? */
    reply_with_perror_errno (saved_errno, "unexpected error in fchown");
    return -1;
  }

  /* Else chown is supported. */
  return 1;
}

/* Read the error file.  Returns a string that the caller must free. */
static char *
read_error_file (char *error_file)
{
  size_t len;
  char *str;

  str = read_file (error_file, &len);
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
  char error_file[] = "/tmp/tarXXXXXX";
  int fd, chown_supported;

  chown_supported = is_chown_supported (dir);
  if (chown_supported == -1)
    return -1;

  fd = mkstemp (error_file);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return -1;
  }

  close (fd);

  /* "tar -C /sysroot%s -xf -" but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "tar -C %R -%sxf - %s2> %s",
                       dir, filter,
                       chown_supported ? "" : "--no-same-owner ",
                       error_file) == -1) {
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
    free (cmd);
    return -1;
  }
  free (cmd);

  /* The semantics of fwrite are too undefined, so write to the
   * file descriptor directly instead.
   */
  fd = fileno (fp);

  r = receive_file (write_cb, &fd);
  if (r == -1) {		/* write error */
    cancel_receive ();
    char *errstr = read_error_file (error_file);
    reply_with_error ("write error on directory: %s: %s", dir, errstr);
    free (errstr);
    unlink (error_file);
    pclose (fp);
    return -1;
  }
  if (r == -2) {		/* cancellation from library */
    /* This error is ignored by the library since it initiated the
     * cancel.  Nevertheless we must send an error reply here.
     */
    reply_with_error ("file upload cancelled");
    pclose (fp);
    unlink (error_file);
    return -1;
  }

  if (pclose (fp) != 0) {
    char *errstr = read_error_file (error_file);
    reply_with_error ("tar subcommand failed on directory: %s: %s",
                      dir, errstr);
    free (errstr);
    unlink (error_file);
    return -1;
  }

  unlink (error_file);

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
