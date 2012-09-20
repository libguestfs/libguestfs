/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

struct drive **
guestfs___checkpoint_drives (guestfs_h *g)
{
  struct drive **i = &g->drives;
  while (*i != NULL) i = &((*i)->next);
  return i;
}

void
guestfs___rollback_drives (guestfs_h *g, struct drive **i)
{
  guestfs___free_drives(i);
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

static void
add_drive (guestfs_h *g, const char *path,
           int readonly, const char *format,
           const char *iface, const char *name,
           int use_cache_none)
{
  struct drive **drv = &(g->drives);

  while (*drv != NULL)
    drv = &((*drv)->next);

  *drv = safe_malloc (g, sizeof (struct drive));
  (*drv)->next = NULL;
  (*drv)->path = safe_strdup (g, path);
  (*drv)->readonly = readonly;
  (*drv)->format = format ? safe_strdup (g, format) : NULL;
  (*drv)->iface = iface ? safe_strdup (g, iface) : NULL;
  (*drv)->name = name ? safe_strdup (g, name) : NULL;
  (*drv)->use_cache_none = use_cache_none;
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
                const char *iface, const char *name)
{
  char *tmpfile = NULL;
  int fd = -1;

  if (format && STRNEQ (format, "raw")) {
    error (g, _("for device '/dev/null', format must be 'raw'"));
    return -1;
  }

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return -1;

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

  add_drive (g, tmpfile, readonly, format, iface, name, 0);
  free (tmpfile);

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
  int use_cache_none;

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

  if (STREQ (filename, "/dev/null"))
    return add_null_drive (g, readonly, format, iface, name);

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

  add_drive (g, filename, readonly, format, iface, name, use_cache_none);
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
  qp->qemu_value = safe_strdup (g, qemu_value);

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

  for (count = 0, drv = g->drives; drv; count++, drv = drv->next)
    ;

  ret = safe_malloc (g, sizeof (char *) * (count + 1));

  for (i = 0, drv = g->drives; drv; i++, drv = drv->next) {
    ret[i] = safe_asprintf (g, "path=%s%s%s%s%s%s%s%s%s",
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

/* Return the location of the tmpdir (eg. "/tmp") and allow users
 * to override it at runtime using $TMPDIR.
 * http://www.pathname.com/fhs/pub/fhs-2.3.html#TMPTEMPORARYFILES
 */
const char *
guestfs_tmpdir (void)
{
  const char *tmpdir;

#ifdef P_tmpdir
  tmpdir = P_tmpdir;
#else
  tmpdir = "/tmp";
#endif

  const char *t = getenv ("TMPDIR");
  if (t) tmpdir = t;

  return tmpdir;
}

/* Return the location of the persistent tmpdir (eg. "/var/tmp") and
 * allow users to override it at runtime using $TMPDIR.
 * http://www.pathname.com/fhs/pub/fhs-2.3.html#VARTMPTEMPORARYFILESPRESERVEDBETWEE
 */
const char *
guestfs___persistent_tmpdir (void)
{
  const char *tmpdir;

  tmpdir = "/var/tmp";

  const char *t = getenv ("TMPDIR");
  if (t) tmpdir = t;

  return tmpdir;
}

/* The g->tmpdir (per-handle temporary directory) is not created when
 * the handle is created.  Instead we create it lazily before the
 * first time it is used, or during launch.
 */
int
guestfs___lazy_make_tmpdir (guestfs_h *g)
{
  if (!g->tmpdir) {
    TMP_TEMPLATE_ON_STACK (dir_template);
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
      return -1;
    }
  }
  return 0;
}

/* Recursively remove a temporary directory.  If removal fails, just
 * return (it's a temporary directory so it'll eventually be cleaned
 * up by a temp cleaner).  This is done using "rm -rf" because that's
 * simpler and safer, but we have to exec to ensure that paths don't
 * need to be quoted.
 */
void
guestfs___remove_tmpdir (const char *dir)
{
  pid_t pid = fork ();

  if (pid == -1) {
    perror ("remove tmpdir: fork");
    return;
  }
  if (pid == 0) {
    execlp ("rm", "rm", "-rf", dir, NULL);
    perror ("remove tmpdir: exec: rm");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  if (waitpid (pid, NULL, 0) == -1) {
    perror ("remove tmpdir: waitpid");
    return;
  }
}

int
guestfs__get_pid (guestfs_h *g)
{
  if (g->state != READY || g->attach_ops == NULL) {
    error (g, _("get-pid can only be called after launch"));
    return -1;
  }

  if (g->attach_ops->get_pid == NULL) {
    guestfs_error_errno (g, ENOTSUP,
                         _("the current attach-method does not support 'get-pid'"));
    return -1;
  }

  return g->attach_ops->get_pid (g);
}

/* Maximum number of disks. */
int
guestfs__max_disks (guestfs_h *g)
{
  const struct attach_ops *attach_ops = get_attach_ops (g);

  if (attach_ops->max_disks == NULL) {
    guestfs_error_errno (g, ENOTSUP,
                         _("the current attach-method does not allow max disks to be queried"));
    return -1;
  }

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
