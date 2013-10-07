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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#include "ignore-value.h"

GUESTFSD_EXT_CMD(str_mount, mount);
GUESTFSD_EXT_CMD(str_umount, umount);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_BIND_STATE __attribute__((cleanup(free_bind_state)))
#else
#define CLEANUP_BIND_STATE
#endif

struct bind_state {
  bool mounted;
  char *sysroot_dev;
  char *sysroot_dev_pts;
  char *sysroot_proc;
  char *sysroot_sys;
  bool dev_ok, dev_pts_ok, proc_ok, sys_ok;
};

/* While running the command, bind-mount /dev, /proc, /sys
 * into the chroot.  However we must be careful to unmount them
 * afterwards because otherwise they would interfere with
 * future mount and unmount operations.
 *
 * We deliberately allow these commands to fail silently, BUT
 * if a mount fails, don't unmount the corresponding mount.
 */
static int
bind_mount (struct bind_state *bs)
{
  int r;

  memset (bs, 0, sizeof *bs);

  bs->sysroot_dev = sysroot_path ("/dev");
  bs->sysroot_dev_pts = sysroot_path ("/dev/pts");
  bs->sysroot_proc = sysroot_path ("/proc");
  bs->sysroot_sys = sysroot_path ("/sys");

  if (bs->sysroot_dev == NULL || bs->sysroot_dev_pts == NULL ||
      bs->sysroot_proc == NULL || bs->sysroot_sys == NULL) {
    reply_with_perror ("malloc");
    free (bs->sysroot_dev);
    free (bs->sysroot_dev_pts);
    free (bs->sysroot_proc);
    free (bs->sysroot_sys);
    return -1;
  }

  r = command (NULL, NULL, str_mount, "--bind", "/dev", bs->sysroot_dev, NULL);
  bs->dev_ok = r != -1;
  r = command (NULL, NULL, str_mount, "--bind", "/dev/pts", bs->sysroot_dev_pts, NULL);
  bs->dev_pts_ok = r != -1;
  r = command (NULL, NULL, str_mount, "--bind", "/proc", bs->sysroot_proc, NULL);
  bs->proc_ok = r != -1;
  r = command (NULL, NULL, str_mount, "--bind", "/sys", bs->sysroot_sys, NULL);
  bs->sys_ok = r != -1;

  bs->mounted = true;

  return 0;
}

static inline void
umount_ignore_fail (const char *path)
{
  ignore_value (command (NULL, NULL, str_umount, path, NULL));
}

static void
free_bind_state (struct bind_state *bs)
{
  if (bs->mounted) {
    if (bs->sys_ok) umount_ignore_fail (bs->sysroot_sys);
    free (bs->sysroot_sys);
    if (bs->proc_ok) umount_ignore_fail (bs->sysroot_proc);
    free (bs->sysroot_proc);
    if (bs->dev_pts_ok) umount_ignore_fail (bs->sysroot_dev_pts);
    free (bs->sysroot_dev_pts);
    if (bs->dev_ok) umount_ignore_fail (bs->sysroot_dev);
    free (bs->sysroot_dev);
    bs->mounted = false;
  }
}

char *
do_command (char *const *argv)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;
  CLEANUP_BIND_STATE struct bind_state bind_state = { .mounted = false };

  /* We need a root filesystem mounted to do this. */
  NEED_ROOT (, return NULL);

  /* Conveniently, argv is already a NULL-terminated argv-style array
   * of parameters, so we can pass it straight in to our internal
   * commandv.  We just have to check the list is non-empty.
   */
  if (argv[0] == NULL) {
    reply_with_error ("passed an empty list");
    return NULL;
  }

  if (bind_mount (&bind_state) == -1)
    return NULL;

  CHROOT_IN;
  r = commandv (&out, &err, (const char * const *) argv);
  CHROOT_OUT;

  free_bind_state (&bind_state);

  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  return out;			/* Caller frees. */
}

char **
do_command_lines (char *const *argv)
{
  CLEANUP_FREE char *out = NULL;
  char **lines;

  out = do_command (argv);
  if (out == NULL)
    return NULL;

  lines = split_lines (out);

  if (lines == NULL)
    return NULL;

  return lines;			/* Caller frees. */
}

char *
do_sh (const char *cmd)
{
  const char *argv[] = { "/bin/sh", "-c", cmd, NULL };

  return do_command ((char **) argv);
}

char **
do_sh_lines (const char *cmd)
{
  const char *argv[] = { "/bin/sh", "-c", cmd, NULL };

  return do_command_lines ((char **) argv);
}
