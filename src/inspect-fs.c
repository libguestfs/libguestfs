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

#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

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

static int check_filesystem (guestfs_h *g, const char *mountable,
                             const struct guestfs_internal_mountable *m,
                             int whole_device);
static int extend_fses (guestfs_h *g);

/* Find out if 'device' contains a filesystem.  If it does, add
 * another entry in g->fses.
 */
int
guestfs___check_for_filesystem_on (guestfs_h *g, const char *mountable)
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
    if (extend_fses (g) == -1)
      return -1;
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
    if (extend_fses (g) == -1)
      return -1;
    fs = &g->fses[g->nr_fses-1];

    r = guestfs___check_installer_iso (g, fs, m->im_device);
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
  /* Not CLEANUP_FREE, as it will be cleaned up with inspection info */
  char *windows_systemroot = NULL;

  if (extend_fses (g) == -1)
    return -1;

  int partnum = -1;
  if (!whole_device && m->im_type == MOUNTABLE_DEVICE) {
    guestfs_push_error_handler (g, NULL, NULL);
    partnum = guestfs_part_to_partnum (g, m->im_device);
    guestfs_pop_error_handler (g);
  }

  struct inspect_fs *fs = &g->fses[g->nr_fses-1];

  fs->mountable = safe_strdup (g, mountable);

  /* Optimize some of the tests by avoiding multiple tests of the same thing. */
  int is_dir_etc = guestfs_is_dir (g, "/etc") > 0;
  int is_dir_bin = guestfs_is_dir (g, "/bin") > 0;
  int is_dir_share = guestfs_is_dir (g, "/share") > 0;

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
    /* Ignore /dev/sda1 which is a shadow of the real root filesystem
     * that is probably /dev/sda5 (see:
     * http://www.freebsd.org/doc/handbook/disk-organization.html)
     */
    if (m->im_type == MOUNTABLE_DEVICE &&
        match (g, m->im_device, re_first_partition))
      return 0;

    fs->is_root = 1;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_freebsd_root (g, fs) == -1)
      return -1;
  }
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/etc/fstab") > 0 &&
           guestfs_is_file (g, "/etc/release") > 0 &&
           guestfs_is_file (g, "/etc/redhat-release") == 0) {
    /* Ignore /dev/sda1 which is a shadow of the real root filesystem
     * that is probably /dev/sda5 (see:
     * http://www.freebsd.org/doc/handbook/disk-organization.html)
     */
    if (m->im_type == MOUNTABLE_DEVICE &&
        match (g, m->im_device, re_first_partition))
      return 0;

    fs->is_root = 1;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_netbsd_root (g, fs) == -1)
      return -1;
  }
  /* Hurd root? */
  else if (guestfs_is_file (g, "/hurd/console") > 0 &&
           guestfs_is_file (g, "/hurd/hello") > 0 &&
           guestfs_is_file (g, "/hurd/null") > 0) {
    fs->is_root = 1;
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
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_linux_root (g, fs) == -1)
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
           guestfs_is_file (g, "/etc/fstab") == 0)
    ;
  /* Linux /var? */
  else if (guestfs_is_dir (g, "/log") > 0 &&
           guestfs_is_dir (g, "/run") > 0 &&
           guestfs_is_dir (g, "/spool") > 0)
    ;
  /* Windows root? */
  else if ((windows_systemroot = guestfs___get_windows_systemroot (g)) != NULL)
  {
    fs->is_root = 1;
    fs->format = OS_FORMAT_INSTALLED;
    if (guestfs___check_windows_root (g, fs, windows_systemroot) == -1)
      return -1;
  }
  /* Windows volume with installed applications (but not root)? */
  else if (guestfs___is_dir_nocase (g, "/System Volume Information") > 0 &&
           guestfs___is_dir_nocase (g, "/Program Files") > 0)
    ;
  /* Windows volume (but not root)? */
  else if (guestfs___is_dir_nocase (g, "/System Volume Information") > 0)
    ;
  /* FreeDOS? */
  else if (guestfs___is_dir_nocase (g, "/FDOS") > 0 &&
           guestfs___is_file_nocase (g, "/FDOS/FREEDOS.BSS") > 0) {
    fs->is_root = 1;
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
  else if ((whole_device || partnum == 1) &&
           (guestfs_is_file (g, "/isolinux/isolinux.cfg") > 0 ||
            guestfs_is_dir (g, "/EFI/BOOT") > 0 ||
            guestfs_is_file (g, "/images/install.img") > 0 ||
            guestfs_is_dir (g, "/.disk") > 0 ||
            guestfs_is_file (g, "/.discinfo") > 0 ||
            guestfs_is_file (g, "/i386/txtsetup.sif") > 0 ||
            guestfs_is_file (g, "/amd64/txtsetup.sif") > 0 ||
            guestfs_is_file (g, "/freedos/freedos.ico") > 0)) {
    fs->is_root = 1;
    fs->format = OS_FORMAT_INSTALLER;
    if (guestfs___check_installer_root (g, fs) == -1)
      return -1;
  }

  /* The above code should have set fs->type and fs->distro fields, so
   * we can now guess the package management system.
   */
  guestfs___check_package_format (g, fs);
  guestfs___check_package_management (g, fs);

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
  CLEANUP_FREE char *p = NULL;
  int r;

  p = guestfs___case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_file (g, p);
  return r > 0;
}

int
guestfs___is_dir_nocase (guestfs_h *g, const char *path)
{
  CLEANUP_FREE char *p = NULL;
  int r;

  p = guestfs___case_sensitive_path_silently (g, path);
  if (!p)
    return 0;
  r = guestfs_is_dir (g, p);
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
void
guestfs___check_package_format (guestfs_h *g, struct inspect_fs *fs)
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
  case OS_DISTRO_BUILDROOT:
  case OS_DISTRO_CIRROS:
  case OS_DISTRO_FREEDOS:
  case OS_DISTRO_OPENBSD:
  case OS_DISTRO_UNKNOWN:
    fs->package_format = OS_PACKAGE_FORMAT_UNKNOWN;
    break;
  }
}

void
guestfs___check_package_management (guestfs_h *g, struct inspect_fs *fs)
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

  case OS_DISTRO_SUSE_BASED:
  case OS_DISTRO_OPENSUSE:
  case OS_DISTRO_SLES:
    fs->package_management = OS_PACKAGE_MANAGEMENT_ZYPPER;
    break;

  case OS_DISTRO_SLACKWARE:
  case OS_DISTRO_TTYLINUX:
  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_BUILDROOT:
  case OS_DISTRO_CIRROS:
  case OS_DISTRO_FREEDOS:
  case OS_DISTRO_OPENBSD:
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
guestfs___first_line_of_file (guestfs_h *g, const char *filename)
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
    guestfs___free_string_list (lines);
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
guestfs___first_egrep_of_file (guestfs_h *g, const char *filename,
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
