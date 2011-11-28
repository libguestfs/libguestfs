/* libguestfs
 * Copyright (C) 2011 Red Hat Inc.
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
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int read_whole_file (guestfs_h *g, const char *filename, char **data_r, size_t *size_r);

/* All these icon_*() functions return the same way.  One of:
 *
 *   ret == NULL:
 *     An error occurred.  Error has been set in the handle.  The caller
 *     should return NULL immediately.
 *
 *   ret == NOT_FOUND:
 *     Not an error, but no icon was found.  'ret' is just a dummy value
 *     which should be ignored (do not free it!)
 *
 *   ret == ordinary pointer:
 *     An icon was found.  'ret' points to the icon buffer, and *size_r
 *     is the size.
 */
static char *icon_favicon (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_fedora (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_rhel (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_debian (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_ubuntu (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_mageia (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_opensuse (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
static char *icon_windows (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);

/* Dummy static object. */
static char *NOT_FOUND = (char *) "not_found";

/* For the unexpected legal consequences of this function, see:
 * http://lists.fedoraproject.org/pipermail/legal/2011-April/001615.html
 *
 * Returns an RBufferOut, so the length of the returned buffer is
 * returned in *size_r.
 *
 * Check optargs for the optional argument.
 */
char *
guestfs__inspect_get_icon (guestfs_h *g, const char *root, size_t *size_r,
                           const struct guestfs_inspect_get_icon_argv *optargs)
{
  struct inspect_fs *fs;
  char *r = NOT_FOUND;
  int favicon, highquality;
  size_t size;

  fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  /* Get optargs, or defaults. */
  favicon =
    optargs->bitmask & GUESTFS_INSPECT_GET_ICON_FAVICON_BITMASK ?
    optargs->favicon : 1;

  highquality =
    optargs->bitmask & GUESTFS_INSPECT_GET_ICON_HIGHQUALITY_BITMASK ?
    optargs->highquality : 0;

  /* Favicons are never high quality, so ... */
  if (highquality)
    favicon = 0;

  /* Try looking for a favicon first. */
  if (favicon) {
    r = icon_favicon (g, fs, &size);
    if (!r)
      return NULL;

    if (r != NOT_FOUND) {
      /* try_favicon succeeded in finding a favicon. */
      *size_r = size;
      return r;
    }
  }

  /* Favicon failed, so let's try a method based on the detected operating
   * system.
   */
  switch (fs->type) {
  case OS_TYPE_LINUX:
  case OS_TYPE_HURD:
    switch (fs->distro) {
    case OS_DISTRO_FEDORA:
      r = icon_fedora (g, fs, &size);
      break;

    case OS_DISTRO_RHEL:
    case OS_DISTRO_REDHAT_BASED:
    case OS_DISTRO_CENTOS:
    case OS_DISTRO_SCIENTIFIC_LINUX:
      r = icon_rhel (g, fs, &size);
      break;

    case OS_DISTRO_DEBIAN:
      r = icon_debian (g, fs, &size);
      break;

    case OS_DISTRO_UBUNTU:
      r = icon_ubuntu (g, fs, &size);
      break;

    case OS_DISTRO_MAGEIA:
      r = icon_mageia (g, fs, &size);
      break;

    case OS_DISTRO_OPENSUSE:
      r = icon_opensuse(g, fs, &size);
      break;

      /* These are just to keep gcc warnings happy. */
    case OS_DISTRO_ARCHLINUX:
    case OS_DISTRO_GENTOO:
    case OS_DISTRO_LINUX_MINT:
    case OS_DISTRO_MANDRIVA:
    case OS_DISTRO_MEEGO:
    case OS_DISTRO_PARDUS:
    case OS_DISTRO_SLACKWARE:
    case OS_DISTRO_TTYLINUX:
    case OS_DISTRO_WINDOWS:
    case OS_DISTRO_UNKNOWN:
    default: ;
    }
    break;

  case OS_TYPE_WINDOWS:
    /* We don't know how to get high quality icons from a Windows guest,
     * so disable this if high quality was specified.
     */
    if (!highquality)
      r = icon_windows (g, fs, &size);
    break;

  case OS_TYPE_FREEBSD:
  case OS_TYPE_NETBSD:
  case OS_TYPE_UNKNOWN:
  default: ;
  }

  if (r == NOT_FOUND) {
    /* Not found, but not an error.  So return the special zero-length
     * buffer.  Use malloc(1) here to ensure that malloc won't return
     * NULL.
     */
    r = safe_malloc (g, 1);
    size = 0;
  }

  *size_r = size;
  return r;
}

/* Check that the named file 'filename' is a PNG file and is reasonable.
 * If it is, download and return it.
 */
static char *
get_png (guestfs_h *g, struct inspect_fs *fs, const char *filename,
         size_t *size_r, size_t max_size)
{
  char *ret = NOT_FOUND;
  char *type = NULL;
  char *local = NULL;
  int r, w, h;

  r = guestfs_exists (g, filename);
  if (r == -1) {
    ret = NULL; /* a real error */
    goto out;
  }
  if (r == 0) goto out;

  /* Check the file type and geometry. */
  type = guestfs_file (g, filename);
  if (!type) goto out;

  if (!STRPREFIX (type, "PNG image data, ")) goto out;
  if (sscanf (&type[16], "%d x %d", &w, &h) != 2) goto out;
  if (w < 16 || h < 16 || w > 1024 || h > 1024) goto out;

  /* Define a maximum reasonable size based on the geometry.  This
   * also limits the maximum we allocate below to around 4 MB.
   */
  if (max_size == 0)
    max_size = 4 * w * h;

  local = guestfs___download_to_tmp (g, fs, filename, "icon", max_size);
  if (!local) goto out;

  /* Successfully passed checks and downloaded.  Read it into memory. */
  if (read_whole_file (g, local, &ret, size_r) == -1) {
    ret = NULL;
    goto out;
  }

 out:
  free (local);
  free (type);

  return ret;
}

/* Return /etc/favicon.png (or \etc\favicon.png) if it exists and if
 * it has a reasonable size and format.
 */
static char *
icon_favicon (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  char *ret;
  char *filename = safe_strdup (g, "/etc/favicon.png");

  if (fs->type == OS_TYPE_WINDOWS) {
    char *f = guestfs___case_sensitive_path_silently (g, filename);
    if (f) {
      free (filename);
      filename = f;
    }
  }

  ret = get_png (g, fs, filename, size_r, 0);
  free (filename);
  return ret;
}

/* Return FEDORA_ICON.  I checked that this exists on at least Fedora 6
 * through 16.
 */
#define FEDORA_ICON "/usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png"

static char *
icon_fedora (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  return get_png (g, fs, FEDORA_ICON, size_r, 0);
}

/* RHEL 3, 4:
 * /usr/share/pixmaps/redhat/shadowman-transparent.png is a 517x515
 * PNG with alpha channel, around 64K in size.
 *
 * RHEL 5, 6:
 * As above, but the file has been optimized to about 16K.
 *
 * Conveniently the RHEL clones also have the same file with the
 * same name, but containing their own logos.  Sense prevails!
 */
#define SHADOWMAN_ICON "/usr/share/pixmaps/redhat/shadowman-transparent.png"

static char *
icon_rhel (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  size_t max_size = 0;

  if (fs->distro == OS_DISTRO_RHEL) {
    if (fs->major_version <= 4)
      max_size = 66000;
    else
      max_size = 17000;
  }

  return get_png (g, fs, SHADOWMAN_ICON, size_r, max_size);
}

#define DEBIAN_ICON "/usr/share/pixmaps/debian-logo.png"

static char *
icon_debian (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  return get_png (g, fs, DEBIAN_ICON, size_r, 2048);
}

#define UBUNTU_ICON "/usr/share/icons/gnome/24x24/places/ubuntu-logo.png"

static char *
icon_ubuntu (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  return get_png (g, fs, UBUNTU_ICON, size_r, 2048);
}

#define MAGEIA_ICON "/usr/share/icons/mageia.png"

static char *
icon_mageia (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  return get_png (g, fs, MAGEIA_ICON, size_r, 2048);
}

#define OPENSUSE_ICON "/usr/share/icons/hicolor/24x24/apps/distributor.png"

static char *
icon_opensuse (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  return get_png (g, fs, OPENSUSE_ICON, size_r, 2048);
}

/* Windows, as usual, has to be much more complicated and stupid than
 * anything else.
 *
 * We have to download %systemroot%\explorer.exe and use a special
 * program called 'wrestool' to extract the icons from this file.  For
 * each version of Windows, the icon we want is in a different place.
 * The icon is in a stupid format (BMP), and in some cases multiple
 * icons are in a single BMP file so we have to do some manipulation
 * on the file.
 *
 * XXX I've only bothered with this nonsense for a few versions of
 * Windows that I have handy.  Please send patches to support other
 * versions.
 */

static char *
icon_windows_xp (guestfs_h *g, struct inspect_fs *fs, const char *explorer,
                 size_t *size_r)
{
  char *ret;
  char *pngfile;
  char *cmd;
  int r;

  pngfile = safe_asprintf (g, "%s/windows-xp-icon.png", g->tmpdir);

  cmd = safe_asprintf (g,
                       "wrestool -x --type=2 --name=143 %s | "
                       "bmptopnm | pnmtopng > %s",
          explorer, pngfile);
  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0) {
    debug (g, "external command failed: %s", cmd);
    free (cmd);
    free (pngfile);
    return NOT_FOUND;
  }

  free (cmd);

  if (read_whole_file (g, pngfile, &ret, size_r) == -1) {
    free (pngfile);
    return NULL;
  }

  free (pngfile);

  return ret;
}

static char *
icon_windows_7 (guestfs_h *g, struct inspect_fs *fs, const char *explorer,
                size_t *size_r)
{
  char *ret;
  char *pngfile;
  char *cmd;
  int r;

  pngfile = safe_asprintf (g, "%s/windows-7-icon.png", g->tmpdir);

  cmd = safe_asprintf (g,
                       "wrestool -x --type=2 --name=6801 %s | "
                       "bmptopnm | pamcut -bottom 54 | pnmtopng > %s",
          explorer, pngfile);
  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0) {
    debug (g, "external command failed: %s", cmd);
    free (cmd);
    free (pngfile);
    return NOT_FOUND;
  }

  free (cmd);

  if (read_whole_file (g, pngfile, &ret, size_r) == -1) {
    free (pngfile);
    return NULL;
  }

  free (pngfile);

  return ret;
}

static char *
icon_windows (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  char *(*fn) (guestfs_h *g, struct inspect_fs *fs, const char *explorer,
               size_t *size_r);
  char *filename1, *filename2, *filename3;
  char *ret;

  /* Windows XP. */
  if (fs->major_version == 5 && fs->minor_version == 1)
    fn = icon_windows_xp;

  /* Windows 7 */
  else if (fs->major_version == 6 && fs->minor_version == 1)
    fn = icon_windows_7;

  /* Not (yet) a supported version of Windows. */
  else return NOT_FOUND;

  if (fs->windows_systemroot == NULL)
    return NOT_FOUND;

  /* Download %systemroot%\explorer.exe */
  filename1 = safe_asprintf (g, "%s/explorer.exe", fs->windows_systemroot);
  filename2 = guestfs___case_sensitive_path_silently (g, filename1);
  free (filename1);
  if (filename2 == NULL)
    return NOT_FOUND;

  filename3 = guestfs___download_to_tmp (g, fs, filename2, "explorer",
                                         MAX_WINDOWS_EXPLORER_SIZE);
  free (filename2);
  if (filename3 == NULL)
    return NOT_FOUND;

  ret = fn (g, fs, filename3, size_r);
  free (filename3);
  return ret;
}

/* Read the whole file into a memory buffer and return it.  The file
 * should be a regular, local, trusted file.
 */
static int
read_whole_file (guestfs_h *g, const char *filename,
                 char **data_r, size_t *size_r)
{
  int fd;
  char *data;
  off_t size;
  off_t n;
  ssize_t r;
  struct stat statbuf;

  fd = open (filename, O_RDONLY);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    return -1;
  }

  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "stat: %s", filename);
    close (fd);
    return -1;
  }

  size = statbuf.st_size;
  data = safe_malloc (g, size);

  n = 0;
  while (n < size) {
    r = read (fd, &data[n], size - n);
    if (r == -1) {
      perrorf (g, "read: %s", filename);
      free (data);
      close (fd);
      return -1;
    }
    if (r == 0) {
      error (g, _("read: %s: unexpected end of file"), filename);
      free (data);
      close (fd);
      return -1;
    }
    n += r;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", filename);
    free (data);
    return -1;
  }

  *data_r = data;
  *size_r = size;

  return 0;
}
