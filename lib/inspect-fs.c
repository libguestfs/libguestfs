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
#include <unistd.h>
#include <string.h>
#include <libintl.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include <pcre.h>

#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "structs-cleanups.h"

static int check_filesystem (guestfs_h *g, const char *mountable,
                             const struct guestfs_internal_mountable *m,
                             int whole_device);
static void extend_fses (guestfs_h *g);
static int get_partition_context (guestfs_h *g, const char *partition, int *partnum_ret, int *nr_partitions_ret);
static int is_symlink_to (guestfs_h *g, const char *file, const char *wanted_target);

/* Find out if 'device' contains a filesystem.  If it does, add
 * another entry in g->fses.
 */
int
guestfs_int_check_for_filesystem_on (guestfs_h *g, const char *mountable)
{
  CLEANUP_FREE char *vfs_type = NULL;
  int is_swap, r;
  struct inspect_fs *fs;
  CLEANUP_FREE_INTERNAL_MOUNTABLE struct guestfs_internal_mountable *m = NULL;
  int whole_device = 0;

  /* Get vfs-type in order to check if it's a Linux(?) swap device.
   * If there's an error we should ignore it, so to do that we have to
   * temporarily replace the error handler with a null one.
   */
  guestfs_push_error_handler (g, NULL, NULL);
  vfs_type = guestfs_vfs_type (g, mountable);
  guestfs_pop_error_handler (g);

  is_swap = vfs_type && STREQ (vfs_type, "swap");
  debug (g, "check_for_filesystem_on: %s (%s)",
         mountable, vfs_type ? vfs_type : "failed to get vfs type");

  if (is_swap) {
    extend_fses (g);
    fs = &g->fses[g->nr_fses-1];
    fs->mountable = safe_strdup (g, mountable);
    return 0;
  }

  m = guestfs_internal_parse_mountable (g, mountable);
  if (m == NULL)
    return -1;

  /* If it's a whole device, see if it is an install ISO. */
  if (m->im_type == MOUNTABLE_DEVICE) {
    whole_device = guestfs_is_whole_device (g, m->im_device);
    if (whole_device == -1) {
      return -1;
    }
  }

  if (whole_device) {
    extend_fses (g);
    fs = &g->fses[g->nr_fses-1];

    r = guestfs_int_check_installer_iso (g, fs, m->im_device);
    if (r == -1) {              /* Fatal error. */
      g->nr_fses--;
      return -1;
    }
    if (r > 0)                  /* Found something. */
      return 0;

    /* Didn't find anything.  Fall through ... */
    g->nr_fses--;
  }

  /* Try mounting the device.  As above, ignore errors. */
  guestfs_push_error_handler (g, NULL, NULL);
  if (vfs_type && STREQ (vfs_type, "ufs")) { /* Hack for the *BSDs. */
    /* FreeBSD fs is a variant of ufs called ufs2 ... */
    r = guestfs_mount_vfs (g, "ro,ufstype=ufs2", "ufs", mountable, "/");
    if (r == -1)
      /* while NetBSD and OpenBSD use another variant labeled 44bsd */
      r = guestfs_mount_vfs (g, "ro,ufstype=44bsd", "ufs", mountable, "/");
  } else {
    r = guestfs_mount_ro (g, mountable, "/");
  }
  guestfs_pop_error_handler (g);
  if (r == -1)
    return 0;

  /* Do the rest of the checks. */
  r = check_filesystem (g, mountable, m, whole_device);

  /* Unmount the filesystem. */
  if (guestfs_umount_all (g) == -1)
    return -1;

  return r;
}

static int
check_filesystem (guestfs_h *g, const char *mountable,
                  const struct guestfs_internal_mountable *m,
                  int whole_device)
{
  int partnum = -1, nr_partitions = -1;
  /* Not CLEANUP_FREE, as it will be cleaned up with inspection info */
  char *windows_systemroot = NULL;

  extend_fses (g);

  if (!whole_device && m->im_type == MOUNTABLE_DEVICE &&
      guestfs_int_is_partition (g, m->im_device)) {
    if (get_partition_context (g, m->im_device,
                               &partnum, &nr_partitions) == -1)
      return -1;
  }

  struct inspect_fs *fs = &g->fses[g->nr_fses-1];

  fs->mountable = safe_strdup (g, mountable);

  /* Optimize some of the tests by avoiding multiple tests of the same thing. */
  const int is_dir_etc = guestfs_is_dir (g, "/etc") > 0;
  const int is_dir_bin = guestfs_is_dir (g, "/bin") > 0;
  const int is_dir_share = guestfs_is_dir (g, "/share") > 0;

  /* Grub /boot? */
  if (guestfs_is_file (g, "/grub/menu.lst") > 0 ||
      guestfs_is_file (g, "/grub/grub.conf") > 0 ||
      guestfs_is_file (g, "/grub2/grub.cfg") > 0)
    ;
  /* FreeBSD root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/etc/freebsd-update.conf") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_freebsd_root (g, fs) == -1)
      return -1;
  }
  /* NetBSD root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/netbsd") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0 &&
           guestfs_is_file (g, "/etc/release") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_netbsd_root (g, fs) == -1)
      return -1;
  }
  /* OpenBSD root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/bsd") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0 &&
           guestfs_is_file (g, "/etc/motd") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_openbsd_root (g, fs) == -1)
      return -1;
  }
  /* Hurd root? */
  else if (guestfs_is_file (g, "/hurd/console") > 0 &&
           guestfs_is_file (g, "/hurd/hello") > 0 &&
           guestfs_is_file (g, "/hurd/null") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED; /* XXX could be more specific */
    if (guestfs_int_check_hurd_root (g, fs) == -1)
      return -1;
  }
  /* Minix root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/service/vm") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0 &&
           guestfs_is_file (g, "/etc/version") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_minix_root (g, fs) == -1)
      return -1;
  }
  /* Linux root? */
  else if (is_dir_etc &&
           (is_dir_bin ||
            is_symlink_to (g, "/bin", "usr/bin") > 0) &&
           (guestfs_is_file (g, "/etc/fstab") > 0 ||
            guestfs_is_file (g, "/etc/hosts") > 0)) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_linux_root (g, fs) == -1)
      return -1;
  }
  /* CoreOS root? */
  else if (is_dir_etc &&
           guestfs_is_dir (g, "/root") > 0 &&
           guestfs_is_dir (g, "/home") > 0 &&
           guestfs_is_dir (g, "/usr") > 0 &&
           guestfs_is_file (g, "/etc/coreos/update.conf") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs_int_check_coreos_root (g, fs) == -1)
      return -1;
  }
  /* Linux /usr/local? */
  else if (is_dir_etc &&
           is_dir_bin &&
           is_dir_share &&
           guestfs_is_dir (g, "/local") == 0 &&
           guestfs_is_file (g, "/etc/fstab") == 0)
    ;
  /* Linux /usr? */
  else if (is_dir_etc &&
           is_dir_bin &&
           is_dir_share &&
           guestfs_is_dir (g, "/local") > 0 &&
           guestfs_is_file (g, "/etc/fstab") == 0) {
    if (guestfs_int_check_linux_usr (g, fs) == -1)
      return -1;
  }
  /* CoreOS /usr? */
  else if (is_dir_bin &&
           is_dir_share &&
           guestfs_is_dir (g, "/local") > 0 &&
           guestfs_is_dir (g, "/share/coreos") > 0) {
    if (guestfs_int_check_coreos_usr (g, fs) == -1)
      return -1;
  }
  /* Linux /var? */
  else if (guestfs_is_dir (g, "/log") > 0 &&
           guestfs_is_dir (g, "/run") > 0 &&
           guestfs_is_dir (g, "/spool") > 0)
    ;
  /* Windows root? */
  else if ((windows_systemroot = guestfs_int_get_windows_systemroot (g)) != NULL)
    {
      fs->role = OS_ROLE_ROOT;
      fs->format = OS_FORMAT_INSTALLED;
      if (guestfs_int_check_windows_root (g, fs, windows_systemroot) == -1)
	return -1;
    }
  /* Windows volume with installed applications (but not root)? */
  else if (guestfs_int_is_dir_nocase (g, "/System Volume Information") > 0 &&
           guestfs_int_is_dir_nocase (g, "/Program Files") > 0)
    ;
  /* Windows volume (but not root)? */
  else if (guestfs_int_is_dir_nocase (g, "/System Volume Information") > 0)
    ;
  /* FreeDOS? */
  else if (guestfs_int_is_dir_nocase (g, "/FDOS") > 0 &&
           guestfs_int_is_file_nocase (g, "/FDOS/FREEDOS.BSS") > 0) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    fs->type = OS_TYPE_DOS;
    fs->distro = OS_DISTRO_FREEDOS;
    /* FreeDOS is a mix of 16 and 32 bit, but assume it requires a
     * 32 bit i386 processor.
     */
    fs->arch = safe_strdup (g, "i386");
  }
  /* Install CD/disk?
   *
   * Note that we checked (above) for an install ISO, but there are
   * other types of install image (eg. USB keys) which that check
   * wouldn't have picked up.
   *
   * Skip these checks if it's not a whole device (eg. CD) or the
   * first partition (eg. bootable USB key).
   */
  else if ((whole_device || (partnum == 1 && nr_partitions == 1)) &&
           (guestfs_is_file (g, "/isolinux/isolinux.cfg") > 0 ||
            guestfs_is_dir (g, "/EFI/BOOT") > 0 ||
            guestfs_is_file (g, "/images/install.img") > 0 ||
            guestfs_is_dir (g, "/.disk") > 0 ||
            guestfs_is_file (g, "/.discinfo") > 0 ||
            guestfs_is_file (g, "/i386/txtsetup.sif") > 0 ||
            guestfs_is_file (g, "/amd64/txtsetup.sif") > 0 ||
            guestfs_is_file (g, "/freedos/freedos.ico") > 0 ||
            guestfs_is_file (g, "/boot/loader.rc") > 0)) {
    fs->role = OS_ROLE_ROOT;
    fs->format = OS_FORMAT_INSTALLER;
    if (guestfs_int_check_installer_root (g, fs) == -1)
      return -1;
  }

  /* The above code should have set fs->type and fs->distro fields, so
   * we can now guess the package management system.
   */
  guestfs_int_check_package_format (g, fs);
  guestfs_int_check_package_management (g, fs);

  return 0;
}

static void
extend_fses (guestfs_h *g)
{
  const size_t n = g->nr_fses + 1;
  struct inspect_fs *p;

  p = safe_realloc (g, g->fses, n * sizeof (struct inspect_fs));

  g->fses = p;
  g->nr_fses = n;

  memset (&g->fses[n-1], 0, sizeof (struct inspect_fs));
}

/* Given a partition (eg. /dev/sda2) then return the partition number
 * (eg. 2) and the total number of other partitions.
 */
static int
get_partition_context (guestfs_h *g, const char *partition,
                       int *partnum_ret, int *nr_partitions_ret)
{
  int partnum, nr_partitions;
  CLEANUP_FREE char *device = NULL;
  CLEANUP_FREE_PARTITION_LIST struct guestfs_partition_list *partitions = NULL;

  partnum = guestfs_part_to_partnum (g, partition);
  if (partnum == -1)
    return -1;

  device = guestfs_part_to_dev (g, partition);
  if (device == NULL)
    return -1;

  partitions = guestfs_part_list (g, device);
  if (partitions == NULL)
    return -1;

  nr_partitions = partitions->len;

  *partnum_ret = partnum;
  *nr_partitions_ret = nr_partitions;
  return 0;
}

static int
is_symlink_to (guestfs_h *g, const char *file, const char *wanted_target)
{
  CLEANUP_FREE char *target = NULL;

  if (guestfs_is_symlink (g, file) == 0)
    return 0;

  target = guestfs_readlink (g, file);
  /* This should not fail, but play safe. */
  if (target == NULL)
    return 0;

  return STREQ (target, wanted_target);
}

int
guestfs_int_is_file_nocase (guestfs_h *g, const char *path)
{
  CLEANUP_FREE char *p = NULL;
  int r;

  p = guestfs_int_case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_file (g, p);
  return r > 0;
}

int
guestfs_int_is_dir_nocase (guestfs_h *g, const char *path)
{
  CLEANUP_FREE char *p = NULL;
  int r;

  p = guestfs_int_case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_dir (g, p);
  return r > 0;
}

/* Parse generic MAJOR.MINOR from the fs->product_name string. */
int
guestfs_int_parse_major_minor (guestfs_h *g, struct inspect_fs *fs)
{
  if (guestfs_int_version_from_x_y (g, &fs->version, fs->product_name) == -1)
    return -1;

  return 0;
}

/* At the moment, package format and package management is just a
 * simple function of the distro and version.v_major fields, so these
 * can never return an error.  We might be cleverer in future.
 */
void
guestfs_int_check_package_format (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->distro) {
  case OS_DISTRO_FEDORA:
  case OS_DISTRO_MEEGO:
  case OS_DISTRO_REDHAT_BASED:
  case OS_DISTRO_RHEL:
  case OS_DISTRO_MAGEIA:
  case OS_DISTRO_MANDRIVA:
  case OS_DISTRO_SUSE_BASED:
  case OS_DISTRO_OPENSUSE:
  case OS_DISTRO_SLES:
  case OS_DISTRO_CENTOS:
  case OS_DISTRO_SCIENTIFIC_LINUX:
  case OS_DISTRO_ORACLE_LINUX:
  case OS_DISTRO_ALTLINUX:
    fs->package_format = OS_PACKAGE_FORMAT_RPM;
    break;

  case OS_DISTRO_DEBIAN:
  case OS_DISTRO_UBUNTU:
  case OS_DISTRO_LINUX_MINT:
    fs->package_format = OS_PACKAGE_FORMAT_DEB;
    break;

  case OS_DISTRO_ARCHLINUX:
    fs->package_format = OS_PACKAGE_FORMAT_PACMAN;
    break;
  case OS_DISTRO_GENTOO:
    fs->package_format = OS_PACKAGE_FORMAT_EBUILD;
    break;
  case OS_DISTRO_PARDUS:
    fs->package_format = OS_PACKAGE_FORMAT_PISI;
    break;

  case OS_DISTRO_ALPINE_LINUX:
    fs->package_format = OS_PACKAGE_FORMAT_APK;
    break;

  case OS_DISTRO_VOID_LINUX:
    fs->package_format = OS_PACKAGE_FORMAT_XBPS;
    break;

  case OS_DISTRO_SLACKWARE:
  case OS_DISTRO_TTYLINUX:
  case OS_DISTRO_COREOS:
  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_BUILDROOT:
  case OS_DISTRO_CIRROS:
  case OS_DISTRO_FREEDOS:
  case OS_DISTRO_FREEBSD:
  case OS_DISTRO_NETBSD:
  case OS_DISTRO_OPENBSD:
  case OS_DISTRO_FRUGALWARE:
  case OS_DISTRO_PLD_LINUX:
  case OS_DISTRO_UNKNOWN:
    fs->package_format = OS_PACKAGE_FORMAT_UNKNOWN;
    break;
  }
}

void
guestfs_int_check_package_management (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->distro) {
  case OS_DISTRO_MEEGO:
    fs->package_management = OS_PACKAGE_MANAGEMENT_YUM;
    break;

  case OS_DISTRO_FEDORA:
    /* If Fedora >= 22 and dnf is installed, say "dnf". */
    if (guestfs_int_version_ge (&fs->version, 22, 0, 0) &&
        guestfs_is_file_opts (g, "/usr/bin/dnf",
                              GUESTFS_IS_FILE_OPTS_FOLLOWSYMLINKS, 1, -1) > 0)
      fs->package_management = OS_PACKAGE_MANAGEMENT_DNF;
    else if (guestfs_int_version_ge (&fs->version, 1, 0, 0))
      fs->package_management = OS_PACKAGE_MANAGEMENT_YUM;
    else
      /* Probably parsing the release file failed, see RHBZ#1332025. */
      fs->package_management = OS_PACKAGE_MANAGEMENT_UNKNOWN;
    break;

  case OS_DISTRO_REDHAT_BASED:
  case OS_DISTRO_RHEL:
  case OS_DISTRO_CENTOS:
  case OS_DISTRO_SCIENTIFIC_LINUX:
  case OS_DISTRO_ORACLE_LINUX:
    if (guestfs_int_version_ge (&fs->version, 5, 0, 0))
      fs->package_management = OS_PACKAGE_MANAGEMENT_YUM;
    else if (guestfs_int_version_ge (&fs->version, 2, 0, 0))
      fs->package_management = OS_PACKAGE_MANAGEMENT_UP2DATE;
    else
      /* Probably parsing the release file failed, see RHBZ#1332025. */
      fs->package_management = OS_PACKAGE_MANAGEMENT_UNKNOWN;
    break;

  case OS_DISTRO_DEBIAN:
  case OS_DISTRO_UBUNTU:
  case OS_DISTRO_LINUX_MINT:
  case OS_DISTRO_ALTLINUX:
    fs->package_management = OS_PACKAGE_MANAGEMENT_APT;
    break;

  case OS_DISTRO_ARCHLINUX:
    fs->package_management = OS_PACKAGE_MANAGEMENT_PACMAN;
    break;
  case OS_DISTRO_GENTOO:
    fs->package_management = OS_PACKAGE_MANAGEMENT_PORTAGE;
    break;
  case OS_DISTRO_PARDUS:
    fs->package_management = OS_PACKAGE_MANAGEMENT_PISI;
    break;
  case OS_DISTRO_MAGEIA:
  case OS_DISTRO_MANDRIVA:
    fs->package_management = OS_PACKAGE_MANAGEMENT_URPMI;
    break;

  case OS_DISTRO_SUSE_BASED:
  case OS_DISTRO_OPENSUSE:
  case OS_DISTRO_SLES:
    fs->package_management = OS_PACKAGE_MANAGEMENT_ZYPPER;
    break;

  case OS_DISTRO_ALPINE_LINUX:
    fs->package_management = OS_PACKAGE_MANAGEMENT_APK;
    break;

  case OS_DISTRO_VOID_LINUX:
    fs->package_management = OS_PACKAGE_MANAGEMENT_XBPS;
    break;

  case OS_DISTRO_SLACKWARE:
  case OS_DISTRO_TTYLINUX:
  case OS_DISTRO_COREOS:
  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_BUILDROOT:
  case OS_DISTRO_CIRROS:
  case OS_DISTRO_FREEDOS:
  case OS_DISTRO_FREEBSD:
  case OS_DISTRO_NETBSD:
  case OS_DISTRO_OPENBSD:
  case OS_DISTRO_FRUGALWARE:
  case OS_DISTRO_PLD_LINUX:
  case OS_DISTRO_UNKNOWN:
    fs->package_management = OS_PACKAGE_MANAGEMENT_UNKNOWN;
    break;
  }
}

/* Get the first line of a small file, without any trailing newline
 * character.
 *
 * NOTE: If the file is completely empty or begins with a '\n'
 * character, this returns an empty string (not NULL).  The caller
 * will usually need to check for this case.
 */
char *
guestfs_int_first_line_of_file (guestfs_h *g, const char *filename)
{
  char **lines = NULL; /* sic: not CLEANUP_FREE_STRING_LIST */
  int64_t size;
  char *ret;

  /* Don't trust guestfs_head_n not to break with very large files.
   * Check the file size is something reasonable first.
   */
  size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    return NULL;
  if (size > MAX_SMALL_FILE_SIZE) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    return NULL;
  }

  lines = guestfs_head_n (g, 1, filename);
  if (lines == NULL)
    return NULL;
  if (lines[0] == NULL) {
    guestfs_int_free_string_list (lines);
    /* Empty file: Return an empty string as explained above. */
    return safe_strdup (g, "");
  }
  /* lines[1] should be NULL because of '1' argument above ... */

  ret = lines[0];               /* caller frees */

  free (lines);

  return ret;
}

/* Get the first matching line (using egrep [-i]) of a small file,
 * without any trailing newline character.
 *
 * Returns: 1 = returned a line (in *ret)
 *          0 = no match
 *          -1 = error
 */
int
guestfs_int_first_egrep_of_file (guestfs_h *g, const char *filename,
				 const char *eregex, int iflag, char **ret)
{
  char **lines;
  int64_t size;
  size_t i;
  struct guestfs_grep_opts_argv optargs;

  /* Don't trust guestfs_grep not to break with very large files.
   * Check the file size is something reasonable first.
   */
  size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    return -1;
  if (size > MAX_SMALL_FILE_SIZE) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    return -1;
  }

  optargs.bitmask = GUESTFS_GREP_OPTS_EXTENDED_BITMASK;
  optargs.extended = 1;
  if (iflag) {
    optargs.bitmask |= GUESTFS_GREP_OPTS_INSENSITIVE_BITMASK;
    optargs.insensitive = 1;
  }
  lines = guestfs_grep_opts_argv (g, eregex, filename, &optargs);
  if (lines == NULL)
    return -1;
  if (lines[0] == NULL) {
    guestfs_int_free_string_list (lines);
    return 0;
  }

  *ret = lines[0];              /* caller frees */

  /* free up any other matches and the array itself */
  for (i = 1; lines[i] != NULL; ++i)
    free (lines[i]);
  free (lines);

  return 1;
}

/* Merge the missing OS inspection information found on the src inspect_fs into
 * the ones of the dst inspect_fs. This function is useful if the inspection
 * information for an OS are gathered by inspecting multiple filesystems.
 */
void
guestfs_int_merge_fs_inspections (guestfs_h *g, struct inspect_fs *dst, struct inspect_fs *src)
{
  size_t n, i, old;
  struct inspect_fstab_entry *fstab = NULL;
  char ** mappings = NULL;

  if (dst->type == 0)
    dst->type = src->type;

  if (dst->distro == 0)
    dst->distro = src->distro;

  if (dst->package_format == 0)
    dst->package_format = src->package_format;

  if (dst->package_management == 0)
    dst->package_management = src->package_management;

  if (dst->product_name == NULL) {
    dst->product_name = src->product_name;
    src->product_name = NULL;
  }

  if (dst->product_variant == NULL) {
    dst->product_variant= src->product_variant;
    src->product_variant = NULL;
  }

  if (version_is_null (&dst->version))
    dst->version = src->version;

  if (dst->arch == NULL) {
    dst->arch = src->arch;
    src->arch = NULL;
  }

  if (dst->hostname == NULL) {
    dst->hostname = src->hostname;
    src->hostname = NULL;
  }

  if (dst->windows_systemroot == NULL) {
    dst->windows_systemroot = src->windows_systemroot;
    src->windows_systemroot = NULL;
  }

  if (dst->windows_current_control_set == NULL) {
    dst->windows_current_control_set = src->windows_current_control_set;
    src->windows_current_control_set = NULL;
  }

  if (src->drive_mappings != NULL) {
    if (dst->drive_mappings == NULL) {
      /* Adopt the drive mappings of src */
      dst->drive_mappings = src->drive_mappings;
      src->drive_mappings = NULL;
    } else {
      n = 0;
      for (; dst->drive_mappings[n] != NULL; n++)
        ;
      old = n;
      for (; src->drive_mappings[n] != NULL; n++)
        ;

      /* Merge the src mappings to dst */
      mappings = safe_realloc (g, dst->drive_mappings,(n + 1) * sizeof (char *));

      for (i = old; i < n; i++)
        mappings[i] = src->drive_mappings[i - old];

      mappings[n] = NULL;
      dst->drive_mappings = mappings;

      free(src->drive_mappings);
      src->drive_mappings = NULL;
    }
  }

  if (src->nr_fstab > 0) {
    n = dst->nr_fstab + src->nr_fstab;
    fstab = safe_realloc (g, dst->fstab, n * sizeof (struct inspect_fstab_entry));

    for (i = 0; i < src->nr_fstab; i++) {
      fstab[dst->nr_fstab + i].mountable = src->fstab[i].mountable;
      fstab[dst->nr_fstab + i].mountpoint = src->fstab[i].mountpoint;
    }
    free(src->fstab);
    src->fstab = NULL;
    src->nr_fstab = 0;

    dst->fstab = fstab;
    dst->nr_fstab = n;
  }
}
