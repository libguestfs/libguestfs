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
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#include "ignore-value.h"

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_BIND_STATE __attribute__((cleanup(free_bind_state)))
#define CLEANUP_RESOLVER_STATE __attribute__((cleanup(free_resolver_state)))
#else
#define CLEANUP_BIND_STATE
#define CLEANUP_RESOLVER_STATE
#endif

struct bind_state {
  bool mounted;
  char *sysroot_dev;
  char *sysroot_dev_pts;
  char *sysroot_proc;
  char *sysroot_selinux;
  char *sysroot_sys;
  char *sysroot_sys_fs_selinux;
  bool dev_ok, dev_pts_ok, proc_ok, selinux_ok, sys_ok, sys_fs_selinux_ok;
};

struct resolver_state {
  bool mounted;
  char *sysroot_etc_resolv_conf;
  char *sysroot_etc_resolv_conf_old;
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
  bs->sysroot_selinux = sysroot_path ("/selinux");
  bs->sysroot_sys = sysroot_path ("/sys");
  bs->sysroot_sys_fs_selinux = sysroot_path ("/sys/fs/selinux");

  if (bs->sysroot_dev == NULL || bs->sysroot_dev_pts == NULL ||
      bs->sysroot_proc == NULL || bs->sysroot_selinux == NULL ||
      bs->sysroot_sys == NULL || bs->sysroot_sys_fs_selinux == NULL) {
    reply_with_perror ("malloc");
    free (bs->sysroot_dev);
    free (bs->sysroot_dev_pts);
    free (bs->sysroot_proc);
    free (bs->sysroot_selinux);
    free (bs->sysroot_sys);
    free (bs->sysroot_sys_fs_selinux);
    return -1;
  }

  /* Note it is tempting to use --rbind here (to bind submounts).
   * However I have not found a reliable way to unmount the same set
   * of directories (umount -R does NOT work).
   */
  r = command (NULL, NULL, "mount", "--bind", "/dev", bs->sysroot_dev, NULL);
  bs->dev_ok = r != -1;
  r = command (NULL, NULL, "mount", "--bind", "/dev/pts", bs->sysroot_dev_pts, NULL);
  bs->dev_pts_ok = r != -1;
  r = command (NULL, NULL, "mount", "--bind", "/proc", bs->sysroot_proc, NULL);
  bs->proc_ok = r != -1;
  /* Note on the next line we have to bind-mount /sys/fs/selinux (appliance
   * kernel) on top of /selinux (where guest is expecting selinux).
   */
  r = command (NULL, NULL, "mount", "--bind", "/sys/fs/selinux", bs->sysroot_selinux, NULL);
  bs->selinux_ok = r != -1;
  r = command (NULL, NULL, "mount", "--bind", "/sys", bs->sysroot_sys, NULL);
  bs->sys_ok = r != -1;
  r = command (NULL, NULL, "mount", "--bind", "/sys/fs/selinux", bs->sysroot_sys_fs_selinux, NULL);
  bs->sys_fs_selinux_ok = r != -1;

  bs->mounted = true;

  return 0;
}

static inline void
umount_ignore_fail (const char *path)
{
  ignore_value (command (NULL, NULL, "umount", path, NULL));
}

static void
free_bind_state (struct bind_state *bs)
{
  if (bs->mounted) {
    if (bs->sys_fs_selinux_ok) umount_ignore_fail (bs->sysroot_sys_fs_selinux);
    free (bs->sysroot_sys_fs_selinux);
    if (bs->sys_ok) umount_ignore_fail (bs->sysroot_sys);
    free (bs->sysroot_sys);
    if (bs->selinux_ok) umount_ignore_fail (bs->sysroot_selinux);
    free (bs->sysroot_selinux);
    if (bs->proc_ok) umount_ignore_fail (bs->sysroot_proc);
    free (bs->sysroot_proc);
    if (bs->dev_pts_ok) umount_ignore_fail (bs->sysroot_dev_pts);
    free (bs->sysroot_dev_pts);
    if (bs->dev_ok) umount_ignore_fail (bs->sysroot_dev);
    free (bs->sysroot_dev);
    bs->mounted = false;
  }
}

/* If the network is enabled, we want <sysroot>/etc/resolv.conf to
 * reflect the contents of /etc/resolv.conf so that name resolution
 * works.  It would be nice to bind-mount the file (single file bind
 * mounts are possible).  However annoyingly that doesn't work for
 * Ubuntu guests where the guest resolv.conf is a dangling symlink,
 * and for reasons unknown mount tries to follow the symlink and
 * fails (likely a bug).  So this is a hack.  Note we only invoke
 * this if the network is enabled.
 */
static int
set_up_etc_resolv_conf (struct resolver_state *rs)
{
  struct stat statbuf;
  CLEANUP_FREE char *buf = NULL;

  rs->sysroot_etc_resolv_conf_old = NULL;

  rs->sysroot_etc_resolv_conf = sysroot_path ("/etc/resolv.conf");

  if (!rs->sysroot_etc_resolv_conf) {
    reply_with_perror ("malloc");
    goto error;
  }

  /* If /etc/resolv.conf exists, rename it to the backup file.  Note
   * that on Ubuntu it's a dangling symlink.
   */
  if (lstat (rs->sysroot_etc_resolv_conf, &statbuf) == 0) {
    /* Make a random name for the backup file. */
    if (asprintf (&buf, "%s/etc/XXXXXXXX", sysroot) == -1) {
      reply_with_perror ("asprintf");
      goto error;
    }
    if (random_name (buf) == -1) {
      reply_with_perror ("random_name");
      goto error;
    }
    rs->sysroot_etc_resolv_conf_old = strdup (buf);
    if (!rs->sysroot_etc_resolv_conf_old) {
      reply_with_perror ("strdup");
      goto error;
    }

    if (verbose)
      fprintf (stderr, "renaming %s to %s\n", rs->sysroot_etc_resolv_conf,
               rs->sysroot_etc_resolv_conf_old);

    if (rename (rs->sysroot_etc_resolv_conf,
                rs->sysroot_etc_resolv_conf_old) == -1) {
      reply_with_perror ("rename: %s to %s", rs->sysroot_etc_resolv_conf,
                         rs->sysroot_etc_resolv_conf_old);
      goto error;
    }
  }

  /* Now that the guest's <sysroot>/etc/resolv.conf is out the way, we
   * can create our own copy of the appliance /etc/resolv.conf.
   */
  ignore_value (command (NULL, NULL, "cp", "/etc/resolv.conf",
                         rs->sysroot_etc_resolv_conf, NULL));

  rs->mounted = true;
  return 0;

 error:
  free (rs->sysroot_etc_resolv_conf);
  free (rs->sysroot_etc_resolv_conf_old);
  return -1;
}

static void
free_resolver_state (struct resolver_state *rs)
{
  if (rs->mounted) {
    unlink (rs->sysroot_etc_resolv_conf);

    if (rs->sysroot_etc_resolv_conf_old) {
      if (verbose)
        fprintf (stderr, "renaming %s to %s\n", rs->sysroot_etc_resolv_conf_old,
                 rs->sysroot_etc_resolv_conf);

      if (rename (rs->sysroot_etc_resolv_conf_old,
                  rs->sysroot_etc_resolv_conf) == -1)
        perror ("error: could not restore /etc/resolv.conf");

      free (rs->sysroot_etc_resolv_conf_old);
    }

    free (rs->sysroot_etc_resolv_conf);
    rs->mounted = false;
  }
}

char *
do_command (char *const *argv)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r, flags;
  CLEANUP_BIND_STATE struct bind_state bind_state = { .mounted = false };
  CLEANUP_RESOLVER_STATE struct resolver_state resolver_state =
    { .mounted = false };

  /* We need a root filesystem mounted to do this. */
  NEED_ROOT (0, return NULL);

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
  if (enable_network) {
    if (set_up_etc_resolv_conf (&resolver_state) == -1)
      return NULL;
  }

  flags = COMMAND_FLAG_DO_CHROOT;

  r = commandvf (&out, &err, flags, (const char * const *) argv);

  free_bind_state (&bind_state);
  free_resolver_state (&resolver_state);

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
