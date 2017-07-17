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

/**
 * This file, and the other C<lib/inspect*.c> files, handle
 * inspection.  See L<guestfs(3)/INSPECTION>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <libintl.h>
#include <assert.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

COMPILE_REGEXP (re_primary_partition, "^/dev/(?:h|s|v)d.[1234]$", 0)

static void check_for_duplicated_bsd_root (guestfs_h *g);
static void collect_coreos_inspection_info (guestfs_h *g);
static void collect_linux_inspection_info (guestfs_h *g);
static void collect_linux_inspection_info_for (guestfs_h *g, struct inspect_fs *root);

/**
 * The main inspection API.
 */
char **
guestfs_impl_inspect_os (guestfs_h *g)
{
  CLEANUP_FREE_STRING_LIST char **fses = NULL;
  char **fs, **ret;

  /* Remove any information previously stored in the handle. */
  guestfs_int_free_inspect_info (g);

  if (guestfs_umount_all (g) == -1)
    return NULL;

  /* Iterate over all detected filesystems.  Inspect each one in turn
   * and add that information to the handle.
   */

  fses = guestfs_list_filesystems (g);
  if (fses == NULL) return NULL;

  for (fs = fses; *fs; fs += 2) {
    if (guestfs_int_check_for_filesystem_on (g, *fs)) {
      guestfs_int_free_inspect_info (g);
      return NULL;
    }
  }

  /* The OS inspection information for CoreOS are gathered by inspecting
   * multiple filesystems. Gather all the inspected information in the
   * inspect_fs struct of the root filesystem.
   */
  collect_coreos_inspection_info (g);

  /* Check if the same filesystem was listed twice as root in g->fses.
   * This may happen for the *BSD root partition where an MBR partition
   * is a shadow of the real root partition probably /dev/sda5
   */
  check_for_duplicated_bsd_root (g);

  /* For Linux guests with a separate /usr filesyste, merge some of the
   * inspected information in that partition to the inspect_fs struct
   * of the root filesystem.
   */
  collect_linux_inspection_info (g);

  /* At this point we have, in the handle, a list of all filesystems
   * found and data about each one.  Now we assemble the list of
   * filesystems which are root devices and return that to the user.
   * Fall through to guestfs_inspect_get_roots to do that.
   */
  ret = guestfs_inspect_get_roots (g);
  if (ret == NULL)
    guestfs_int_free_inspect_info (g);
  return ret;
}

/**
 * Traverse through the filesystem list and find out if it contains
 * the C</> and C</usr> filesystems of a CoreOS image. If this is the
 * case, sum up all the collected information on the root fs.
 */
static void
collect_coreos_inspection_info (guestfs_h *g)
{
  size_t i;
  struct inspect_fs *root = NULL, *usr = NULL;

  for (i = 0; i < g->nr_fses; ++i) {
    struct inspect_fs *fs = &g->fses[i];

    if (fs->distro == OS_DISTRO_COREOS && fs->role == OS_ROLE_ROOT)
      root = fs;
  }

  if (root == NULL)
    return;

  for (i = 0; i < g->nr_fses; ++i) {
    struct inspect_fs *fs = &g->fses[i];

    if (fs->distro != OS_DISTRO_COREOS || fs->role != OS_ROLE_USR)
      continue;

    /* CoreOS is designed to contain 2 /usr partitions (USR-A, USR-B):
     * https://coreos.com/docs/sdk-distributors/sdk/disk-partitions/
     * One is active and one passive. During the initial boot, the passive
     * partition is empty and it gets filled up when an update is performed.
     * Then, when the system reboots, the boot loader is instructed to boot
     * from the passive partition. If both partitions are valid, we cannot
     * determine which the active and which the passive is, unless we peep into
     * the boot loader. As a workaround, we check the OS versions and pick the
     * one with the higher version as active.
     */
    if (usr && guestfs_int_version_cmp_ge (&usr->version, &fs->version))
      continue;

    usr = fs;
  }

  if (usr == NULL)
    return;

  guestfs_int_merge_fs_inspections (g, root, usr);
}

/**
 * Traverse through the filesystems and find the /usr filesystem for
 * the specified C<root>: if found, merge its basic inspection details
 * to the root when they were set (i.e. because the /usr had os-release
 * or other ways to identify the OS).
 */
static void
collect_linux_inspection_info_for (guestfs_h *g, struct inspect_fs *root)
{
  size_t i;
  struct inspect_fs *usr = NULL;

  for (i = 0; i < g->nr_fses; ++i) {
    struct inspect_fs *fs = &g->fses[i];
    size_t j;

    if (!(fs->distro == root->distro || fs->distro == OS_DISTRO_UNKNOWN) ||
        fs->role != OS_ROLE_USR)
      continue;

    for (j = 0; j < root->nr_fstab; ++j) {
      if (STREQ (fs->mountable, root->fstab[j].mountable)) {
        usr = fs;
        goto got_usr;
      }
    }
  }

  assert (usr == NULL);
  return;

 got_usr:
  /* If the version information in /usr is not null, then most probably
   * there was an os-release file there, so reset what is in root
   * and pick the results from /usr.
   */
  if (!version_is_null (&usr->version)) {
    root->distro = OS_DISTRO_UNKNOWN;
    free (root->product_name);
    root->product_name = NULL;
  }

  guestfs_int_merge_fs_inspections (g, root, usr);
}

/**
 * Traverse through the filesystem list and find out if it contains
 * the C</> and C</usr> filesystems of a Linux image (but not CoreOS,
 * for which there is a separate C<collect_coreos_inspection_info>).
 * If this is the case, sum up all the collected information on each
 * root fs from the respective /usr filesystems.
 */
static void
collect_linux_inspection_info (guestfs_h *g)
{
  size_t i;

  for (i = 0; i < g->nr_fses; ++i) {
    struct inspect_fs *fs = &g->fses[i];

    if (fs->distro != OS_DISTRO_COREOS && fs->role == OS_ROLE_ROOT)
      collect_linux_inspection_info_for (g, fs);
  }
}

/**
 * On *BSD systems, sometimes F</dev/sda[1234]> is a shadow of the
 * real root filesystem that is probably F</dev/sda5> (see:
 * L<http://www.freebsd.org/doc/handbook/disk-organization.html>)
 */
static void
check_for_duplicated_bsd_root (guestfs_h *g)
{
  size_t i;
  struct inspect_fs *bsd_primary = NULL;

  for (i = 0; i < g->nr_fses; ++i) {
    bool is_bsd;
    struct inspect_fs *fs = &g->fses[i];

    is_bsd =
      fs->type == OS_TYPE_FREEBSD ||
      fs->type == OS_TYPE_NETBSD ||
      fs->type == OS_TYPE_OPENBSD;

    if (fs->role == OS_ROLE_ROOT && is_bsd &&
        match (g, fs->mountable, re_primary_partition)) {
      bsd_primary = fs;
      continue;
    }

    if (fs->role == OS_ROLE_ROOT && bsd_primary &&
        bsd_primary->type == fs->type) {
      /* remove the root role from the bsd_primary */
      bsd_primary->role = OS_ROLE_UNKNOWN;
      bsd_primary->format = OS_FORMAT_UNKNOWN;
      return;
    }
  }
}

static int
compare_strings (const void *vp1, const void *vp2)
{
  const char *s1 = * (char * const *) vp1;
  const char *s2 = * (char * const *) vp2;

  return strcmp (s1, s2);
}

char **
guestfs_impl_inspect_get_roots (guestfs_h *g)
{
  size_t i;
  DECLARE_STRINGSBUF (ret);

  /* NB. Doesn't matter if g->nr_fses == 0.  We just return an empty
   * list in this case.
   */
  for (i = 0; i < g->nr_fses; ++i) {
    if (g->fses[i].role == OS_ROLE_ROOT)
      guestfs_int_add_string (g, &ret, g->fses[i].mountable);
  }
  guestfs_int_end_stringsbuf (g, &ret);

  qsort (ret.argv, ret.size-1, sizeof (char *), compare_strings);

  return ret.argv;
}

char *
guestfs_impl_inspect_get_type (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  char *ret = NULL;

  if (!fs)
    return NULL;

  switch (fs->type) {
  case OS_TYPE_DOS: ret = safe_strdup (g, "dos"); break;
  case OS_TYPE_FREEBSD: ret = safe_strdup (g, "freebsd"); break;
  case OS_TYPE_HURD: ret = safe_strdup (g, "hurd"); break;
  case OS_TYPE_LINUX: ret = safe_strdup (g, "linux"); break;
  case OS_TYPE_MINIX: ret = safe_strdup (g, "minix"); break;
  case OS_TYPE_NETBSD: ret = safe_strdup (g, "netbsd"); break;
  case OS_TYPE_OPENBSD: ret = safe_strdup (g, "openbsd"); break;
  case OS_TYPE_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_TYPE_UNKNOWN: ret = safe_strdup (g, "unknown"); break;
  }

  if (ret == NULL)
    abort ();

  return ret;
}

char *
guestfs_impl_inspect_get_arch (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->arch ? : "unknown");
}

char *
guestfs_impl_inspect_get_distro (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  char *ret = NULL;

  if (!fs)
    return NULL;

  switch (fs->distro) {
  case OS_DISTRO_ALPINE_LINUX: ret = safe_strdup (g, "alpinelinux"); break;
  case OS_DISTRO_ALTLINUX: ret = safe_strdup (g, "altlinux"); break;
  case OS_DISTRO_ARCHLINUX: ret = safe_strdup (g, "archlinux"); break;
  case OS_DISTRO_BUILDROOT: ret = safe_strdup (g, "buildroot"); break;
  case OS_DISTRO_CENTOS: ret = safe_strdup (g, "centos"); break;
  case OS_DISTRO_CIRROS: ret = safe_strdup (g, "cirros"); break;
  case OS_DISTRO_COREOS: ret = safe_strdup (g, "coreos"); break;
  case OS_DISTRO_DEBIAN: ret = safe_strdup (g, "debian"); break;
  case OS_DISTRO_FEDORA: ret = safe_strdup (g, "fedora"); break;
  case OS_DISTRO_FREEBSD: ret = safe_strdup (g, "freebsd"); break;
  case OS_DISTRO_FREEDOS: ret = safe_strdup (g, "freedos"); break;
  case OS_DISTRO_FRUGALWARE: ret = safe_strdup (g, "frugalware"); break;
  case OS_DISTRO_GENTOO: ret = safe_strdup (g, "gentoo"); break;
  case OS_DISTRO_LINUX_MINT: ret = safe_strdup (g, "linuxmint"); break;
  case OS_DISTRO_MAGEIA: ret = safe_strdup (g, "mageia"); break;
  case OS_DISTRO_MANDRIVA: ret = safe_strdup (g, "mandriva"); break;
  case OS_DISTRO_MEEGO: ret = safe_strdup (g, "meego"); break;
  case OS_DISTRO_NETBSD: ret = safe_strdup (g, "netbsd"); break;
  case OS_DISTRO_OPENBSD: ret = safe_strdup (g, "openbsd"); break;
  case OS_DISTRO_OPENSUSE: ret = safe_strdup (g, "opensuse"); break;
  case OS_DISTRO_ORACLE_LINUX: ret = safe_strdup (g, "oraclelinux"); break;
  case OS_DISTRO_PARDUS: ret = safe_strdup (g, "pardus"); break;
  case OS_DISTRO_PLD_LINUX: ret = safe_strdup (g, "pldlinux"); break;
  case OS_DISTRO_REDHAT_BASED: ret = safe_strdup (g, "redhat-based"); break;
  case OS_DISTRO_RHEL: ret = safe_strdup (g, "rhel"); break;
  case OS_DISTRO_SCIENTIFIC_LINUX: ret = safe_strdup (g, "scientificlinux"); break;
  case OS_DISTRO_SLACKWARE: ret = safe_strdup (g, "slackware"); break;
  case OS_DISTRO_SLES: ret = safe_strdup (g, "sles"); break;
  case OS_DISTRO_SUSE_BASED: ret = safe_strdup (g, "suse-based"); break;
  case OS_DISTRO_TTYLINUX: ret = safe_strdup (g, "ttylinux"); break;
  case OS_DISTRO_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_DISTRO_UBUNTU: ret = safe_strdup (g, "ubuntu"); break;
  case OS_DISTRO_VOID_LINUX: ret = safe_strdup (g, "voidlinux"); break;
  case OS_DISTRO_UNKNOWN: ret = safe_strdup (g, "unknown"); break;
  }

  if (ret == NULL)
    abort ();

  return ret;
}

int
guestfs_impl_inspect_get_major_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->version.v_major;
}

int
guestfs_impl_inspect_get_minor_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->version.v_minor;
}

char *
guestfs_impl_inspect_get_product_name (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->product_name ? : "unknown");
}

char *
guestfs_impl_inspect_get_product_variant (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->product_variant ? : "unknown");
}

char *
guestfs_impl_inspect_get_windows_systemroot (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_systemroot) {
    error (g, _("not a Windows guest, or systemroot could not be determined"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_systemroot);
}

char *
guestfs_impl_inspect_get_windows_software_hive (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_software_hive) {
    error (g, _("not a Windows guest, or software hive not found"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_software_hive);
}

char *
guestfs_impl_inspect_get_windows_system_hive (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_system_hive) {
    error (g, _("not a Windows guest, or system hive not found"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_system_hive);
}

char *
guestfs_impl_inspect_get_windows_current_control_set (guestfs_h *g,
						      const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_current_control_set) {
    error (g, _("not a Windows guest, or CurrentControlSet could not be determined"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_current_control_set);
}

char *
guestfs_impl_inspect_get_format (guestfs_h *g, const char *root)
{
  char *ret = NULL;
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  switch (fs->format) {
  case OS_FORMAT_INSTALLED: ret = safe_strdup (g, "installed"); break;
  case OS_FORMAT_INSTALLER: ret = safe_strdup (g, "installer"); break;
  case OS_FORMAT_UNKNOWN: ret = safe_strdup (g, "unknown"); break;
  }

  if (ret == NULL)
    abort ();

  return ret;
}

int
guestfs_impl_inspect_is_live (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_live_disk;
}

int
guestfs_impl_inspect_is_netinst (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_netinst_disk;
}

int
guestfs_impl_inspect_is_multipart (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_multipart_disk;
}

char **
guestfs_impl_inspect_get_mountpoints (guestfs_h *g, const char *root)
{
  char **ret;
  size_t i, count, nr;
  struct inspect_fs *fs;

  fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

#define CRITERION(fs, i) fs->fstab[i].mountpoint[0] == '/'

  nr = fs->nr_fstab;

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
      ret[2*count+1] = safe_strdup (g, fs->fstab[i].mountable);
      count++;
    }
#undef CRITERION

  return ret;
}

char **
guestfs_impl_inspect_get_filesystems (guestfs_h *g, const char *root)
{
  char **ret;
  size_t i, nr;
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);

  if (!fs)
    return NULL;

  nr = fs->nr_fstab;
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
    ret[i] = safe_strdup (g, fs->fstab[i].mountable);

  return ret;
}

char **
guestfs_impl_inspect_get_drive_mappings (guestfs_h *g, const char *root)
{
  DECLARE_STRINGSBUF (ret);
  size_t i;
  struct inspect_fs *fs;

  fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  if (fs->drive_mappings) {
    for (i = 0; fs->drive_mappings[i] != NULL; ++i)
      guestfs_int_add_string (g, &ret, fs->drive_mappings[i]);
  }

  guestfs_int_end_stringsbuf (g, &ret);
  return ret.argv;
}

char *
guestfs_impl_inspect_get_package_format (guestfs_h *g, const char *root)
{
  char *ret = NULL;
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  switch (fs->package_format) {
  case OS_PACKAGE_FORMAT_RPM: ret = safe_strdup (g, "rpm"); break;
  case OS_PACKAGE_FORMAT_DEB: ret = safe_strdup (g, "deb"); break;
  case OS_PACKAGE_FORMAT_PACMAN: ret = safe_strdup (g, "pacman"); break;
  case OS_PACKAGE_FORMAT_EBUILD: ret = safe_strdup (g, "ebuild"); break;
  case OS_PACKAGE_FORMAT_PISI: ret = safe_strdup (g, "pisi"); break;
  case OS_PACKAGE_FORMAT_PKGSRC: ret = safe_strdup (g, "pkgsrc"); break;
  case OS_PACKAGE_FORMAT_APK: ret = safe_strdup (g, "apk"); break;
  case OS_PACKAGE_FORMAT_XBPS: ret = safe_strdup (g, "xbps"); break;
  case OS_PACKAGE_FORMAT_UNKNOWN:
    ret = safe_strdup (g, "unknown");
    break;
  }

  if (ret == NULL)
    abort ();

  return ret;
}

char *
guestfs_impl_inspect_get_package_management (guestfs_h *g, const char *root)
{
  char *ret = NULL;
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  switch (fs->package_management) {
  case OS_PACKAGE_MANAGEMENT_APK: ret = safe_strdup (g, "apk"); break;
  case OS_PACKAGE_MANAGEMENT_APT: ret = safe_strdup (g, "apt"); break;
  case OS_PACKAGE_MANAGEMENT_DNF: ret = safe_strdup (g, "dnf"); break;
  case OS_PACKAGE_MANAGEMENT_PACMAN: ret = safe_strdup (g, "pacman"); break;
  case OS_PACKAGE_MANAGEMENT_PISI: ret = safe_strdup (g, "pisi"); break;
  case OS_PACKAGE_MANAGEMENT_PORTAGE: ret = safe_strdup (g, "portage"); break;
  case OS_PACKAGE_MANAGEMENT_UP2DATE: ret = safe_strdup (g, "up2date"); break;
  case OS_PACKAGE_MANAGEMENT_URPMI: ret = safe_strdup (g, "urpmi"); break;
  case OS_PACKAGE_MANAGEMENT_XBPS: ret = safe_strdup (g, "xbps"); break;
  case OS_PACKAGE_MANAGEMENT_YUM: ret = safe_strdup (g, "yum"); break;
  case OS_PACKAGE_MANAGEMENT_ZYPPER: ret = safe_strdup (g, "zypper"); break;
  case OS_PACKAGE_MANAGEMENT_UNKNOWN:
    ret = safe_strdup (g, "unknown");
    break;
  }

  if (ret == NULL)
    abort ();

  return ret;
}

char *
guestfs_impl_inspect_get_hostname (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = guestfs_int_search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->hostname ? : "unknown");
}

void
guestfs_int_free_inspect_info (guestfs_h *g)
{
  size_t i, j;

  for (i = 0; i < g->nr_fses; ++i) {
    free (g->fses[i].mountable);
    free (g->fses[i].product_name);
    free (g->fses[i].product_variant);
    free (g->fses[i].arch);
    free (g->fses[i].hostname);
    free (g->fses[i].windows_systemroot);
    free (g->fses[i].windows_software_hive);
    free (g->fses[i].windows_system_hive);
    free (g->fses[i].windows_current_control_set);
    for (j = 0; j < g->fses[i].nr_fstab; ++j) {
      free (g->fses[i].fstab[j].mountable);
      free (g->fses[i].fstab[j].mountpoint);
    }
    free (g->fses[i].fstab);
    if (g->fses[i].drive_mappings)
      guestfs_int_free_string_list (g->fses[i].drive_mappings);
  }
  free (g->fses);
  g->nr_fses = 0;
  g->fses = NULL;
}

/**
 * Download a guest file to a local temporary file.  The file is
 * cached in the temporary directory, and is not downloaded again.
 *
 * The name of the temporary (downloaded) file is returned.  The
 * caller must free the pointer, but does I<not> need to delete the
 * temporary file.  It will be deleted when the handle is closed.
 *
 * Refuse to download the guest file if it is larger than C<max_size>.
 * On this and other errors, C<NULL> is returned.
 *
 * There is actually one cache per C<struct inspect_fs *> in order to
 * handle the case of multiple roots.
 */
char *
guestfs_int_download_to_tmp (guestfs_h *g,
			     const char *filename,
			     const char *basename, uint64_t max_size)
{
  char *r;
  int fd;
  char devfd[32];
  int64_t size;

  if (asprintf (&r, "%s/%s", g->tmpdir, basename) == -1) {
    perrorf (g, "asprintf");
    return NULL;
  }

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

/* Parse small, unsigned ints, as used in version numbers. */
int
guestfs_int_parse_unsigned_int (guestfs_h *g, const char *str)
{
  long ret;
  const int r = xstrtol (str, NULL, 10, &ret, "");
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}

/* Like parse_unsigned_int, but ignore trailing stuff. */
int
guestfs_int_parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str)
{
  long ret;
  const int r = xstrtol (str, NULL, 10, &ret, NULL);
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}

struct inspect_fs *
guestfs_int_search_for_root (guestfs_h *g, const char *root)
{
  size_t i;

  if (g->nr_fses == 0) {
    error (g, _("no inspection data: call guestfs_inspect_os first"));
    return NULL;
  }

  for (i = 0; i < g->nr_fses; ++i) {
    struct inspect_fs *fs = &g->fses[i];
    if (fs->role == OS_ROLE_ROOT && STREQ (root, fs->mountable))
      return fs;
  }

  error (g, _("%s: root device not found: only call this function with a root device previously returned by guestfs_inspect_os"),
         root);
  return NULL;
}

int
guestfs_int_is_partition (guestfs_h *g, const char *partition)
{
  CLEANUP_FREE char *device = NULL;

  guestfs_push_error_handler (g, NULL, NULL);

  if ((device = guestfs_part_to_dev (g, partition)) == NULL) {
    guestfs_pop_error_handler (g);
    return 0;
  }

  if (guestfs_device_index (g, device) == -1) {
    guestfs_pop_error_handler (g);
    return 0;
  }

  guestfs_pop_error_handler (g);

  return 1;
}
