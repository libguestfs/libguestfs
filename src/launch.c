/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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
#include <stdbool.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static mode_t get_umask (guestfs_h *g);

static const struct attach_ops *
get_attach_ops (guestfs_h *g)
{
  switch (g->attach_method) {
  case ATTACH_METHOD_APPLIANCE: return &attach_ops_appliance;
  case ATTACH_METHOD_LIBVIRT:   return &attach_ops_libvirt;
  case ATTACH_METHOD_UNIX:      return &attach_ops_unix;
  default: abort ();
  }
}

int
guestfs__launch (guestfs_h *g)
{
  /* Configured? */
  if (g->state != CONFIG) {
    error (g, _("the libguestfs handle has already been launched"));
    return -1;
  }

  /* Start the clock ... */
  gettimeofday (&g->launch_t, NULL);
  TRACE0 (launch_start);

  /* Make the temporary directory. */
  if (guestfs___lazy_make_tmpdir (g) == -1)
    return -1;

  /* Allow anyone to read the temporary directory.  The socket in this
   * directory won't be readable but anyone can see it exists if they
   * want. (RHBZ#610880).
   */
  if (chmod (g->tmpdir, 0755) == -1)
    warning (g, "chmod: %s: %m (ignored)", g->tmpdir);

  /* Some common debugging information. */
  if (g->verbose) {
    CLEANUP_FREE char *attach_method = guestfs__get_attach_method (g);

    debug (g, "launch: attach-method=%s", attach_method);
    debug (g, "launch: tmpdir=%s", g->tmpdir);
    debug (g, "launch: umask=0%03o", get_umask (g));
    debug (g, "launch: euid=%d", geteuid ());
  }

  /* Launch the appliance. */
  g->attach_ops = get_attach_ops (g);
  return g->attach_ops->launch (g, g->attach_method_arg);
}

/* launch (of the appliance) generates approximate progress
 * messages.  Currently these are defined as follows:
 *
 *    0 / 12: launch clock starts
 *    3 / 12: appliance created
 *    6 / 12: detected that guest kernel started
 *    9 / 12: detected that /init script is running
 *   12 / 12: launch completed successfully
 *
 * Notes:
 * (1) This is not a documented ABI and the behaviour may be changed
 * or removed in future.
 * (2) Messages are only sent if more than 5 seconds has elapsed
 * since the launch clock started.
 * (3) There is a gross hack in proto.c to make this work.
 */
void
guestfs___launch_send_progress (guestfs_h *g, int perdozen)
{
  struct timeval tv;

  gettimeofday (&tv, NULL);
  if (guestfs___timeval_diff (&g->launch_t, &tv) >= 5000) {
    guestfs_progress progress_message =
      { .proc = 0, .serial = 0, .position = perdozen, .total = 12 };

    guestfs___progress_message_callback (g, &progress_message);
  }
}

/* Note that since this calls 'debug' it should only be called
 * from the parent process.
 */
void
guestfs___print_timestamped_message (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int err;
  struct timeval tv;

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  gettimeofday (&tv, NULL);

  debug (g, "[%05" PRIi64 "ms] %s",
         guestfs___timeval_diff (&g->launch_t, &tv), msg);

  free (msg);
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
int64_t
guestfs___timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

/* Since this is the most common error seen by people who have
 * installation problems, buggy qemu, etc, and since no one reads the
 * FAQ, describe in this error message what resources are available to
 * debug launch problems.
 */
void
guestfs___launch_failed_error (guestfs_h *g)
{
  if (g->verbose)
    error (g, _("guestfs_launch failed, see earlier error messages"));
  else
    error (g, _("guestfs_launch failed.\n"
                "See http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs\n"
                "and/or run 'libguestfs-test-tool'."));
}

int
guestfs__get_pid (guestfs_h *g)
{
  if (g->state != READY || g->attach_ops == NULL) {
    error (g, _("get-pid can only be called after launch"));
    return -1;
  }

  if (g->attach_ops->get_pid == NULL)
    NOT_SUPPORTED (g, -1,
                   _("the current attach-method does not support 'get-pid'"));

  return g->attach_ops->get_pid (g);
}

/* Maximum number of disks. */
int
guestfs__max_disks (guestfs_h *g)
{
  const struct attach_ops *attach_ops = get_attach_ops (g);

  if (attach_ops->max_disks == NULL)
    NOT_SUPPORTED (g, -1,
                   _("the current attach-method does not allow max disks to be queried"));

  return attach_ops->max_disks (g);
}

/* You had to call this function after launch in versions <= 1.0.70,
 * but it is now a no-op.
 */
int
guestfs__wait_ready (guestfs_h *g)
{
  if (g->state != READY)  {
    error (g, _("qemu has not been launched yet"));
    return -1;
  }

  return 0;
}

int
guestfs__kill_subprocess (guestfs_h *g)
{
  return guestfs__shutdown (g);
}

/* Access current state. */
int
guestfs__is_config (guestfs_h *g)
{
  return g->state == CONFIG;
}

int
guestfs__is_launching (guestfs_h *g)
{
  return g->state == LAUNCHING;
}

int
guestfs__is_ready (guestfs_h *g)
{
  return g->state == READY;
}

int
guestfs__is_busy (guestfs_h *g)
{
  /* There used to be a BUSY state but it was removed in 1.17.36. */
  return 0;
}

int
guestfs__get_state (guestfs_h *g)
{
  return g->state;
}

/* Add arbitrary qemu parameters.  Useful for testing. */
int
guestfs__config (guestfs_h *g,
                 const char *qemu_param, const char *qemu_value)
{
  struct qemu_param *qp;

  if (qemu_param[0] != '-') {
    error (g, _("parameter must begin with '-' character"));
    return -1;
  }

  /* A bit fascist, but the user will probably break the extra
   * parameters that we add if they try to set any of these.
   */
  if (STREQ (qemu_param, "-kernel") ||
      STREQ (qemu_param, "-initrd") ||
      STREQ (qemu_param, "-nographic") ||
      STREQ (qemu_param, "-serial") ||
      STREQ (qemu_param, "-full-screen") ||
      STREQ (qemu_param, "-std-vga") ||
      STREQ (qemu_param, "-vnc")) {
    error (g, _("parameter '%s' isn't allowed"), qemu_param);
    return -1;
  }

  qp = safe_malloc (g, sizeof *qp);
  qp->qemu_param = safe_strdup (g, qemu_param);
  qp->qemu_value = qemu_value ? safe_strdup (g, qemu_value) : NULL;

  qp->next = g->qemu_params;
  g->qemu_params = qp;

  return 0;
}

/* Construct the Linux command line passed to the appliance.  This is
 * used by the 'appliance' and 'libvirt' attach-methods, and is simply
 * located in this file because it's a convenient place for this
 * common code.
 *
 * The 'appliance_dev' parameter must be the full device name of the
 * appliance disk and must have already been adjusted to take into
 * account virtio-blk or virtio-scsi; eg "/dev/sdb".
 *
 * The 'flags' parameter can contain the following flags logically
 * or'd together (or 0):
 *
 * GUESTFS___APPLIANCE_COMMAND_LINE_IS_TCG: If we are launching a qemu
 * TCG guest (ie. KVM is known to be disabled or unavailable).  If you
 * don't know, don't pass this flag.
 *
 * Note that this returns a newly allocated buffer which must be freed
 * by the caller.
 */
#if defined(__arm__)
#define SERIAL_CONSOLE "ttyAMA0"
#else
#define SERIAL_CONSOLE "ttyS0"
#endif

char *
guestfs___appliance_command_line (guestfs_h *g, const char *appliance_dev,
                                  int flags)
{
  char root[64] = "";
  char *term = getenv ("TERM");
  char *ret;
  bool tcg = flags & APPLIANCE_COMMAND_LINE_IS_TCG;
  char lpj_s[64] = "";

  if (appliance_dev)
    snprintf (root, sizeof root, " root=%s", appliance_dev);

  if (tcg) {
    int lpj = guestfs___get_lpj (g);
    if (lpj > 0)
      snprintf (lpj_s, sizeof lpj_s, " lpj=%d", lpj);
  }

  ret = safe_asprintf
    (g,
     "panic=1"             /* force kernel to panic if daemon exits */
#ifdef __i386__
     " noapic"                  /* workaround for RHBZ#857026 */
#endif
     " console=" SERIAL_CONSOLE /* serial console */
     " udevtimeout=600" /* good for very slow systems (RHBZ#480319) */
     " no_timer_check"  /* fix for RHBZ#502058 */
     "%s"               /* lpj */
     " acpi=off"        /* we don't need ACPI, turn it off */
     " printk.time=1"   /* display timestamp before kernel messages */
     " cgroup_disable=memory"   /* saves us about 5 MB of RAM */
     "%s"                       /* root=appliance_dev */
     " %s"                      /* selinux */
     "%s"                       /* verbose */
     " TERM=%s"                 /* TERM environment variable */
     "%s%s",                    /* append */
     lpj_s,
     root,
     g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
     g->verbose ? " guestfs_verbose=1" : "",
     term ? term : "linux",
     g->append ? " " : "", g->append ? g->append : "");

  return ret;
}

/* glibc documents, but does not actually implement, a 'getumask(3)'
 * call.  This implements a thread-safe way to get the umask.  Note
 * this is only called when g->verbose is true and after g->tmpdir
 * has been created.
 */
static mode_t
get_umask (guestfs_h *g)
{
  mode_t ret;
  int fd;
  struct stat statbuf;
  CLEANUP_FREE char *filename = safe_asprintf (g, "%s/umask-check", g->tmpdir);

  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0777);
  if (fd == -1)
    return -1;

  if (fstat (fd, &statbuf) == -1) {
    close (fd);
    return -1;
  }

  close (fd);

  ret = statbuf.st_mode;
  ret &= 0777;
  ret = ret ^ 0777;

  return ret;
}
