/* libguestfs
 * Copyright (C) 2010-2012 Red Hat Inc.
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

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include <pcre.h>

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

#if defined(HAVE_HIVEX)

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
    case OS_TYPE_HURD:
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
      case OS_PACKAGE_FORMAT_PKGSRC:
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
    case OS_TYPE_NETBSD:
    case OS_TYPE_DOS:
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

/* This data comes from the Name database, and contains the application
 * names and the first 4 bytes of the link field.
 */
struct rpm_names_list {
  struct rpm_name *names;
  size_t len;
};
struct rpm_name {
  char *name;
  char link[4];
};

static void
free_rpm_names_list (struct rpm_names_list *list)
{
  size_t i;

  for (i = 0; i < list->len; ++i)
    free (list->names[i].name);
  free (list->names);
}

static int
compare_links (const void *av, const void *bv)
{
  const struct rpm_name *a = av;
  const struct rpm_name *b = bv;
  return memcmp (a->link, b->link, 4);
}

static int
read_rpm_name (guestfs_h *g,
               const unsigned char *key, size_t keylen,
               const unsigned char *value, size_t valuelen,
               void *listv)
{
  struct rpm_names_list *list = listv;
  char *name;

  /* Ignore bogus entries. */
  if (keylen == 0 || valuelen < 4)
    return 0;

  /* The name (key) field won't be NUL-terminated, so we must do that. */
  name = safe_malloc (g, keylen+1);
  memcpy (name, key, keylen);
  name[keylen] = '\0';

  list->names = safe_realloc (g, list->names,
                              (list->len + 1) * sizeof (struct rpm_name));
  list->names[list->len].name = name;
  memcpy (list->names[list->len].link, value, 4);
  list->len++;

  return 0;
}

struct read_package_data {
  struct rpm_names_list *list;
  struct guestfs_application_list *apps;
};

static int
read_package (guestfs_h *g,
              const unsigned char *key, size_t keylen,
              const unsigned char *value, size_t valuelen,
              void *datav)
{
  struct read_package_data *data = datav;
  struct rpm_name nkey, *entry;
  char *p;
  size_t len;
  ssize_t max;
  char *nul_name_nul, *version, *release;

  /* This function reads one (key, value) pair from the Packages
   * database.  The key is the link field (see struct rpm_name).  The
   * value is a long binary string, but we can extract the version
   * number from it as below.  First we have to look up the link field
   * in the list of links (which is sorted by link field).
   */

  /* Ignore bogus entries. */
  if (keylen < 4 || valuelen == 0)
    return 0;

  /* Look up the link (key) in the list. */
  memcpy (nkey.link, key, 4);
  entry = bsearch (&nkey, data->list->names, data->list->len,
                   sizeof (struct rpm_name), compare_links);
  if (!entry)
    return 0;                   /* Not found - ignore it. */

  /* We found a matching link entry, so that gives us the application
   * name (entry->name).  Now we can get other data for this
   * application out of the binary value string.  XXX This is a real
   * hack.
   */

  /* Look for \0<name>\0 */
  len = strlen (entry->name);
  nul_name_nul = safe_malloc (g, len + 2);
  nul_name_nul[0] = '\0';
  memcpy (&nul_name_nul[1], entry->name, len);
  nul_name_nul[len+1] = '\0';
  p = memmem (value, valuelen, nul_name_nul, len+2);
  free (nul_name_nul);
  if (!p)
    return 0;

  /* Following that are \0-delimited version and release fields. */
  p += len + 2; /* Note we have to skip \0 + name + \0. */
  max = valuelen - (p - (char *) value);
  if (max < 0)
    max = 0;
  version = safe_strndup (g, p, max);

  len = strlen (version);
  p += len + 1;
  max = valuelen - (p - (char *) value);
  if (max < 0)
    max = 0;
  release = safe_strndup (g, p, max);

  /* Add the application and what we know. */
  add_application (g, data->apps, entry->name, "", 0, version, release,
                   "", "", "", "");

  free (version);
  free (release);

  return 0;
}

static struct guestfs_application_list *
list_applications_rpm (guestfs_h *g, struct inspect_fs *fs)
{
  char *Name = NULL, *Packages = NULL;
  struct rpm_names_list list = { .names = NULL, .len = 0 };
  struct guestfs_application_list *apps = NULL;

  Name = guestfs___download_to_tmp (g, fs,
                                    "/var/lib/rpm/Name", "rpm_Name",
                                    MAX_PKG_DB_SIZE);
  if (Name == NULL)
    goto error;

  Packages = guestfs___download_to_tmp (g, fs,
                                        "/var/lib/rpm/Packages", "rpm_Packages",
                                        MAX_PKG_DB_SIZE);
  if (Packages == NULL)
    goto error;

  /* Read Name database. */
  if (guestfs___read_db_dump (g, Name, &list, read_rpm_name) == -1)
    goto error;

  /* Sort the names by link field for fast searching. */
  qsort (list.names, list.len, sizeof (struct rpm_name), compare_links);

  /* Allocate 'apps' list. */
  apps = safe_malloc (g, sizeof *apps);
  apps->len = 0;
  apps->val = NULL;

  /* Read Packages database. */
  struct read_package_data data = { .list = &list, .apps = apps };
  if (guestfs___read_db_dump (g, Packages, &data, read_package) == -1)
    goto error;

  free (Name);
  free (Packages);
  free_rpm_names_list (&list);

  return apps;

 error:
  free (Name);
  free (Packages);
  free_rpm_names_list (&list);
  if (apps != NULL)
    guestfs_free_application_list (apps);

  return NULL;
}

#endif /* defined DB_DUMP */

static struct guestfs_application_list *
list_applications_deb (guestfs_h *g, struct inspect_fs *fs)
{
  char *status = NULL;
  status = guestfs___download_to_tmp (g, fs, "/var/lib/dpkg/status", "status",
                                      MAX_PKG_DB_SIZE);
  if (status == NULL)
    return NULL;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
  FILE *fp = NULL;
  char line[1024];
  size_t len;
  char *name = NULL, *version = NULL, *release = NULL;
  int installed_flag = 0;

  fp = fopen (status, "r");
  if (fp == NULL) {
    perrorf (g, "fopen: %s", status);
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
    perrorf (g, "fclose: %s", status);
    fp = NULL;
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
  free (status);
  return ret;
}

static void list_applications_windows_from_path (guestfs_h *g, hive_h *h, struct guestfs_application_list *apps, const char **path, size_t path_len);

static struct guestfs_application_list *
list_applications_windows (guestfs_h *g, struct inspect_fs *fs)
{
  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  char *software_path = guestfs___case_sensitive_path_silently (g, software);
  if (!software_path) {
    /* Missing software hive is a problem. */
    error (g, "no HKLM\\SOFTWARE hive found in the guest");
    return NULL;
  }

  char *software_hive = NULL;
  struct guestfs_application_list *ret = NULL;
  hive_h *h = NULL;

  software_hive = guestfs___download_to_tmp (g, fs, software_path, "software",
                                             MAX_REGISTRY_SIZE);
  if (software_hive == NULL)
    goto out;

  free (software_path);
  software_path = NULL;

  h = hivex_open (software_hive, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
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
  free (software_hive);

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

#else /* no hivex at compile time */

/* XXX These functions should be in an optgroup. */

#define NOT_IMPL(r)                                                     \
  error (g, _("inspection API not available since this version of libguestfs was compiled without the hivex library")); \
  return r

struct guestfs_application_list *
guestfs__inspect_list_applications (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

#endif /* no hivex at compile time */
