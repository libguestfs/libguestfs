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
#include <assert.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static void free_drive_struct (struct drive *drv);

size_t
guestfs___checkpoint_drives (guestfs_h *g)
{
  return g->nr_drives;
}

void
guestfs___rollback_drives (guestfs_h *g, size_t old_i)
{
  size_t i;

  for (i = old_i; i < g->nr_drives; ++i) {
    if (g->drives[i])
      free_drive_struct (g->drives[i]);
  }
  g->nr_drives = old_i;
}

/* Add struct drive to the g->drives vector at the given index. */
static void
add_drive_to_handle_at (guestfs_h *g, struct drive *d, size_t drv_index)
{
  if (drv_index >= g->nr_drives) {
    g->drives = safe_realloc (g, g->drives,
                              sizeof (struct drive *) * (drv_index + 1));
    while (g->nr_drives <= drv_index) {
      g->drives[g->nr_drives] = NULL;
      g->nr_drives++;
    }
  }

  assert (g->drives[drv_index] == NULL);

  g->drives[drv_index] = d;
}

/* Add struct drive to the end of the g->drives vector in the handle. */
static void
add_drive_to_handle (guestfs_h *g, struct drive *d)
{
  add_drive_to_handle_at (g, d, g->nr_drives);
}

static struct drive *
create_drive_struct (guestfs_h *g, const char *path,
                     int readonly, const char *format,
                     const char *iface, const char *name,
                     const char *disk_label,
                     int use_cache_none)
{
  struct drive *drv = safe_malloc (g, sizeof (struct drive));

  drv->path = safe_strdup (g, path);
  drv->readonly = readonly;
  drv->format = format ? safe_strdup (g, format) : NULL;
  drv->iface = iface ? safe_strdup (g, iface) : NULL;
  drv->name = name ? safe_strdup (g, name) : NULL;
  drv->disk_label = disk_label ? safe_strdup (g, disk_label) : NULL;
  drv->use_cache_none = use_cache_none;
  drv->priv = drv->free_priv = NULL;

  return drv;
}

/* Called during launch to add a dummy slot to g->drives. */
void
guestfs___add_dummy_appliance_drive (guestfs_h *g)
{
  struct drive *drv;

  drv = create_drive_struct (g, "", 0, NULL, NULL, NULL, NULL, 0);
  add_drive_to_handle (g, drv);
}

void
guestfs___free_drives (guestfs_h *g)
{
  struct drive *drv;
  size_t i;

  ITER_DRIVES (g, i, drv) {
    free_drive_struct (drv);
  }

  free (g->drives);

  g->drives = NULL;
  g->nr_drives = 0;
}

static void
free_drive_struct (struct drive *drv)
{
  free (drv->path);
  free (drv->format);
  free (drv->iface);
  free (drv->name);
  free (drv->disk_label);
  if (drv->priv && drv->free_priv)
    drv->free_priv (drv->priv);
  free (drv);
}

/* cache=none improves reliability in the event of a host crash.
 *
 * However this option causes qemu to try to open the file with
 * O_DIRECT.  This fails on some filesystem types (notably tmpfs).
 * So we check if we can open the file with or without O_DIRECT,
 * and use cache=none (or not) accordingly.
 *
 * Notes:
 *
 * (1) In qemu, cache=none and cache=off are identical.
 *
 * (2) cache=none does not disable caching entirely.  qemu still
 * maintains a writeback cache internally, which will be written out
 * when qemu is killed (with SIGTERM).  It disables *host kernel*
 * caching by using O_DIRECT.  To disable caching entirely in kernel
 * and qemu we would need to use cache=directsync but there is a
 * performance penalty for that.
 *
 * (3) This function is only called on the !readonly path.  We must
 * try to open with O_RDWR to test that the file is readable and
 * writable here.
 */
static int
test_cache_none (guestfs_h *g, const char *filename)
{
  int fd = open (filename, O_RDWR|O_DIRECT);
  if (fd >= 0) {
    close (fd);
    return 1;
  }

  fd = open (filename, O_RDWR);
  if (fd >= 0) {
    close (fd);
    return 0;
  }

  perrorf (g, "%s", filename);
  return -1;
}

/* Check string parameter matches ^[-_[:alnum:]]+$ (in C locale). */
static int
valid_format_iface (const char *str)
{
  size_t len = strlen (str);

  if (len == 0)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (c != '-' && c != '_' && !c_isalnum (c))
      return 0;
  }
  return 1;
}

/* Check the disk label is reasonable.  It can't contain certain
 * characters, eg. '/', ','.  However be stricter here and ensure it's
 * just alphabetic and <= 20 characters in length.
 */
static int
valid_disk_label (const char *str)
{
  size_t len = strlen (str);

  if (len == 0 || len > 20)
    return 0;

  while (len > 0) {
    char c = *str++;
    len--;
    if (!c_isalpha (c))
      return 0;
  }
  return 1;
}

/* The low-level function that adds a drive. */
static int
add_drive (guestfs_h *g, struct drive *drv)
{
  size_t i, drv_index;

  if (g->state == CONFIG) {
    /* Not hotplugging, so just add it to the handle. */
    add_drive_to_handle (g, drv);
    return 0;
  }

  /* ... else, hotplugging case. */
  if (!g->attach_ops || !g->attach_ops->hot_add_drive) {
    error (g, _("the current attach-method does not support hotplugging drives"));
    return -1;
  }

  if (!drv->disk_label) {
    error (g, _("'label' is required when hotplugging drives"));
    return -1;
  }

  /* Get the first free index, or add it at the end. */
  drv_index = g->nr_drives;
  for (i = 0; i < g->nr_drives; ++i)
    if (g->drives[i] == NULL)
      drv_index = i;

  /* Hot-add the drive. */
  if (g->attach_ops->hot_add_drive (g, drv, drv_index) == -1)
    return -1;

  add_drive_to_handle_at (g, drv, drv_index);

  /* Call into the appliance to wait for the new drive to appear. */
  if (guestfs_internal_hot_add_drive (g, drv->disk_label) == -1)
    return -1;

  return 0;
}

/* Traditionally you have been able to use /dev/null as a filename, as
 * many times as you like.  Ancient KVM (RHEL 5) cannot handle adding
 * /dev/null readonly.  qemu 1.2 + virtio-scsi segfaults when you use
 * any zero-sized file including /dev/null.  Therefore, we replace
 * /dev/null with a non-zero sized temporary file.  This shouldn't
 * make any difference since users are not supposed to try and access
 * a null drive.
 */
static int
add_null_drive (guestfs_h *g, int readonly, const char *format,
                const char *iface, const char *name, const char *disk_label)
{
  char *tmpfile = NULL;
  int fd = -1, r;
  struct drive *drv;

  if (format && STRNEQ (format, "raw")) {
    error (g, _("for device '/dev/null', format must be 'raw'"));
    return -1;
  }

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return -1;

  /* Because we create a special file, there is no point forcing qemu
   * to create an overlay as well.  Save time by setting readonly = 0.
   */
  readonly = 0;

  tmpfile = safe_asprintf (g, "%s/devnull%d", g->tmpdir, ++g->unique);
  fd = open (tmpfile, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    goto err;
  }
  if (ftruncate (fd, 4096) == -1) {
    perrorf (g, "truncate: %s", tmpfile);
    goto err;
  }
  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    goto err;
  }

  drv = create_drive_struct (g, tmpfile, readonly, format, iface, name, disk_label, 0);
  r = add_drive (g, drv);
  free (tmpfile);
  if (r == -1) {
    free_drive_struct (drv);
    return -1;
  }

  return 0;

 err:
  free (tmpfile);
  if (fd >= 0)
    close (fd);
  return -1;
}

int
guestfs__add_drive_opts (guestfs_h *g, const char *filename,
                         const struct guestfs_add_drive_opts_argv *optargs)
{
  int readonly;
  const char *format;
  const char *iface;
  const char *name;
  const char *disk_label;
  int use_cache_none;
  struct drive *drv;

  if (strchr (filename, ':') != NULL) {
    error (g, _("filename cannot contain ':' (colon) character. "
                "This is a limitation of qemu."));
    return -1;
  }

  readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
             ? optargs->readonly : 0;
  format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
           ? optargs->format : NULL;
  iface = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
          ? optargs->iface : NULL;
  name = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK
         ? optargs->name : NULL;
  disk_label = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_LABEL_BITMASK
         ? optargs->label : NULL;

  if (format && !valid_format_iface (format)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "format");
    return -1;
  }
  if (iface && !valid_format_iface (iface)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "iface");
    return -1;
  }
  if (disk_label && !valid_disk_label (disk_label)) {
    error (g, _("label parameter is empty, too long, or contains disallowed characters"));
    return -1;
  }

  if (STREQ (filename, "/dev/null"))
    return add_null_drive (g, readonly, format, iface, name, disk_label);

  /* For writable files, see if we can use cache=none.  This also
   * checks for the existence of the file.  For readonly we have
   * to do the check explicitly.
   */
  use_cache_none = readonly ? 0 : test_cache_none (g, filename);
  if (use_cache_none == -1)
    return -1;

  if (readonly) {
    if (access (filename, R_OK) == -1) {
      perrorf (g, "%s", filename);
      return -1;
    }
  }

  drv = create_drive_struct (g, filename, readonly, format, iface, name, disk_label,
                             use_cache_none);
  if (add_drive (g, drv) == -1) {
    free_drive_struct (drv);
    return -1;
  }

  return 0;
}

int
guestfs__add_drive_ro (guestfs_h *g, const char *filename)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .readonly = 1,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_with_if (guestfs_h *g, const char *filename,
                            const char *iface)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK,
    .iface = iface,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *iface)
{
  const struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
             | GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .iface = iface,
    .readonly = 1,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_cdrom (guestfs_h *g, const char *filename)
{
  if (strchr (filename, ':') != NULL) {
    error (g, _("filename cannot contain ':' (colon) character. "
                "This is a limitation of qemu."));
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  return guestfs__config (g, "-cdrom", filename);
}

/* Depending on whether we are hotplugging or not, this function
 * does slightly different things: If not hotplugging, then the
 * drive just disappears as if it had never been added.  The later
 * drives "move up" to fill the space.  When hotplugging we have to
 * do some complex stuff, and we usually end up leaving an empty
 * (NULL) slot in the g->drives vector.
 */
int
guestfs__remove_drive (guestfs_h *g, const char *label)
{
  size_t i;
  struct drive *drv;

  ITER_DRIVES (g, i, drv) {
    if (drv->disk_label && STREQ (label, drv->disk_label))
      goto found;
  }
  error (g, _("disk with label '%s' not found"), label);
  return -1;

 found:
  if (g->state == CONFIG) {     /* Not hotplugging. */
    free_drive_struct (drv);

    g->nr_drives--;
    for (; i < g->nr_drives; ++i)
      g->drives[i] = g->drives[i+1];

    return 0;
  }
  else {                        /* Hotplugging. */
    if (!g->attach_ops || !g->attach_ops->hot_remove_drive) {
      error (g, _("the current attach-method does not support hotplugging drives"));
      return -1;
    }

    if (guestfs_internal_hot_remove_drive_precheck (g, label) == -1)
      return -1;

    if (g->attach_ops->hot_remove_drive (g, drv, i) == -1)
      return -1;

    free_drive_struct (drv);
    g->drives[i] = NULL;
    if (i == g->nr_drives-1)
      g->nr_drives--;

    if (guestfs_internal_hot_remove_drive (g, label) == -1)
      return -1;

    return 0;
  }
}

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

/* Internal command to return the list of drives. */
char **
guestfs__debug_drives (guestfs_h *g)
{
  size_t i, count;
  char **ret;
  struct drive *drv;

  count = 0;
  ITER_DRIVES (g, i, drv) {
    count++;
  }

  ret = safe_malloc (g, sizeof (char *) * (count + 1));

  count = 0;
  ITER_DRIVES (g, i, drv) {
    ret[count++] =
      safe_asprintf (g, "path=%s%s%s%s%s%s%s%s%s",
                     drv->path,
                     drv->readonly ? " readonly" : "",
                     drv->format ? " format=" : "",
                     drv->format ? : "",
                     drv->iface ? " iface=" : "",
                     drv->iface ? : "",
                     drv->name ? " name=" : "",
                     drv->name ? : "",
                     drv->use_cache_none ? " cache=none" : "");
  }

  ret[count] = NULL;

  return ret;                   /* caller frees */
}

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
  char *term = getenv ("TERM");
  char *ret;
  bool tcg = flags & APPLIANCE_COMMAND_LINE_IS_TCG;
  char lpj_s[64] = "";

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
     " root=%s"                 /* root (appliance_dev) */
     " %s"                      /* selinux */
     "%s"                       /* verbose */
     " TERM=%s"                 /* TERM environment variable */
     "%s%s",                    /* append */
     lpj_s,
     appliance_dev,
     g->selinux ? "selinux=1 enforcing=0" : "selinux=0",
     g->verbose ? " guestfs_verbose=1" : "",
     term ? term : "linux",
     g->append ? " " : "", g->append ? g->append : "");

  return ret;
}
