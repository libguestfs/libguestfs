/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <errno.h>

#ifdef HAVE_LINUX_FS_H
#include <linux/fs.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int disk_create_raw (guestfs_h *g, const char *filename, int64_t size, const struct guestfs_disk_create_argv *optargs);
static int disk_create_qcow2 (guestfs_h *g, const char *filename, int64_t size, const char *backingfile, const struct guestfs_disk_create_argv *optargs);
static char *qemu_escape_param (guestfs_h *g, const char *param);

int
guestfs__disk_create (guestfs_h *g, const char *filename,
                      const char *format, int64_t size,
                      const struct guestfs_disk_create_argv *optargs)
{
  const char *backingfile;

  backingfile = optargs->bitmask & GUESTFS_DISK_CREATE_BACKINGFILE_BITMASK ?
    optargs->backingfile : NULL;

  /* Ensure size is valid. */
  if (backingfile) {
    if (size != -1) {
      error (g, _("if using a backing file, size must be passed as -1"));
      return -1;
    }
  } else {
    /* XXX Actually size == 0 could be valid, although not useful and
     * it causes qemu to break.
     */
    if (size <= 0) {
      error (g, _("invalid size: %" PRIi64), size);
      return -1;
    }
  }

  /* Now the format-specific code. */
  if (STREQ (format, "raw")) {
    if (backingfile) {
      error (g, _("backingfile cannot be used for raw format disks"));
      return -1;
    }
    if (disk_create_raw (g, filename, size, optargs) == -1)
      return -1;
  }
  else if (STREQ (format, "qcow2")) {
    if (disk_create_qcow2 (g, filename, size, backingfile, optargs) == -1)
      return -1;
  }
  else {
    /* Be conservative about what formats we support, since we don't
     * want to make unlimited promises through the API.  We can always
     * add more later.
     */
    error (g, _("unsupported format '%s'"), format);
    return -1;
  }

  return 0;
}

static int
disk_create_raw_block (guestfs_h *g, const char *filename)
{
  int fd;

  fd = open (filename, O_WRONLY|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    perrorf (g, _("cannot open block device: %s"), filename);
    return -1;
  }

  /* Just discard blocks, if possible.  However don't try too hard. */
#if defined(BLKGETSIZE64) && defined(BLKDISCARD)
  uint64_t size;
  uint64_t range[2];

  if (ioctl (fd, BLKGETSIZE64, &size) == 0) {
    range[0] = 0;
    range[1] = size;
    if (ioctl (fd, BLKDISCARD, range) == 0)
      debug (g, "disk_create: %s: BLKDISCARD failed on this device: %m",
             filename);
  }
#endif

  close (fd);

  return 0;
}

static int
disk_create_raw (guestfs_h *g, const char *filename, int64_t size,
                 const struct guestfs_disk_create_argv *optargs)
{
  int allocated = 0;
  int fd;
  struct stat statbuf;

  /* backingfile parameter not present checked above */

  if (optargs->bitmask & GUESTFS_DISK_CREATE_BACKINGFORMAT_BITMASK) {
    error (g, _("backingformat parameter cannot be used with raw format"));
    return -1;
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_PREALLOCATION_BITMASK) {
    if (STREQ (optargs->preallocation, "sparse"))
      allocated = 0;
    else if (STREQ (optargs->preallocation, "full"))
      allocated = 1;
    else {
      error (g, _("invalid value for preallocation parameter '%s'"),
             optargs->preallocation);
      return -1;
    }
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_COMPAT_BITMASK) {
    error (g, _("compat parameter cannot be used with raw format"));
    return -1;
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_CLUSTERSIZE_BITMASK) {
    error (g, _("clustersize parameter cannot be used with raw format"));
    return -1;
  }

  if (stat (filename, &statbuf) == 0) {
    /* Refuse to overwrite char devices. */
    if (S_ISCHR (statbuf.st_mode)) {
      error (g, _("refusing to overwrite char device '%s'"), filename);
      return -1;
    }
    /* Block devices have to be handled specially. */
    if (S_ISBLK (statbuf.st_mode))
      return disk_create_raw_block (g, filename);
  }

  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perrorf (g, _("cannot create raw file: %s"), filename);
    return -1;
  }

  if (!allocated) {             /* Sparse file. */
    if (ftruncate (fd, size) == -1) {
      perrorf (g, _("%s: truncate"), filename);
      close (fd);
      unlink (filename);
      return -1;
    }
  }
  else {                        /* Allocated file. */
#ifdef HAVE_POSIX_FALLOCATE
    int err;

    err = posix_fallocate (fd, 0, size);
    if (err != 0) {
      errno = err;
      perrorf (g, _("%s: fallocate"), filename);
      close (fd);
      unlink (filename);
      return -1;
    }
#else
    /* Slow emulation of posix_fallocate on platforms which don't have it. */
    char buffer[BUFSIZ];
    size_t remaining = size;
    size_t n;
    ssize_t r;

    memset (buffer, 0, sizeof buffer);

    while (remaining > 0) {
      n = remaining > sizeof buffer ? sizeof buffer : remaining;
      r = write (fd, buffer, n);
      if (r == -1) {
        perrorf (g, _("%s: write"), filename);
        close (fd);
        unlink (filename);
        return -1;
      }
      remaining -= r;
    }
#endif
  }

  if (close (fd) == -1) {
    perrorf (g, _("%s: close"), filename);
    unlink (filename);
    return -1;
  }

  return 0;
}

/* http://graphics.stanford.edu/~seander/bithacks.html#DetermineIfPowerOf2 */
static int
is_power_of_2 (unsigned v)
{
  return v && ((v & (v - 1)) == 0);
}

static int
disk_create_qcow2 (guestfs_h *g, const char *orig_filename, int64_t size,
                   const char *backingfile,
                   const struct guestfs_disk_create_argv *optargs)
{
  CLEANUP_FREE char *filename = NULL;
  const char *backingformat = NULL;
  const char *preallocation = NULL;
  const char *compat = NULL;
  int clustersize = -1;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (optionsv);
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  /* If the filename is something like "file:foo" then qemu-img will
   * try to interpret that as "foo" in the file:/// protocol.  To
   * avoid that, if the path is relative prefix it with "./" since
   * qemu-img won't try to interpret such a path.
   */
  if (orig_filename[0] != '/')
    filename = safe_asprintf (g, "./%s", orig_filename);
  else
    filename = safe_strdup (g, orig_filename);

  if (optargs->bitmask & GUESTFS_DISK_CREATE_BACKINGFORMAT_BITMASK) {
    backingformat = optargs->backingformat;
    if (STRNEQ (backingformat, "raw") && STRNEQ (backingformat, "qcow2")) {
      error (g, _("invalid value for backingformat parameter '%s'"),
             backingformat);
      return -1;
    }
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_PREALLOCATION_BITMASK) {
    preallocation = optargs->preallocation;
    if (STRNEQ (preallocation, "off") && STRNEQ (preallocation, "metadata")) {
      error (g, _("invalid value for preallocation parameter '%s'"),
             preallocation);
      return -1;
    }
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_COMPAT_BITMASK) {
    compat = optargs->compat;
    if (STRNEQ (compat, "0.10") && STRNEQ (compat, "1.1")) {
      error (g, _("invalid value for compat parameter '%s'"), compat);
      return -1;
    }
  }
  if (optargs->bitmask & GUESTFS_DISK_CREATE_CLUSTERSIZE_BITMASK) {
    clustersize = optargs->clustersize;
    if (clustersize < 512 || clustersize > 2097152 ||
        !is_power_of_2 ((unsigned) clustersize)) {
      error (g, _("invalid value for clustersize parameter '%d'"),
             clustersize);
      return -1;
    }
  }

  /* Assemble the qemu-img command line. */
  guestfs_int_cmd_add_arg (cmd, "qemu-img");
  guestfs_int_cmd_add_arg (cmd, "create");
  guestfs_int_cmd_add_arg (cmd, "-f");
  guestfs_int_cmd_add_arg (cmd, "qcow2");

  /* -o parameter. */
  if (backingfile) {
    CLEANUP_FREE char *p = qemu_escape_param (g, backingfile);
    guestfs_int_add_sprintf (g, &optionsv, "backing_file=%s", p);
  }
  if (backingformat)
    guestfs_int_add_sprintf (g, &optionsv, "backing_fmt=%s", backingformat);
  if (preallocation)
    guestfs_int_add_sprintf (g, &optionsv, "preallocation=%s", preallocation);
  if (compat)
    guestfs_int_add_sprintf (g, &optionsv, "compat=%s", compat);
  if (clustersize >= 0)
    guestfs_int_add_sprintf (g, &optionsv, "cluster_size=%d", clustersize);
  guestfs_int_end_stringsbuf (g, &optionsv);

  if (optionsv.size > 1) {
    CLEANUP_FREE char *options = guestfs_int_join_strings (",", optionsv.argv);
    guestfs_int_cmd_add_arg (cmd, "-o");
    guestfs_int_cmd_add_arg (cmd, options);
  }

  /* Complete the command line. */
  guestfs_int_cmd_add_arg (cmd, filename);
  if (size >= 0)
    guestfs_int_cmd_add_arg_format (cmd, "%" PRIi64, size);

  r = guestfs_int_cmd_run (cmd);
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "qemu-img", orig_filename);
    return -1;
  }

  return 0;
}

/* XXX Duplicated in launch-direct.c. */
static char *
qemu_escape_param (guestfs_h *g, const char *param)
{
  size_t i, len = strlen (param);
  char *p, *ret;

  ret = p = safe_malloc (g, len*2 + 1); /* max length of escaped name*/
  for (i = 0; i < len; ++i) {
    *p++ = param[i];
    if (param[i] == ',')
      *p++ = ',';
  }
  *p = '\0';

  return ret;
}
