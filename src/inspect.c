/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
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
#include <string.h>
#include <sys/stat.h>

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

/* Some limits on what we will read, for safety. */

/* Small text configuration files.
 *
 * The upper limit is for general files that we grep or download.  The
 * largest such file is probably "txtsetup.sif" from Windows CDs
 * (~500K).  This number has to be larger than any legitimate file and
 * smaller than the protocol message size.
 *
 * The lower limit is for files parsed by Augeas on the daemon side,
 * where Augeas is running in reduced memory and can potentially
 * create a lot of metadata so we really need to be careful about
 * those.
 */
#define MAX_SMALL_FILE_SIZE    (2 * 1000 * 1000)
#define MAX_AUGEAS_FILE_SIZE        (100 * 1000)

/* Maximum Windows Registry hive that we will download to /tmp.  Some
 * registries can be legitimately very large.
 */
#define MAX_REGISTRY_SIZE    (100 * 1000 * 1000)

/* Maximum RPM or dpkg database we will download to /tmp. */
#define MAX_PKG_DB_SIZE       (10 * 1000 * 1000)

/* Compile all the regular expressions once when the shared library is
 * loaded.  PCRE is thread safe so we're supposedly OK here if
 * multiple threads call into the libguestfs API functions below
 * simultaneously.
 */
static pcre *re_fedora;
static pcre *re_rhel_old;
static pcre *re_rhel;
static pcre *re_rhel_no_minor;
static pcre *re_major_minor;
static pcre *re_aug_seq;
static pcre *re_xdev;
static pcre *re_first_partition;
static pcre *re_freebsd;
static pcre *re_windows_version;

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

  COMPILE (re_fedora, "Fedora release (\\d+)", 0);
  COMPILE (re_rhel_old,
           "(?:Red Hat|CentOS|Scientific Linux).*release (\\d+).*Update (\\d+)", 0);
  COMPILE (re_rhel,
           "(?:Red Hat|CentOS|Scientific Linux).*release (\\d+)\\.(\\d+)", 0);
  COMPILE (re_rhel_no_minor,
           "(?:Red Hat|CentOS|Scientific Linux).*release (\\d+)", 0);
  COMPILE (re_major_minor, "(\\d+)\\.(\\d+)", 0);
  COMPILE (re_aug_seq, "/\\d+$", 0);
  COMPILE (re_xdev, "^/dev/(?:h|s|v|xv)d([a-z]\\d*)$", 0);
  COMPILE (re_first_partition, "^/dev/(?:h|s|v)d.1$", 0);
  COMPILE (re_freebsd, "^/dev/ad(\\d+)s(\\d+)([a-z])$", 0);
  COMPILE (re_windows_version, "^(\\d+)\\.(\\d+)", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_fedora);
  pcre_free (re_rhel_old);
  pcre_free (re_rhel);
  pcre_free (re_rhel_no_minor);
  pcre_free (re_major_minor);
  pcre_free (re_aug_seq);
  pcre_free (re_xdev);
  pcre_free (re_first_partition);
  pcre_free (re_freebsd);
  pcre_free (re_windows_version);
}

/* The main inspection code. */
static int check_for_filesystem_on (guestfs_h *g, const char *device, int is_block, int is_partnum);

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
  char **devices;
  devices = guestfs_list_devices (g);
  if (devices == NULL)
    return NULL;

  size_t i;
  for (i = 0; devices[i] != NULL; ++i) {
    if (check_for_filesystem_on (g, devices[i], 1, 0) == -1) {
      guestfs___free_string_list (devices);
      guestfs___free_inspect_info (g);
      return NULL;
    }
  }
  guestfs___free_string_list (devices);

  /* Look at all partitions. */
  char **partitions;
  partitions = guestfs_list_partitions (g);
  if (partitions == NULL) {
    guestfs___free_inspect_info (g);
    return NULL;
  }

  for (i = 0; partitions[i] != NULL; ++i) {
    if (check_for_filesystem_on (g, partitions[i], 0, i+1) == -1) {
      guestfs___free_string_list (partitions);
      guestfs___free_inspect_info (g);
      return NULL;
    }
  }
  guestfs___free_string_list (partitions);

  /* Look at all LVs. */
  if (guestfs___feature_available (g, "lvm2")) {
    char **lvs;
    lvs = guestfs_lvs (g);
    if (lvs == NULL) {
      guestfs___free_inspect_info (g);
      return NULL;
    }

    for (i = 0; lvs[i] != NULL; ++i) {
      if (check_for_filesystem_on (g, lvs[i], 0, 0) == -1) {
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

/* Find out if 'device' contains a filesystem.  If it does, add
 * another entry in g->fses.
 */
static int check_filesystem (guestfs_h *g, const char *device, int is_block, int is_partnum);
static int check_linux_root (guestfs_h *g, struct inspect_fs *fs);
static int check_freebsd_root (guestfs_h *g, struct inspect_fs *fs);
static int check_installer_root (guestfs_h *g, struct inspect_fs *fs);
static void check_architecture (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_unix (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_redhat (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_freebsd (guestfs_h *g, struct inspect_fs *fs);
static int check_fstab (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_root (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_arch (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_software_registry (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs);
static char *resolve_windows_path_silently (guestfs_h *g, const char *);
static int extend_fses (guestfs_h *g);
static int parse_unsigned_int (guestfs_h *g, const char *str);
static int parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str);
static int add_fstab_entry (guestfs_h *g, struct inspect_fs *fs,
                            const char *spec, const char *mp);
static char *resolve_fstab_device (guestfs_h *g, const char *spec);
static void check_package_format (guestfs_h *g, struct inspect_fs *fs);
static void check_package_management (guestfs_h *g, struct inspect_fs *fs);
static int download_to_tmp (guestfs_h *g, const char *filename, char *localtmp, int64_t max_size);
static int inspect_with_augeas (guestfs_h *g, struct inspect_fs *fs, const char *filename, int (*f) (guestfs_h *, struct inspect_fs *));
static char *first_line_of_file (guestfs_h *g, const char *filename);
static int first_egrep_of_file (guestfs_h *g, const char *filename, const char *eregex, int iflag, char **ret);

static int
check_for_filesystem_on (guestfs_h *g, const char *device,
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

  if (g->verbose)
    fprintf (stderr, "check_for_filesystem_on: %s %d %d (%s)\n",
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
  int r = guestfs_mount_ro (g, device, "/");
  if (r == -1 && vfs_type && STREQ (vfs_type, "ufs")) /* Hack for the *BSDs. */
    r = guestfs_mount_vfs (g, "ro,ufstype=ufs2", "ufs", device, "/");
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
      guestfs_is_file (g, "/grub/grub.conf") > 0)
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
    if (check_freebsd_root (g, fs) == -1)
      return -1;
  }
  /* Linux root? */
  else if (is_dir_etc &&
           is_dir_bin &&
           guestfs_is_file (g, "/etc/fstab") > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_LINUX_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (check_linux_root (g, fs) == -1)
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
  else if (guestfs_is_file (g, "/AUTOEXEC.BAT") > 0 ||
           guestfs_is_file (g, "/autoexec.bat") > 0 ||
           guestfs_is_dir (g, "/Program Files") > 0 ||
           guestfs_is_dir (g, "/WINDOWS") > 0 ||
           guestfs_is_dir (g, "/Windows") > 0 ||
           guestfs_is_dir (g, "/windows") > 0 ||
           guestfs_is_dir (g, "/WIN32") > 0 ||
           guestfs_is_dir (g, "/Win32") > 0 ||
           guestfs_is_dir (g, "/WINNT") > 0 ||
           guestfs_is_file (g, "/boot.ini") > 0 ||
           guestfs_is_file (g, "/ntldr") > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_WINDOWS_ROOT;
    fs->format = OS_FORMAT_INSTALLED;
    if (check_windows_root (g, fs) == -1)
      return -1;
  }
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
    if (check_installer_root (g, fs) == -1)
      return -1;
  }

  return 0;
}

/* Set fs->product_name to the first line of the release file. */
static int
parse_release_file (guestfs_h *g, struct inspect_fs *fs,
                    const char *release_filename)
{
  fs->product_name = first_line_of_file (g, release_filename);
  if (fs->product_name == NULL)
    return -1;
  return 0;
}

/* Parse generic MAJOR.MINOR from the fs->product_name string. */
static int
parse_major_minor (guestfs_h *g, struct inspect_fs *fs)
{
  char *major, *minor;

  if (match2 (g, fs->product_name, re_major_minor, &major, &minor)) {
    fs->major_version = parse_unsigned_int (g, major);
    free (major);
    if (fs->major_version == -1) {
      free (minor);
      return -1;
    }
    fs->minor_version = parse_unsigned_int (g, minor);
    free (minor);
    if (fs->minor_version == -1)
      return -1;
  }
  return 0;
}

/* Ubuntu has /etc/lsb-release containing:
 *   DISTRIB_ID=Ubuntu                                # Distro
 *   DISTRIB_RELEASE=10.04                            # Version
 *   DISTRIB_CODENAME=lucid
 *   DISTRIB_DESCRIPTION="Ubuntu 10.04.1 LTS"         # Product name
 *
 * [Ubuntu-derived ...] Linux Mint was found to have this:
 *   DISTRIB_ID=LinuxMint
 *   DISTRIB_RELEASE=10
 *   DISTRIB_CODENAME=julia
 *   DISTRIB_DESCRIPTION="Linux Mint 10 Julia"
 * Linux Mint also has /etc/linuxmint/info with more information,
 * but we can use the LSB file.
 *
 * Mandriva has:
 *   LSB_VERSION=lsb-4.0-amd64:lsb-4.0-noarch
 *   DISTRIB_ID=MandrivaLinux
 *   DISTRIB_RELEASE=2010.1
 *   DISTRIB_CODENAME=Henry_Farman
 *   DISTRIB_DESCRIPTION="Mandriva Linux 2010.1"
 * Mandriva also has a normal release file called /etc/mandriva-release.
 */
static int
parse_lsb_release (guestfs_h *g, struct inspect_fs *fs)
{
  const char *filename = "/etc/lsb-release";
  int64_t size;
  char **lines;
  size_t i;
  int r = 0;

  /* Don't trust guestfs_head_n not to break with very large files.
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

  lines = guestfs_head_n (g, 10, filename);
  if (lines == NULL)
    return -1;

  for (i = 0; lines[i] != NULL; ++i) {
    if (fs->distro == 0 &&
        STREQ (lines[i], "DISTRIB_ID=Ubuntu")) {
      fs->distro = OS_DISTRO_UBUNTU;
      r = 1;
    }
    else if (fs->distro == 0 &&
             STREQ (lines[i], "DISTRIB_ID=LinuxMint")) {
      fs->distro = OS_DISTRO_LINUX_MINT;
      r = 1;
    }
    else if (fs->distro == 0 &&
             STREQ (lines[i], "DISTRIB_ID=MandrivaLinux")) {
      fs->distro = OS_DISTRO_MANDRIVA;
      r = 1;
    }
    else if (STRPREFIX (lines[i], "DISTRIB_RELEASE=")) {
      char *major, *minor;
      if (match2 (g, &lines[i][16], re_major_minor, &major, &minor)) {
        fs->major_version = parse_unsigned_int (g, major);
        free (major);
        if (fs->major_version == -1) {
          free (minor);
          guestfs___free_string_list (lines);
          return -1;
        }
        fs->minor_version = parse_unsigned_int (g, minor);
        free (minor);
        if (fs->minor_version == -1) {
          guestfs___free_string_list (lines);
          return -1;
        }
      }
    }
    else if (fs->product_name == NULL &&
             (STRPREFIX (lines[i], "DISTRIB_DESCRIPTION=\"") ||
              STRPREFIX (lines[i], "DISTRIB_DESCRIPTION='"))) {
      size_t len = strlen (lines[i]) - 21 - 1;
      fs->product_name = safe_strndup (g, &lines[i][21], len);
      r = 1;
    }
    else if (fs->product_name == NULL &&
             STRPREFIX (lines[i], "DISTRIB_DESCRIPTION=")) {
      size_t len = strlen (lines[i]) - 20;
      fs->product_name = safe_strndup (g, &lines[i][20], len);
      r = 1;
    }
  }

  guestfs___free_string_list (lines);
  return r;
}

/* The currently mounted device is known to be a Linux root.  Try to
 * determine from this the distro, version, etc.  Also parse
 * /etc/fstab to determine the arrangement of mountpoints and
 * associated devices.
 */
static int
check_linux_root (guestfs_h *g, struct inspect_fs *fs)
{
  int r;

  fs->type = OS_TYPE_LINUX;

  if (guestfs_exists (g, "/etc/lsb-release") > 0) {
    r = parse_lsb_release (g, fs);
    if (r == -1)        /* error */
      return -1;
    if (r == 1)         /* ok - detected the release from this file */
      goto skip_release_checks;
  }

  if (guestfs_exists (g, "/etc/redhat-release") > 0) {
    fs->distro = OS_DISTRO_REDHAT_BASED; /* Something generic Red Hat-like. */

    if (parse_release_file (g, fs, "/etc/redhat-release") == -1)
      return -1;

    char *major, *minor;
    if ((major = match1 (g, fs->product_name, re_fedora)) != NULL) {
      fs->distro = OS_DISTRO_FEDORA;
      fs->major_version = parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1)
        return -1;
    }
    else if (match2 (g, fs->product_name, re_rhel_old, &major, &minor) ||
             match2 (g, fs->product_name, re_rhel, &major, &minor)) {
      fs->distro = OS_DISTRO_RHEL;
      fs->major_version = parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1) {
        free (minor);
        return -1;
      }
      fs->minor_version = parse_unsigned_int (g, minor);
      free (minor);
      if (fs->minor_version == -1)
        return -1;
    }
    else if ((major = match1 (g, fs->product_name, re_rhel_no_minor)) != NULL) {
      fs->distro = OS_DISTRO_RHEL;
      fs->major_version = parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1)
        return -1;
      fs->minor_version = 0;
    }
  }
  else if (guestfs_exists (g, "/etc/debian_version") > 0) {
    fs->distro = OS_DISTRO_DEBIAN;

    if (parse_release_file (g, fs, "/etc/debian_version") == -1)
      return -1;

    if (parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/pardus-release") > 0) {
    fs->distro = OS_DISTRO_PARDUS;

    if (parse_release_file (g, fs, "/etc/pardus-release") == -1)
      return -1;

    if (parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/arch-release") > 0) {
    fs->distro = OS_DISTRO_ARCHLINUX;

    /* /etc/arch-release file is empty and I can't see a way to
     * determine the actual release or product string.
     */
  }
  else if (guestfs_exists (g, "/etc/gentoo-release") > 0) {
    fs->distro = OS_DISTRO_GENTOO;

    if (parse_release_file (g, fs, "/etc/gentoo-release") == -1)
      return -1;

    if (parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/meego-release") > 0) {
    fs->distro = OS_DISTRO_MEEGO;

    if (parse_release_file (g, fs, "/etc/meego-release") == -1)
      return -1;

    if (parse_major_minor (g, fs) == -1)
      return -1;
  }

 skip_release_checks:;

  /* If distro test above was successful, work out the package format. */
  check_package_format (g, fs);
  check_package_management (g, fs);

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* We already know /etc/fstab exists because it's part of the test
   * for Linux root above.  We must now parse this file to determine
   * which filesystems are used by the operating system and how they
   * are mounted.
   */
  if (inspect_with_augeas (g, fs, "/etc/fstab", check_fstab) == -1)
    return -1;

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
    return -1;

  return 0;
}

/* The currently mounted device is known to be a FreeBSD root. */
static int
check_freebsd_root (guestfs_h *g, struct inspect_fs *fs)
{
  fs->type = OS_TYPE_FREEBSD;

  /* FreeBSD has no authoritative version file.  The version number is
   * in /etc/motd, which the system administrator might edit, but
   * we'll use that anyway.
   */

  if (guestfs_exists (g, "/etc/motd") > 0) {
    if (parse_release_file (g, fs, "/etc/motd") == -1)
      return -1;

    if (parse_major_minor (g, fs) == -1)
      return -1;
  }

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* We already know /etc/fstab exists because it's part of the test above. */
  if (inspect_with_augeas (g, fs, "/etc/fstab", check_fstab) == -1)
    return -1;

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
    return -1;

  return 0;
}

/* Debian/Ubuntu install disks are easy ...
 *
 * These files are added by the debian-cd program, and it is worth
 * looking at the source code to determine exact values, in
 * particular '/usr/share/debian-cd/tools/start_new_disc'
 *
 * XXX Architecture?  We could parse it out of the product name
 * string, but that seems quite hairy.  We could look for the names
 * of packages.  Also note that some Debian install disks are
 * multiarch.
 */
static int
check_debian_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  fs->product_name = first_line_of_file (g, "/.disk/info");
  if (!fs->product_name)
    return -1;

  fs->type = OS_TYPE_LINUX;
  if (STRPREFIX (fs->product_name, "Ubuntu"))
    fs->distro = OS_DISTRO_UBUNTU;
  else if (STRPREFIX (fs->product_name, "Debian"))
    fs->distro = OS_DISTRO_DEBIAN;

  (void) parse_major_minor (g, fs);

  if (guestfs_is_file (g, "/.disk/cd_type") > 0) {
    char *cd_type = first_line_of_file (g, "/.disk/cd_type");
    if (!cd_type)
      return -1;

    if (STRPREFIX (cd_type, "dvd/single") ||
        STRPREFIX (cd_type, "full_cd/single")) {
      fs->is_multipart_disk = 0;
      fs->is_netinst_disk = 0;
    }
    else if (STRPREFIX (cd_type, "dvd") ||
             STRPREFIX (cd_type, "full_cd")) {
      fs->is_multipart_disk = 1;
      fs->is_netinst_disk = 0;
    }
    else if (STRPREFIX (cd_type, "not_complete")) {
      fs->is_multipart_disk = 0;
      fs->is_netinst_disk = 1;
    }

    free (cd_type);
  }

  return 0;
}

/* Take string which must look like "key = value" and find the value.
 * There may or may not be spaces before and after the equals sign.
 * This function is used by both check_fedora_installer_root and
 * check_w2k3_installer_root.
 */
static const char *
find_value (const char *kv)
{
  const char *p;

  p = strchr (kv, '=');
  if (!p)
    abort ();

  do {
    ++p;
  } while (c_isspace (*p));

  return p;
}

/* Fedora CDs and DVD (not netinst).  The /.treeinfo file contains
 * an initial section somewhat like this:
 *
 * [general]
 * version = 14
 * arch = x86_64
 * family = Fedora
 * variant = Fedora
 * discnum = 1
 * totaldiscs = 1
 */
static int
check_fedora_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  char *str;
  const char *v;
  int r;
  int discnum = 0, totaldiscs = 0;

  fs->type = OS_TYPE_LINUX;

  r = first_egrep_of_file (g, "/.treeinfo",
                           "^family = Fedora$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_FEDORA;
    free (str);
  }

  r = first_egrep_of_file (g, "/.treeinfo",
                           "^family = Red Hat Enterprise Linux$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_RHEL;
    free (str);
  }

  /* XXX should do major.minor before this */
  r = first_egrep_of_file (g, "/.treeinfo",
                           "^version = [[:digit:]]+", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    fs->major_version = parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  r = first_egrep_of_file (g, "/.treeinfo",
                           "^arch = [-_[:alnum:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    fs->arch = safe_strdup (g, v);
    free (str);
  }

  r = first_egrep_of_file (g, "/.treeinfo",
                           "^discnum = [[:digit:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    discnum = parse_unsigned_int (g, v);
    free (str);
    if (discnum == -1)
      return -1;
  }

  r = first_egrep_of_file (g, "/.treeinfo",
                           "^totaldiscs = [[:digit:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    totaldiscs = parse_unsigned_int (g, v);
    free (str);
    if (totaldiscs == -1)
      return -1;
  }

  fs->is_multipart_disk = totaldiscs > 0;
  /* and what about discnum? */

  return 0;
}

/* Linux with /isolinux/isolinux.cfg.
 *
 * This file is not easily parsable so we have to do our best.
 * Look for the "menu title" line which contains:
 *   menu title Welcome to Fedora 14!   # since at least Fedora 10
 *   menu title Welcome to Red Hat Enterprise Linux 6.0!
 */
static int
check_isolinux_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  char *str;
  int r;

  fs->type = OS_TYPE_LINUX;

  r = first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                           "^menu title Welcome to Fedora [[:digit:]]+",
                           0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_FEDORA;
    fs->major_version = parse_unsigned_int_ignore_trailing (g, &str[29]);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  /* XXX parse major.minor */
  r = first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                           "^menu title Welcome to Red Hat Enterprise Linux [[:digit:]]+",
                           0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_RHEL;
    fs->major_version = parse_unsigned_int_ignore_trailing (g, &str[47]);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  return 0;
}

/* Windows 2003 and similar versions.
 *
 * NB: txtsetup file contains Windows \r\n line endings, which guestfs_grep
 * does not remove.  We have to remove them by hand here.
 */
static void
trim_cr (char *str)
{
  size_t n = strlen (str);
  if (n > 0 && str[n-1] == '\r')
    str[n-1] = '\0';
}

static void
trim_quot (char *str)
{
  size_t n = strlen (str);
  if (n > 0 && str[n-1] == '"')
    str[n-1] = '\0';
}

static int
check_w2k3_installer_root (guestfs_h *g, struct inspect_fs *fs,
                           const char *txtsetup)
{
  char *str;
  const char *v;
  int r;

  fs->type = OS_TYPE_WINDOWS;
  fs->distro = OS_DISTRO_WINDOWS;

  r = first_egrep_of_file (g, txtsetup,
                           "^productname[[:space:]]*=[[:space:]]*\"", 1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    trim_quot (str);
    v = find_value (str);
    fs->product_name = safe_strdup (g, v+1);
    free (str);
  }

  r = first_egrep_of_file (g, txtsetup,
                           "^majorversion[[:space:]]*=[[:space:]]*[[:digit:]]+",
                           1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    v = find_value (str);
    fs->major_version = parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  r = first_egrep_of_file (g, txtsetup,
                           "^minorversion[[:space:]]*=[[:space:]]*[[:digit:]]+",
                           1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    v = find_value (str);
    fs->minor_version = parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->minor_version == -1)
      return -1;
  }

  /* This is the windows systemroot that would be chosen on
   * installation by default, although not necessarily the one that
   * the user will finally choose.
   */
  r = first_egrep_of_file (g, txtsetup, "^defaultpath[[:space:]]*=[[:space:]]*",
                           1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    v = find_value (str);
    fs->windows_systemroot = safe_strdup (g, v);
    free (str);
  }

  return 0;
}

/* The currently mounted device is very likely to be an installer. */
static int
check_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  /* The presence of certain files indicates a live CD.
   *
   * XXX Fedora netinst contains a ~120MB squashfs called
   * /images/install.img.  However this is not a live CD (unlike the
   * Fedora live CDs which contain the same, but larger file).  We
   * need to unpack this and look inside to tell the difference.
   */
  if (guestfs_is_file (g, "/casper/filesystem.squashfs") > 0)
    fs->is_live_disk = 1;

  /* Debian/Ubuntu. */
  if (guestfs_is_file (g, "/.disk/info") > 0) {
    if (check_debian_installer_root (g, fs) == -1)
      return -1;
  }

  /* Fedora CDs and DVD (not netinst). */
  else if (guestfs_is_file (g, "/.treeinfo") > 0) {
    if (check_fedora_installer_root (g, fs) == -1)
      return -1;
  }

  /* Linux with /isolinux/isolinux.cfg. */
  else if (guestfs_is_file (g, "/isolinux/isolinux.cfg") > 0) {
    if (check_isolinux_installer_root (g, fs) == -1)
      return -1;
  }

  /* Windows 2003 64 bit */
  else if (guestfs_is_file (g, "/amd64/txtsetup.sif") > 0) {
    fs->arch = safe_strdup (g, "x86_64");
    if (check_w2k3_installer_root (g, fs, "/amd64/txtsetup.sif") == -1)
      return -1;
  }

  /* Windows 2003 32 bit */
  else if (guestfs_is_file (g, "/i386/txtsetup.sif") > 0) {
    fs->arch = safe_strdup (g, "i386");
    if (check_w2k3_installer_root (g, fs, "/i386/txtsetup.sif") == -1)
      return -1;
  }

  return 0;
}

static void
check_architecture (guestfs_h *g, struct inspect_fs *fs)
{
  const char *binaries[] =
    { "/bin/bash", "/bin/ls", "/bin/echo", "/bin/rm", "/bin/sh" };
  size_t i;

  for (i = 0; i < sizeof binaries / sizeof binaries[0]; ++i) {
    if (guestfs_is_file (g, binaries[i]) > 0) {
      /* Ignore errors from file_architecture call. */
      guestfs_error_handler_cb old_error_cb = g->error_cb;
      g->error_cb = NULL;
      char *arch = guestfs_file_architecture (g, binaries[i]);
      g->error_cb = old_error_cb;

      if (arch) {
        /* String will be owned by handle, freed by
         * guestfs___free_inspect_info.
         */
        fs->arch = arch;
        break;
      }
    }
  }
}

/* Try several methods to determine the hostname from a Linux or
 * FreeBSD guest.  Note that type and distro have been set, so we can
 * use that information to direct the search.
 */
static int
check_hostname_unix (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->type) {
  case OS_TYPE_LINUX:
    /* Red Hat-derived would be in /etc/sysconfig/network, and
     * Debian-derived in the file /etc/hostname.  Very old Debian and
     * SUSE use /etc/HOSTNAME.  It's best to just look for each of
     * these files in turn, rather than try anything clever based on
     * distro.
     */
    if (guestfs_is_file (g, "/etc/HOSTNAME")) {
      fs->hostname = first_line_of_file (g, "/etc/HOSTNAME");
      if (fs->hostname == NULL)
        return -1;
    }
    else if (guestfs_is_file (g, "/etc/hostname")) {
      fs->hostname = first_line_of_file (g, "/etc/hostname");
      if (fs->hostname == NULL)
        return -1;
    }
    else if (guestfs_is_file (g, "/etc/sysconfig/network")) {
      if (inspect_with_augeas (g, fs, "/etc/sysconfig/network",
                               check_hostname_redhat) == -1)
        return -1;
    }
    break;

  case OS_TYPE_FREEBSD:
    /* /etc/rc.conf contains the hostname, but there is no Augeas lens
     * for this file.
     */
    if (guestfs_is_file (g, "/etc/rc.conf")) {
      if (check_hostname_freebsd (g, fs) == -1)
        return -1;
    }
    break;

  case OS_TYPE_WINDOWS: /* not here, see check_windows_system_registry */
  case OS_TYPE_UNKNOWN:
  default:
    /* nothing, keep GCC warnings happy */;
  }

  return 0;
}

/* Parse the hostname from /etc/sysconfig/network.  This must be called
 * from the inspect_with_augeas wrapper.
 */
static int
check_hostname_redhat (guestfs_h *g, struct inspect_fs *fs)
{
  char *hostname;

  hostname = guestfs_aug_get (g, "/files/etc/sysconfig/network/HOSTNAME");
  if (!hostname)
    return -1;

  fs->hostname = hostname;  /* freed by guestfs___free_inspect_info */
  return 0;
}

/* Parse the hostname from /etc/rc.conf.  On FreeBSD this file
 * contains comments, blank lines and:
 *   hostname="freebsd8.example.com"
 *   ifconfig_re0="DHCP"
 *   keymap="uk.iso"
 *   sshd_enable="YES"
 */
static int
check_hostname_freebsd (guestfs_h *g, struct inspect_fs *fs)
{
  const char *filename = "/etc/rc.conf";
  int64_t size;
  char **lines;
  size_t i;

  /* Don't trust guestfs_read_lines not to break with very large files.
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

  lines = guestfs_read_lines (g, filename);
  if (lines == NULL)
    return -1;

  for (i = 0; lines[i] != NULL; ++i) {
    if (STRPREFIX (lines[i], "hostname=\"") ||
        STRPREFIX (lines[i], "hostname='")) {
      size_t len = strlen (lines[i]) - 10 - 1;
      fs->hostname = safe_strndup (g, &lines[i][10], len);
      break;
    } else if (STRPREFIX (lines[i], "hostname=")) {
      size_t len = strlen (lines[i]) - 9;
      fs->hostname = safe_strndup (g, &lines[i][9], len);
      break;
    }
  }

  guestfs___free_string_list (lines);
  return 0;
}

static int
check_fstab (guestfs_h *g, struct inspect_fs *fs)
{
  char **lines = guestfs_aug_ls (g, "/files/etc/fstab");
  if (lines == NULL)
    return -1;

  if (lines[0] == NULL) {
    error (g, _("could not parse /etc/fstab or empty file"));
    guestfs___free_string_list (lines);
    return -1;
  }

  size_t i;
  char augpath[256];
  for (i = 0; lines[i] != NULL; ++i) {
    /* Ignore comments.  Only care about sequence lines which
     * match m{/\d+$}.
     */
    if (match (g, lines[i], re_aug_seq)) {
      snprintf (augpath, sizeof augpath, "%s/spec", lines[i]);
      char *spec = guestfs_aug_get (g, augpath);
      if (spec == NULL) {
        guestfs___free_string_list (lines);
        return -1;
      }

      snprintf (augpath, sizeof augpath, "%s/file", lines[i]);
      char *mp = guestfs_aug_get (g, augpath);
      if (mp == NULL) {
        guestfs___free_string_list (lines);
        free (spec);
        return -1;
      }

      int r = add_fstab_entry (g, fs, spec, mp);
      free (spec);
      free (mp);

      if (r == -1) {
        guestfs___free_string_list (lines);
        return -1;
      }
    }
  }

  guestfs___free_string_list (lines);
  return 0;
}

/* Add a filesystem and possibly a mountpoint entry for
 * the root filesystem 'fs'.
 *
 * 'spec' is the fstab spec field, which might be a device name or a
 * pseudodevice or 'UUID=...' or 'LABEL=...'.
 *
 * 'mp' is the mount point, which could also be 'swap' or 'none'.
 */
static int
add_fstab_entry (guestfs_h *g, struct inspect_fs *fs,
                 const char *spec, const char *mp)
{
  /* Ignore certain mountpoints. */
  if (STRPREFIX (mp, "/dev/") ||
      STREQ (mp, "/dev") ||
      STRPREFIX (mp, "/media/") ||
      STRPREFIX (mp, "/proc/") ||
      STREQ (mp, "/proc") ||
      STRPREFIX (mp, "/selinux/") ||
      STREQ (mp, "/selinux") ||
      STRPREFIX (mp, "/sys/") ||
      STREQ (mp, "/sys"))
    return 0;

  /* Ignore /dev/fd (floppy disks) (RHBZ#642929) and CD-ROM drives. */
  if ((STRPREFIX (spec, "/dev/fd") && c_isdigit (spec[7])) ||
      STREQ (spec, "/dev/floppy") ||
      STREQ (spec, "/dev/cdrom"))
    return 0;

  /* Resolve UUID= and LABEL= to the actual device. */
  char *device = NULL;
  if (STRPREFIX (spec, "UUID="))
    device = guestfs_findfs_uuid (g, &spec[5]);
  else if (STRPREFIX (spec, "LABEL="))
    device = guestfs_findfs_label (g, &spec[6]);
  /* Ignore "/.swap" (Pardus) and pseudo-devices like "tmpfs". */
  else if (STRPREFIX (spec, "/dev/"))
    /* Resolve guest block device names. */
    device = resolve_fstab_device (g, spec);

  /* If we haven't resolved the device successfully by this point,
   * we don't care, just ignore it.
   */
  if (device == NULL)
    return 0;

  char *mountpoint = safe_strdup (g, mp);

  /* Add this to the fstab entry in 'fs'.
   * Note these are further filtered by guestfs_inspect_get_mountpoints
   * and guestfs_inspect_get_filesystems.
   */
  size_t n = fs->nr_fstab + 1;
  struct inspect_fstab_entry *p;

  p = realloc (fs->fstab, n * sizeof (struct inspect_fstab_entry));
  if (p == NULL) {
    perrorf (g, "realloc");
    free (device);
    free (mountpoint);
    return -1;
  }

  fs->fstab = p;
  fs->nr_fstab = n;

  /* These are owned by the handle and freed by guestfs___free_inspect_info. */
  fs->fstab[n-1].device = device;
  fs->fstab[n-1].mountpoint = mountpoint;

  if (g->verbose)
    fprintf (stderr, "fstab: device=%s mountpoint=%s\n", device, mountpoint);

  return 0;
}

/* Resolve block device name to the libguestfs device name, eg.
 * /dev/xvdb1 => /dev/vdb1; and /dev/mapper/VG-LV => /dev/VG/LV.  This
 * assumes that disks were added in the same order as they appear to
 * the real VM, which is a reasonable assumption to make.  Return
 * anything we don't recognize unchanged.
 */
static char *
resolve_fstab_device (guestfs_h *g, const char *spec)
{
  char *a1;
  char *device = NULL;
  char *bsddisk, *bsdslice, *bsdpart;

  if (STRPREFIX (spec, "/dev/mapper/")) {
    /* LVM2 does some strange munging on /dev/mapper paths for VGs and
     * LVs which contain '-' character:
     *
     * ><fs> lvcreate LV--test VG--test 32
     * ><fs> debug ls /dev/mapper
     * VG----test-LV----test
     *
     * This makes it impossible to reverse those paths directly, so
     * we have implemented lvm_canonical_lv_name in the daemon.
     */
    device = guestfs_lvm_canonical_lv_name (g, spec);
  }
  else if ((a1 = match1 (g, spec, re_xdev)) != NULL) {
    char **devices = guestfs_list_devices (g);
    if (devices == NULL)
      return NULL;

    size_t count;
    for (count = 0; devices[count] != NULL; count++)
      ;

    size_t i = a1[0] - 'a'; /* a1[0] is always [a-z] because of regex. */
    if (i < count) {
      size_t len = strlen (devices[i]) + strlen (a1) + 16;
      device = safe_malloc (g, len);
      snprintf (device, len, "%s%s", devices[i], &a1[1]);
    }

    free (a1);
    guestfs___free_string_list (devices);
  }
  else if (match3 (g, spec, re_freebsd, &bsddisk, &bsdslice, &bsdpart)) {
    /* FreeBSD disks are organized quite differently.  See:
     * http://www.freebsd.org/doc/handbook/disk-organization.html
     * FreeBSD "partitions" are exposed as quasi-extended partitions
     * numbered from 5 in Linux.  I have no idea what happens when you
     * have multiple "slices" (the FreeBSD term for MBR partitions).
     */
    int disk = parse_unsigned_int (g, bsddisk);
    int slice = parse_unsigned_int (g, bsdslice);
    int part = bsdpart[0] - 'a' /* counting from 0 */;
    free (bsddisk);
    free (bsdslice);
    free (bsdpart);

    if (disk == -1 || disk > 26 ||
        slice <= 0 || slice > 1 /* > 4 .. see comment above */ ||
        part < 0 || part >= 26)
      goto out;

    device = safe_asprintf (g, "/dev/sd%c%d", disk + 'a', part + 5);
  }

 out:
  /* Didn't match device pattern, return original spec unchanged. */
  if (device == NULL)
    device = safe_strdup (g, spec);

  return device;
}

/* XXX Handling of boot.ini in the Perl version was pretty broken.  It
 * essentially didn't do anything for modern Windows guests.
 * Therefore I've omitted all that code.
 */
static int
check_windows_root (guestfs_h *g, struct inspect_fs *fs)
{
  fs->type = OS_TYPE_WINDOWS;
  fs->distro = OS_DISTRO_WINDOWS;

  /* Try to find Windows systemroot using some common locations. */
  const char *systemroots[] =
    { "/windows", "/winnt", "/win32", "/win" };
  size_t i;
  char *systemroot = NULL;
  for (i = 0;
       systemroot == NULL && i < sizeof systemroots / sizeof systemroots[0];
       ++i) {
    systemroot = resolve_windows_path_silently (g, systemroots[i]);
  }

  if (!systemroot) {
    error (g, _("cannot resolve Windows %%SYSTEMROOT%%"));
    return -1;
  }

  if (g->verbose)
    fprintf (stderr, "windows %%SYSTEMROOT%% = %s", systemroot);

  /* Freed by guestfs___free_inspect_info. */
  fs->windows_systemroot = systemroot;

  if (check_windows_arch (g, fs) == -1)
    return -1;

  /* Product name and version. */
  if (check_windows_software_registry (g, fs) == -1)
    return -1;

  check_package_format (g, fs);
  check_package_management (g, fs);

  /* Hostname. */
  if (check_windows_system_registry (g, fs) == -1)
    return -1;

  return 0;
}

static int
check_windows_arch (guestfs_h *g, struct inspect_fs *fs)
{
  size_t len = strlen (fs->windows_systemroot) + 32;
  char cmd_exe[len];
  snprintf (cmd_exe, len, "%s/system32/cmd.exe", fs->windows_systemroot);

  char *cmd_exe_path = resolve_windows_path_silently (g, cmd_exe);
  if (!cmd_exe_path)
    return 0;

  char *arch = guestfs_file_architecture (g, cmd_exe_path);
  free (cmd_exe_path);

  if (arch)
    fs->arch = arch;        /* freed by guestfs___free_inspect_info */

  return 0;
}

/* At the moment, pull just the ProductName and version numbers from
 * the registry.  In future there is a case for making many more
 * registry fields available to callers.
 */
static int
check_windows_software_registry (guestfs_h *g, struct inspect_fs *fs)
{
  TMP_TEMPLATE_ON_STACK (software_local);

  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  char *software_path = resolve_windows_path_silently (g, software);
  if (!software_path)
    /* If the software hive doesn't exist, just accept that we cannot
     * find product_name etc.
     */
    return 0;

  int ret = -1;
  hive_h *h = NULL;
  hive_value_h *values = NULL;

  if (download_to_tmp (g, software_path, software_local,
                       MAX_REGISTRY_SIZE) == -1)
    goto out;

  h = hivex_open (software_local, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
  if (h == NULL) {
    perrorf (g, "hivex_open");
    goto out;
  }

  hive_node_h node = hivex_root (h);
  const char *hivepath[] =
    { "Microsoft", "Windows NT", "CurrentVersion" };
  size_t i;
  for (i = 0;
       node != 0 && i < sizeof hivepath / sizeof hivepath[0];
       ++i) {
    node = hivex_node_get_child (h, node, hivepath[i]);
  }

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion");
    goto out;
  }

  values = hivex_node_values (h, node);

  for (i = 0; values[i] != 0; ++i) {
    char *key = hivex_value_key (h, values[i]);
    if (key == NULL) {
      perrorf (g, "hivex_value_key");
      goto out;
    }

    if (STRCASEEQ (key, "ProductName")) {
      fs->product_name = hivex_value_string (h, values[i]);
      if (!fs->product_name) {
        perrorf (g, "hivex_value_string");
        free (key);
        goto out;
      }
    }
    else if (STRCASEEQ (key, "CurrentVersion")) {
      char *version = hivex_value_string (h, values[i]);
      if (!version) {
        perrorf (g, "hivex_value_string");
        free (key);
        goto out;
      }
      char *major, *minor;
      if (match2 (g, version, re_windows_version, &major, &minor)) {
        fs->major_version = parse_unsigned_int (g, major);
        free (major);
        if (fs->major_version == -1) {
          free (minor);
          free (key);
          free (version);
          goto out;
        }
        fs->minor_version = parse_unsigned_int (g, minor);
        free (minor);
        if (fs->minor_version == -1) {
          free (key);
          free (version);
          goto out;
        }
      }

      free (version);
    }

    free (key);
  }

  ret = 0;

 out:
  if (h) hivex_close (h);
  free (values);
  free (software_path);

  /* Free up the temporary file. */
  unlink (software_local);
#undef software_local_len

  return ret;
}

static int
check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs)
{
  TMP_TEMPLATE_ON_STACK (system_local);

  size_t len = strlen (fs->windows_systemroot) + 64;
  char system[len];
  snprintf (system, len, "%s/system32/config/system",
            fs->windows_systemroot);

  char *system_path = resolve_windows_path_silently (g, system);
  if (!system_path)
    /* If the system hive doesn't exist, just accept that we cannot
     * find hostname etc.
     */
    return 0;

  int ret = -1;
  hive_h *h = NULL;
  hive_value_h *values = NULL;

  if (download_to_tmp (g, system_path, system_local, MAX_REGISTRY_SIZE) == -1)
    goto out;

  h = hivex_open (system_local, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
  if (h == NULL) {
    perrorf (g, "hivex_open");
    goto out;
  }

  hive_node_h node = hivex_root (h);
  /* XXX Don't hard-code ControlSet001.  The current control set would
   * be another good thing to expose up through the inspection API.
   */
  const char *hivepath[] =
    { "ControlSet001", "Services", "Tcpip", "Parameters" };
  size_t i;
  for (i = 0;
       node != 0 && i < sizeof hivepath / sizeof hivepath[0];
       ++i) {
    node = hivex_node_get_child (h, node, hivepath[i]);
  }

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SYSTEM\\ControlSet001\\Services\\Tcpip\\Parameters");
    goto out;
  }

  values = hivex_node_values (h, node);

  for (i = 0; values[i] != 0; ++i) {
    char *key = hivex_value_key (h, values[i]);
    if (key == NULL) {
      perrorf (g, "hivex_value_key");
      goto out;
    }

    if (STRCASEEQ (key, "Hostname")) {
      fs->hostname = hivex_value_string (h, values[i]);
      if (!fs->hostname) {
        perrorf (g, "hivex_value_string");
        free (key);
        goto out;
      }
    }
    /* many other interesting fields here ... */

    free (key);
  }

  ret = 0;

 out:
  if (h) hivex_close (h);
  free (values);
  free (system_path);

  /* Free up the temporary file. */
  unlink (system_local);
#undef system_local_len

  return ret;
}

static char *
resolve_windows_path_silently (guestfs_h *g, const char *path)
{
  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;
  char *ret = guestfs_case_sensitive_path (g, path);
  g->error_cb = old_error_cb;
  return ret;
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

/* Parse small, unsigned ints, as used in version numbers. */
static int
parse_unsigned_int (guestfs_h *g, const char *str)
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
static int
parse_unsigned_int_ignore_trailing (guestfs_h *g, const char *str)
{
  long ret;
  int r = xstrtol (str, NULL, 10, &ret, NULL);
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
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
  case OS_DISTRO_MANDRIVA:
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
  case OS_DISTRO_MANDRIVA:
    fs->package_management = OS_PACKAGE_MANAGEMENT_URPMI;
    break;

  case OS_DISTRO_WINDOWS:
  case OS_DISTRO_UNKNOWN:
  default:
    fs->package_management = OS_PACKAGE_MANAGEMENT_UNKNOWN;
    break;
  }
}

static struct inspect_fs *
search_for_root (guestfs_h *g, const char *root)
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

  return ret;
}

char *
guestfs__inspect_get_type (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->type) {
  case OS_TYPE_LINUX: ret = safe_strdup (g, "linux"); break;
  case OS_TYPE_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_TYPE_FREEBSD: ret = safe_strdup (g, "freebsd"); break;
  case OS_TYPE_UNKNOWN: default: ret = safe_strdup (g, "unknown"); break;
  }

  return ret;
}

char *
guestfs__inspect_get_arch (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->arch ? : "unknown");
}

char *
guestfs__inspect_get_distro (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->distro) {
  case OS_DISTRO_ARCHLINUX: ret = safe_strdup (g, "archlinux"); break;
  case OS_DISTRO_DEBIAN: ret = safe_strdup (g, "debian"); break;
  case OS_DISTRO_FEDORA: ret = safe_strdup (g, "fedora"); break;
  case OS_DISTRO_GENTOO: ret = safe_strdup (g, "gentoo"); break;
  case OS_DISTRO_LINUX_MINT: ret = safe_strdup (g, "linuxmint"); break;
  case OS_DISTRO_MANDRIVA: ret = safe_strdup (g, "mandriva"); break;
  case OS_DISTRO_MEEGO: ret = safe_strdup (g, "meego"); break;
  case OS_DISTRO_PARDUS: ret = safe_strdup (g, "pardus"); break;
  case OS_DISTRO_REDHAT_BASED: ret = safe_strdup (g, "redhat-based"); break;
  case OS_DISTRO_RHEL: ret = safe_strdup (g, "rhel"); break;
  case OS_DISTRO_WINDOWS: ret = safe_strdup (g, "windows"); break;
  case OS_DISTRO_UBUNTU: ret = safe_strdup (g, "ubuntu"); break;
  case OS_DISTRO_UNKNOWN: default: ret = safe_strdup (g, "unknown"); break;
  }

  return ret;
}

int
guestfs__inspect_get_major_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->major_version;
}

int
guestfs__inspect_get_minor_version (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->minor_version;
}

char *
guestfs__inspect_get_product_name (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->product_name ? : "unknown");
}

char *
guestfs__inspect_get_windows_systemroot (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  if (!fs->windows_systemroot) {
    error (g, _("not a Windows guest, or systemroot could not be determined"));
    return NULL;
  }

  return safe_strdup (g, fs->windows_systemroot);
}

char *
guestfs__inspect_get_format (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
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
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_live_disk;
}

int
guestfs__inspect_is_netinst (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_netinst_disk;
}

int
guestfs__inspect_is_multipart (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return -1;

  return fs->is_multipart_disk;
}

char **
guestfs__inspect_get_mountpoints (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  char **ret;

  /* If no fstab information (Windows) return just the root. */
  if (fs->nr_fstab == 0) {
    ret = calloc (3, sizeof (char *));
    ret[0] = safe_strdup (g, "/");
    ret[1] = safe_strdup (g, root);
    ret[2] = NULL;
    return ret;
  }

#define CRITERION fs->fstab[i].mountpoint[0] == '/'
  size_t i, count = 0;
  for (i = 0; i < fs->nr_fstab; ++i)
    if (CRITERION)
      count++;

  /* Hashtables have 2N+1 entries. */
  ret = calloc (2*count+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  count = 0;
  for (i = 0; i < fs->nr_fstab; ++i)
    if (CRITERION) {
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
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  char **ret;

  /* If no fstab information (Windows) return just the root. */
  if (fs->nr_fstab == 0) {
    ret = calloc (2, sizeof (char *));
    ret[0] = safe_strdup (g, root);
    ret[1] = NULL;
    return ret;
  }

  ret = calloc (fs->nr_fstab + 1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    return NULL;
  }

  size_t i;
  for (i = 0; i < fs->nr_fstab; ++i)
    ret[i] = safe_strdup (g, fs->fstab[i].device);

  return ret;
}

char *
guestfs__inspect_get_package_format (guestfs_h *g, const char *root)
{
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  char *ret;
  switch (fs->package_format) {
  case OS_PACKAGE_FORMAT_RPM: ret = safe_strdup (g, "rpm"); break;
  case OS_PACKAGE_FORMAT_DEB: ret = safe_strdup (g, "deb"); break;
  case OS_PACKAGE_FORMAT_PACMAN: ret = safe_strdup (g, "pacman"); break;
  case OS_PACKAGE_FORMAT_EBUILD: ret = safe_strdup (g, "ebuild"); break;
  case OS_PACKAGE_FORMAT_PISI: ret = safe_strdup (g, "pisi"); break;
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
  struct inspect_fs *fs = search_for_root (g, root);
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
  struct inspect_fs *fs = search_for_root (g, root);
  if (!fs)
    return NULL;

  return safe_strdup (g, fs->hostname ? : "unknown");
}

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
  struct inspect_fs *fs = search_for_root (g, root);
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
  TMP_TEMPLATE_ON_STACK (tmpfile);

  if (download_to_tmp (g, "/var/lib/rpm/Name", tmpfile, MAX_PKG_DB_SIZE) == -1)
    return NULL;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
#define cmd_len (strlen (tmpfile) + 64)
  char cmd[cmd_len];
  FILE *pp = NULL;
  char line[1024];
  size_t len;

  snprintf (cmd, cmd_len, DB_DUMP " -p '%s'", tmpfile);

  if (g->verbose)
    fprintf (stderr, "list_applications_rpm: %s\n", cmd);

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
  unlink (tmpfile);
#undef cmd_len

  return ret;
}
#endif /* defined DB_DUMP */

static struct guestfs_application_list *
list_applications_deb (guestfs_h *g, struct inspect_fs *fs)
{
  TMP_TEMPLATE_ON_STACK (tmpfile);

  if (download_to_tmp (g, "/var/lib/dpkg/status", tmpfile,
                       MAX_PKG_DB_SIZE) == -1)
    return NULL;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
  FILE *fp = NULL;
  char line[1024];
  size_t len;
  char *name = NULL, *version = NULL, *release = NULL;
  int installed_flag = 0;

  fp = fopen (tmpfile, "r");
  if (fp == NULL) {
    perrorf (g, "fopen: %s", tmpfile);
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
    perrorf (g, "fclose: %s", tmpfile);
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
  unlink (tmpfile);
  return ret;
}

/* XXX We already download the SOFTWARE hive when doing general
 * inspection.  We could avoid this second download of the same file
 * by caching these entries in the handle.
 */
static struct guestfs_application_list *
list_applications_windows (guestfs_h *g, struct inspect_fs *fs)
{
  TMP_TEMPLATE_ON_STACK (software_local);

  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  char *software_path = resolve_windows_path_silently (g, software);
  if (!software_path)
    /* If the software hive doesn't exist, just accept that we cannot
     * find product_name etc.
     */
    return 0;

  struct guestfs_application_list *apps = NULL, *ret = NULL;
  hive_h *h = NULL;
  hive_node_h *children = NULL;

  if (download_to_tmp (g, software_path, software_local,
                       MAX_REGISTRY_SIZE) == -1)
    goto out;

  h = hivex_open (software_local, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
  if (h == NULL) {
    perrorf (g, "hivex_open");
    goto out;
  }

  hive_node_h node = hivex_root (h);
  const char *hivepath[] =
    { "Microsoft", "Windows", "CurrentVersion", "Uninstall" };
  size_t i;
  for (i = 0;
       node != 0 && i < sizeof hivepath / sizeof hivepath[0];
       ++i) {
    node = hivex_node_get_child (h, node, hivepath[i]);
  }

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall");
    goto out;
  }

  children = hivex_node_children (h, node);
  if (children == NULL) {
    perrorf (g, "hivex_node_children");
    goto out;
  }

  /* Allocate 'apps' list. */
  apps = safe_malloc (g, sizeof *apps);
  apps->len = 0;
  apps->val = NULL;

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
    if (name == NULL) {
      perrorf (g, "hivex_node_get_name");
      goto out;
    }

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

  ret = apps;

 out:
  if (ret == NULL && apps != NULL)
    guestfs_free_application_list (apps);
  if (h) hivex_close (h);
  free (children);
  free (software_path);

  /* Free up the temporary file. */
  unlink (software_local);
#undef software_local_len

  return ret;
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

/* Download to a guest file to a local temporary file.  Refuse to
 * download the guest file if it is larger than max_size.  The caller
 * is responsible for deleting the temporary file after use.
 */
static int
download_to_tmp (guestfs_h *g, const char *filename,
                 char *localtmp, int64_t max_size)
{
  int fd;
  char buf[32];
  int64_t size;

  size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    return -1;
  if (size > max_size) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    return -1;
  }

  fd = mkstemp (localtmp);
  if (fd == -1) {
    perrorf (g, "mkstemp");
    return -1;
  }

  snprintf (buf, sizeof buf, "/dev/fd/%d", fd);

  if (guestfs_download (g, filename, buf) == -1) {
    close (fd);
    unlink (localtmp);
    return -1;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", localtmp);
    unlink (localtmp);
    return -1;
  }

  return 0;
}

/* Call 'f' with Augeas opened and having parsed 'filename' (this file
 * must exist).  As a security measure, this bails if the file is too
 * large for a reasonable configuration file.  After the call to 'f'
 * Augeas is closed.
 */
static int
inspect_with_augeas (guestfs_h *g, struct inspect_fs *fs, const char *filename,
                     int (*f) (guestfs_h *, struct inspect_fs *))
{
  /* Security: Refuse to do this if filename is too large. */
  int64_t size = guestfs_filesize (g, filename);
  if (size == -1)
    /* guestfs_filesize failed and has already set error in handle */
    return -1;
  if (size > MAX_AUGEAS_FILE_SIZE) {
    error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
           filename, size);
    return -1;
  }

  /* If !feature_available (g, "augeas") then the next call will fail.
   * Arguably we might want to fall back to a non-Augeas method in
   * this case.
   */
  if (guestfs_aug_init (g, "/", 16|32) == -1)
    return -1;

  int r = -1;

  /* Tell Augeas to only load one file (thanks Raphaël Pinson). */
  char buf[strlen (filename) + 64];
  snprintf (buf, strlen (filename) + 64, "/augeas/load//incl[. != \"%s\"]",
            filename);
  if (guestfs_aug_rm (g, buf) == -1)
    goto out;

  if (guestfs_aug_load (g) == -1)
    goto out;

  r = f (g, fs);

 out:
  guestfs_aug_close (g);

  return r;
}

/* Get the first line of a small file, without any trailing newline
 * character.
 */
static char *
first_line_of_file (guestfs_h *g, const char *filename)
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
static int
first_egrep_of_file (guestfs_h *g, const char *filename,
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

#else /* no PCRE or hivex at compile time */

/* XXX These functions should be in an optgroup. */

#define NOT_IMPL(r)                                                     \
  error (g, _("inspection API not available since this version of libguestfs was compiled without PCRE or hivex libraries")); \
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
guestfs__inspect_get_windows_systemroot (guestfs_h *g, const char *root)
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

struct guestfs_application_list *
guestfs__inspect_list_applications (guestfs_h *g, const char *root)
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

#endif /* no PCRE or hivex at compile time */

void
guestfs___free_inspect_info (guestfs_h *g)
{
  size_t i;
  for (i = 0; i < g->nr_fses; ++i) {
    free (g->fses[i].device);
    free (g->fses[i].product_name);
    free (g->fses[i].arch);
    free (g->fses[i].hostname);
    free (g->fses[i].windows_systemroot);
    size_t j;
    for (j = 0; j < g->fses[i].nr_fstab; ++j) {
      free (g->fses[i].fstab[j].device);
      free (g->fses[i].fstab[j].mountpoint);
    }
    free (g->fses[i].fstab);
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

#ifdef HAVE_PCRE

/* Match a regular expression which contains no captures.  Returns
 * true if it matches or false if it doesn't.
 */
int
guestfs___match (guestfs_h *g, const char *str, const pcre *re)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, sizeof vec / sizeof vec[0]);
  if (r == PCRE_ERROR_NOMATCH)
    return 0;
  if (r != 1) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return 0;
  }

  return 1;
}

/* Match a regular expression which contains exactly one capture.  If
 * the string matches, return the capture, otherwise return NULL.  The
 * caller must free the result.
 */
char *
guestfs___match1 (guestfs_h *g, const char *str, const pcre *re)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, sizeof vec / sizeof vec[0]);
  if (r == PCRE_ERROR_NOMATCH)
    return NULL;
  if (r != 2) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return NULL;
  }

  return safe_strndup (g, &str[vec[2]], vec[3]-vec[2]);
}

/* Match a regular expression which contains exactly two captures. */
int
guestfs___match2 (guestfs_h *g, const char *str, const pcre *re,
                  char **ret1, char **ret2)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, 30);
  if (r == PCRE_ERROR_NOMATCH)
    return 0;
  if (r != 3) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return 0;
  }

  *ret1 = safe_strndup (g, &str[vec[2]], vec[3]-vec[2]);
  *ret2 = safe_strndup (g, &str[vec[4]], vec[5]-vec[4]);

  return 1;
}

/* Match a regular expression which contains exactly three captures. */
int
guestfs___match3 (guestfs_h *g, const char *str, const pcre *re,
                  char **ret1, char **ret2, char **ret3)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, 30);
  if (r == PCRE_ERROR_NOMATCH)
    return 0;
  if (r != 4) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return 0;
  }

  *ret1 = safe_strndup (g, &str[vec[2]], vec[3]-vec[2]);
  *ret2 = safe_strndup (g, &str[vec[4]], vec[5]-vec[4]);
  *ret3 = safe_strndup (g, &str[vec[6]], vec[7]-vec[6]);

  return 1;
}

#endif /* HAVE_PCRE */
