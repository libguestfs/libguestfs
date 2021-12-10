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
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <libintl.h>
#include <sys/wait.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

/* External tools are required for some icon types.  Check we have them. */
#if defined(PBMTEXT) && defined (PNMTOPNG)
#define CAN_DO_CIRROS 1
#endif
#if defined(WRESTOOL) && defined(BMPTOPNM) && defined(PNMTOPNG) &&	\
  defined(PAMCUT)
#define CAN_DO_WINDOWS 1
#endif

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
static char *icon_favicon (guestfs_h *g, const char *type, size_t *size_r);
static char *icon_fedora (guestfs_h *g, size_t *size_r);
static char *icon_rhel (guestfs_h *g, int major, size_t *size_r);
static char *icon_debian (guestfs_h *g, size_t *size_r);
static char *icon_ubuntu (guestfs_h *g, size_t *size_r);
static char *icon_mageia (guestfs_h *g, size_t *size_r);
static char *icon_opensuse (guestfs_h *g, size_t *size_r);
#if CAN_DO_CIRROS
static char *icon_cirros (guestfs_h *g, size_t *size_r);
#endif
static char *icon_voidlinux (guestfs_h *g, size_t *size_r);
static char *icon_altlinux (guestfs_h *g, size_t *size_r);
static char *icon_gentoo (guestfs_h *g, size_t *size_r);
static char *icon_openmandriva (guestfs_h *g, size_t *size_r);
#if CAN_DO_WINDOWS
static char *icon_windows (guestfs_h *g, const char *root, size_t *size_r);
#endif

static char *case_sensitive_path_silently (guestfs_h *g, const char *path);

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
  char *r = NOT_FOUND;
  int favicon, highquality;
  size_t size;
  CLEANUP_FREE char *type = NULL;
  CLEANUP_FREE char *distro = NULL;

  type = guestfs_inspect_get_type (g, root);
  if (!type)
    return NULL;
  distro = guestfs_inspect_get_distro (g, root);
  if (!distro)
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
    r = icon_favicon (g, type, &size);
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
  if (STREQ (type, "linux") || STREQ (type, "hurd")) {
    if (STREQ (distro, "fedora")) {
      r = icon_fedora (g, &size);
    }
    else if (STREQ (distro, "rhel") ||
             STREQ (distro, "redhat-based") ||
             STREQ (distro, "centos") ||
             STREQ (distro, "rocky") ||
             STREQ (distro, "scientificlinux") ||
             STREQ (distro, "oraclelinux")) {
      r = icon_rhel (g, guestfs_inspect_get_major_version (g, root), &size);
    }
    else if (STREQ (distro, "debian")) {
      r = icon_debian (g, &size);
    }
    else if (STREQ (distro, "ubuntu")) {
      if (!highquality)
        r = icon_ubuntu (g, &size);
    }
    else if (STREQ (distro, "mageia")) {
      r = icon_mageia (g, &size);
    }
    else if (STREQ (distro, "suse-based") ||
             STREQ (distro, "opensuse") ||
             STREQ (distro, "sles")) {
      r = icon_opensuse (g, &size);
    }
    else if (STREQ (distro, "cirros")) {
#if CAN_DO_CIRROS
      r = icon_cirros (g, &size);
#endif
    }
    else if (STREQ (distro, "voidlinux")) {
      r = icon_voidlinux (g, &size);
    }
    else if (STREQ (distro, "altlinux")) {
      r = icon_altlinux (g, &size);
    }
    else if (STREQ (distro, "gentoo")) {
      r = icon_gentoo (g, &size);
    }
    else if (STREQ (distro, "openmandriva")) {
      r = icon_openmandriva (g, &size);
    }
  }
  else if (STREQ (type, "windows")) {
#if CAN_DO_WINDOWS
    /* We don't know how to get high quality icons from a Windows guest,
     * so disable this if high quality was specified.
     */
    if (!highquality)
      r = icon_windows (g, root, &size);
#endif
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
get_png (guestfs_h *g, const char *filename, size_t *size_r, size_t max_size)
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

  local = guestfs_int_download_to_tmp (g, real, "png", max_size);
  if (!local)
    return NOT_FOUND;

  /* Successfully passed checks and downloaded.  Read it into memory. */
  if (guestfs_int_read_whole_file (g, local, &ret, size_r) == -1)
    return NULL;

  return ret;
}

static char *
find_png (guestfs_h *g, const char **filenames, size_t *size_r, size_t max_size)
{
  size_t i;
  char *ret;

  for (i = 0; filenames[i] != NULL; ++i) {
    ret = get_png (g, filenames[i], size_r, max_size);
    if (ret == NULL)
      return NULL;
    if (ret != NOT_FOUND)
      return ret;
  }
  return NOT_FOUND;
}

/* Return /etc/favicon.png (or \etc\favicon.png) if it exists and if
 * it has a reasonable size and format.
 */
static char *
icon_favicon (guestfs_h *g, const char *type, size_t *size_r)
{
  char *ret;
  char *filename = safe_strdup (g, "/etc/favicon.png");

  if (STREQ (type, "windows")) {
    char *f = case_sensitive_path_silently (g, filename);
    if (f) {
      free (filename);
      filename = f;
    }
  }

  ret = get_png (g, filename, size_r, 0);
  free (filename);
  return ret;
}

/* Return FEDORA_ICON.  I checked that this exists on at least Fedora 6
 * through 16.
 */
#define FEDORA_ICON "/usr/share/icons/hicolor/96x96/apps/fedora-logo-icon.png"

static char *
icon_fedora (guestfs_h *g, size_t *size_r)
{
  return get_png (g, FEDORA_ICON, size_r, 0);
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
 *
 * Use a generic 100K limit for all the images, as logos in the
 * RHEL clones have different sizes.
 */
static char *
icon_rhel (guestfs_h *g, int major, size_t *size_r)
{
  const char *shadowman;

  if (major < 7)
    shadowman = "/usr/share/pixmaps/redhat/shadowman-transparent.png";
  else
    shadowman = "/usr/share/icons/hicolor/96x96/apps/system-logo-icon.png";

  return get_png (g, shadowman, size_r, 102400);
}

#define DEBIAN_ICON "/usr/share/pixmaps/debian-logo.png"

static char *
icon_debian (guestfs_h *g, size_t *size_r)
{
  return get_png (g, DEBIAN_ICON, size_r, 2048);
}

static char *
icon_ubuntu (guestfs_h *g, size_t *size_r)
{
  const char *icons[] = {
    "/usr/share/icons/gnome/24x24/places/ubuntu-logo.png",

    /* Very low quality and only present when ubuntu-desktop packages
     * have been installed.
     */
    "/usr/share/help/C/ubuntu-help/figures/ubuntu-logo.png",
    NULL
  };

  return find_png (g, icons, size_r, 2048);
}

#define MAGEIA_ICON "/usr/share/icons/mageia.png"

static char *
icon_mageia (guestfs_h *g, size_t *size_r)
{
  return get_png (g, MAGEIA_ICON, size_r, 10240);
}

static char *
icon_opensuse (guestfs_h *g, size_t *size_r)
{
  const char *icons[] = {
    "/usr/share/icons/hicolor/48x48/apps/distributor.png",
    "/usr/share/icons/hicolor/24x24/apps/distributor.png",
    NULL
  };

  return find_png (g, icons, size_r, 10240);
}

#if CAN_DO_CIRROS

/* Cirros's logo is a text file! */
#define CIRROS_LOGO "/usr/share/cirros/logo"

static char *
icon_cirros (guestfs_h *g, size_t *size_r)
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

  local = guestfs_int_download_to_tmp (g, CIRROS_LOGO, "png", 1024);
  if (!local)
    return NOT_FOUND;

  /* Use pbmtext to render it. */
  pngfile = guestfs_int_make_temp_path (g, "cirros", "png");
  if (!pngfile)
    return NOT_FOUND;

  guestfs_int_cmd_add_string_unquoted (cmd, PBMTEXT " < ");
  guestfs_int_cmd_add_string_quoted   (cmd, local);
  guestfs_int_cmd_add_string_unquoted (cmd, " | " PNMTOPNG " > ");
  guestfs_int_cmd_add_string_quoted   (cmd, pngfile);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return NULL;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0)
    return NOT_FOUND;

  /* Read it into memory. */
  if (guestfs_int_read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

#endif /* CAN_DO_CIRROS */

#define VOIDLINUX_ICON "/usr/share/void-artwork/void-logo.png"

static char *
icon_voidlinux (guestfs_h *g, size_t *size_r)
{
  return get_png (g, VOIDLINUX_ICON, size_r, 20480);
}

#define ALTLINUX_ICON "/usr/share/icons/hicolor/48x48/apps/altlinux.png"

static char *
icon_altlinux (guestfs_h *g, size_t *size_r)
{
  return get_png (g, ALTLINUX_ICON, size_r, 20480);
}

/* Installed by x11-themes/gentoo-artwork. */
#define GENTOO_ICON "/usr/share/icons/gentoo/48x48/gentoo.png"

static char *
icon_gentoo (guestfs_h *g, size_t *size_r)
{
  return get_png (g, GENTOO_ICON, size_r, 10240);
}

static char *
icon_openmandriva (guestfs_h *g, size_t *size_r)
{
  const char *icons[] = {
    "/usr/share/icons/large/mandriva.png",
    "/usr/share/icons/mandriva.png",
    NULL
  };

  return find_png (g, icons, size_r, 10240);
}

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
icon_windows_xp (guestfs_h *g, const char *systemroot, size_t *size_r)
{
  CLEANUP_FREE char *filename = NULL;
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  CLEANUP_FREE char *pngfile = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  char *ret;

  /* Download %systemroot%\explorer.exe */
  filename = safe_asprintf (g, "%s/explorer.exe", systemroot);
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

  filename_downloaded = guestfs_int_download_to_tmp (g, filename_case, "exe",
						     MAX_WINDOWS_EXPLORER_SIZE);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  pngfile = guestfs_int_make_temp_path (g, "windows-xp-icon", "png");
  if (!pngfile)
    return NOT_FOUND;

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

  if (guestfs_int_read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

/* For Windows 7 we get the icon from explorer.exe.  Prefer
 * %systemroot%\SysWOW64\explorer.exe, a PE32 binary that usually
 * contains the icons on 64 bit guests.  Note the whole SysWOW64
 * directory doesn't exist on 32 bit guests, so we have to be prepared
 * for that.
 */
static const char *win7_explorer[] = {
  "SysWOW64/explorer.exe",
  "explorer.exe",
  NULL
};

static char *
icon_windows_7 (guestfs_h *g, const char *systemroot, size_t *size_r)
{
  size_t i;
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  CLEANUP_FREE char *pngfile = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  char *ret;

  for (i = 0; win7_explorer[i] != NULL; ++i) {
    CLEANUP_FREE char *filename = NULL;

    filename = safe_asprintf (g, "%s/%s", systemroot, win7_explorer[i]);

    free (filename_case);
    filename_case = case_sensitive_path_silently (g, filename);
    if (filename_case == NULL)
      continue;

    guestfs_push_error_handler (g, NULL, NULL);
    r = guestfs_is_file (g, filename_case);
    guestfs_pop_error_handler (g);
    if (r == -1)
      return NULL;
    if (r)
      break;
  }
  if (win7_explorer[i] == NULL)
    return NOT_FOUND;

  filename_downloaded = guestfs_int_download_to_tmp (g, filename_case, "exe",
						     MAX_WINDOWS_EXPLORER_SIZE);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  pngfile = guestfs_int_make_temp_path (g, "windows-7-icon", "png");
  if (!pngfile)
    return NOT_FOUND;

  guestfs_int_cmd_add_string_unquoted (cmd,
                                       WRESTOOL " -x --type=2 --name=6801 ");
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

  if (guestfs_int_read_whole_file (g, pngfile, &ret, size_r) == -1)
    return NULL;

  return ret;
}

/* There are several sources we might use:
 * - /ProgramData/Microsoft/Windows Live/WLive48x48.png
 * - w-brand.png (in a very long directory name)
 * - /Windows/System32/slui.exe --type=14 group icon #2
 */
static char *
icon_windows_8 (guestfs_h *g, size_t *size_r)
{
  CLEANUP_FREE char *filename_case = NULL;
  CLEANUP_FREE char *filename_downloaded = NULL;
  int r;
  char *ret;

  filename_case = case_sensitive_path_silently
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

  filename_downloaded = guestfs_int_download_to_tmp (g, filename_case, "png",
						     8192);
  if (filename_downloaded == NULL)
    return NOT_FOUND;

  if (guestfs_int_read_whole_file (g, filename_downloaded, &ret, size_r) == -1)
    return NULL;

  return ret;
}

static char *
icon_windows (guestfs_h *g, const char *root, size_t *size_r)
{
  CLEANUP_FREE char *systemroot =
    guestfs_inspect_get_windows_systemroot (g, root);
  int major = guestfs_inspect_get_major_version (g, root);
  int minor = guestfs_inspect_get_minor_version (g, root);

  if (systemroot == NULL)
    return NOT_FOUND;

  /* Windows XP. */
  if (major == 5 && minor == 1)
    return icon_windows_xp (g, systemroot, size_r);

  /* Windows 7. */
  else if (major == 6 && minor == 1)
    return icon_windows_7 (g, systemroot, size_r);

  /* Windows 8. */
  else if (major == 6 && minor == 2)
    return icon_windows_8 (g, size_r);

  /* Not (yet) a supported version of Windows. */
  else return NOT_FOUND;
}

#endif /* CAN_DO_WINDOWS */

/* NB: This function DOES NOT test for the existence of the file.  It
 * will return non-NULL even if the file/directory does not exist.
 * You have to call guestfs_is_file{,_opts} etc.
 */
static char *
case_sensitive_path_silently (guestfs_h *g, const char *path)
{
  char *ret;

  guestfs_push_error_handler (g, NULL, NULL);
  ret = guestfs_case_sensitive_path (g, path);
  guestfs_pop_error_handler (g);

  return ret;
}

/**
 * Download a guest file to a local temporary file.
 *
 * The name of the temporary (downloaded) file is returned.  The
 * caller must free the pointer, but does I<not> need to delete the
 * temporary file.  It will be deleted when the handle is closed.
 *
 * The name of the temporary file is randomly generated, but an
 * extension can be specified using C<extension> (or pass C<NULL> for none).
 *
 * Refuse to download the guest file if it is larger than C<max_size>.
 * On this and other errors, C<NULL> is returned.
 */
char *
guestfs_int_download_to_tmp (guestfs_h *g, const char *filename,
                             const char *extension,
                             uint64_t max_size)
{
  char *r;
  int fd;
  char devfd[32];
  int64_t size;

  r = guestfs_int_make_temp_path (g, "download", extension);
  if (r == NULL)
    return NULL;

  /* Check size of remote file. */
  size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    goto error;
  if ((uint64_t) size > max_size) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    goto error;
  }

  fd = open (r, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0600);
  if (fd == -1) {
    perrorf (g, "open: %s", r);
    goto error;
  }

  snprintf (devfd, sizeof devfd, "/dev/fd/%d", fd);

  if (guestfs_download (g, filename, devfd) == -1) {
    unlink (r);
    close (fd);
    goto error;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", r);
    unlink (r);
    goto error;
  }

  return r;

 error:
  free (r);
  return NULL;
}
