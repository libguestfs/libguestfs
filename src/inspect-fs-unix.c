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
#include "hash.h"
#include "hash-pjw.h"

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
static pcre *re_fedora;
static pcre *re_rhel_old;
static pcre *re_rhel;
static pcre *re_rhel_no_minor;
static pcre *re_centos_old;
static pcre *re_centos;
static pcre *re_centos_no_minor;
static pcre *re_scientific_linux_old;
static pcre *re_scientific_linux;
static pcre *re_scientific_linux_no_minor;
static pcre *re_major_minor;
static pcre *re_xdev;
static pcre *re_cciss;
static pcre *re_mdN;
static pcre *re_freebsd;
static pcre *re_diskbyid;
static pcre *re_netbsd;

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
           "Red Hat.*release (\\d+).*Update (\\d+)", 0);
  COMPILE (re_rhel,
           "Red Hat.*release (\\d+)\\.(\\d+)", 0);
  COMPILE (re_rhel_no_minor,
           "Red Hat.*release (\\d+)", 0);
  COMPILE (re_centos_old,
           "CentOS.*release (\\d+).*Update (\\d+)", 0);
  COMPILE (re_centos,
           "CentOS.*release (\\d+)\\.(\\d+)", 0);
  COMPILE (re_centos_no_minor,
           "CentOS.*release (\\d+)", 0);
  COMPILE (re_scientific_linux_old,
           "Scientific Linux.*release (\\d+).*Update (\\d+)", 0);
  COMPILE (re_scientific_linux,
           "Scientific Linux.*release (\\d+)\\.(\\d+)", 0);
  COMPILE (re_scientific_linux_no_minor,
           "Scientific Linux.*release (\\d+)", 0);
  COMPILE (re_major_minor, "(\\d+)\\.(\\d+)", 0);
  COMPILE (re_xdev, "^/dev/(h|s|v|xv)d([a-z]+)(\\d*)$", 0);
  COMPILE (re_cciss, "^/dev/(cciss/c\\d+d\\d+)(?:p(\\d+))?$", 0);
  COMPILE (re_mdN, "^(/dev/md\\d+)$", 0);
  COMPILE (re_freebsd, "^/dev/ad(\\d+)s(\\d+)([a-z])$", 0);
  COMPILE (re_diskbyid, "^/dev/disk/by-id/.*-part(\\d+)$", 0);
  COMPILE (re_netbsd, "^NetBSD (\\d+)\\.(\\d+)", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_fedora);
  pcre_free (re_rhel_old);
  pcre_free (re_rhel);
  pcre_free (re_rhel_no_minor);
  pcre_free (re_centos_old);
  pcre_free (re_centos);
  pcre_free (re_centos_no_minor);
  pcre_free (re_scientific_linux_old);
  pcre_free (re_scientific_linux);
  pcre_free (re_scientific_linux_no_minor);
  pcre_free (re_major_minor);
  pcre_free (re_xdev);
  pcre_free (re_cciss);
  pcre_free (re_mdN);
  pcre_free (re_freebsd);
  pcre_free (re_diskbyid);
  pcre_free (re_netbsd);
}

static void check_architecture (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_unix (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_redhat (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_freebsd (guestfs_h *g, struct inspect_fs *fs);
static int check_fstab (guestfs_h *g, struct inspect_fs *fs);
static int add_fstab_entry (guestfs_h *g, struct inspect_fs *fs,
                            const char *spec, const char *mp,
                            Hash_table *md_map);
static char *resolve_fstab_device (guestfs_h *g, const char *spec,
                                   Hash_table *md_map);
static int inspect_with_augeas (guestfs_h *g, struct inspect_fs *fs, const char **configfiles, int (*f) (guestfs_h *, struct inspect_fs *));
static int is_partition (guestfs_h *g, const char *partition);

/* Hash structure for uuid->path lookups */
typedef struct md_uuid {
  uint32_t uuid[4];
  char *path;
} md_uuid;

static size_t uuid_hash(const void *x, size_t table_size);
static bool uuid_cmp(const void *x, const void *y);
static void md_uuid_free(void *x);

static int parse_uuid(const char *str, uint32_t *uuid);

/* Hash structure for path(mdadm)->path(appliance) lookup */
typedef struct {
  char *mdadm;
  char *app;
} mdadm_app;

static size_t mdadm_app_hash(const void *x, size_t table_size);
static bool mdadm_app_cmp(const void *x, const void *y);
static void mdadm_app_free(void *x);

static ssize_t map_app_md_devices (guestfs_h *g, Hash_table **map);
static int map_md_devices(guestfs_h *g, Hash_table **map);

/* Set fs->product_name to the first line of the release file. */
static int
parse_release_file (guestfs_h *g, struct inspect_fs *fs,
                    const char *release_filename)
{
  fs->product_name = guestfs___first_line_of_file (g, release_filename);
  if (fs->product_name == NULL)
    return -1;
  if (STREQ (fs->product_name, "")) {
    free (fs->product_name);
    fs->product_name = NULL;
    error (g, _("release file %s is empty or malformed"), release_filename);
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
    else if (fs->distro == 0 &&
             STREQ (lines[i], "DISTRIB_ID=\"Mageia\"")) {
      fs->distro = OS_DISTRO_MAGEIA;
      r = 1;
    }
    else if (STRPREFIX (lines[i], "DISTRIB_RELEASE=")) {
      char *major, *minor;
      if (match2 (g, &lines[i][16], re_major_minor, &major, &minor)) {
        fs->major_version = guestfs___parse_unsigned_int (g, major);
        free (major);
        if (fs->major_version == -1) {
          free (minor);
          guestfs___free_string_list (lines);
          return -1;
        }
        fs->minor_version = guestfs___parse_unsigned_int (g, minor);
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

  /* The unnecessary construct in the next line is required to
   * workaround -Wstrict-overflow warning in gcc 4.5.1.
   */
  return r ? 1 : 0;
}

/* The currently mounted device is known to be a Linux root.  Try to
 * determine from this the distro, version, etc.  Also parse
 * /etc/fstab to determine the arrangement of mountpoints and
 * associated devices.
 */
int
guestfs___check_linux_root (guestfs_h *g, struct inspect_fs *fs)
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
      fs->major_version = guestfs___parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1)
        return -1;
    }
    else if (match2 (g, fs->product_name, re_rhel_old, &major, &minor) ||
             match2 (g, fs->product_name, re_rhel, &major, &minor)) {
      fs->distro = OS_DISTRO_RHEL;
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
    else if ((major = match1 (g, fs->product_name, re_rhel_no_minor)) != NULL) {
      fs->distro = OS_DISTRO_RHEL;
      fs->major_version = guestfs___parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1)
        return -1;
      fs->minor_version = 0;
    }
    else if (match2 (g, fs->product_name, re_centos_old, &major, &minor) ||
             match2 (g, fs->product_name, re_centos, &major, &minor)) {
      fs->distro = OS_DISTRO_CENTOS;
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
    else if ((major = match1 (g, fs->product_name, re_centos_no_minor)) != NULL) {
      fs->distro = OS_DISTRO_CENTOS;
      fs->major_version = guestfs___parse_unsigned_int (g, major);
      free (major);
      if (fs->major_version == -1)
        return -1;
      fs->minor_version = 0;
    }
    else if (match2 (g, fs->product_name, re_scientific_linux_old, &major, &minor) ||
             match2 (g, fs->product_name, re_scientific_linux, &major, &minor)) {
      fs->distro = OS_DISTRO_SCIENTIFIC_LINUX;
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
    else if ((major = match1 (g, fs->product_name, re_scientific_linux_no_minor)) != NULL) {
      fs->distro = OS_DISTRO_SCIENTIFIC_LINUX;
      fs->major_version = guestfs___parse_unsigned_int (g, major);
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

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/pardus-release") > 0) {
    fs->distro = OS_DISTRO_PARDUS;

    if (parse_release_file (g, fs, "/etc/pardus-release") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
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

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/meego-release") > 0) {
    fs->distro = OS_DISTRO_MEEGO;

    if (parse_release_file (g, fs, "/etc/meego-release") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/slackware-version") > 0) {
    fs->distro = OS_DISTRO_SLACKWARE;

    if (parse_release_file (g, fs, "/etc/slackware-version") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/ttylinux-target") > 0) {
    fs->distro = OS_DISTRO_TTYLINUX;

    if (parse_release_file (g, fs, "/etc/ttylinux-target") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  else if (guestfs_exists (g, "/etc/SuSE-release") > 0) {
    fs->distro = OS_DISTRO_OPENSUSE;

    if (parse_release_file (g, fs, "/etc/SuSE-release") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }
  /* Buildroot (http://buildroot.net) is an embedded Linux distro
   * toolkit.  It is used by specific distros such as Cirros.
   */
  else if (guestfs_exists (g, "/etc/br-version") > 0) {
    if (guestfs_exists (g, "/usr/share/cirros/logo") > 0)
      fs->distro = OS_DISTRO_CIRROS;
    else
      fs->distro = OS_DISTRO_BUILDROOT;

    /* /etc/br-version has the format YYYY.MM[-git/hg/svn release] */
    if (parse_release_file (g, fs, "/etc/br-version") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
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
  const char *configfiles[] = { "/etc/fstab", "/etc/mdadm.conf", NULL };
  if (inspect_with_augeas (g, fs, configfiles, check_fstab) == -1)
    return -1;

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
    return -1;

  return 0;
}

/* The currently mounted device is known to be a FreeBSD root. */
int
guestfs___check_freebsd_root (guestfs_h *g, struct inspect_fs *fs)
{
  fs->type = OS_TYPE_FREEBSD;

  /* FreeBSD has no authoritative version file.  The version number is
   * in /etc/motd, which the system administrator might edit, but
   * we'll use that anyway.
   */

  if (guestfs_exists (g, "/etc/motd") > 0) {
    if (parse_release_file (g, fs, "/etc/motd") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* We already know /etc/fstab exists because it's part of the test above. */
  const char *configfiles[] = { "/etc/fstab", NULL };
  if (inspect_with_augeas (g, fs, configfiles, check_fstab) == -1)
    return -1;

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
    return -1;

  return 0;
}

/* The currently mounted device is maybe to be a *BSD root. */
int
guestfs___check_netbsd_root (guestfs_h *g, struct inspect_fs *fs)
{

  if (guestfs_exists (g, "/etc/release") > 0) {
    char *major, *minor;
    if (parse_release_file (g, fs, "/etc/release") == -1)
      return -1;

    if (match2 (g, fs->product_name, re_netbsd, &major, &minor)) {
      fs->type = OS_TYPE_NETBSD;
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
  } else {
    return -1;
  }

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* We already know /etc/fstab exists because it's part of the test above. */
  const char *configfiles[] = { "/etc/fstab", NULL };
  if (inspect_with_augeas (g, fs, configfiles, check_fstab) == -1)
    return -1;

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
    return -1;

  return 0;
}

/* The currently mounted device may be a Hurd root.  Hurd has distros
 * just like Linux.
 */
int
guestfs___check_hurd_root (guestfs_h *g, struct inspect_fs *fs)
{
  fs->type = OS_TYPE_HURD;

  if (guestfs_exists (g, "/etc/debian_version") > 0) {
    fs->distro = OS_DISTRO_DEBIAN;

    if (parse_release_file (g, fs, "/etc/debian_version") == -1)
      return -1;

    if (guestfs___parse_major_minor (g, fs) == -1)
      return -1;
  }

  /* Arch Hurd also exists, but inconveniently it doesn't have
   * the normal /etc/arch-release file.  XXX
   */

  /* Determine the architecture. */
  check_architecture (g, fs);

  /* XXX Check for /etc/fstab. */

  /* Determine hostname. */
  if (check_hostname_unix (g, fs) == -1)
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

/* Try several methods to determine the hostname from a Linux or
 * FreeBSD guest.  Note that type and distro have been set, so we can
 * use that information to direct the search.
 */
static int
check_hostname_unix (guestfs_h *g, struct inspect_fs *fs)
{
  switch (fs->type) {
  case OS_TYPE_LINUX:
  case OS_TYPE_HURD:
    /* Red Hat-derived would be in /etc/sysconfig/network, and
     * Debian-derived in the file /etc/hostname.  Very old Debian and
     * SUSE use /etc/HOSTNAME.  It's best to just look for each of
     * these files in turn, rather than try anything clever based on
     * distro.
     */
    if (guestfs_is_file (g, "/etc/HOSTNAME")) {
      fs->hostname = guestfs___first_line_of_file (g, "/etc/HOSTNAME");
      if (fs->hostname == NULL)
        return -1;
      if (STREQ (fs->hostname, "")) {
        free (fs->hostname);
        fs->hostname = NULL;
      }
    }

    if (!fs->hostname && guestfs_is_file (g, "/etc/hostname")) {
      fs->hostname = guestfs___first_line_of_file (g, "/etc/hostname");
      if (fs->hostname == NULL)
        return -1;
      if (STREQ (fs->hostname, "")) {
        free (fs->hostname);
        fs->hostname = NULL;
      }
    }

    if (!fs->hostname && guestfs_is_file (g, "/etc/sysconfig/network")) {
      const char *configfiles[] = { "/etc/sysconfig/network", NULL };
      if (inspect_with_augeas (g, fs, configfiles,
                               check_hostname_redhat) == -1)
        return -1;
    }
    break;

  case OS_TYPE_FREEBSD:
  case OS_TYPE_NETBSD:
    /* /etc/rc.conf contains the hostname, but there is no Augeas lens
     * for this file.
     */
    if (guestfs_is_file (g, "/etc/rc.conf")) {
      if (check_hostname_freebsd (g, fs) == -1)
        return -1;
    }
    break;

  case OS_TYPE_WINDOWS: /* not here, see check_windows_system_registry */
  case OS_TYPE_DOS:
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

  /* Errors here are not fatal (RHBZ#726739), since it could be
   * just missing HOSTNAME field in the file.
   */
  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;
  hostname = guestfs_aug_get (g, "/files/etc/sysconfig/network/HOSTNAME");
  g->error_cb = old_error_cb;

  /* This is freed by guestfs___free_inspect_info.  Note that hostname
   * could be NULL because we ignored errors above.
   */
  fs->hostname = hostname;
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
  char **entries, **entry;
  char augpath[256];
  char *spec, *mp;
  int r;

  /* Generate a map of MD device paths listed in /etc/mdadm.conf to MD device
   * paths in the guestfs appliance */
  Hash_table *md_map;
  if (map_md_devices (g, &md_map) == -1) return -1;

  entries = guestfs_aug_match (g, "/files/etc/fstab/*[label() != '#comment']");
  if (entries == NULL) goto error;

  if (entries[0] == NULL) {
    error (g, _("could not parse /etc/fstab or empty file"));
    goto error;
  }

  for (entry = entries; *entry != NULL; entry++) {
    snprintf (augpath, sizeof augpath, "%s/spec", *entry);
    spec = guestfs_aug_get (g, augpath);
    if (spec == NULL) goto error;

    snprintf (augpath, sizeof augpath, "%s/file", *entry);
    mp = guestfs_aug_get (g, augpath);
    if (mp == NULL) {
      free (spec);
      goto error;
    }

    r = add_fstab_entry (g, fs, spec, mp, md_map);
    free (spec);
    free (mp);

    if (r == -1) goto error;
  }

  if (md_map) hash_free (md_map);
  guestfs___free_string_list (entries);
  return 0;

error:
  if (md_map) hash_free (md_map);
  if (entries) guestfs___free_string_list (entries);
  return -1;
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
                 const char *spec, const char *mp, Hash_table *md_map)
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
  else if (STREQ (spec, "/dev/root"))
    /* Resolve /dev/root to the current device. */
    device = safe_strdup (g, fs->device);
  else if (STRPREFIX (spec, "/dev/"))
    /* Resolve guest block device names. */
    device = resolve_fstab_device (g, spec, md_map);

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

  debug (g, "fstab: device=%s mountpoint=%s", device, mountpoint);

  return 0;
}

/* Compute a uuid hash as a simple xor of of its 4 32bit components */
static size_t
uuid_hash(const void *x, size_t table_size)
{
  const md_uuid *a = x;

  size_t h = a->uuid[0];
  for (size_t i = 1; i < 4; i++) {
    h ^= a->uuid[i];
  }

  return h % table_size;
}

static bool
uuid_cmp(const void *x, const void *y)
{
  const md_uuid *a = x;
  const md_uuid *b = y;

  for (size_t i = 0; i < 1; i++) {
    if (a->uuid[i] != b->uuid[i]) return 0;
  }

  return 1;
}

static void
md_uuid_free(void *x)
{
  md_uuid *a = x;
  free(a->path);
  free(a);
}

/* Taken from parse_uuid in mdadm */
static int
parse_uuid (const char *str, uint32_t *uuid)
{
  size_t hit = 0; /* number of Hex digIT */
  char c;
  size_t i;
  int n;

  for (i = 0; i < 4; i++)
    uuid[i] = 0;

  while ((c = *str++)) {
    if (c >= '0' && c <= '9')
      n = c - '0';
    else if (c >= 'a' && c <= 'f')
      n = 10 + c - 'a';
    else if (c >= 'A' && c <= 'F')
      n = 10 + c - 'A';
    else if (strchr (":. -", c))
      continue;
    else
      return -1;

    if (hit < 32) {
      uuid[hit / 8] <<= 4;
      uuid[hit / 8] += n;
    }
    hit++;
  }
  if (hit == 32) return 0;

  return -1;
}

/* Create a mapping of uuids to appliance md device names */
static ssize_t
map_app_md_devices (guestfs_h *g, Hash_table **map)
{
  char **mds = NULL;
  size_t n = 0;

  /* A hash mapping uuids to md device names */
  *map = hash_initialize(16, NULL, uuid_hash, uuid_cmp, md_uuid_free);
  if (*map == NULL) g->abort_cb();

  mds = guestfs_list_md_devices(g);
  if (mds == NULL) goto error;

  for (char **md = mds; *md != NULL; md++) {
    char **detail = guestfs_md_detail(g, *md);
    if (detail == NULL) goto error;

    /* Iterate over keys until we find uuid */
    char **i;
    for (i = detail; *i != NULL; i += 2) {
      if (STREQ(*i, "uuid")) break;
    }

    /* We found it */
    if (*i) {
      /* Next item is the uuid value */
      i++;

      md_uuid *entry = safe_malloc(g, sizeof(md_uuid));
      entry->path = safe_strdup(g, *md);

      if (parse_uuid(*i, entry->uuid) == -1) {
        /* Invalid UUID is weird, but not fatal. */
        debug(g, "inspect-os: guestfs_md_detail returned invalid "
                 "uuid for %s: %s", *md, *i);
        guestfs___free_string_list(detail);
        md_uuid_free(entry);
        continue;
      }

      const void *matched = NULL;
      switch (hash_insert_if_absent(*map, entry, &matched)) {
        case -1:
          g->abort_cb();

        case 0:
          /* Duplicate uuid in for md device is weird, but not fatal. */
          debug(g, "inspect-os: md devices %s and %s have the same uuid",
                ((md_uuid *)matched)->path, entry->path);
          md_uuid_free(entry);
          break;

        default:
          n++;
      }
    }

    guestfs___free_string_list(detail);
  }

  guestfs___free_string_list(mds);

  return n;

error:
  hash_free(*map); *map = NULL;
  guestfs___free_string_list(mds);

  return -1;
}

static size_t
mdadm_app_hash(const void *x, size_t table_size)
{
  const mdadm_app *a = x;
  return hash_pjw(a->mdadm, table_size);
}

static bool
mdadm_app_cmp(const void *x, const void *y)
{
  const mdadm_app *a = x;
  const mdadm_app *b = y;

  return STREQ (a->mdadm, b->mdadm);
}

static void
mdadm_app_free(void *x)
{
  mdadm_app *a = x;
  free(a->mdadm);
  free(a->app);
  free(a);
}

/* Get a map of md device names in mdadm.conf to their device names in the
 * appliance */
static int
map_md_devices(guestfs_h *g, Hash_table **map)
{
  Hash_table *app_map = NULL;
  char **matches = NULL;
  ssize_t n_app_md_devices;

  *map = NULL;

  /* Get a map of md device uuids to their device names in the appliance */
  n_app_md_devices = map_app_md_devices (g, &app_map);
  if (n_app_md_devices == -1) goto error;

  /* Nothing to do if there are no md devices */
  if (n_app_md_devices == 0) {
    hash_free(app_map);
    return 0;
  }

  /* Get all arrays listed in mdadm.conf */
  matches = guestfs_aug_match(g, "/files/etc/mdadm.conf/array");
  if (!matches) goto error;

  /* Log a debug message if we've got md devices, but nothing in mdadm.conf */
  if (matches[0] == NULL) {
    debug(g, "Appliance has MD devices, but augeas returned no array matches "
             "in mdadm.conf");
    guestfs___free_string_list(matches);
    hash_free(app_map);
    return 0;
  }

  *map = hash_initialize(16, NULL, mdadm_app_hash, mdadm_app_cmp,
                                   mdadm_app_free);
  if (!*map) g->abort_cb();

  for (char **match = matches; *match != NULL; match++) {
    /* Get device name and uuid for each array */
    char *dev_path = safe_asprintf(g, "%s/devicename", *match);
    char *dev = guestfs_aug_get(g, dev_path);
    free(dev_path);
    if (!dev) goto error;

    char *uuid_path = safe_asprintf(g, "%s/uuid", *match);
    char *uuid = guestfs_aug_get(g, uuid_path);
    free(uuid_path);
    if (!uuid) {
      free(dev);
      continue;
    }

    /* Parse the uuid into an md_uuid structure so we can look it up in the
     * uuid->appliance device map */
    md_uuid mdadm;
    mdadm.path = dev;
    if (parse_uuid(uuid, mdadm.uuid) == -1) {
      /* Invalid uuid. Weird, but not fatal. */
      debug(g, "inspect-os: mdadm.conf contains invalid uuid for %s: %s",
            dev, uuid);
      free(dev);
      free(uuid);
      continue;
    }
    free(uuid);

    /* If there's a corresponding uuid in the appliance, create a new
     * entry in the transitive map */
    md_uuid *app = hash_lookup(app_map, &mdadm);
    if (app) {
      mdadm_app *entry = safe_malloc(g, sizeof(mdadm_app));
      entry->mdadm = dev;
      entry->app = safe_strdup(g, app->path);

      switch (hash_insert_if_absent(*map, entry, NULL)) {
        case -1:
          g->abort_cb();

        case 0:
          /* Duplicate uuid in for md device is weird, but not fatal. */
          debug(g, "inspect-os: mdadm.conf contains multiple entries for %s",
                app->path);
          mdadm_app_free(entry);
          continue;

        default:
          ;;
      }
    } else {
      free(dev);
    }
  }

  hash_free(app_map);
  guestfs___free_string_list(matches);

  return 0;

error:
  if (app_map) hash_free(app_map);
  if (matches) guestfs___free_string_list(matches);
  if (*map) hash_free(*map);

  return -1;
}

static int
resolve_fstab_device_xdev (guestfs_h *g, const char *type, const char *disk,
                           const char *part, char **device_ret)
{
  char *name, *device;
  char **devices;
  size_t i, count;
  struct drive *drive;
  const char *p;

  /* type: (h|s|v|xv)
   * disk: ([a-z]+)
   * part: (\d*)
   */

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    return -1;

  /* Check any hints we were passed for a non-heuristic mapping */
  name = safe_asprintf (g, "%sd%s", type, disk);
  i = 0;
  drive = g->drives;
  while (drive) {
    if (drive->name && STREQ (drive->name, name)) {
      device = safe_asprintf (g, "%s%s", devices[i], part);
      if (!is_partition (g, device)) {
        free (device);
        goto out;
      }
      *device_ret = device;
      break;
    }

    i++; drive = drive->next;
  }
  free (name);

  /* Guess the appliance device name if we didn't find a matching hint */
  if (!*device_ret) {
    /* Count how many disks the libguestfs appliance has */
    for (count = 0; devices[count] != NULL; count++)
      ;

    /* Calculate the numerical index of the disk */
    i = disk[0] - 'a';
    for (p = disk + 1; *p != '\0'; p++) {
      i += 1; i *= 26;
      i += *p - 'a';
    }

    /* Check the index makes sense wrt the number of disks the appliance has.
     * If it does, map it to an appliance disk.
     */
    if (i < count) {
      device = safe_asprintf (g, "%s%s", devices[i], part);
      if (!is_partition (g, device)) {
        free (device);
        goto out;
      }
      *device_ret = device;
    }
  }

 out:
  guestfs___free_string_list (devices);
  return 0;
}

static int
resolve_fstab_device_cciss (guestfs_h *g, const char *disk, const char *part,
                            char **device_ret)
{
  char *device;
  char **devices;
  size_t i;
  struct drive *drive;

  /* disk: (cciss/c\d+d\d+)
   * part: (\d+)?
   */

  devices = guestfs_list_devices (g);
  if (devices == NULL)
    return -1;

  /* Check any hints we were passed for a non-heuristic mapping */
  i = 0;
  drive = g->drives;
  while (drive) {
    if (drive->name && STREQ(drive->name, disk)) {
      if (part) {
        device = safe_asprintf (g, "%s%s", devices[i], part);
        if (!is_partition (g, device)) {
          free (device);
          goto out;
        }
        *device_ret = device;
      }
      else
        *device_ret = safe_strdup (g, devices[i]);
      break;
    }

    i++; drive = drive->next;
  }

  /* We don't try to guess mappings for cciss devices */

 out:
  guestfs___free_string_list (devices);
  return 0;
}

static int
resolve_fstab_device_diskbyid (guestfs_h *g, const char *part,
                               char **device_ret)
{
  int nr_devices;
  char *device;

  /* For /dev/disk/by-id there is a limit to what we can do because
   * original SCSI ID information has likely been lost.  This
   * heuristic will only work for guests that have a single block
   * device.
   *
   * So the main task here is to make sure the assumptions above are
   * true.
   *
   * XXX Use hints from virt-p2v if available.
   * See also: https://bugzilla.redhat.com/show_bug.cgi?id=836573#c3
   */

  nr_devices = guestfs_nr_devices (g);
  if (nr_devices == -1)
    return -1;

  /* If #devices isn't 1, give up trying to translate this fstab entry. */
  if (nr_devices != 1)
    return 0;

  /* Make the partition name and check it exists. */
  device = safe_asprintf (g, "/dev/sda%s", part);
  if (!is_partition (g, device)) {
    free (device);
    return 0;
  }

  *device_ret = device;
  return 0;
}

/* Resolve block device name to the libguestfs device name, eg.
 * /dev/xvdb1 => /dev/vdb1; and /dev/mapper/VG-LV => /dev/VG/LV.  This
 * assumes that disks were added in the same order as they appear to
 * the real VM, which is a reasonable assumption to make.  Return
 * anything we don't recognize unchanged.
 */
static char *
resolve_fstab_device (guestfs_h *g, const char *spec, Hash_table *md_map)
{
  char *device = NULL;
  char *type, *slice, *disk, *part;
  int r;

  if (STRPREFIX (spec, "/dev/mapper/") && guestfs_exists (g, spec) > 0) {
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
  else if (match3 (g, spec, re_xdev, &type, &disk, &part)) {
    r = resolve_fstab_device_xdev (g, type, disk, part, &device);
    free (type);
    free (disk);
    free (part);
    if (r == -1)
      return NULL;
  }
  else if (match2 (g, spec, re_cciss, &disk, &part)) {
    r = resolve_fstab_device_cciss (g, disk, part, &device);
    free (disk);
    free (part);
    if (r == -1)
      return NULL;
  }
  else if (md_map && (disk = match1 (g, spec, re_mdN)) != NULL) {
    mdadm_app entry;
    entry.mdadm = disk;

    mdadm_app *app = hash_lookup (md_map, &entry);
    if (app) device = safe_strdup (g, app->app);

    free(disk);
  }
  else if (match3 (g, spec, re_freebsd, &disk, &slice, &part)) {
    /* FreeBSD disks are organized quite differently.  See:
     * http://www.freebsd.org/doc/handbook/disk-organization.html
     * FreeBSD "partitions" are exposed as quasi-extended partitions
     * numbered from 5 in Linux.  I have no idea what happens when you
     * have multiple "slices" (the FreeBSD term for MBR partitions).
     */
    int disk_i = guestfs___parse_unsigned_int (g, disk);
    int slice_i = guestfs___parse_unsigned_int (g, slice);
    int part_i = part[0] - 'a' /* counting from 0 */;
    free (disk);
    free (slice);
    free (part);

    if (disk_i != -1 && disk_i <= 26 &&
        slice_i > 0 && slice_i <= 1 /* > 4 .. see comment above */ &&
        part_i >= 0 && part_i < 26) {
      device = safe_asprintf (g, "/dev/sd%c%d", disk_i + 'a', part_i + 5);
    }
  }
  else if ((part = match1 (g, spec, re_diskbyid)) != NULL) {
    r = resolve_fstab_device_diskbyid (g, part, &device);
    free (part);
    if (r == -1)
      return NULL;
  }

  /* Didn't match device pattern, return original spec unchanged. */
  if (device == NULL)
    device = safe_strdup (g, spec);

  return device;
}

/* Call 'f' with Augeas opened and having parsed 'filename' (this file
 * must exist).  As a security measure, this bails if the file is too
 * large for a reasonable configuration file.  After the call to 'f'
 * Augeas is closed.
 */
static int
inspect_with_augeas (guestfs_h *g, struct inspect_fs *fs,
                     const char **configfiles,
                     int (*f) (guestfs_h *, struct inspect_fs *))
{
  /* Security: Refuse to do this if a config file is too large. */
  for (const char **i = configfiles; *i != NULL; i++) {
    if (guestfs_exists(g, *i) == 0) continue;

    int64_t size = guestfs_filesize (g, *i);
    if (size == -1)
      /* guestfs_filesize failed and has already set error in handle */
      return -1;
    if (size > MAX_AUGEAS_FILE_SIZE) {
      error (g, _("size of %s is unreasonably large (%" PRIi64 " bytes)"),
             *i, size);
      return -1;
    }
  }

  /* If !feature_available (g, "augeas") then the next call will fail.
   * Arguably we might want to fall back to a non-Augeas method in
   * this case.
   */
  if (guestfs_aug_init (g, "/", 16|32) == -1)
    return -1;

  int r = -1;

  /* Tell Augeas to only load one file (thanks Raphaël Pinson). */
#define AUGEAS_LOAD "/augeas/load//incl[. != \""
#define AUGEAS_LOAD_LEN (strlen(AUGEAS_LOAD))
  size_t conflen = strlen(configfiles[0]);
  size_t buflen = AUGEAS_LOAD_LEN + conflen + 1 /* Closing " */;
  char *buf = safe_malloc(g, buflen + 2 /* Closing ] + null terminator */);

  memcpy(buf, AUGEAS_LOAD, AUGEAS_LOAD_LEN);
  memcpy(buf + AUGEAS_LOAD_LEN, configfiles[0], conflen);
  buf[buflen - 1] = '"';
#undef AUGEAS_LOAD_LEN
#undef AUGEAS_LOAD

#define EXCL " and . != \""
#define EXCL_LEN (strlen(EXCL))
  for (const char **i = &configfiles[1]; *i != NULL; i++) {
    size_t orig_buflen = buflen;
    conflen = strlen(*i);
    buflen += EXCL_LEN + conflen + 1 /* Closing " */;
    buf = safe_realloc(g, buf, buflen + 2 /* Closing ] + null terminator */);
    char *s = buf + orig_buflen;

    memcpy(s, EXCL, EXCL_LEN);
    memcpy(s + EXCL_LEN, *i, conflen);
    buf[buflen - 1] = '"';
  }
#undef EXCL_LEN
#undef EXCL

  buf[buflen] = ']';
  buf[buflen + 1] = '\0';

  if (guestfs_aug_rm (g, buf) == -1) {
    free(buf);
    goto out;
  }
  free(buf);

  if (guestfs_aug_load (g) == -1)
    goto out;

  r = f (g, fs);

 out:
  guestfs_aug_close (g);

  return r;
}

static int
is_partition (guestfs_h *g, const char *partition)
{
  char *device;
  guestfs_error_handler_cb old_error_cb;

  old_error_cb = g->error_cb;
  g->error_cb = NULL;

  if ((device = guestfs_part_to_dev (g, partition)) == NULL) {
    g->error_cb = old_error_cb;
    return 0;
  }

  if (guestfs_device_index (g, device) == -1) {
    g->error_cb = old_error_cb;
    free (device);
    return 0;
  }

  g->error_cb = old_error_cb;
  free (device);

  return 1;
}

#endif /* defined(HAVE_HIVEX) */
