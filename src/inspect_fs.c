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
#include <endian.h>

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

/* Compile all the regular expressions once when the shared library is
 * loaded.  PCRE is thread safe so we're supposedly OK here if
 * multiple threads call into the libguestfs API functions below
 * simultaneously.
 */
static pcre *re_first_partition;
static pcre *re_major_minor;

static void compile_regexps (void) __attribute__((constructor));
static void free_regexps (void) __attribute__((destructor));

static void
compile_regexps (void)
{
  const char *err;
  int offset;

#define COMPILE(re,pattern,options)                                     \
  do {                                                                  \
    re = pcre_compile ((pattern), (options), &err, &offset, NULL);      \
    if (re == NULL) {                                                   \
      ignore_value (write (2, err, strlen (err)));                      \
      abort ();                                                         \
    }                                                                   \
  } while (0)

  COMPILE (re_first_partition, "^/dev/(?:h|s|v)d.1$", 0);
  COMPILE (re_major_minor, "(\\d+)\\.(\\d+)", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_first_partition);
  pcre_free (re_major_minor);
}

static int check_filesystem (guestfs_h *g, const char *device, int is_block, int is_partnum);
static void check_package_format (guestfs_h *g, struct inspect_fs *fs);
static void check_package_management (guestfs_h *g, struct inspect_fs *fs);
static int extend_fses (guestfs_h *g);

/* Find out if 'device' contains a filesystem.  If it does, add
 * another entry in g->fses.
 */
int
guestfs___check_for_filesystem_on (guestfs_h *g, const char *device,
                                   int is_block, int is_partnum)
{
  /* Get vfs-type in order to check if it's a Linux(?) swap device.
   * If there's an error we should ignore it, so to do that we have to
   * temporarily replace the error handler with a null one.
   */
  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;
  char *vfs_type = guestfs_vfs_type (g, device);
  g->error_cb = old_error_cb;

  int is_swap = vfs_type && STREQ (vfs_type, "swap");

  debug (g, "check_for_filesystem_on: %s %d %d (%s)",
         device, is_block, is_partnum,
         vfs_type ? vfs_type : "failed to get vfs type");

  if (is_swap) {
    free (vfs_type);
    if (extend_fses (g) == -1)
      return -1;
    g->fses[g->nr_fses-1].is_swap = 1;
    return 0;
  }

  /* Try mounting the device.  As above, ignore errors. */
  g->error_cb = NULL;
  int r;
  if (vfs_type && STREQ (vfs_type, "ufs")) { /* Hack for the *BSDs. */
    /* FreeBSD fs is a variant of ufs called ufs2 ... */
    r = guestfs_mount_vfs (g, "ro,ufstype=ufs2", "ufs", device, "/");
    if (r == -1)
      /* while NetBSD and OpenBSD use another variant labeled 44bsd */
      r = guestfs_mount_vfs (g, "ro,ufstype=44bsd", "ufs", device, "/");
  } else {
    r = guestfs_mount_ro (g, device, "/");
  }
  free (vfs_type);
  g->error_cb = old_error_cb;
  if (r == -1)
    return 0;

  /* Do the rest of the checks. */
  r = check_filesystem (g, device, is_block, is_partnum);

  /* Unmount the filesystem. */
  if (guestfs_umount_all (g) == -1)
    return -1;

  return r;
}

/* is_block and is_partnum are just hints: is_block is true if the
 * filesystem is a whole block device (eg. /dev/sda).  is_partnum
 * is > 0 if the filesystem is a direct partition, and in this case
 * it is the partition number counting from 1
 * (eg. /dev/sda1 => is_partnum == 1).
 */
static int
check_filesystem (guestfs_h *g, const char *device,
                  int is_block, int is_partnum)
{
  if (extend_fses (g) == -1)
    return -1;

  struct inspect_fs *fs = &g->fses[g->nr_fses-1];

  fs->device = safe_strdup (g, device);
  fs->is_mountable = 1;

  /* Optimize some of the tests by avoiding multiple tests of the same thing. */
  int is_dir_etc = guestfs_is_dir (g, "/etc") > 0;
  int is_dir_bin = guestfs_is_dir (g, "/bin") > 0;
  int is_dir_share = guestfs_is_dir (g, "/share") > 0;

  /* Grub /boot? */
  if (guestfs_is_file (g, "/grub/menu.lst") > 0 ||
      guestfs_is_file (g, "/grub/grub.conf") > 0 ||
      guestfs_is_file (g, "/grub2/grub.cfg") > 0)
    fs->content = FS_CONTENT_LINUX_BOOT;
  /* FreeBSD root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/etc/freebsd-update.conf") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0) {
    /* Ignore /dev/sda1 which is a shadow of the real root filesystem
     * that is probably /dev/sda5 (see:
     * http://www.freebsd.org/doc/handbook/disk-organization.html)
     */
    if (match (g, device, re_first_partition))
      return 0;

    fs->is_root = 1;
    fs->content = FS_CONTENT_FREEBSD_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_freebsd_root (g, fs) == -1)
      return -1;
  }
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/etc/fstab") > 0 &&
           guestfs_is_file (g, "/etc/release") > 0) {
    /* Ignore /dev/sda1 which is a shadow of the real root filesystem
     * that is probably /dev/sda5 (see:
     * http://www.freebsd.org/doc/handbook/disk-organization.html)
     */
    if (match (g, device, re_first_partition))
      return 0;

    fs->is_root = 1;
    fs->content = FS_CONTENT_NETBSD_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_netbsd_root (g, fs) == -1)
      return -1;
  }
  /* Hurd root? */
  else if (guestfs_is_file (g, "/hurd/console") > 0 &&
           guestfs_is_file (g, "/hurd/hello") > 0 &&
           guestfs_is_file (g, "/hurd/null") > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_HURD_ROOT;
    fs->format = OS_FORMAT_INSTALLED; /* XXX could be more specific */
    if (guestfs___check_hurd_root (g, fs) == -1)
      return -1;
  }
  /* Linux root? */
  else if (is_dir_etc &&
           (is_dir_bin ||
            (guestfs_is_symlink (g, "/bin") > 0 &&
             guestfs_is_dir (g, "/usr/bin") > 0)) &&
           guestfs_is_file (g, "/etc/fstab") > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_LINUX_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_linux_root (g, fs) == -1)
      return -1;
  }
  /* Linux /usr/local? */
  else if (is_dir_etc &&
           is_dir_bin &&
           is_dir_share &&
           guestfs_exists (g, "/local") == 0 &&
           guestfs_is_file (g, "/etc/fstab") == 0)
    fs->content = FS_CONTENT_LINUX_USR_LOCAL;
  /* Linux /usr? */
  else if (is_dir_etc &&
           is_dir_bin &&
           is_dir_share &&
           guestfs_exists (g, "/local") > 0 &&
           guestfs_is_file (g, "/etc/fstab") == 0)
    fs->content = FS_CONTENT_LINUX_USR;
  /* Linux /var? */
  else if (guestfs_is_dir (g, "/log") > 0 &&
           guestfs_is_dir (g, "/run") > 0 &&
           guestfs_is_dir (g, "/spool") > 0)
    fs->content = FS_CONTENT_LINUX_VAR;
  /* Windows root? */
  else if (guestfs___has_windows_systemroot (g) >= 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_WINDOWS_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_windows_root (g, fs) == -1)
      return -1;
  }
  /* Windows volume with installed applications (but not root)? */
  else if (guestfs___is_dir_nocase (g, "/System Volume Information") > 0 &&
           guestfs___is_dir_nocase (g, "/Program Files") > 0)
    fs->content = FS_CONTENT_WINDOWS_VOLUME_WITH_APPS;
  /* Windows volume (but not root)? */
  else if (guestfs___is_dir_nocase (g, "/System Volume Information") > 0)
    fs->content = FS_CONTENT_WINDOWS_VOLUME;
  /* Install CD/disk?  Skip these checks if it's not a whole device
   * (eg. CD) or the first partition (eg. bootable USB key).
   */
  else if ((is_block || is_partnum == 1) &&
           (guestfs_is_file (g, "/isolinux/isolinux.cfg") > 0 ||
            guestfs_is_dir (g, "/EFI/BOOT") > 0 ||
            guestfs_is_file (g, "/images/install.img") > 0 ||
            guestfs_is_dir (g, "/.disk") > 0 ||
            guestfs_is_file (g, "/.discinfo") > 0 ||
            guestfs_is_file (g, "/i386/txtsetup.sif") > 0 ||
            guestfs_is_file (g, "/amd64/txtsetup.sif")) > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_INSTALLER;
    fs->format = OS_FORMAT_INSTALLER;
    if (guestfs___check_installer_root (g, fs) == -1)
      return -1;
  }

  /* The above code should have set fs->type and fs->distro fields, so
   * we can now guess the package management system.
   */
  check_package_format (g, fs);
  check_package_management (g, fs);

  return 0;
}

static int
extend_fses (guestfs_h *g)
{
  size_t n = g->nr_fses + 1;
  struct inspect_fs *p;

  p = realloc (g->fses, n * sizeof (struct inspect_fs));
  if (p == NULL) {
    perrorf (g, "realloc");
    return -1;
  }

  g->fses = p;
  g->nr_fses = n;

  memset (&g->fses[n-1], 0, sizeof (struct inspect_fs));

  return 0;
}

int
guestfs___is_file_nocase (guestfs_h *g, const char *path)
{
  char *p;
  int r;

  p = guestfs___case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_file (g, p);
  free (p);
  return r > 0;
}

int
guestfs___is_dir_nocase (guestfs_h *g, const char *path)
{
  char *p;
  int r;

  p = guestfs___case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_dir (g, p);
  free (p);
  return r > 0;
}

/* Parse small, unsigned ints, as used in version numbers. */
int
guestfs___parse_unsigned_int (guestfs_h *g, const char *str)
{
  long ret;
  int r = xstrtol (str, NULL, 10, &ret, "");
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}

/* Like parse_unsigned_int, but ignore trailing stuff. */
int
guestfs___parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str)
{
  long ret;
  int r = xstrtol (str, NULL, 10, &ret, NULL);
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}

/* Parse generic MAJOR.MINOR from the fs->product_name string. */
int
guestfs___parse_major_minor (guestfs_h *g, struct inspect_fs *fs)
{
  char *major, *minor;

  if (match2 (g, fs->product_name, re_major_minor, &major, &minor)) {
    fs->major_version = guestfs___parse_unsigned_int (g, major);
    free (major);
    if (fs->major_version == -1) {
      free (minor);
      return -1;
    }
    fs->minor_version = guestfs___parse_unsigned_int (g, minor);
    free (minor);
    if (fs->minor_version == -1)
      return -1;
  }
  return 0;
}

/* At the moment, package format and package management is just a
 * simple function of the distro and major_version fields, so these
 * can never return an error.  We might be cleverer in future.
 */
static void
check_package_format (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->distro) {
  case OS_DISTRO_FEDORA:
  case OS_DISTRO_MEEGO:
  case OS_DISTRO_REDHAT_BASED:
  case OS_DISTRO_RHEL:
  case OS_DISTRO_MAGEIA:
  case OS_DISTRO_MANDRIVA:
  case OS_DISTRO_OPENSUSE:
  case OS_DISTRO_CENTOS:
  case OS_DISTRO_SCIENTIFIC_LINUX:
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

  case OS_DISTRO_SLACKWARE:
  case OS_DISTRO_TTYLINUX:
  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_UNKNOWN:
  default:
    fs->package_format = OS_PACKAGE_FORMAT_UNKNOWN;
    break;
  }
}

static void
check_package_management (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->distro) {
  case OS_DISTRO_FEDORA:
  case OS_DISTRO_MEEGO:
    fs->package_management = OS_PACKAGE_MANAGEMENT_YUM;
    break;

  case OS_DISTRO_REDHAT_BASED:
  case OS_DISTRO_RHEL:
  case OS_DISTRO_CENTOS:
  case OS_DISTRO_SCIENTIFIC_LINUX:
    if (fs->major_version >= 5)
      fs->package_management = OS_PACKAGE_MANAGEMENT_YUM;
    else
      fs->package_management = OS_PACKAGE_MANAGEMENT_UP2DATE;
    break;

  case OS_DISTRO_DEBIAN:
  case OS_DISTRO_UBUNTU:
  case OS_DISTRO_LINUX_MINT:
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

  case OS_DISTRO_OPENSUSE:
    fs->package_management = OS_PACKAGE_MANAGEMENT_ZYPPER;
    break;

  case OS_DISTRO_SLACKWARE:
  case OS_DISTRO_TTYLINUX:
  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_UNKNOWN:
  default:
    fs->package_management = OS_PACKAGE_MANAGEMENT_UNKNOWN;
    break;
  }
}

/* Get the first line of a small file, without any trailing newline
 * character.
 */
char *
guestfs___first_line_of_file (guestfs_h *g, const char *filename)
{
  char **lines;
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
    error (g, _("%s: file is empty"), filename);
    guestfs___free_string_list (lines);
    return NULL;
  }
  /* lines[1] should be NULL because of '1' argument above ... */

  ret = lines[0];               /* caller frees */
  free (lines);                 /* free the array */

  return ret;
}

/* Get the first matching line (using guestfs_egrep{,i}) of a small file,
 * without any trailing newline character.
 *
 * Returns: 1 = returned a line (in *ret)
 *          0 = no match
 *          -1 = error
 */
int
guestfs___first_egrep_of_file (guestfs_h *g, const char *filename,
                               const char *eregex, int iflag, char **ret)
{
  char **lines;
  int64_t size;
  size_t i;

  /* Don't trust guestfs_egrep not to break with very large files.
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

  lines = (!iflag ? guestfs_egrep : guestfs_egrepi) (g, eregex, filename);
  if (lines == NULL)
    return -1;
  if (lines[0] == NULL) {
    guestfs___free_string_list (lines);
    return 0;
  }

  *ret = lines[0];              /* caller frees */

  /* free up any other matches and the array itself */
  for (i = 1; lines[i] != NULL; ++i)
    free (lines[i]);
  free (lines);

  return 1;
}

#endif /* defined(HAVE_HIVEX) */
