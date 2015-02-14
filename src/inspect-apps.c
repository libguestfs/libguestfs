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

/* be32toh is usually a macro definend in <endian.h>, but it might be
 * a function in some system so check both, and if neither is defined
 * then define be32toh for RHEL 5.
 */
#if !defined(HAVE_BE32TOH) && !defined(be32toh)
#if __BYTE_ORDER == __LITTLE_ENDIAN
#define be32toh(x) __bswap_32 (x)
#else
#define be32toh(x) (x)
#endif
#endif

#include <pcre.h>

#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#ifdef DB_DUMP
static struct guestfs_application2_list *list_applications_rpm (guestfs_h *g, struct inspect_fs *fs);
#endif
static struct guestfs_application2_list *list_applications_deb (guestfs_h *g, struct inspect_fs *fs);
static struct guestfs_application2_list *list_applications_windows (guestfs_h *g, struct inspect_fs *fs);
static void add_application (guestfs_h *g, struct guestfs_application2_list *, const char *name, const char *display_name, int32_t epoch, const char *version, const char *release, const char *arch, const char *install_path, const char *publisher, const char *url, const char *description);
static void sort_applications (struct guestfs_application2_list *);

/* The deprecated guestfs_inspect_list_applications call, which is now
 * just a wrapper around guestfs_inspect_list_applications2.
 */
struct guestfs_application_list *
guestfs_impl_inspect_list_applications (guestfs_h *g, const char *root)
{
  struct guestfs_application_list *ret;
  struct guestfs_application2_list *r;
  size_t i;

  /* Call the new function. */
  r = guestfs_inspect_list_applications2 (g, root);
  if (!r)
    return NULL;

  /* Translate the structures from the new format to the old format. */
  ret = safe_malloc (g, sizeof (struct guestfs_application_list));
  ret->len = r->len;
  ret->val =
    safe_malloc (g, sizeof (struct guestfs_application) * r->len);
  for (i = 0; i < r->len; ++i) {
    ret->val[i].app_name = r->val[i].app2_name;
    ret->val[i].app_display_name = r->val[i].app2_display_name;
    ret->val[i].app_epoch = r->val[i].app2_epoch;
    ret->val[i].app_version = r->val[i].app2_version;
    ret->val[i].app_release = r->val[i].app2_release;
    ret->val[i].app_install_path = r->val[i].app2_install_path;
    ret->val[i].app_trans_path = r->val[i].app2_trans_path;
    ret->val[i].app_publisher = r->val[i].app2_publisher;
    ret->val[i].app_url = r->val[i].app2_url;
    ret->val[i].app_source_package = r->val[i].app2_source_package;
    ret->val[i].app_summary = r->val[i].app2_summary;
    ret->val[i].app_description = r->val[i].app2_description;

    /* The other strings that we don't copy must be freed. */
    free (r->val[i].app2_arch);
    free (r->val[i].app2_spare1);
    free (r->val[i].app2_spare2);
    free (r->val[i].app2_spare3);
    free (r->val[i].app2_spare4);
  }
  free (r->val);                /* Must not free the other strings. */
  free (r);

  return ret;
}

/* Unlike the simple inspect-get-* calls, this one assumes that the
 * disks are mounted up, and reads files from the mounted disks.
 */
struct guestfs_application2_list *
guestfs_impl_inspect_list_applications2 (guestfs_h *g, const char *root)
{
  struct guestfs_application2_list *ret = NULL;
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

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
        ; /* nothing */
      }
      break;

    case OS_TYPE_WINDOWS:
      ret = list_applications_windows (g, fs);
      if (ret == NULL)
        return NULL;
      break;

    case OS_TYPE_FREEBSD:
    case OS_TYPE_MINIX:
    case OS_TYPE_NETBSD:
    case OS_TYPE_DOS:
    case OS_TYPE_OPENBSD:
    case OS_TYPE_UNKNOWN:
      ; /* nothing */
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
 * names and the first 4 bytes of each link field.
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
  const unsigned char *link_p;
  char *name;

  /* Ignore bogus entries. */
  if (keylen == 0 || valuelen < 4)
    return 0;

  /* A name entry will have as many links as installed instances of
   * that package.  For example, if glibc.i686 and glibc.x86_64 are
   * both installed, then there will be a link for each Packages
   * entry.  Add an entry onto list for all installed instances.
   */
  for (link_p = value; link_p < value + valuelen; link_p += 8) {
    name = safe_strndup (g, (const char *) key, keylen);

    list->names = safe_realloc (g, list->names,
                                (list->len + 1) * sizeof (struct rpm_name));
    list->names[list->len].name = name;
    memcpy (list->names[list->len].link, link_p, 4);
    list->len++;
  }

  return 0;
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcast-align"

/* tag constants, see rpmtag.h in RPM for complete list */
#define RPMTAG_VERSION 1001
#define RPMTAG_RELEASE 1002
#define RPMTAG_ARCH 1022

static char *
get_rpm_header_tag (guestfs_h *g, const unsigned char *header_start,
                    size_t header_len, uint32_t tag)
{
  uint32_t num_fields, offset;
  const unsigned char *cursor = header_start + 8, *store, *header_end;

  /* This function parses the RPM header structure to pull out various
   * tag strings (version, release, arch, etc.).  For more detail on the
   * header format, see:
   * http://www.rpm.org/max-rpm/s1-rpm-file-format-rpm-file-format.html#S2-RPM-FILE-FORMAT-HEADER
   */

  /* The minimum header size that makes sense here is 24 bytes.  Four
   * bytes for number of fields, followed by four bytes denoting the
   * size of the store, then 16 bytes for the first index entry.
   */
  if (header_len < 24)
    return NULL;

  num_fields = be32toh (*(uint32_t *) header_start);
  store = header_start + 8 + (16 * num_fields);

  /* The first byte *after* the buffer.  If you are here, you've gone
   * too far! */
  header_end = header_start + header_len;

  while (cursor < store && cursor <= header_end - 16) {
    if (be32toh (*(uint32_t *) cursor) == tag) {
      offset = be32toh(*(uint32_t *) (cursor + 8));
      if (store + offset >= header_end)
        return NULL;
      return safe_strndup(g, (const char *) (store + offset),
                          header_end - (store + offset));
    }
    cursor += 16;
  }

  return NULL;
}

#pragma GCC diagnostic pop

struct read_package_data {
  struct rpm_names_list *list;
  struct guestfs_application2_list *apps;
};

static int
read_package (guestfs_h *g,
              const unsigned char *key, size_t keylen,
              const unsigned char *value, size_t valuelen,
              void *datav)
{
  struct read_package_data *data = datav;
  struct rpm_name nkey, *entry;
  CLEANUP_FREE char *version = NULL, *release = NULL, *arch = NULL;

  /* This function reads one (key, value) pair from the Packages
   * database.  The key is the link field (see struct rpm_name).  The
   * value is a long binary string, but we can extract the header data
   * from it as below.  First we have to look up the link field in the
   * list of links (which is sorted by link field).
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
   * application out of the binary value string.
   */

  version = get_rpm_header_tag (g, value, valuelen, RPMTAG_VERSION);
  release = get_rpm_header_tag (g, value, valuelen, RPMTAG_RELEASE);
  arch = get_rpm_header_tag (g, value, valuelen, RPMTAG_ARCH);

  /* Add the application and what we know. */
  if (version && release)
    add_application (g, data->apps, entry->name, "", 0, version, release,
                     arch ? arch : "", "", "", "", "");

  return 0;
}

static struct guestfs_application2_list *
list_applications_rpm (guestfs_h *g, struct inspect_fs *fs)
{
  CLEANUP_FREE char *Name = NULL, *Packages = NULL;
  struct rpm_names_list list = { .names = NULL, .len = 0 };
  struct guestfs_application2_list *apps = NULL;
  struct read_package_data data;

  Name = guestfs_int_download_to_tmp (g, fs,
                                    "/var/lib/rpm/Name", "rpm_Name",
                                    MAX_PKG_DB_SIZE);
  if (Name == NULL)
    goto error;

  Packages = guestfs_int_download_to_tmp (g, fs,
                                        "/var/lib/rpm/Packages", "rpm_Packages",
                                        MAX_PKG_DB_SIZE);
  if (Packages == NULL)
    goto error;

  /* Read Name database. */
  if (guestfs_int_read_db_dump (g, Name, &list, read_rpm_name) == -1)
    goto error;

  /* Sort the names by link field for fast searching. */
  qsort (list.names, list.len, sizeof (struct rpm_name), compare_links);

  /* Allocate 'apps' list. */
  apps = safe_malloc (g, sizeof *apps);
  apps->len = 0;
  apps->val = NULL;

  /* Read Packages database. */
  data.list = &list;
  data.apps = apps;
  if (guestfs_int_read_db_dump (g, Packages, &data, read_package) == -1)
    goto error;

  free_rpm_names_list (&list);

  return apps;

 error:
  free_rpm_names_list (&list);
  guestfs_free_application2_list (apps);

  return NULL;
}

#endif /* defined DB_DUMP */

static struct guestfs_application2_list *
list_applications_deb (guestfs_h *g, struct inspect_fs *fs)
{
  CLEANUP_FREE char *status = NULL;
  struct guestfs_application2_list *apps = NULL, *ret = NULL;
  FILE *fp;
  char line[1024];
  size_t len;
  CLEANUP_FREE char *name = NULL, *version = NULL, *release = NULL, *arch = NULL;
  int installed_flag = 0;

  status = guestfs_int_download_to_tmp (g, fs, "/var/lib/dpkg/status", "status",
                                      MAX_PKG_DB_SIZE);
  if (status == NULL)
    return NULL;

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
    else if (STRPREFIX (line, "Architecture: ")) {
      free (arch);
      arch = safe_strdup (g, &line[14]);
    }
    else if (STREQ (line, "")) {
      if (installed_flag && name && version)
        add_application (g, apps, name, "", 0, version, release ? : "",
                         arch ? : "", "", "", "", "");
      free (name);
      free (version);
      free (release);
      free (arch);
      name = version = release = arch = NULL;
      installed_flag = 0;
    }
  }

  if (fclose (fp) == -1) {
    perrorf (g, "fclose: %s", status);
    goto out;
  }

  ret = apps;

 out:
  if (ret == NULL)
    guestfs_free_application2_list (apps);
  /*
  if (fp)
    fclose (fp);
  */
  return ret;
}

static void list_applications_windows_from_path (guestfs_h *g, struct guestfs_application2_list *apps, const char **path, size_t path_len);

static struct guestfs_application2_list *
list_applications_windows (guestfs_h *g, struct inspect_fs *fs)
{
  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  CLEANUP_FREE char *software_path;
  struct guestfs_application2_list *ret = NULL;

  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  software_path = guestfs_case_sensitive_path (g, software);
  if (!software_path)
    return NULL;

  if (guestfs_hivex_open (g, software_path,
                          GUESTFS_HIVEX_OPEN_VERBOSE, g->verbose, -1) == -1)
    return NULL;

  /* Allocate apps list. */
  ret = safe_malloc (g, sizeof *ret);
  ret->len = 0;
  ret->val = NULL;

  /* Ordinary native applications. */
  const char *hivepath[] =
    { "Microsoft", "Windows", "CurrentVersion", "Uninstall" };
  list_applications_windows_from_path (g, ret, hivepath,
                                       sizeof hivepath / sizeof hivepath[0]);

  /* 32-bit emulated Windows apps running on the WOW64 emulator.
   * http://support.microsoft.com/kb/896459 (RHBZ#692545).
   */
  const char *hivepath2[] =
    { "WOW6432node", "Microsoft", "Windows", "CurrentVersion", "Uninstall" };
  list_applications_windows_from_path (g, ret, hivepath2,
                                       sizeof hivepath2 / sizeof hivepath2[0]);

  guestfs_hivex_close (g);
  return ret;
}

static void
list_applications_windows_from_path (guestfs_h *g,
                                     struct guestfs_application2_list *apps,
                                     const char **path, size_t path_len)
{
  CLEANUP_FREE_HIVEX_NODE_LIST struct guestfs_hivex_node_list *children = NULL;
  int64_t node;
  size_t i;

  node = guestfs_hivex_root (g);

  for (i = 0; node != 0 && i < path_len; ++i)
    node = guestfs_hivex_node_get_child (g, node, path[i]);

  if (node == 0)
    return;

  children = guestfs_hivex_node_children (g, node);
  if (children == NULL)
    return;

  /* Consider any child node that has a DisplayName key.
   * See also:
   * http://nsis.sourceforge.net/Add_uninstall_information_to_Add/Remove_Programs#Optional_values
   */
  for (i = 0; i < children->len; ++i) {
    int64_t child = children->val[i].hivex_node_h;
    int64_t value;
    CLEANUP_FREE char *name = NULL, *display_name = NULL, *version = NULL,
      *install_path = NULL, *publisher = NULL, *url = NULL, *comments = NULL;

    /* Use the node name as a proxy for the package name in Linux.  The
     * display name is not language-independent, so it cannot be used.
     */
    name = guestfs_hivex_node_name (g, child);
    if (name == NULL)
      continue;

    value = guestfs_hivex_node_get_value (g, child, "DisplayName");
    if (value) {
      display_name = guestfs_hivex_value_utf8 (g, value);
      if (display_name) {
        value = guestfs_hivex_node_get_value (g, child, "DisplayVersion");
        if (value)
          version = guestfs_hivex_value_utf8 (g, value);
        value = guestfs_hivex_node_get_value (g, child, "InstallLocation");
        if (value)
          install_path = guestfs_hivex_value_utf8 (g, value);
        value = guestfs_hivex_node_get_value (g, child, "Publisher");
        if (value)
          publisher = guestfs_hivex_value_utf8 (g, value);
        value = guestfs_hivex_node_get_value (g, child, "URLInfoAbout");
        if (value)
          url = guestfs_hivex_value_utf8 (g, value);
        value = guestfs_hivex_node_get_value (g, child, "Comments");
        if (value)
          comments = guestfs_hivex_value_utf8 (g, value);

        add_application (g, apps, name, display_name, 0,
                         version ? : "",
                         "", "",
                         install_path ? : "",
                         publisher ? : "",
                         url ? : "",
                         comments ? : "");
      }
    }
  }
}

static void
add_application (guestfs_h *g, struct guestfs_application2_list *apps,
                 const char *name, const char *display_name, int32_t epoch,
                 const char *version, const char *release, const char *arch,
                 const char *install_path,
                 const char *publisher, const char *url,
                 const char *description)
{
  apps->len++;
  apps->val = safe_realloc (g, apps->val,
                            apps->len * sizeof (struct guestfs_application2));
  apps->val[apps->len-1].app2_name = safe_strdup (g, name);
  apps->val[apps->len-1].app2_display_name = safe_strdup (g, display_name);
  apps->val[apps->len-1].app2_epoch = epoch;
  apps->val[apps->len-1].app2_version = safe_strdup (g, version);
  apps->val[apps->len-1].app2_release = safe_strdup (g, release);
  apps->val[apps->len-1].app2_arch = safe_strdup (g, arch);
  apps->val[apps->len-1].app2_install_path = safe_strdup (g, install_path);
  /* XXX Translated path is not implemented yet. */
  apps->val[apps->len-1].app2_trans_path = safe_strdup (g, "");
  apps->val[apps->len-1].app2_publisher = safe_strdup (g, publisher);
  apps->val[apps->len-1].app2_url = safe_strdup (g, url);
  /* XXX The next two are not yet implemented for any package
   * format, but we could easily support them for rpm and deb.
   */
  apps->val[apps->len-1].app2_source_package = safe_strdup (g, "");
  apps->val[apps->len-1].app2_summary = safe_strdup (g, "");
  apps->val[apps->len-1].app2_description = safe_strdup (g, description);
  /* XXX Reserved for future use. */
  apps->val[apps->len-1].app2_spare1 = safe_strdup (g, "");
  apps->val[apps->len-1].app2_spare2 = safe_strdup (g, "");
  apps->val[apps->len-1].app2_spare3 = safe_strdup (g, "");
  apps->val[apps->len-1].app2_spare4 = safe_strdup (g, "");
}

/* Sort applications by name before returning the list. */
static int
compare_applications (const void *vp1, const void *vp2)
{
  const struct guestfs_application2 *v1 = vp1;
  const struct guestfs_application2 *v2 = vp2;

  return strcmp (v1->app2_name, v2->app2_name);
}

static void
sort_applications (struct guestfs_application2_list *apps)
{
  if (apps && apps->val)
    qsort (apps->val, apps->len, sizeof (struct guestfs_application2),
           compare_applications);
}
