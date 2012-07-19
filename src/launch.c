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
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

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

int
guestfs__add_drive_opts (guestfs_h *g, const char *filename,
                         const struct guestfs_add_drive_opts_argv *optargs)
{
  int readonly;
  char *format;
  char *iface;
  char *name;
  int use_cache_none;
  int is_null;

  if (strchr (filename, ':') != NULL) {
    error (g, _("filename cannot contain ':' (colon) character. "
                "This is a limitation of qemu."));
    return -1;
  }

  readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
             ? optargs->readonly : 0;
  format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
           ? safe_strdup (g, optargs->format) : NULL;
  iface = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
          ? safe_strdup (g, optargs->iface) : NULL;
  name = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK
          ? safe_strdup (g, optargs->name) : NULL;

  if (format && !valid_format_iface (format)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "format");
    goto err_out;
  }
  if (iface && !valid_format_iface (iface)) {
    error (g, _("%s parameter is empty or contains disallowed characters"),
           "iface");
    goto err_out;
  }

  /* Traditionally you have been able to use /dev/null as a filename,
   * as many times as you like.  Treat this as a special case, because
   * old versions of qemu have some problems.
   */
  is_null = STREQ (filename, "/dev/null");
  if (is_null) {
    if (format && STRNEQ (format, "raw")) {
      error (g, _("for device '/dev/null', format must be 'raw'"));
      goto err_out;
    }
    /* Ancient KVM (RHEL 5) cannot handle the case where we try to add
     * a snapshot on top of /dev/null.  Modern qemu can handle it OK,
     * but the device size is still 0, so it shouldn't matter whether
     * or not this is readonly.
     */
    readonly = 0;
  }

  /* For writable files, see if we can use cache=none.  This also
   * checks for the existence of the file.  For readonly we have
   * to do the check explicitly.
   */
  use_cache_none = readonly ? 0 : test_cache_none (g, filename);
  if (use_cache_none == -1)
    goto err_out;

  if (readonly) {
    if (access (filename, R_OK) == -1) {
      perrorf (g, "%s", filename);
      goto err_out;
    }
  }

  struct drive **i = &(g->drives);
  while (*i != NULL) i = &((*i)->next);

  *i = safe_malloc (g, sizeof (struct drive));
  (*i)->next = NULL;
  (*i)->path = safe_strdup (g, filename);
  (*i)->readonly = readonly;
  (*i)->format = format;
  (*i)->iface = iface;
  (*i)->name = name;
  (*i)->use_cache_none = use_cache_none;

  return 0;

err_out:
  free (format);
  free (iface);
  free (name);
  return -1;
}

int
guestfs__add_drive_ro (guestfs_h *g, const char *filename)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK,
    .readonly = 1,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_with_if (guestfs_h *g, const char *filename,
                            const char *iface)
{
  struct guestfs_add_drive_opts_argv optargs = {
    .bitmask = GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK,
    .iface = iface,
  };

  return guestfs__add_drive_opts (g, filename, &optargs);
}

int
guestfs__add_drive_ro_with_if (guestfs_h *g, const char *filename,
                               const char *iface)
{
  struct guestfs_add_drive_opts_argv optargs = {
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
guestfs__launch (guestfs_h *g)
{
  /* Configured? */
  if (g->state != CONFIG) {
    error (g, _("the libguestfs handle has already been launched"));
    return -1;
  }

  TRACE0 (launch_start);

  /* Make the temporary directory. */
  if (!g->tmpdir) {
    TMP_TEMPLATE_ON_STACK (dir_template);
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
      return -1;
    }
  }

  /* Allow anyone to read the temporary directory.  The socket in this
   * directory won't be readable but anyone can see it exists if they
   * want. (RHBZ#610880).
   */
  if (chmod (g->tmpdir, 0755) == -1)
    warning (g, "chmod: %s: %m (ignored)", g->tmpdir);

  /* Launch the appliance or attach to an existing daemon. */
  switch (g->attach_method) {
  case ATTACH_METHOD_APPLIANCE:
    return guestfs___launch_appliance (g);

  case ATTACH_METHOD_UNIX:
    return guestfs___launch_unix (g, g->attach_method_arg);

  default:
    abort ();
  }
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
