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
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <sys/types.h>
#include <sys/stat.h>

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
  CLEANUP_FREE char *buf = NULL;
  int fd, r, err, saved_errno;

  /* Create a randomly named file. */
  if (asprintf (&buf, "%s%s/XXXXXXXX.XXX", sysroot, dir) == -1) {
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("asprintf");
    return -1;
  }
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

// https://gcc.gnu.org/bugzilla/show_bug.cgi?id=99196
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
/* Takes optional arguments, consult optargs_bitmask. */
int
do_tar_in (const char *dir, const char *compress, int xattrs, int selinux, int acls)
{
  const char *filter;
  int err, r;
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
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

  if (!(optargs_bitmask & GUESTFS_TAR_IN_XATTRS_BITMASK))
    xattrs = 0;

  if (!(optargs_bitmask & GUESTFS_TAR_IN_SELINUX_BITMASK))
    selinux = 0;

  if (!(optargs_bitmask & GUESTFS_TAR_IN_ACLS_BITMASK))
    acls = 0;

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
  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    err = errno;
    r = cancel_receive ();
    errno = err;
    reply_with_perror ("open_memstream");
    unlink (error_file);
    return -1;
  }
  fprintf (fp, "tar -C ");
  sysroot_shell_quote (dir, fp);
  fprintf (fp, "%s -xf - %s%s%s%s2> %s",
           filter,
           chown_supported ? "" : "--no-same-owner ",
           /* --xattrs-include=* is a workaround for a bug
            * in tar, and hopefully won't be required
            * forever.  See RHBZ#771927.
            */
           xattrs ? "--xattrs --xattrs-include='*' " : "",
           selinux ? "--selinux " : "",
           acls ? "--acls " : "",
           error_file);
  if (fclose (fp) == EOF)
    goto cmd_error;

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
  return do_tar_in (dir, "gzip", 0, 0, 0);
}

/* Has one FileIn parameter. */
int
do_txz_in (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_IN_COMPRESS_BITMASK;
  return do_tar_in (dir, "xz", 0, 0, 0);
}

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_tar_out (const char *dir, const char *compress, int numericowner,
            char *const *excludes, int xattrs, int selinux, int acls)
{
  CLEANUP_FREE char *buf = NULL;
  struct stat statbuf;
  const char *filter;
  int r;
  FILE *fp;
  CLEANUP_UNLINK_FREE char *exclude_from_file = NULL;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  CLEANUP_FREE char *buffer = NULL;

  buffer = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (buffer == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

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
    exclude_from_file = make_exclude_from_file ("tar-out", excludes);
    if (!exclude_from_file)
      return -1;
  }

  if (!(optargs_bitmask & GUESTFS_TAR_OUT_XATTRS_BITMASK))
    xattrs = 0;

  if (!(optargs_bitmask & GUESTFS_TAR_OUT_SELINUX_BITMASK))
    selinux = 0;

  if (!(optargs_bitmask & GUESTFS_TAR_OUT_ACLS_BITMASK))
    acls = 0;

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
  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return -1;
  }
  fprintf (fp, "tar -C ");
  shell_quote (buf, fp);
  fprintf (fp, "%s%s%s%s%s%s%s -cf - .",
           filter,
           numericowner ? " --numeric-owner" : "",
           exclude_from_file ? " -X " : "",
           exclude_from_file ? exclude_from_file : "",
           xattrs ? " --xattrs" : "",
           selinux ? " --selinux" : "",
           acls ? " --acls" : "");
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
  return do_tar_out (dir, "gzip", 0, NULL, 0, 0, 0);
}

/* Has one FileOut parameter. */
int
do_txz_out (const char *dir)
{
  optargs_bitmask = GUESTFS_TAR_OUT_COMPRESS_BITMASK;
  return do_tar_out (dir, "xz", 0, NULL, 0, 0, 0);
}
