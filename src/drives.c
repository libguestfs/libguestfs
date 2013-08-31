/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/* Drives added are stored in an array in the handle.  Code here
 * manages that array and the individual 'struct drive' data.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Create and free the 'drive' struct. */
static struct drive *
create_drive_struct (guestfs_h *g, const char *path,
                     bool readonly, const char *format,
                     const char *iface, const char *name,
                     const char *disk_label, const char *cachemode)
{
  struct drive *drv = safe_malloc (g, sizeof (struct drive));

  drv->path = safe_strdup (g, path);
  drv->readonly = readonly;
  drv->format = format ? safe_strdup (g, format) : NULL;
  drv->iface = iface ? safe_strdup (g, iface) : NULL;
  drv->name = name ? safe_strdup (g, name) : NULL;
  drv->disk_label = disk_label ? safe_strdup (g, disk_label) : NULL;
  drv->cachemode = cachemode ? safe_strdup (g, cachemode) : NULL;
  drv->priv = drv->free_priv = NULL;

  return drv;
}

/* Traditionally you have been able to use /dev/null as a filename, as
 * many times as you like.  Ancient KVM (RHEL 5) cannot handle adding
 * /dev/null readonly.  qemu 1.2 + virtio-scsi segfaults when you use
 * any zero-sized file including /dev/null.  Therefore, we replace
 * /dev/null with a non-zero sized temporary file.  This shouldn't
 * make any difference since users are not supposed to try and access
 * a null drive.
 */
static struct drive *
create_null_drive_struct (guestfs_h *g, bool readonly, const char *format,
                          const char *iface, const char *name,
                          const char *disk_label)
{
  CLEANUP_FREE char *tmpfile = NULL;
  int fd = -1;

  if (format && STRNEQ (format, "raw")) {
    error (g, _("for device '/dev/null', format must be 'raw'"));
    return NULL;
  }

  if (guestfs___lazy_make_tmpdir (g) == -1)
    return NULL;

  /* Because we create a special file, there is no point forcing qemu
   * to create an overlay as well.  Save time by setting readonly = false.
   */
  readonly = false;

  tmpfile = safe_asprintf (g, "%s/devnull%d", g->tmpdir, ++g->unique);
  fd = open (tmpfile, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    perrorf (g, "open: %s", tmpfile);
    close (fd);
    return NULL;
  }
  if (ftruncate (fd, 4096) == -1) {
    perrorf (g, "truncate: %s", tmpfile);
    close (fd);
    return NULL;
  }
  if (close (fd) == -1) {
    perrorf (g, "close: %s", tmpfile);
    return NULL;
  }

  return create_drive_struct (g, tmpfile, readonly, format, iface, name,
                              disk_label, NULL);
}

static struct drive *
create_dummy_drive_struct (guestfs_h *g)
{
  /* A special drive struct that is used as a dummy slot for the appliance. */
  return create_drive_struct (g, "", 0, NULL, NULL, NULL, NULL, 0);
}

static void
free_drive_struct (struct drive *drv)
{
  free (drv->path);
  free (drv->format);
  free (drv->iface);
  free (drv->name);
  free (drv->disk_label);
  free (drv->cachemode);
  if (drv->priv && drv->free_priv)
    drv->free_priv (drv->priv);
  free (drv);
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

/* Called during launch to add a dummy slot to g->drives. */
void
guestfs___add_dummy_appliance_drive (guestfs_h *g)
{
  struct drive *drv;

  drv = create_dummy_drive_struct (g);
  add_drive_to_handle (g, drv);
}

/* Free up all the drives in the handle. */
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

int
guestfs__add_drive_opts (guestfs_h *g, const char *filename,
                         const struct guestfs_add_drive_opts_argv *optargs)
{
  bool readonly;
  const char *format;
  const char *iface;
  const char *name;
  const char *disk_label;
  const char *cachemode;
  struct drive *drv;

  if (strchr (filename, ':') != NULL) {
    error (g, _("filename cannot contain ':' (colon) character. "
                "This is a limitation of qemu."));
    return -1;
  }

  readonly = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_READONLY_BITMASK
             ? optargs->readonly : false;
  format = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_FORMAT_BITMASK
           ? optargs->format : NULL;
  iface = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_IFACE_BITMASK
          ? optargs->iface : NULL;
  name = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_NAME_BITMASK
         ? optargs->name : NULL;
  disk_label = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_LABEL_BITMASK
         ? optargs->label : NULL;
  cachemode = optargs->bitmask & GUESTFS_ADD_DRIVE_OPTS_CACHEMODE_BITMASK
    ? optargs->cachemode : NULL;

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
  if (cachemode &&
      !(STREQ (cachemode, "writeback") || STREQ (cachemode, "unsafe"))) {
    error (g, _("cachemode parameter must be 'writeback' (default) or 'unsafe'"));
    return -1;
  }

  if (STREQ (filename, "/dev/null"))
    drv = create_null_drive_struct (g, readonly, format, iface, name,
                                    disk_label);
  else {
    /* We have to check for the existence of the file since that's
     * required by the API.
     */
    if (access (filename, R_OK) == -1) {
      perrorf (g, "%s", filename);
      return -1;
    }

    drv = create_drive_struct (g, filename, readonly, format, iface, name,
                               disk_label, cachemode);
  }

  if (drv == NULL)
    return -1;

  /* Add the drive. */
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
    .readonly = true,
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
    .readonly = true,
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

/* Checkpoint and roll back drives, so that groups of drives can be
 * added atomicly.  Only used by guestfs_add_domain.
 */
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
      safe_asprintf (g, "path=%s%s%s%s%s%s%s%s%s%s",
                     drv->path,
                     drv->readonly ? " readonly" : "",
                     drv->format ? " format=" : "",
                     drv->format ? : "",
                     drv->iface ? " iface=" : "",
                     drv->iface ? : "",
                     drv->name ? " name=" : "",
                     drv->name ? : "",
                     drv->cachemode ? " cache=" : "",
                     drv->cachemode ? : "");
  }

  ret[count] = NULL;

  return ret;                   /* caller frees */
}
