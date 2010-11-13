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
           "(?:Red Hat Enterprise Linux|CentOS|Scientific Linux).*release (\\d+).*Update (\\d+)", 0);
  COMPILE (re_rhel,
           "(?:Red Hat Enterprise Linux|CentOS|Scientific Linux).*release (\\d+)\\.(\\d+)", 0);
  COMPILE (re_rhel_no_minor,
           "(?:Red Hat Enterprise Linux|CentOS|Scientific Linux).*release (\\d+)", 0);
  COMPILE (re_major_minor, "(\\d+)\\.(\\d+)", 0);
  COMPILE (re_aug_seq, "/\\d+$", 0);
  COMPILE (re_xdev, "^/dev/(?:h|s|v|xv)d([a-z]\\d*)$", 0);
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
  pcre_free (re_windows_version);
}

/* The main inspection code. */
static int check_for_filesystem_on (guestfs_h *g, const char *device);

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
    if (check_for_filesystem_on (g, devices[i]) == -1) {
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
    if (check_for_filesystem_on (g, partitions[i]) == -1) {
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
      if (check_for_filesystem_on (g, lvs[i]) == -1) {
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
   */
  size_t count = 0;
  for (i = 0; i < g->nr_fses; ++i)
    if (g->fses[i].is_root)
      count++;

  char **ret = calloc (count+1, sizeof (char *));
  if (ret == NULL) {
    perrorf (g, "calloc");
    guestfs___free_inspect_info (g);
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

/* Find out if 'device' contains a filesystem.  If it does, add
 * another entry in g->fses.
 */
static int check_filesystem (guestfs_h *g, const char *device);
static int check_linux_root (guestfs_h *g, struct inspect_fs *fs);
static void check_architecture (guestfs_h *g, struct inspect_fs *fs);
static int check_fstab (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_root (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_arch (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_registry (guestfs_h *g, struct inspect_fs *fs);
static char *resolve_windows_path_silently (guestfs_h *g, const char *);
static int extend_fses (guestfs_h *g);
static int parse_unsigned_int (guestfs_h *g, const char *str);
static int add_fstab_entry (guestfs_h *g, struct inspect_fs *fs,
                            const char *spec, const char *mp);
static char *resolve_fstab_device (guestfs_h *g, const char *spec);

static int
check_for_filesystem_on (guestfs_h *g, const char *device)
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
    fprintf (stderr, "check_for_filesystem_on: %s (%s)\n",
             device, vfs_type ? vfs_type : "failed to get vfs type");

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
  r = check_filesystem (g, device);

  /* Unmount the filesystem. */
  if (guestfs_umount_all (g) == -1)
    return -1;

  return r;
}

static int
check_filesystem (guestfs_h *g, const char *device)
{
  if (extend_fses (g) == -1)
    return -1;

  struct inspect_fs *fs = &g->fses[g->nr_fses-1];

  fs->device = safe_strdup (g, device);
  fs->is_mountable = 1;

  /* Grub /boot? */
  if (guestfs_is_file (g, "/grub/menu.lst") > 0 ||
      guestfs_is_file (g, "/grub/grub.conf") > 0)
    fs->content = FS_CONTENT_LINUX_BOOT;
  /* Linux root? */
  else if (guestfs_is_dir (g, "/etc") > 0 &&
           guestfs_is_dir (g, "/bin") > 0 &&
           guestfs_is_file (g, "/etc/fstab") > 0) {
    fs->is_root = 1;
    fs->content = FS_CONTENT_LINUX_ROOT;
    if (check_linux_root (g, fs) == -1)
      return -1;
  }
  /* Linux /usr/local? */
  else if (guestfs_is_dir (g, "/etc") > 0 &&
           guestfs_is_dir (g, "/bin") > 0 &&
           guestfs_is_dir (g, "/share") > 0 &&
           guestfs_exists (g, "/local") == 0 &&
           guestfs_is_file (g, "/etc/fstab") == 0)
    fs->content = FS_CONTENT_LINUX_USR_LOCAL;
  /* Linux /usr? */
  else if (guestfs_is_dir (g, "/etc") > 0 &&
           guestfs_is_dir (g, "/bin") > 0 &&
           guestfs_is_dir (g, "/share") > 0 &&
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
    if (check_windows_root (g, fs) == -1)
      return -1;
  }

  return 0;
}

/* Set fs->product_name to the first line of the release file. */
static int
parse_release_file (guestfs_h *g, struct inspect_fs *fs,
                    const char *release_filename)
{
  char **product_name = guestfs_head_n (g, 1, release_filename);
  if (product_name == NULL)
    return -1;
  if (product_name[0] == NULL) {
    error (g, _("%s: file is empty"), release_filename);
    guestfs___free_string_list (product_name);
    return -1;
  }

  /* Note that this string becomes owned by the handle and will
   * be freed by guestfs___free_inspect_info.
   */
  fs->product_name = product_name[0];
  free (product_name);

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
 * In theory other distros could have this LSB file, but none do.
 */
static int
parse_lsb_release (guestfs_h *g, struct inspect_fs *fs)
{
  char **lines;
  size_t i;
  int r = 0;

  lines = guestfs_head_n (g, 10, "/etc/lsb-release");
  if (lines == NULL)
    return -1;

  for (i = 0; lines[i] != NULL; ++i) {
    if (fs->distro == 0 &&
        STREQ (lines[i], "DISTRIB_ID=Ubuntu")) {
      fs->distro = OS_DISTRO_UBUNTU;
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

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* We already know /etc/fstab exists because it's part of the test
   * for Linux root above.  We must now parse this file to determine
   * which filesystems are used by the operating system and how they
   * are mounted.
   */
  if (check_fstab (g, fs) == -1)
    return -1;

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

static int check_fstab_aug_open (guestfs_h *g, struct inspect_fs *fs);

static int
check_fstab (guestfs_h *g, struct inspect_fs *fs)
{
  int r;
  int64_t size;

  /* Security: Refuse to do this if /etc/fstab is huge. */
  size = guestfs_filesize (g, "/etc/fstab");
  if (size == -1 || size > 100000) {
    error (g, _("size of /etc/fstab unreasonable (%" PRIi64 " bytes)"), size);
    return -1;
  }

  /* XXX What if !feature_available (g, "augeas")? */
  if (guestfs_aug_init (g, "/", 16|32) == -1)
    return -1;

  /* Tell Augeas to only load /etc/fstab (thanks Raphaël Pinson). */
  guestfs_aug_rm (g, "/augeas/load//incl[. != \"/etc/fstab\"]");
  guestfs_aug_load (g);

  r = check_fstab_aug_open (g, fs);
  guestfs_aug_close (g);
  if (r == -1)
    return -1;

  return 0;
}

static int
check_fstab_aug_open (guestfs_h *g, struct inspect_fs *fs)
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
  else {
    /* Didn't match device pattern, return original spec unchanged. */
    device = safe_strdup (g, spec);
  }

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

  if (check_windows_registry (g, fs) == -1)
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
check_windows_registry (guestfs_h *g, struct inspect_fs *fs)
{
  TMP_TEMPLATE_ON_STACK (dir);
#define dir_len (strlen (dir))
#define software_hive_len (dir_len + 16)
  char software_hive[software_hive_len];
#define cmd_len (dir_len + 16)
  char cmd[cmd_len];

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

  if (mkdtemp (dir) == NULL) {
    perrorf (g, "mkdtemp");
    goto out;
  }

  snprintf (software_hive, software_hive_len, "%s/software", dir);

  if (guestfs_download (g, software_path, software_hive) == -1)
    goto out;

  h = hivex_open (software_hive, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
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

  /* Free up the temporary directory.  Note the directory name cannot
   * contain shell meta-characters because of the way it was
   * constructed above.
   */
  snprintf (cmd, cmd_len, "rm -rf %s", dir);
  ignore_value (system (cmd));
#undef dir_len
#undef software_hive_len
#undef cmd_len

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

#endif /* no PCRE or hivex at compile time */

void
guestfs___free_inspect_info (guestfs_h *g)
{
  size_t i;
  for (i = 0; i < g->nr_fses; ++i) {
    free (g->fses[i].device);
    free (g->fses[i].product_name);
    free (g->fses[i].arch);
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
