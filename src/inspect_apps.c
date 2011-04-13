/* libguestfs
 * Copyright (C) 2010-2011 Red Hat Inc.
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
#include <endian.h>

#ifdef HAVE_PCRE
#include <pcre.h>
#endif

#ifdef HAVE_HIVEX
#include <hivex.h>
#endif

#include "c-ctype.h"
#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if defined(HAVE_PCRE) && defined(HAVE_HIVEX)

#ifdef DB_DUMP
static struct guestfs_application_list *list_applications_rpm (guestfs_h *g, struct inspect_fs *fs);
#endif
static struct guestfs_application_list *list_applications_deb (guestfs_h *g, struct inspect_fs *fs);
static struct guestfs_application_list *list_applications_windows (guestfs_h *g, struct inspect_fs *fs);
static void add_application (guestfs_h *g, struct guestfs_application_list *, const char *name, const char *display_name, int32_t epoch, const char *version, const char *release, const char *install_path, const char *publisher, const char *url, const char *description);
static void sort_applications (struct guestfs_application_list *);

/* Unlike the simple inspect-get-* calls, this one assumes that the
 * disks are mounted up, and reads files from the mounted disks.
 */
struct guestfs_application_list *
guestfs__inspect_list_applications (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  struct guestfs_application_list *ret = NULL;

  /* Presently we can only list applications for installed disks.  It
   * is possible in future to get lists of packages from installers.
   */
  if (fs->format == OS_FORMAT_INSTALLED) {
    switch (fs->type) {
    case OS_TYPE_LINUX:
      switch (fs->package_format) {
      case OS_PACKAGE_FORMAT_RPM:
#ifdef DB_DUMP
        ret = list_applications_rpm (g, fs);
        if (ret == NULL)
          return NULL;
#endif
        break;

      case OS_PACKAGE_FORMAT_DEB:
        ret = list_applications_deb (g, fs);
        if (ret == NULL)
          return NULL;
        break;

      case OS_PACKAGE_FORMAT_PACMAN:
      case OS_PACKAGE_FORMAT_EBUILD:
      case OS_PACKAGE_FORMAT_PISI:
      case OS_PACKAGE_FORMAT_UNKNOWN:
      default:
        /* nothing - keep GCC happy */;
      }
      break;

    case OS_TYPE_WINDOWS:
      ret = list_applications_windows (g, fs);
      if (ret == NULL)
        return NULL;
      break;

    case OS_TYPE_FREEBSD:
    case OS_TYPE_UNKNOWN:
    default:
      /* nothing - keep GCC happy */;
    }
  }

  if (ret == NULL) {
    /* Don't know how to do inspection.  Not an error, return an
     * empty list.
     */
    ret = safe_malloc (g, sizeof *ret);
    ret->len = 0;
    ret->val = NULL;
  }

  sort_applications (ret);

  return ret;
}

#ifdef DB_DUMP
static struct guestfs_application_list *
list_applications_rpm (guestfs_h *g, struct inspect_fs *fs)
{
  const char *basename = "rpm_Name";
  char tmpdir_basename[strlen (g->tmpdir) + strlen (basename) + 2];
  snprintf (tmpdir_basename, sizeof tmpdir_basename, "%s/%s",
            g->tmpdir, basename);

  if (guestfs___download_to_tmp (g, "/var/lib/rpm/Name", basename,
                                 MAX_PKG_DB_SIZE) == -1)
    return NULL;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
#define cmd_len (strlen (tmpdir_basename) + 64)
  char cmd[cmd_len];
  FILE *pp = NULL;
  char line[1024];
  size_t len;

  snprintf (cmd, cmd_len, DB_DUMP " -p '%s'", tmpdir_basename);

  debug (g, "list_applications_rpm: %s", cmd);

  pp = popen (cmd, "r");
  if (pp == NULL) {
    perrorf (g, "popen: %s", cmd);
    goto out;
  }

  /* Ignore everything to end-of-header marker. */
  for (;;) {
    if (fgets (line, sizeof line, pp) == NULL) {
      error (g, _("unexpected end of output from db_dump command"));
      goto out;
    }

    len = strlen (line);
    if (len > 0 && line[len-1] == '\n') {
      line[len-1] = '\0';
      len--;
    }

    if (STREQ (line, "HEADER=END"))
      break;
  }

  /* Allocate 'apps' list. */
  apps = safe_malloc (g, sizeof *apps);
  apps->len = 0;
  apps->val = NULL;

  /* Read alternate lines until end of data marker. */
  for (;;) {
    if (fgets (line, sizeof line, pp) == NULL) {
      error (g, _("unexpected end of output from db_dump command"));
      goto out;
    }

    len = strlen (line);
    if (len > 0 && line[len-1] == '\n') {
      line[len-1] = '\0';
      len--;
    }

    if (STREQ (line, "DATA=END"))
      break;

    char *p = line;
    if (len > 0 && line[0] == ' ')
      p = line+1;
    /* Ignore any application name that contains non-printable chars.
     * In the db_dump output these would be escaped with backslash, so
     * we can just ignore any such line.
     */
    if (strchr (p, '\\') == NULL)
      add_application (g, apps, p, "", 0, "", "", "", "", "", "");

    /* Discard next line. */
    if (fgets (line, sizeof line, pp) == NULL) {
      error (g, _("unexpected end of output from db_dump command"));
      goto out;
    }
  }

  /* Catch errors from the db_dump command. */
  if (pclose (pp) == -1) {
    perrorf (g, "pclose: %s", cmd);
    goto out;
  }
  pp = NULL;

  ret = apps;

 out:
  if (ret == NULL && apps != NULL)
    guestfs_free_application_list (apps);
  if (pp)
    pclose (pp);

  return ret;
}
#endif /* defined DB_DUMP */

static struct guestfs_application_list *
list_applications_deb (guestfs_h *g, struct inspect_fs *fs)
{
  const char *basename = "deb_status";
  char tmpdir_basename[strlen (g->tmpdir) + strlen (basename) + 2];
  snprintf (tmpdir_basename, sizeof tmpdir_basename, "%s/%s",
            g->tmpdir, basename);

  if (guestfs___download_to_tmp (g, "/var/lib/dpkg/status", basename,
                                 MAX_PKG_DB_SIZE) == -1)
    return NULL;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
  FILE *fp = NULL;
  char line[1024];
  size_t len;
  char *name = NULL, *version = NULL, *release = NULL;
  int installed_flag = 0;

  fp = fopen (tmpdir_basename, "r");
  if (fp == NULL) {
    perrorf (g, "fopen: %s", tmpdir_basename);
    goto out;
  }

  /* Allocate 'apps' list. */
  apps = safe_malloc (g, sizeof *apps);
  apps->len = 0;
  apps->val = NULL;

  /* Read the temporary file.  Each package entry is separated by
   * a blank line.
   * XXX Strictly speaking this is in mailbox header format, so it
   * would be possible for fields to spread across multiple lines,
   * although for the short fields that we are concerned about this is
   * unlikely and not seen in practice.
   */
  while (fgets (line, sizeof line, fp) != NULL) {
    len = strlen (line);
    if (len > 0 && line[len-1] == '\n') {
      line[len-1] = '\0';
      len--;
    }

    if (STRPREFIX (line, "Package: ")) {
      free (name);
      name = safe_strdup (g, &line[9]);
    }
    else if (STRPREFIX (line, "Status: ")) {
      installed_flag = strstr (&line[8], "installed") != NULL;
    }
    else if (STRPREFIX (line, "Version: ")) {
      free (version);
      free (release);
      char *p = strchr (&line[9], '-');
      if (p) {
        *p = '\0';
        version = safe_strdup (g, &line[9]);
        release = safe_strdup (g, p+1);
      } else {
        version = safe_strdup (g, &line[9]);
        release = NULL;
      }
    }
    else if (STREQ (line, "")) {
      if (installed_flag && name && version)
        add_application (g, apps, name, "", 0, version, release ? : "",
                         "", "", "", "");
      free (name);
      free (version);
      free (release);
      name = version = release = NULL;
      installed_flag = 0;
    }
  }

  if (fclose (fp) == -1) {
    perrorf (g, "fclose: %s", tmpdir_basename);
    goto out;
  }
  fp = NULL;

  ret = apps;

 out:
  if (ret == NULL && apps != NULL)
    guestfs_free_application_list (apps);
  if (fp)
    fclose (fp);
  free (name);
  free (version);
  free (release);
  return ret;
}

static void list_applications_windows_from_path (guestfs_h *g, hive_h *h, struct guestfs_application_list *apps, const char **path, size_t path_len);

static struct guestfs_application_list *
list_applications_windows (guestfs_h *g, struct inspect_fs *fs)
{
  const char *basename = "software";
  char tmpdir_basename[strlen (g->tmpdir) + strlen (basename) + 2];
  snprintf (tmpdir_basename, sizeof tmpdir_basename, "%s/%s",
            g->tmpdir, basename);

  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  char *software_path = guestfs___case_sensitive_path_silently (g, software);
  if (!software_path)
    /* If the software hive doesn't exist, just accept that we cannot
     * list windows apps.
     */
    return 0;

  struct guestfs_application_list *ret = NULL;
  hive_h *h = NULL;

  if (guestfs___download_to_tmp (g, software_path, basename,
                                 MAX_REGISTRY_SIZE) == -1)
    goto out;

  free (software_path);
  software_path = NULL;

  h = hivex_open (tmpdir_basename, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
  if (h == NULL) {
    perrorf (g, "hivex_open");
    goto out;
  }

  /* Allocate apps list. */
  ret = safe_malloc (g, sizeof *ret);
  ret->len = 0;
  ret->val = NULL;

  /* Ordinary native applications. */
  const char *hivepath[] =
    { "Microsoft", "Windows", "CurrentVersion", "Uninstall" };
  list_applications_windows_from_path (g, h, ret, hivepath,
                                       sizeof hivepath / sizeof hivepath[0]);

  /* 32-bit emulated Windows apps running on the WOW64 emulator.
   * http://support.microsoft.com/kb/896459 (RHBZ#692545).
   */
  const char *hivepath2[] =
    { "WOW6432node", "Microsoft", "Windows", "CurrentVersion", "Uninstall" };
  list_applications_windows_from_path (g, h, ret, hivepath2,
                                       sizeof hivepath2 / sizeof hivepath2[0]);

 out:
  if (h) hivex_close (h);
  free (software_path);

  return ret;
}

static void
list_applications_windows_from_path (guestfs_h *g, hive_h *h,
                                     struct guestfs_application_list *apps,
                                     const char **path, size_t path_len)
{
  hive_node_h *children = NULL;
  hive_node_h node;
  size_t i;

  node = hivex_root (h);

  for (i = 0; node != 0 && i < path_len; ++i)
    node = hivex_node_get_child (h, node, path[i]);

  if (node == 0)
    return;

  children = hivex_node_children (h, node);
  if (children == NULL)
    return;

  /* Consider any child node that has a DisplayName key.
   * See also:
   * http://nsis.sourceforge.net/Add_uninstall_information_to_Add/Remove_Programs#Optional_values
   */
  for (i = 0; children[i] != 0; ++i) {
    hive_value_h value;
    char *name = NULL;
    char *display_name = NULL;
    char *version = NULL;
    char *install_path = NULL;
    char *publisher = NULL;
    char *url = NULL;
    char *comments = NULL;

    /* Use the node name as a proxy for the package name in Linux.  The
     * display name is not language-independent, so it cannot be used.
     */
    name = hivex_node_name (h, children[i]);
    if (name == NULL)
      continue;

    value = hivex_node_get_value (h, children[i], "DisplayName");
    if (value) {
      display_name = hivex_value_string (h, value);
      if (display_name) {
        value = hivex_node_get_value (h, children[i], "DisplayVersion");
        if (value)
          version = hivex_value_string (h, value);
        value = hivex_node_get_value (h, children[i], "InstallLocation");
        if (value)
          install_path = hivex_value_string (h, value);
        value = hivex_node_get_value (h, children[i], "Publisher");
        if (value)
          publisher = hivex_value_string (h, value);
        value = hivex_node_get_value (h, children[i], "URLInfoAbout");
        if (value)
          url = hivex_value_string (h, value);
        value = hivex_node_get_value (h, children[i], "Comments");
        if (value)
          comments = hivex_value_string (h, value);

        add_application (g, apps, name, display_name, 0,
                         version ? : "",
                         "",
                         install_path ? : "",
                         publisher ? : "",
                         url ? : "",
                         comments ? : "");
      }
    }

    free (name);
    free (display_name);
    free (version);
    free (install_path);
    free (publisher);
    free (url);
    free (comments);
  }

  free (children);
}

static void
add_application (guestfs_h *g, struct guestfs_application_list *apps,
                 const char *name, const char *display_name, int32_t epoch,
                 const char *version, const char *release,
                 const char *install_path,
                 const char *publisher, const char *url,
                 const char *description)
{
  apps->len++;
  apps->val = safe_realloc (g, apps->val,
                            apps->len * sizeof (struct guestfs_application));
  apps->val[apps->len-1].app_name = safe_strdup (g, name);
  apps->val[apps->len-1].app_display_name = safe_strdup (g, display_name);
  apps->val[apps->len-1].app_epoch = epoch;
  apps->val[apps->len-1].app_version = safe_strdup (g, version);
  apps->val[apps->len-1].app_release = safe_strdup (g, release);
  apps->val[apps->len-1].app_install_path = safe_strdup (g, install_path);
  /* XXX Translated path is not implemented yet. */
  apps->val[apps->len-1].app_trans_path = safe_strdup (g, "");
  apps->val[apps->len-1].app_publisher = safe_strdup (g, publisher);
  apps->val[apps->len-1].app_url = safe_strdup (g, url);
  /* XXX The next two are not yet implemented for any package
   * format, but we could easily support them for rpm and deb.
   */
  apps->val[apps->len-1].app_source_package = safe_strdup (g, "");
  apps->val[apps->len-1].app_summary = safe_strdup (g, "");
  apps->val[apps->len-1].app_description = safe_strdup (g, description);
}

/* Sort applications by name before returning the list. */
static int
compare_applications (const void *vp1, const void *vp2)
{
  const struct guestfs_application *v1 = vp1;
  const struct guestfs_application *v2 = vp2;

  return strcmp (v1->app_name, v2->app_name);
}

static void
sort_applications (struct guestfs_application_list *apps)
{
  if (apps && apps->val)
    qsort (apps->val, apps->len, sizeof (struct guestfs_application),
           compare_applications);
}

#else /* no PCRE or hivex at compile time */

/* XXX These functions should be in an optgroup. */

#define NOT_IMPL(r)                                                     \
  error (g, _("inspection API not available since this version of libguestfs was compiled without PCRE or hivex libraries")); \
  return r

struct guestfs_application_list *
guestfs__inspect_list_applications (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

#endif /* no PCRE or hivex at compile time */
