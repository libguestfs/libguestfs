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
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
do_touch (const char *path)
{
  int fd;
  int r;
  struct stat buf;

  /* RHBZ#582484: Restrict touch to regular files.  It's also OK
   * here if the file does not exist, since we will create it.
   *
   * XXX Coverity flags this as a time-of-check to time-of-use race
   * condition, particularly in the libguestfs live case.  Not clear
   * how to fix this yet, since unconditionally opening the file can
   * cause a hang, so you have to somehow check it first before you
   * open it.
   */
  CHROOT_IN;
  r = lstat (path, &buf);
  CHROOT_OUT;

  if (r == -1) {
    if (errno != ENOENT) {
      reply_with_perror ("lstat: %s", path);
      return -1;
    }
  } else {
    if (! S_ISREG (buf.st_mode)) {
      reply_with_error ("%s: touch can only be used on a regular files", path);
      return -1;
    }
  }

  CHROOT_IN;
  fd = open (path, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  r = futimens (fd, NULL);
  if (r == -1) {
    reply_with_perror ("futimens: %s", path);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

int
do_rm (const char *path)
{
  int r;

  CHROOT_IN;
  r = unlink (path);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

int
do_rm_f (const char *path)
{
  int r;

  CHROOT_IN;
  r = unlink (path);
  CHROOT_OUT;

  /* Ignore ENOENT. */
  if (r == -1 && errno != ENOENT) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return 0;
}

int
do_chmod (int mode, const char *path)
{
  int r;

  if (mode < 0) {
    reply_with_error ("%s: mode is negative", path);
    return -1;
  }

  CHROOT_IN;
  r = chmod (path, mode);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s: 0%o", path, (unsigned) mode);
    return -1;
  }

  return 0;
}

int
do_chown (int owner, int group, const char *path)
{
  int r;

  CHROOT_IN;
  r = chown (path, owner, group);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s: %d.%d", path, owner, group);
    return -1;
  }

  return 0;
}

int
do_lchown (int owner, int group, const char *path)
{
  int r;

  CHROOT_IN;
  r = lchown (path, owner, group);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s: %d.%d", path, owner, group);
    return -1;
  }

  return 0;
}

int
do_write_file (const char *path, const char *content, int size)
{
  int fd;

  /* This call is deprecated, and it has a broken interface.  New code
   * should use the 'guestfs_write' call instead.  Because we used an
   * XDR string type, 'content' cannot contain ASCII NUL and 'size'
   * must never be longer than the string.  We must check this to
   * ensure random stuff from XDR or daemon memory isn't written to
   * the file (RHBZ#597135).
   */
  if (size < 0) {
    reply_with_error ("size cannot be negative");
    return -1;
  }

  /* Note content_len must be small because of the limits on protocol
   * message size.
   */
  const int content_len = (int) strlen (content);

  if (size == 0)
    size = content_len;
  else if (size > content_len) {
    reply_with_error ("size parameter is larger than string content");
    return -1;
  }

  CHROOT_IN;
  fd = open (path, O_WRONLY|O_TRUNC|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  if (xwrite (fd, content, size) == -1) {
    reply_with_perror ("write");
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

int
do_internal_write (const char *path, const char *content, size_t size)
{
  int fd;

  CHROOT_IN;
  fd = open (path, O_WRONLY|O_TRUNC|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  if (xwrite (fd, content, size) == -1) {
    reply_with_perror ("write");
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

int
do_internal_write_append (const char *path, const char *content, size_t size)
{
  int fd;

  CHROOT_IN;
  fd = open (path, O_WRONLY|O_APPEND|O_CREAT|O_NOCTTY|O_CLOEXEC, 0666);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  if (xwrite (fd, content, size) == -1) {
    reply_with_perror ("write");
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", path);
    return -1;
  }

  return 0;
}

static char *
pread_fd (int fd, int count, int64_t offset, size_t *size_r,
          const char *display_path)
{
  ssize_t r;
  char *buf;

  if (count < 0) {
    reply_with_error ("count is negative");
    close (fd);
    return NULL;
  }

  if (offset < 0) {
    reply_with_error ("offset is negative");
    close (fd);
    return NULL;
  }

  /* The actual limit on messages is smaller than this.  This check
   * just limits the amount of memory we'll try and allocate in the
   * function.  If the message is larger than the real limit, that
   * will be caught later when we try to serialize the message.
   */
  if (count >= GUESTFS_MESSAGE_MAX) {
    reply_with_error ("%s: count is too large for the protocol, use smaller reads", display_path);
    close (fd);
    return NULL;
  }

  buf = malloc (count);
  if (buf == NULL) {
    reply_with_perror ("malloc");
    close (fd);
    return NULL;
  }

  r = pread (fd, buf, count, offset);
  if (r == -1) {
    reply_with_perror ("pread: %s", display_path);
    close (fd);
    free (buf);
    return NULL;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", display_path);
    free (buf);
    return NULL;
  }

  /* Mustn't touch *size_r until we are sure that we won't return any
   * error (RHBZ#589039).
   */
  *size_r = r;
  return buf;
}

char *
do_pread (const char *path, int count, int64_t offset, size_t *size_r)
{
  int fd;

  CHROOT_IN;
  fd = open (path, O_RDONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return NULL;
  }

  return pread_fd (fd, count, offset, size_r, path);
}

char *
do_pread_device (const char *device, int count, int64_t offset, size_t *size_r)
{
  int fd = open (device, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return NULL;
  }

  return pread_fd (fd, count, offset, size_r, device);
}

static int
pwrite_fd (int fd, const char *content, size_t size, int64_t offset,
           const char *display_path, int settle)
{
  ssize_t r;

  r = pwrite (fd, content, size, offset);
  if (r == -1) {
    reply_with_perror ("pwrite: %s", display_path);
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", display_path);
    return -1;
  }

  /* When you call close on any block device, udev kicks off a rule
   * which runs blkid to reexamine the device.  We need to wait for
   * this rule to finish running since it holds the device open and
   * can cause other operations to fail, notably BLKRRPART.  'settle'
   * flag is only set on block devices.
   *
   * XXX We should be smarter about when we do this or should get rid
   * of the udev rules since we don't use blkid in cached mode.
   */
  if (settle)
    udev_settle ();

  return r;
}

int
do_pwrite (const char *path, const char *content, size_t size, int64_t offset)
{
  int fd;

  if (offset < 0) {
    reply_with_error ("offset is negative");
    return -1;
  }

  CHROOT_IN;
  fd = open (path, O_WRONLY|O_CLOEXEC);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }

  return pwrite_fd (fd, content, size, offset, path, 0);
}

int
do_pwrite_device (const char *device, const char *content, size_t size,
                  int64_t offset)
{
  if (offset < 0) {
    reply_with_error ("offset is negative");
    return -1;
  }

  int fd = open (device, O_WRONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", device);
    return -1;
  }

  return pwrite_fd (fd, content, size, offset, device, 1);
}

/* zcat | file */
char *
do_zfile (const char *method, const char *path)
{
  size_t len;
  const char *zcat;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  FILE *fp;
  char line[256];

  if (STREQ (method, "gzip") || STREQ (method, "compress"))
    zcat = "zcat";
  else if (STREQ (method, "bzip2"))
    zcat = "bzcat";
  else {
    reply_with_error ("unknown method");
    return NULL;
  }

  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return NULL;
  }
  fprintf (fp, "%s ", zcat);
  sysroot_shell_quote (path, fp);
  fprintf (fp, " | file -bsL -");
  if (fclose (fp) == EOF)
    goto cmd_error;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    return NULL;
  }

  if (fgets (line, sizeof line, fp) == NULL) {
    reply_with_perror ("fgets");
    pclose (fp);
    return NULL;
  }

  if (pclose (fp) == -1) {
    reply_with_perror ("pclose");
    return NULL;
  }

  len = strlen (line);
  if (len > 0 && line[len-1] == '\n')
    line[len-1] = '\0';

  return strdup (line);
}

int64_t
do_filesize (const char *path)
{
  int r;
  struct stat buf;

  CHROOT_IN;
  r = stat (path, &buf);        /* follow symlinks */
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("%s", path);
    return -1;
  }

  return buf.st_size;
}

int
do_copy_attributes (const char *src, const char *dest, int all, int mode, int xattributes, int ownership)
{
  int r;
  struct stat srcstat, deststat;

  static const unsigned int file_mask = 07777;

  /* If it was specified to copy everything, manually enable all the flags
   * not manually specified to avoid checking for flag || all everytime.
   */
  if (all) {
    if (!(optargs_bitmask & GUESTFS_COPY_ATTRIBUTES_MODE_BITMASK))
      mode = 1;
    if (!(optargs_bitmask & GUESTFS_COPY_ATTRIBUTES_XATTRIBUTES_BITMASK))
      xattributes = 1;
    if (!(optargs_bitmask & GUESTFS_COPY_ATTRIBUTES_OWNERSHIP_BITMASK))
      ownership = 1;
  }

  CHROOT_IN;
  r = stat (src, &srcstat);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("stat: %s", src);
    return -1;
  }

  CHROOT_IN;
  r = stat (dest, &deststat);
  CHROOT_OUT;

  if (r == -1) {
    reply_with_perror ("stat: %s", dest);
    return -1;
  }

  if (mode &&
      ((srcstat.st_mode & file_mask) != (deststat.st_mode & file_mask))) {
    CHROOT_IN;
    r = chmod (dest, (srcstat.st_mode & file_mask));
    CHROOT_OUT;

    if (r == -1) {
      reply_with_perror ("chmod: %s", dest);
      return -1;
    }
  }

  if (ownership &&
      (srcstat.st_uid != deststat.st_uid || srcstat.st_gid != deststat.st_gid)) {
    CHROOT_IN;
    r = chown (dest, srcstat.st_uid, srcstat.st_gid);
    CHROOT_OUT;

    if (r == -1) {
      reply_with_perror ("chown: %s", dest);
      return -1;
    }
  }

  if (xattributes && optgroup_linuxxattrs_available ()) {
    if (!copy_xattrs (src, dest))
      /* copy_xattrs replies with an error already. */
      return -1;
  }

  return 0;
}
