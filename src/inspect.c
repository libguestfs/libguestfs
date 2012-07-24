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

/* The main inspection code. */
char **
guestfs__inspect_os (guestfs_h *g)
{
  /* Remove any information previously stored in the handle. */
  guestfs___free_inspect_info (g);

  if (guestfs_umount_all (g) == -1)
    return NULL;

  /* Iterate over all possible devices.  Try to mount each
   * (read-only).  Examine ones which contain filesystems and add that
   * information to the handle.
   */
  /* Look to see if any devices directly contain filesystems (RHBZ#590167). */
  char **devices = guestfs_list_devices (g);
  if (devices == NULL)
    return NULL;

  size_t i;
  for (i = 0; devices[i] != NULL; ++i) {
    if (guestfs___check_for_filesystem_on (g, devices[i], 1, 0) == -1) {
      guestfs___free_string_list (devices);
      guestfs___free_inspect_info (g);
      return NULL;
    }
  }
  guestfs___free_string_list (devices);

  /* Look at all partitions. */
  char **partitions = guestfs_list_partitions (g);
  if (partitions == NULL) {
    guestfs___free_inspect_info (g);
    return NULL;
  }

  for (i = 0; partitions[i] != NULL; ++i) {
    if (guestfs___check_for_filesystem_on (g, partitions[i], 0, i+1) == -1) {
      guestfs___free_string_list (partitions);
      guestfs___free_inspect_info (g);
      return NULL;
    }
  }
  guestfs___free_string_list (partitions);

  /* Look at MD devices. */
  char **mds = guestfs_list_md_devices (g);
  if (mds == NULL) {
    guestfs___free_inspect_info (g);
    return NULL;
  }

  for (i = 0; mds[i] != NULL; ++i) {
    if (guestfs___check_for_filesystem_on (g, mds[i], 0, i+1) == -1) {
      guestfs___free_string_list (mds);
      guestfs___free_inspect_info (g);
      return NULL;
    }
  }
  guestfs___free_string_list (mds);

  /* Look at all LVs. */
  if (guestfs___feature_available (g, "lvm2")) {
    char **lvs;
    lvs = guestfs_lvs (g);
    if (lvs == NULL) {
      guestfs___free_inspect_info (g);
      return NULL;
    }

    for (i = 0; lvs[i] != NULL; ++i) {
      if (guestfs___check_for_filesystem_on (g, lvs[i], 0, 0) == -1) {
        guestfs___free_string_list (lvs);
        guestfs___free_inspect_info (g);
        return NULL;
      }
    }
    guestfs___free_string_list (lvs);
  }

  /* At this point we have, in the handle, a list of all filesystems
   * found and data about each one.  Now we assemble the list of
   * filesystems which are root devices and return that to the user.
   * Fall through to guestfs__inspect_get_roots to do that.
   */
  char **ret = guestfs__inspect_get_roots (g);
  if (ret == NULL)
    guestfs___free_inspect_info (g);
  return ret;
}

static int
compare_strings (const void *vp1, const void *vp2)
{
  const char *s1 = * (char * const *) vp1;
  const char *s2 = * (char * const *) vp2;

  return strcmp (s1, s2);
}

char **
guestfs__inspect_get_roots (guestfs_h *g)
{
  /* NB. Doesn't matter if g->nr_fses == 0.  We just return an empty
   * list in this case.
   */

  size_t i;
  size_t count = 0;
  for (i = 0; i < g->nr_fses; ++i)
    if (g->fses[i].is_root)
      count++;

  char **ret = calloc (count+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  count = 0;
  for (i = 0; i < g->nr_fses; ++i) {
    if (g->fses[i].is_root) {
      ret[count] = safe_strdup (g, g->fses[i].device);
      count++;
    }
  }
  ret[count] = NULL;

  qsort (ret, count, sizeof (char *), compare_strings);

  return ret;
}

char *
guestfs__inspect_get_type (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->type) {
  case OS_TYPE_DOS: ret = safe_strdup (g, "dos"); break;
  case OS_TYPE_FREEBSD: ret = safe_strdup (g, "freebsd"); break;
  case OS_TYPE_HURD: ret = safe_strdup (g, "hurd"); break;
  case OS_TYPE_LINUX: ret = safe_strdup (g, "linux"); break;
  case OS_TYPE_NETBSD: ret = safe_strdup (g, "netbsd"); break;
  case OS_TYPE_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_TYPE_UNKNOWN: default: ret = safe_strdup (g, "unknown"); break;
  }

  return ret;
}

char *
guestfs__inspect_get_arch (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->arch ? : "unknown");
}

char *
guestfs__inspect_get_distro (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->distro) {
  case OS_DISTRO_ARCHLINUX: ret = safe_strdup (g, "archlinux"); break;
  case OS_DISTRO_BUILDROOT: ret = safe_strdup (g, "buildroot"); break;
  case OS_DISTRO_CENTOS: ret = safe_strdup (g, "centos"); break;
  case OS_DISTRO_CIRROS: ret = safe_strdup (g, "cirros"); break;
  case OS_DISTRO_DEBIAN: ret = safe_strdup (g, "debian"); break;
  case OS_DISTRO_FEDORA: ret = safe_strdup (g, "fedora"); break;
  case OS_DISTRO_FREEDOS: ret = safe_strdup (g, "freedos"); break;
  case OS_DISTRO_GENTOO: ret = safe_strdup (g, "gentoo"); break;
  case OS_DISTRO_LINUX_MINT: ret = safe_strdup (g, "linuxmint"); break;
  case OS_DISTRO_MAGEIA: ret = safe_strdup (g, "mageia"); break;
  case OS_DISTRO_MANDRIVA: ret = safe_strdup (g, "mandriva"); break;
  case OS_DISTRO_MEEGO: ret = safe_strdup (g, "meego"); break;
  case OS_DISTRO_OPENSUSE: ret = safe_strdup (g, "opensuse"); break;
  case OS_DISTRO_PARDUS: ret = safe_strdup (g, "pardus"); break;
  case OS_DISTRO_REDHAT_BASED: ret = safe_strdup (g, "redhat-based"); break;
  case OS_DISTRO_RHEL: ret = safe_strdup (g, "rhel"); break;
  case OS_DISTRO_SCIENTIFIC_LINUX: ret = safe_strdup (g, "scientificlinux"); break;
  case OS_DISTRO_SLACKWARE: ret = safe_strdup (g, "slackware"); break;
  case OS_DISTRO_TTYLINUX: ret = safe_strdup (g, "ttylinux"); break;
  case OS_DISTRO_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_DISTRO_UBUNTU: ret = safe_strdup (g, "ubuntu"); break;
  case OS_DISTRO_UNKNOWN: default: ret = safe_strdup (g, "unknown"); break;
  }

  return ret;
}

int
guestfs__inspect_get_major_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->major_version;
}

int
guestfs__inspect_get_minor_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->minor_version;
}

char *
guestfs__inspect_get_product_name (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->product_name ? : "unknown");
}

char *
guestfs__inspect_get_product_variant (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->product_variant ? : "unknown");
}

char *
guestfs__inspect_get_windows_systemroot (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_systemroot) {
    error (g, _("not a Windows guest, or systemroot could not be determined"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_systemroot);
}

char *
guestfs__inspect_get_windows_current_control_set (guestfs_h *g,
                                                  const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_current_control_set) {
    error (g, _("not a Windows guest, or CurrentControlSet could not be determined"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_current_control_set);
}

char *
guestfs__inspect_get_format (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->format) {
  case OS_FORMAT_INSTALLED: ret = safe_strdup (g, "installed"); break;
  case OS_FORMAT_INSTALLER: ret = safe_strdup (g, "installer"); break;
  case OS_FORMAT_UNKNOWN: default: ret = safe_strdup (g, "unknown"); break;
  }

  return ret;
}

int
guestfs__inspect_is_live (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_live_disk;
}

int
guestfs__inspect_is_netinst (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_netinst_disk;
}

int
guestfs__inspect_is_multipart (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_multipart_disk;
}

char **
guestfs__inspect_get_mountpoints (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

#define CRITERION(fs, i) fs->fstab[i].mountpoint[0] == '/'

  char **ret;
  size_t i, count, nr = fs->nr_fstab;

  if (nr == 0)
    count = 1;
  else {
    count = 0;
    for (i = 0; i < nr; ++i)
      if (CRITERION (fs, i))
        count++;
  }

  /* Hashtables have 2N+1 entries. */
  ret = calloc (2*count+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  /* If no fstab information (Windows) return just the root. */
  if (nr == 0) {
    ret[0] = safe_strdup (g, "/");
    ret[1] = safe_strdup (g, root);
    ret[2] = NULL;
    return ret;
  }

  count = 0;
  for (i = 0; i < nr; ++i)
    if (CRITERION (fs, i)) {
      ret[2*count] = safe_strdup (g, fs->fstab[i].mountpoint);
      ret[2*count+1] = safe_strdup (g, fs->fstab[i].device);
      count++;
    }
#undef CRITERION

  return ret;
}

char **
guestfs__inspect_get_filesystems (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char **ret;
  size_t i, nr = fs->nr_fstab;

  ret = calloc (nr == 0 ? 2 : nr+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  /* If no fstab information (Windows) return just the root. */
  if (nr == 0) {
    ret[0] = safe_strdup (g, root);
    ret[1] = NULL;
    return ret;
  }

  for (i = 0; i < nr; ++i)
    ret[i] = safe_strdup (g, fs->fstab[i].device);

  return ret;
}

char **
guestfs__inspect_get_drive_mappings (guestfs_h *g, const char *root)
{
  char **ret;
  size_t i, count;
  struct inspect_fs *fs;

  fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  /* If no drive mappings, return an empty hashtable. */
  if (!fs->drive_mappings)
    count = 0;
  else {
    for (count = 0; fs->drive_mappings[count] != NULL; count++)
      ;
  }

  ret = calloc (count+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  /* We need to make a deep copy of the hashtable since the caller
   * will free it.
   */
  for (i = 0; i < count; ++i)
    ret[i] = safe_strdup (g, fs->drive_mappings[i]);

  ret[count] = NULL;

  return ret;
}

char *
guestfs__inspect_get_package_format (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->package_format) {
  case OS_PACKAGE_FORMAT_RPM: ret = safe_strdup (g, "rpm"); break;
  case OS_PACKAGE_FORMAT_DEB: ret = safe_strdup (g, "deb"); break;
  case OS_PACKAGE_FORMAT_PACMAN: ret = safe_strdup (g, "pacman"); break;
  case OS_PACKAGE_FORMAT_EBUILD: ret = safe_strdup (g, "ebuild"); break;
  case OS_PACKAGE_FORMAT_PISI: ret = safe_strdup (g, "pisi"); break;
  case OS_PACKAGE_FORMAT_PKGSRC: ret = safe_strdup (g, "pkgsrc"); break;
  case OS_PACKAGE_FORMAT_UNKNOWN:
  default:
    ret = safe_strdup (g, "unknown");
    break;
  }

  return ret;
}

char *
guestfs__inspect_get_package_management (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->package_management) {
  case OS_PACKAGE_MANAGEMENT_YUM: ret = safe_strdup (g, "yum"); break;
  case OS_PACKAGE_MANAGEMENT_UP2DATE: ret = safe_strdup (g, "up2date"); break;
  case OS_PACKAGE_MANAGEMENT_APT: ret = safe_strdup (g, "apt"); break;
  case OS_PACKAGE_MANAGEMENT_PACMAN: ret = safe_strdup (g, "pacman"); break;
  case OS_PACKAGE_MANAGEMENT_PORTAGE: ret = safe_strdup (g, "portage"); break;
  case OS_PACKAGE_MANAGEMENT_PISI: ret = safe_strdup (g, "pisi"); break;
  case OS_PACKAGE_MANAGEMENT_URPMI: ret = safe_strdup (g, "urpmi"); break;
  case OS_PACKAGE_MANAGEMENT_ZYPPER: ret = safe_strdup (g, "zypper"); break;
  case OS_PACKAGE_MANAGEMENT_UNKNOWN:
  default:
    ret = safe_strdup (g, "unknown");
    break;
  }

  return ret;
}

char *
guestfs__inspect_get_hostname (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs___search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->hostname ? : "unknown");
}

#else /* no hivex at compile time */

/* XXX These functions should be in an optgroup. */

#define NOT_IMPL(r)                                                     \
  guestfs_error_errno (g, ENOTSUP, _("inspection API not available since this version of libguestfs was compiled without the hivex library")); \
  return r

char **
guestfs__inspect_os (guestfs_h *g)
{
  NOT_IMPL(NULL);
}

char **
guestfs__inspect_get_roots (guestfs_h *g)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_type (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_arch (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_distro (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

int
guestfs__inspect_get_major_version (guestfs_h *g, const char *root)
{
  NOT_IMPL(-1);
}

int
guestfs__inspect_get_minor_version (guestfs_h *g, const char *root)
{
  NOT_IMPL(-1);
}

char *
guestfs__inspect_get_product_name (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_product_variant (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_windows_systemroot (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_windows_current_control_set (guestfs_h *g,
                                                  const char *root)
{
  NOT_IMPL(NULL);
}

char **
guestfs__inspect_get_mountpoints (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char **
guestfs__inspect_get_filesystems (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char **
guestfs__inspect_get_drive_mappings (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_package_format (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_package_management (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_hostname (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

char *
guestfs__inspect_get_format (guestfs_h *g, const char *root)
{
  NOT_IMPL(NULL);
}

int
guestfs__inspect_is_live (guestfs_h *g, const char *root)
{
  NOT_IMPL(-1);
}

int
guestfs__inspect_is_netinst (guestfs_h *g, const char *root)
{
  NOT_IMPL(-1);
}

int
guestfs__inspect_is_multipart (guestfs_h *g, const char *root)
{
  NOT_IMPL(-1);
}

#endif /* no hivex at compile time */

void
guestfs___free_inspect_info (guestfs_h *g)
{
  size_t i;
  for (i = 0; i < g->nr_fses; ++i) {
    free (g->fses[i].device);
    free (g->fses[i].product_name);
    free (g->fses[i].product_variant);
    free (g->fses[i].arch);
    free (g->fses[i].hostname);
    free (g->fses[i].windows_systemroot);
    free (g->fses[i].windows_current_control_set);
    size_t j;
    for (j = 0; j < g->fses[i].nr_fstab; ++j) {
      free (g->fses[i].fstab[j].device);
      free (g->fses[i].fstab[j].mountpoint);
    }
    free (g->fses[i].fstab);
    if (g->fses[i].drive_mappings)
      guestfs___free_string_list (g->fses[i].drive_mappings);
  }
  free (g->fses);
  g->nr_fses = 0;
  g->fses = NULL;
}

/* In the Perl code this is a public function. */
int
guestfs___feature_available (guestfs_h *g, const char *feature)
{
  /* If there's an error we should ignore it, so to do that we have to
   * temporarily replace the error handler with a null one.
   */
  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;

  const char *groups[] = { feature, NULL };
  int r = guestfs_available (g, (char * const *) groups);

  g->error_cb = old_error_cb;

  return r == 0 ? 1 : 0;
}

/* Download a guest file to a local temporary file.  The file is
 * cached in the temporary directory, and is not downloaded again.
 *
 * The name of the temporary (downloaded) file is returned.  The
 * caller must free the pointer, but does *not* need to delete the
 * temporary file.  It will be deleted when the handle is closed.
 *
 * Refuse to download the guest file if it is larger than max_size.
 * On this and other errors, NULL is returned.
 *
 * There is actually one cache per 'struct inspect_fs *' in order
 * to handle the case of multiple roots.
 */
char *
guestfs___download_to_tmp (guestfs_h *g, struct inspect_fs *fs,
                           const char *filename,
                           const char *basename, uint64_t max_size)
{
  char *r;
  int fd;
  char devfd[32];
  int64_t size;

  /* Make the basename unique by prefixing it with the fs number. */
  if (asprintf (&r, "%s/%td-%s", g->tmpdir, fs - g->fses, basename) == -1) {
    perrorf (g, "asprintf");
    return NULL;
  }

  /* If the file has already been downloaded, return. */
  if (access (r, R_OK) == 0)
    return r;

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

struct inspect_fs *
guestfs___search_for_root (guestfs_h *g, const char *root)
{
  if (g->nr_fses == 0) {
    error (g, _("no inspection data: call guestfs_inspect_os first"));
    return NULL;
  }

  size_t i;
  struct inspect_fs *fs;
  for (i = 0; i < g->nr_fses; ++i) {
    fs = &g->fses[i];
    if (fs->is_root && STREQ (root, fs->device))
      return fs;
  }

  error (g, _("%s: root device not found: only call this function with a root device previously returned by guestfs_inspect_os"),
         root);
  return NULL;
}
