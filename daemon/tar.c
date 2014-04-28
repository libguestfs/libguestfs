/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2014 Red Hat Inc.
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

#include "read-file.h"

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

GUESTFSD_EXT_CMD(str_tar, tar);

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
  int fd, r, err, saved_errno;

  /* Create a randomly named file. */
  snprintf (buf, len, "%s%s/XXXXXXXX.XXX", sysroot, dir);
  if (random_name (buf) == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("random_name");
    return -1;
  }

  /* Maybe 'dir' is not a directory or filesystem not writable? */
  fd = open (buf, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
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
    err = errno;
    r = cancel_receive ();
    errno = err;
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
/* Takes optional arguments, consult optargs_bitmask. */
int
do_tar_in (const char *dir, const char *compress)
{
  const char *filter;
  int err, r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  char error_file[] = "/tmp/tarXXXXXX";
  int fd, chown_supported;

  chown_supported = is_chown_supported (dir);
  if (chown_supported == -1)
    return -1;

  if ((optargs_bitmask & GUESTFS_TAR_IN_COMPRESS_BITMASK)) {
    if (STREQ (compress, "compress"))
      filter = " --compress";
    else if (STREQ (compress, "gzip"))
      filter = " --gzip";
    else if (STREQ (compress, "bzip2"))
      filter = " --bzip2";
    else if (STREQ (compress, "xz"))
      filter = " --xz";
    else if (STREQ (compress, "lzop"))
      filter = " --lzop";
    else {
      reply_with_error ("unknown compression type: %s", compress);
      return -1;
    }
  } else
    filter = "";

  fd = mkstemp (error_file);
  if (fd == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("mkstemp");
    return -1;
  }

  close (fd);

  /* "tar -C /sysroot%s -xf -" but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "%s -C %R%s -xf - %s2> %s",
                       str_tar,
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
    reply_with_error ("write error on directory: %s: %s", dir, errstr);
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
    CLEANUP_FREE char *errstr = read_error_file (error_file);
    reply_with_error ("tar subcommand failed on directory: %s: %s",
                      dir, errstr);
    unlink (error_file);
    return -1;
  }

  unlink (error_file);

  return 0;
}

/* Has one FileIn parameter. */
int
do_tgz_in (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_IN_COMPRESS_BITMASK;
  return do_tar_in (dir, "gzip");
}

/* Has one FileIn parameter. */
int
do_txz_in (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_IN_COMPRESS_BITMASK;
  return do_tar_in (dir, "xz");
}

/* Turn list 'excludes' into a temporary file, and return a string
 * containing the temporary file name.  Caller must unlink the file
 * and free the string.
 */
static char *
make_exclude_from_file (char *const *excludes)
{
  size_t i;
  int fd;
  char template[] = "/tmp/excludesXXXXXX";
  char *ret;

  fd = mkstemp (template);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return NULL;
  }

  for (i = 0; excludes[i] != NULL; ++i) {
    if (strchr (excludes[i], '\n')) {
      reply_with_error ("tar-out: excludes file patterns cannot contain \\n character");
      goto error;
    }

    if (xwrite (fd, excludes[i], strlen (excludes[i])) == -1 ||
        xwrite (fd, "\n", 1) == -1) {
      reply_with_perror ("write");
      goto error;
    }

    if (verbose)
      fprintf (stderr, "tar-out: adding excludes pattern '%s'\n", excludes[i]);
  }

  if (close (fd) == -1) {
    reply_with_perror ("close");
    fd = -1;
    goto error;
  }
  fd = -1;

  ret = strdup (template);
  if (ret == NULL) {
    reply_with_perror ("strdup");
    goto error;
  }

  return ret;

 error:
  if (fd >= 0)
    close (fd);
  unlink (template);
  return NULL;
}

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_tar_out (const char *dir, const char *compress, int numericowner,
            char *const *excludes)
{
  CLEANUP_FREE char *buf = NULL;
  struct stat statbuf;
  const char *filter;
  int r;
  FILE *fp;
  CLEANUP_UNLINK_FREE char *exclude_from_file = NULL;
  CLEANUP_FREE char *cmd = NULL;
  char buffer[GUESTFS_MAX_CHUNK_SIZE];

  if ((optargs_bitmask & GUESTFS_TAR_OUT_COMPRESS_BITMASK)) {
    if (STREQ (compress, "compress"))
      filter = " --compress";
    else if (STREQ (compress, "gzip"))
      filter = " --gzip";
    else if (STREQ (compress, "bzip2"))
      filter = " --bzip2";
    else if (STREQ (compress, "xz"))
      filter = " --xz";
    else if (STREQ (compress, "lzop"))
      filter = " --lzop";
    else {
      reply_with_error ("unknown compression type: %s", compress);
      return -1;
    }
  } else
    filter = "";

  if (!(optargs_bitmask & GUESTFS_TAR_OUT_NUMERICOWNER_BITMASK))
    numericowner = 0;

  if ((optargs_bitmask & GUESTFS_TAR_OUT_EXCLUDES_BITMASK)) {
    exclude_from_file = make_exclude_from_file (excludes);
    if (!exclude_from_file)
      return -1;
  }

  /* Check the filename exists and is a directory (RHBZ#908322). */
  buf = sysroot_path (dir);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (stat (buf, &statbuf) == -1) {
    reply_with_perror ("stat: %s", dir);
    return -1;
  }

  if (! S_ISDIR (statbuf.st_mode)) {
    reply_with_error ("%s: not a directory", dir);
    return -1;
  }

  /* "tar -C /sysroot%s -cf - ." but we have to quote the dir. */
  if (asprintf_nowarn (&cmd, "%s -C %Q%s%s%s%s -cf - .",
                       str_tar,
                       buf, filter,
                       numericowner ? " --numeric-owner" : "",
                       exclude_from_file ? " -X " : "",
                       exclude_from_file ? exclude_from_file : "") == -1) {
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

  while ((r = fread (buffer, 1, sizeof buffer, fp)) > 0) {
    if (send_file_write (buffer, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    fprintf (stderr, "fread: %s: %m\n", dir);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    fprintf (stderr, "pclose: %s: %m\n", dir);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}

/* Has one FileOut parameter. */
int
do_tgz_out (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_OUT_COMPRESS_BITMASK;
  return do_tar_out (dir, "gzip", 0, NULL);
}

/* Has one FileOut parameter. */
int
do_txz_out (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_OUT_COMPRESS_BITMASK;
  return do_tar_out (dir, "xz", 0, NULL);
}
