/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * F<lib/launch-direct.c>, F<lib/launch-libvirt.c> etc, so this file
 * mostly passes calls through to the current backend.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <assert.h>
#include <libintl.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"
#include "structs-cleanups.h"

static struct backend {
  struct backend *next;
  const char *name;
  const struct backend_ops *ops;
} *backends = NULL;

int
guestfs_impl_launch (guestfs_h *g)
{
  int r;

  /* Configured? */
  if (g->state != CONFIG) {
    error (g, _("the libguestfs handle has already been launched"));
    return -1;
  }

  /* Too many drives?
   *
   * Some backends such as ‘unix:’ don't allow us to query max_disks.
   * Don't fail in this case.
   */
  guestfs_push_error_handler (g, NULL, NULL);
  r = guestfs_max_disks (g);
  guestfs_pop_error_handler (g);
  if (r >= 0 && g->nr_drives > (size_t) r) {
    error (g, _("too many drives have been added, the current backend only supports %d drives"), r);
    return -1;
  }

  /* Start the clock ... */
  gettimeofday (&g->launch_t, NULL);

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
 * There is a hack in F<lib/proto.c> to make this work.
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

/**
 * Unblock the C<SIGTERM> signal.  Call this after L<fork(2)> so that
 * the parent process can send C<SIGTERM> to the child process in case
 * C<SIGTERM> is blocked.  See L<https://bugzilla.redhat.com/1460338>.
 */
void
guestfs_int_unblock_sigterm (void)
{
  sigset_t sigset;

  sigemptyset (&sigset);
  sigaddset (&sigset, SIGTERM);
  sigprocmask (SIG_UNBLOCK, &sigset, NULL);
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
                   _("the current backend does not support ‘get-pid’"));

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
    error (g, _("parameter ‘%s’ isn't allowed"), hv_param);
    return -1;
  }

  hp = safe_malloc (g, sizeof *hp);
  hp->hv_param = safe_strdup (g, hv_param);
  hp->hv_value = hv_value ? safe_strdup (g, hv_value) : NULL;

  hp->next = g->hv_params;
  g->hv_params = hp;

  return 0;
}

/**
 * Create the path for a socket with the selected filename in the
 * tmpdir.
 */
int
guestfs_int_create_socketname (guestfs_h *g, const char *filename,
                               char (*sockpath)[UNIX_PATH_MAX])
{
  int r;

  if (guestfs_int_lazy_make_sockdir (g) == -1)
    return -1;

  r = snprintf (*sockpath, UNIX_PATH_MAX, "%s/%s", g->sockdir, filename);
  if (r >= UNIX_PATH_MAX) {
    error (g, _("socket path too long: %s/%s"), g->sockdir, filename);
    return -1;
  }
  if (r < 0) {
    perrorf (g, _("%s"), g->sockdir);
    return -1;
  }

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
#ifdef HAVE_LIBVIRT
  guestfs_int_init_libvirt_backend,
#endif
};
