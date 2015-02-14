/* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <assert.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static struct backend {
  struct backend *next;
  const char *name;
  const struct backend_ops *ops;
} *backends = NULL;

static mode_t get_umask (guestfs_h *g);

int
guestfs_impl_launch (guestfs_h *g)
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
  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return -1;

  /* Allow anyone to read the temporary directory.  The socket in this
   * directory won't be readable but anyone can see it exists if they
   * want. (RHBZ#610880).
   */
  if (chmod (g->tmpdir, 0755) == -1)
    warning (g, "chmod: %s: %m (ignored)", g->tmpdir);

  /* Some common debugging information. */
  if (g->verbose) {
    CLEANUP_FREE_VERSION struct guestfs_version *v =
      guestfs_version (g);
    struct backend *b;
    CLEANUP_FREE char *backend = guestfs_get_backend (g);

    debug (g, "launch: program=%s", g->program);
    debug (g, "launch: version=%"PRIi64".%"PRIi64".%"PRIi64"%s",
           v->major, v->minor, v->release, v->extra);

    for (b = backends; b != NULL; b = b->next)
      debug (g, "launch: backend registered: %s", b->name);
    debug (g, "launch: backend=%s", backend);

    debug (g, "launch: tmpdir=%s", g->tmpdir);
    debug (g, "launch: umask=0%03o", get_umask (g));
    debug (g, "launch: euid=%d", geteuid ());
  }

  /* Launch the appliance. */
  if (g->backend_ops->launch (g, g->backend_data, g->backend_arg) == -1)
    return -1;

  return 0;
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
 * (3) There is a hack in proto.c to make this work.
 */
void
guestfs_int_launch_send_progress (guestfs_h *g, int perdozen)
{
  struct timeval tv;

  gettimeofday (&tv, NULL);
  if (guestfs_int_timeval_diff (&g->launch_t, &tv) >= 5000) {
    guestfs_progress progress_message =
      { .proc = 0, .serial = 0, .position = perdozen, .total = 12 };

    guestfs_int_progress_message_callback (g, &progress_message);
  }
}

/* Note that since this calls 'debug' it should only be called
 * from the parent process.
 */
void
guestfs_int_print_timestamped_message (guestfs_h *g, const char *fs, ...)
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
         guestfs_int_timeval_diff (&g->launch_t, &tv), msg);

  free (msg);
}

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
int64_t
guestfs_int_timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

int
guestfs_impl_get_pid (guestfs_h *g)
{
  if (g->state != READY || g->backend_ops == NULL) {
    error (g, _("get-pid can only be called after launch"));
    return -1;
  }

  if (g->backend_ops->get_pid == NULL)
    NOT_SUPPORTED (g, -1,
                   _("the current backend does not support 'get-pid'"));

  return g->backend_ops->get_pid (g, g->backend_data);
}

/* Maximum number of disks. */
int
guestfs_impl_max_disks (guestfs_h *g)
{
  if (g->backend_ops->max_disks == NULL)
    NOT_SUPPORTED (g, -1,
                   _("the current backend does not allow max disks to be queried"));

  return g->backend_ops->max_disks (g, g->backend_data);
}

/* You had to call this function after launch in versions <= 1.0.70,
 * but it is now a no-op.
 */
int
guestfs_impl_wait_ready (guestfs_h *g)
{
  if (g->state != READY)  {
    error (g, _("qemu has not been launched yet"));
    return -1;
  }

  return 0;
}

int
guestfs_impl_kill_subprocess (guestfs_h *g)
{
  return guestfs_shutdown (g);
}

/* Access current state. */
int
guestfs_impl_is_config (guestfs_h *g)
{
  return g->state == CONFIG;
}

int
guestfs_impl_is_launching (guestfs_h *g)
{
  return g->state == LAUNCHING;
}

int
guestfs_impl_is_ready (guestfs_h *g)
{
  return g->state == READY;
}

int
guestfs_impl_is_busy (guestfs_h *g)
{
  /* There used to be a BUSY state but it was removed in 1.17.36. */
  return 0;
}

int
guestfs_impl_get_state (guestfs_h *g)
{
  return g->state;
}

/* Add arbitrary qemu parameters.  Useful for testing. */
int
guestfs_impl_config (guestfs_h *g,
                 const char *hv_param, const char *hv_value)
{
  struct hv_param *hp;

  /*
    XXX For qemu this made sense, but not for uml.
  if (hv_param[0] != '-') {
    error (g, _("parameter must begin with '-' character"));
    return -1;
  }
  */

  /* A bit fascist, but the user will probably break the extra
   * parameters that we add if they try to set any of these.
   */
  if (STREQ (hv_param, "-kernel") ||
      STREQ (hv_param, "-initrd") ||
      STREQ (hv_param, "-nographic") ||
      STREQ (hv_param, "-display") ||
      STREQ (hv_param, "-serial") ||
      STREQ (hv_param, "-full-screen") ||
      STREQ (hv_param, "-std-vga") ||
      STREQ (hv_param, "-vnc")) {
    error (g, _("parameter '%s' isn't allowed"), hv_param);
    return -1;
  }

  hp = safe_malloc (g, sizeof *hp);
  hp->hv_param = safe_strdup (g, hv_param);
  hp->hv_value = hv_value ? safe_strdup (g, hv_value) : NULL;

  hp->next = g->hv_params;
  g->hv_params = hp;

  return 0;
}

/* Construct the Linux command line passed to the appliance.  This is
 * used by the 'direct' and 'libvirt' backends, and is simply
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
#if defined(__powerpc64__)
#define SERIAL_CONSOLE "console=hvc0 console=ttyS0"
#elif defined(__arm__) || defined(__aarch64__)
#define SERIAL_CONSOLE "console=ttyAMA0"
#else
#define SERIAL_CONSOLE "console=ttyS0"
#endif

char *
guestfs_int_appliance_command_line (guestfs_h *g, const char *appliance_dev,
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
    int lpj = guestfs_int_get_lpj (g);
    if (lpj > 0)
      snprintf (lpj_s, sizeof lpj_s, " lpj=%d", lpj);
  }

  ret = safe_asprintf
    (g,
     "panic=1"             /* force kernel to panic if daemon exits */
#ifdef __arm__
     " mem=%dM"
#endif
#ifdef VALGRIND_DAEMON
     " guestfs_valgrind_daemon=1"
#endif
#ifdef __i386__
     " noapic"                  /* workaround for RHBZ#857026 */
#endif
     " " SERIAL_CONSOLE /* serial console */
#ifdef __aarch64__
     " earlyprintk=pl011,0x9000000 ignore_loglevel"
     /* This option turns off the EFI RTC device.  QEMU VMs don't
      * currently provide EFI, and if the device is compiled in it
      * will try to call the EFI function GetTime unconditionally
      * (causing a call to NULL).  However this option requires a
      * non-upstream patch.
      */
     " efi-rtc=noprobe"
#endif
     " udevtimeout=6000"/* for slow systems (RHBZ#480319, RHBZ#1096579) */
     " udev.event-timeout=6000" /* for newer udevd */
     " no_timer_check"  /* fix for RHBZ#502058 */
     "%s"               /* lpj */
     " acpi=off"        /* we don't need ACPI, turn it off */
     " printk.time=1"   /* display timestamp before kernel messages */
     " cgroup_disable=memory"   /* saves us about 5 MB of RAM */
     "%s"                       /* root=appliance_dev */
     " %s"                      /* selinux */
     "%s"                       /* verbose */
     "%s"                       /* network */
     " TERM=%s"                 /* TERM environment variable */
     "%s%s",                    /* append */
#ifdef __arm__
     g->memsize,
#endif
     lpj_s,
     root,
     g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
     g->verbose ? " guestfs_verbose=1" : "",
     g->enable_network ? " guestfs_network=1" : "",
     term ? term : "linux",
     g->append ? " " : "", g->append ? g->append : "");

  return ret;
}

/* Return the right CPU model to use as the -cpu parameter or its
 * equivalent in libvirt.  This returns:
 *
 * - "host" (means use -cpu host)
 * - some string such as "cortex-a57" (means use -cpu string)
 * - NULL (means no -cpu option at all)
 *
 * This is made unnecessarily hard and fragile because of two stupid
 * choices in QEMU:
 *
 * (1) The default for qemu-system-aarch64 -M virt is to emulate a
 * cortex-a15 (WTF?).
 *
 * (2) We don't know for sure if KVM will work, but -cpu host is
 * broken with TCG, so we almost always pass a broken -cpu flag if KVM
 * is semi-broken in any way.
 */
const char *
guestfs_int_get_cpu_model (int kvm)
{
#if defined(__arm__)            /* 32 bit ARM. */
  return NULL;

#elif defined(__aarch64__)
  /* With -M virt, the default -cpu is cortex-a15.  Stupid. */
  if (kvm)
    return "host";
  else
    return "cortex-a57";

#elif defined(__i386__) || defined(__x86_64__)
  /* It is faster to pass the CPU host model to the appliance,
   * allowing maximum speed for things like checksums, encryption.
   * Only do this with KVM.  It is broken in subtle ways on TCG, and
   * fairly pointless anyway.
   */
  if (kvm)
    return "host";
  else
    return NULL;

#else
  /* Hope for the best ... */
  if (kvm)
    return "host";
  else
    return NULL;
#endif
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

/* Register backends in a global list when the library is loaded. */
void
guestfs_int_register_backend (const char *name, const struct backend_ops *ops)
{
  struct backend *b;

  b = malloc (sizeof *b);
  if (!b) abort ();

  b->name = name;
  b->ops = ops;

  b->next = backends;
  backends = b;
}

/* Set the current backend.  Notes:
 * (1) Callers must ensure this is only called in the config state.
 * (2) This shouldn't call 'error' since it may be called early in
 * handle initialization.  It can return an error code however.
 */
int
guestfs_int_set_backend (guestfs_h *g, const char *method)
{
  struct backend *b;
  size_t len, arg_offs = 0;

  assert (g->state == CONFIG);

  /* For backwards compatibility with old code (RHBZ#1055452). */
  if (STREQ (method, "appliance"))
    method = "direct";

  for (b = backends; b != NULL; b = b->next) {
    if (STREQ (method, b->name))
      break;
    len = strlen (b->name);
    if (STRPREFIX (method, b->name) && method[len] == ':') {
      arg_offs = len+1;
      break;
    }
  }

  if (b == NULL)
    return -1;                  /* Not found. */

  /* At this point, we know it's a valid method. */
  free (g->backend);
  g->backend = safe_strdup (g, method);
  if (arg_offs > 0)
    g->backend_arg = &g->backend[arg_offs];
  else
    g->backend_arg = NULL;

  g->backend_ops = b->ops;

  free (g->backend_data);
  if (b->ops->data_size > 0)
    g->backend_data = safe_calloc (g, 1, b->ops->data_size);
  else
    g->backend_data = NULL;

  return 0;
}
