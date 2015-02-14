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

/* External tools are required for some icon types.  Check we have them. */
#if defined(PBMTEXT) && defined (PNMTOPNG)
#define CAN_DO_CIRROS 1
#endif
#if defined(WRESTOOL) && defined(BMPTOPNM) && defined(PNMTOPNG) && \
    defined(PAMCUT)
#define CAN_DO_WINDOWS 1
#endif

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
#if CAN_DO_CIRROS
static char *icon_cirros (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
#endif
#if CAN_DO_WINDOWS
static char *icon_windows (guestfs_h *g, struct inspect_fs *fs, size_t *size_r);
#endif

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
guestfs_impl_inspect_get_icon (guestfs_h *g, const char *root, size_t *size_r,
                           const struct guestfs_inspect_get_icon_argv *optargs)
{
  struct inspect_fs *fs;
  char *r = NOT_FOUND;
  int favicon, highquality;
  size_t size;

  fs = guestfs_int_search_for_root (g, root);
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
    case OS_DISTRO_ORACLE_LINUX:
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

    case OS_DISTRO_SUSE_BASED:
    case OS_DISTRO_OPENSUSE:
    case OS_DISTRO_SLES:
      r = icon_opensuse (g, fs, &size);
      break;

    case OS_DISTRO_CIRROS:
#if CAN_DO_CIRROS
      r = icon_cirros (g, fs, &size);
#endif
      break;

      /* These are just to keep gcc warnings happy. */
    case OS_DISTRO_ARCHLINUX:
    case OS_DISTRO_BUILDROOT:
    case OS_DISTRO_FREEDOS:
    case OS_DISTRO_GENTOO:
    case OS_DISTRO_LINUX_MINT:
    case OS_DISTRO_MANDRIVA:
    case OS_DISTRO_MEEGO:
    case OS_DISTRO_PARDUS:
    case OS_DISTRO_SLACKWARE:
    case OS_DISTRO_TTYLINUX:
    case OS_DISTRO_WINDOWS:
    case OS_DISTRO_OPENBSD:
    case OS_DISTRO_UNKNOWN:
      ; /* nothing */
    }
    break;

  case OS_TYPE_WINDOWS:
#if CAN_DO_WINDOWS
    /* We don't know how to get high quality icons from a Windows guest,
     * so disable this if high quality was specified.
     */
    if (!highquality)
      r = icon_windows (g, fs, &size);
#endif
    break;

  case OS_TYPE_FREEBSD:
  case OS_TYPE_NETBSD:
  case OS_TYPE_DOS:
  case OS_TYPE_OPENBSD:
  case OS_TYPE_MINIX:
  case OS_TYPE_UNKNOWN:
    ; /* nothing */
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
  char *ret;
  CLEANUP_FREE char *real = NULL;
  CLEANUP_FREE char *type = NULL;
  CLEANUP_FREE char *local = NULL;
  int r, w, h;

  r = guestfs_is_file_opts (g, filename,
                            GUESTFS_IS_FILE_OPTS_FOLLOWSYMLINKS, 1, -1);
  if (r == -1)
    return NULL; /* a real error */
  if (r == 0)
    return NOT_FOUND;

  /* Resolve the path, in case it's a symbolic link (as in RHEL 7). */
  guestfs_push_error_handler (g, NULL, NULL);
  real = guestfs_realpath (g, filename);
  guestfs_pop_error_handler (g);
  if (real == NULL)
    return NOT_FOUND; /* could just be a broken link */

  /* Check the file type and geometry. */
  type = guestfs_file (g, real);
  if (!type)
    return NOT_FOUND;

  if (!STRPREFIX (type, "PNG image data, "))
    return NOT_FOUND;
  if (sscanf (&type[16], "%d x %d", &w, &h) != 2)
    return NOT_FOUND;
  if (w < 16 || h < 16 || w > 1024 || h > 1024)
    return NOT_FOUND;

  /* Define a maximum reasonable size based on the geometry.  This
   * also limits the maximum we allocate below to around 4 MB.
   */
  if (max_size == 0)
    max_size = 4 * w * h;

  local = guestfs_int_download_to_tmp (g, fs, real, "icon", max_size);
  if (!local)
    return NOT_FOUND;

  /* Successfully passed checks and downloaded.  Read it into memory. */
  if (read_whole_file (g, local, &ret, size_r) == -1)
    return NULL;

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
    char *f = guestfs_int_case_sensitive_path_silently (g, filename);
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
 * In RHEL 7 the logos were completely broken (RHBZ#1063300).
 *
 * Conveniently the RHEL clones also have the same file with the
 * same name, but containing their own logos.  Sense prevails!
 */
static char *
icon_rhel (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  size_t max_size = 0;
  const char *shadowman;

  if (fs->major_version >= 5 && fs->major_version <= 6)
    max_size = 17000;
  else
    max_size = 66000;

  if (fs->major_version <= 6)
    shadowman = "/usr/share/pixmaps/redhat/shadowman-transparent.png";
  else
    shadowman = "/usr/share/pixmaps/fedora-logo-sprite.png";

  return get_png (g, fs, shadowman, size_r, max_size);
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

#if CAN_DO_CIRROS

/* Cirros's logo is a text file! */
#define CIRROS_LOGO "/usr/share/cirros/logo"

static char *
icon_cirros (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  char *ret;
  CLEANUP_FREE char *type = NULL;
  CLEANUP_FREE char *local = NULL;
  CLEANUP_FREE char *pngfile = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  r = guestfs_is_file_opts (g, CIRROS_LOGO,
                            GUESTFS_IS_FILE_OPTS_FOLLOWSYMLINKS, 1, -1);
  if (r == -1)
    return NULL; /* a real error */
  if (r == 0)
    return NOT_FOUND;

  /* Check the file type and geometry. */
  type = guestfs_file (g, CIRROS_LOGO);
  if (!type)
    return NOT_FOUND;

  if (!STRPREFIX (type, "ASCII text"))
    return NOT_FOUND;

  local = guestfs_int_download_to_tmp (g, fs, CIRROS_LOGO, "icon", 1024);
  if (!local)
    return NOT_FOUND;

  /* Use pbmtext to render it. */
  pngfile = safe_asprintf (g, "%s/cirros.png", g->tmpdir);

  guestfs_int_cmd_add_string_unquoted (cmd, PBMTEXT " < ");
  guestfs_int_cmd_add_string_quoted   (cmd, local);
  guestfs_int_cmd_add_string_unquoted (cmd, " | " PNMTOPNG " > ");
  guestfs_int_cmd_add_string_quoted   (cmd, pngfile);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return NOT_FOUND;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0)
    return NOT_FOUND;

  /* Read it into memory. */
  if (read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

#endif /* CAN_DO_CIRROS */

#if CAN_DO_WINDOWS

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
icon_windows_xp (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  CLEANUP_FREE char *filename = NULL;
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  CLEANUP_FREE char *pngfile = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  char *ret;

  /* Download %systemroot%\explorer.exe */
  filename = safe_asprintf (g, "%s/explorer.exe", fs->windows_systemroot);
  filename_case = guestfs_case_sensitive_path (g, filename);
  if (filename_case == NULL)
    return NULL;

  guestfs_push_error_handler (g, NULL, NULL);
  r = guestfs_is_file (g, filename_case);
  guestfs_pop_error_handler (g);
  if (r == -1)
    return NULL;
  if (r == 0)
    return NOT_FOUND;

  filename_downloaded = guestfs_int_download_to_tmp (g, fs, filename_case,
                                                   "explorer.exe",
                                                   MAX_WINDOWS_EXPLORER_SIZE);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  pngfile = safe_asprintf (g, "%s/windows-xp-icon.png", g->tmpdir);

  guestfs_int_cmd_add_string_unquoted (cmd, WRESTOOL " -x --type=2 --name=143 ");
  guestfs_int_cmd_add_string_quoted   (cmd, filename_downloaded);
  guestfs_int_cmd_add_string_unquoted (cmd,
                                     " | " BMPTOPNM " | " PNMTOPNG " > ");
  guestfs_int_cmd_add_string_quoted   (cmd, pngfile);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return NULL;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0)
    return NOT_FOUND;

  if (read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

static char *
icon_windows_7 (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  CLEANUP_FREE char *filename = NULL;
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  CLEANUP_FREE char *pngfile = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  char *ret;

  /* Download %systemroot%\explorer.exe */
  filename = safe_asprintf (g, "%s/explorer.exe", fs->windows_systemroot);
  filename_case = guestfs_case_sensitive_path (g, filename);
  if (filename_case == NULL)
    return NULL;

  guestfs_push_error_handler (g, NULL, NULL);
  r = guestfs_is_file (g, filename_case);
  guestfs_pop_error_handler (g);
  if (r == -1)
    return NULL;
  if (r == 0)
    return NOT_FOUND;

  filename_downloaded = guestfs_int_download_to_tmp (g, fs, filename_case,
                                                   "explorer.exe",
                                                   MAX_WINDOWS_EXPLORER_SIZE);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  pngfile = safe_asprintf (g, "%s/windows-7-icon.png", g->tmpdir);

  guestfs_int_cmd_add_string_unquoted (cmd, WRESTOOL " -x --type=2 --name=6801 ");
  guestfs_int_cmd_add_string_quoted   (cmd, filename_downloaded);
  guestfs_int_cmd_add_string_unquoted (cmd,
                                     " | " BMPTOPNM " | "
                                     PAMCUT " -bottom 54 | "
                                     PNMTOPNG " > ");
  guestfs_int_cmd_add_string_quoted   (cmd, pngfile);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return NULL;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0)
    return NOT_FOUND;

  if (read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

/* There are several sources we might use:
 * - /ProgramData/Microsoft/Windows Live/WLive48x48.png
 * - w-brand.png (in a very long directory name)
 * - /Windows/System32/slui.exe --type=14 group icon #2
 */
static char *
icon_windows_8 (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  int r;
  char *ret;

  filename_case = guestfs_int_case_sensitive_path_silently
    (g, "/ProgramData/Microsoft/Windows Live/WLive48x48.png");
  if (filename_case == NULL)
    return NOT_FOUND; /* Not an error since a parent dir might not exist. */

  guestfs_push_error_handler (g, NULL, NULL);
  r = guestfs_is_file (g, filename_case);
  guestfs_pop_error_handler (g);
  if (r == -1)
    return NULL;
  if (r == 0)
    return NOT_FOUND;

  filename_downloaded = guestfs_int_download_to_tmp (g, fs, filename_case,
                                                   "wlive48x48.png", 8192);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  if (read_whole_file (g, filename_downloaded, &ret, size_r) == -1)
    return NULL;

  return ret;
}

static char *
icon_windows (guestfs_h *g, struct inspect_fs *fs, size_t *size_r)
{
  if (fs->windows_systemroot == NULL)
    return NOT_FOUND;

  /* Windows XP. */
  if (fs->major_version == 5 && fs->minor_version == 1)
    return icon_windows_xp (g, fs, size_r);

  /* Windows 7. */
  else if (fs->major_version == 6 && fs->minor_version == 1)
    return icon_windows_7 (g, fs, size_r);

  /* Windows 8. */
  else if (fs->major_version == 6 && fs->minor_version == 2)
    return icon_windows_8 (g, fs, size_r);

  /* Not (yet) a supported version of Windows. */
  else return NOT_FOUND;
}

#endif /* CAN_DO_WINDOWS */

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

  fd = open (filename, O_RDONLY|O_CLOEXEC);
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
