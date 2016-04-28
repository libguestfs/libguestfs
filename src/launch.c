/* libguestfs
 * Copyright (C) 2009-2016 Red Hat Inc.
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

/**
 * This file implements L<guestfs(3)/guestfs_launch>.
 *
 * Most of the work is done by the backends (see
 * L<guestfs(3)/BACKEND>), which are implemented in
 * F<src/launch-direct.c>, F<src/launch-libvirt.c> etc, so this file
 * mostly passes calls through to the current backend.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <assert.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static struct backend {
  struct backend *next;
  const char *name;
  const struct backend_ops *ops;
} *backends = NULL;

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

  /* Some common debugging information. */
  if (g->verbose) {
    CLEANUP_FREE_VERSION struct guestfs_version *v =
      guestfs_version (g);
    struct backend *b;
    CLEANUP_FREE char *backend = guestfs_get_backend (g);
    int mask;

    debug (g, "launch: program=%s", g->program);
    if (STRNEQ (g->identifier, ""))
      debug (g, "launch: identifier=%s", g->identifier);
    debug (g, "launch: version=%"PRIi64".%"PRIi64".%"PRIi64"%s",
           v->major, v->minor, v->release, v->extra);

    for (b = backends; b != NULL; b = b->next)
      debug (g, "launch: backend registered: %s", b->name);
    debug (g, "launch: backend=%s", backend);

    debug (g, "launch: tmpdir=%s", g->tmpdir);
    mask = guestfs_int_getumask (g);
    if (mask >= 0)
      debug (g, "launch: umask=0%03o", (unsigned) mask);
    debug (g, "launch: euid=%ju", (uintmax_t) geteuid ());
  }

  /* Launch the appliance. */
  if (g->backend_ops->launch (g, g->backend_data, g->backend_arg) == -1)
    return -1;

  return 0;
}

/**
 * This function sends a launch progress message.
 *
 * Launching the appliance generates approximate progress
 * messages.  Currently these are defined as follows:
 *
 *    0 / 12: launch clock starts
 *    3 / 12: appliance created
 *    6 / 12: detected that guest kernel started
 *    9 / 12: detected that /init script is running
 *   12 / 12: launch completed successfully
 *
 * Notes:
 *
 * =over 4
 *
 * =item 1.
 *
 * This is not a documented ABI and the behaviour may be changed
 * or removed in future.
 *
 * =item 2.
 *
 * Messages are only sent if more than 5 seconds has elapsed
 * since the launch clock started.
 *
 * =item 3.
 *
 * There is a hack in F<src/proto.c> to make this work.
 *
 * =back
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

/**
 * Compute C<y - x> and return the result in milliseconds.
 *
 * Approximately the same as this code:
 * L<http://www.mpp.mpg.de/~huber/util/timevaldiff.c>
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

/**
 * Returns the maximum number of disks allowed to be added to the
 * backend (backend dependent).
 */
int
guestfs_impl_max_disks (guestfs_h *g)
{
  if (g->backend_ops->max_disks == NULL)
    NOT_SUPPORTED (g, -1,
                   _("the current backend does not allow max disks to be queried"));

  return g->backend_ops->max_disks (g, g->backend_data);
}

/**
 * Implementation of L<guestfs(3)/guestfs_wait_ready>.  You had to
 * call this function after launch in versions E<le> 1.0.70, but it is
 * now an (almost) no-op.
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

#if defined(__powerpc64__)
#define SERIAL_CONSOLE "console=hvc0 console=ttyS0"
#elif defined(__arm__) || defined(__aarch64__)
#define SERIAL_CONSOLE "console=ttyAMA0"
#else
#define SERIAL_CONSOLE "console=ttyS0"
#endif

#if defined(__aarch64__)
#define EARLYPRINTK " earlyprintk=pl011,0x9000000"
#else
#define EARLYPRINTK ""
#endif

/**
 * Construct the Linux command line passed to the appliance.  This is
 * used by the C<direct> and C<libvirt> backends, and is simply
 * located in this file because it's a convenient place for this
 * common code.
 *
 * The C<appliance_dev> parameter must be the full device name of the
 * appliance disk and must have already been adjusted to take into
 * account virtio-blk or virtio-scsi; eg C</dev/sdb>.
 *
 * The C<flags> parameter can contain the following flags logically
 * or'd together (or 0):
 *
 * =over 4
 *
 * =item C<APPLIANCE_COMMAND_LINE_IS_TCG>
 *
 * If we are launching a qemu TCG guest (ie. KVM is known to be
 * disabled or unavailable).  If you don't know, don't pass this flag.
 *
 * =back
 *
 * Note that this function returns a newly allocated buffer which must
 * be freed by the caller.
 */
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
#ifdef __i386__
     " noapic"                  /* workaround for RHBZ#857026 */
#endif
     " " SERIAL_CONSOLE         /* serial console */
     EARLYPRINTK                /* get messages from early boot */
#ifdef __aarch64__
     " ignore_loglevel"
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
     " acpi=off"        /* ACPI is slow - 150-200ms extra on my laptop */
     " printk.time=1"   /* display timestamp before kernel messages */
     " cgroup_disable=memory"   /* saves us about 5 MB of RAM */
     " usbcore.nousb"           /* disable USB, only saves about 1ms */
     "%s"                       /* root=appliance_dev */
     " %s"                      /* selinux */
     " %s"                      /* quiet/verbose */
     "%s"                       /* network */
     " TERM=%s"                 /* TERM environment variable */
     "%s%s"                     /* handle identifier */
     "%s%s",                    /* append */
#ifdef __arm__
     g->memsize,
#endif
     lpj_s,
     root,
     g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
     g->verbose ? "guestfs_verbose=1" : "quiet",
     g->enable_network ? " guestfs_network=1" : "",
     term ? term : "linux",
     STRNEQ (g->identifier, "") ? " guestfs_identifier=" : "",
     g->identifier,
     g->append ? " " : "", g->append ? g->append : "");

  return ret;
}

/**
 * Return the right CPU model to use as the qemu C<-cpu> parameter or
 * its equivalent in libvirt.  This returns:
 *
 * =over 4
 *
 * =item C<"host">
 *
 * The literal string C<"host"> means use C<-cpu host>.
 *
 * =item some string
 *
 * Some string such as C<"cortex-a57"> means use C<-cpu cortex-a57>.
 *
 * =item C<NULL>
 *
 * C<NULL> means no C<-cpu> option at all.  Note returning C<NULL>
 * does not indicate an error.
 *
 * =back
 *
 * This is made unnecessarily hard and fragile because of two stupid
 * choices in QEMU:
 *
 * =over 4
 *
 * =item *
 *
 * The default for C<qemu-system-aarch64 -M virt> is to emulate a
 * C<cortex-a15> (WTF?).
 *
 * =item *
 *
 * We don't know for sure if KVM will work, but C<-cpu host> is broken
 * with TCG, so we almost always pass a broken C<-cpu> flag if KVM is
 * semi-broken in any way.
 *
 * =back
 */
const char *
guestfs_int_get_cpu_model (int kvm)
{
#if defined(__aarch64__)
  /* With -M virt, the default -cpu is cortex-a15.  Stupid. */
  if (kvm)
    return "host";
  else
    return "cortex-a57";
#else
  /* On most architectures, it is faster to pass the CPU host model to
   * the appliance, allowing maximum speed for things like checksums
   * and encryption.  Only do this with KVM.  It is broken in subtle
   * ways on TCG, and fairly pointless when you're emulating anyway.
   */
  if (kvm)
    return "host";
  else
    return NULL;
#endif
}

/**
 * Create the path for a socket with the selected filename in the
 * tmpdir.
 */
int
guestfs_int_create_socketname (guestfs_h *g, const char *filename,
                               char (*sockpath)[UNIX_PATH_MAX])
{
  if (guestfs_int_lazy_make_sockdir (g) == -1)
    return -1;

  if (strlen (g->sockdir) + 1 + strlen (filename) > UNIX_PATH_MAX-1) {
    error (g, _("socket path too long: %s/%s"), g->sockdir, filename);
    return -1;
  }

  snprintf (*sockpath, UNIX_PATH_MAX, "%s/%s", g->sockdir, filename);

  return 0;
}

/**
 * When the library is loaded, each backend calls this function to
 * register itself in a global list.
 */
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

/**
 * Implementation of L<guestfs(3)/guestfs_set_backend>.
 *
 * =over 4
 *
 * =item *
 *
 * Callers must ensure this is only called in the config state.
 *
 * =item *
 *
 * This shouldn't call C<error> since it may be called early in
 * handle initialization.  It can return an error code however.
 *
 * =back
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

/* This hack is only required to make static linking work.  See:
 * https://stackoverflow.com/questions/1202494/why-doesnt-attribute-constructor-work-in-a-static-library
 */
void *
guestfs_int_force_load_backends[] = {
  guestfs_int_init_direct_backend,
#ifdef HAVE_LIBVIRT_BACKEND
  guestfs_int_init_libvirt_backend,
#endif
  guestfs_int_init_uml_backend,
  guestfs_int_init_unix_backend,
};
