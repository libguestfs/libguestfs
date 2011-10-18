/* libguestfs
 * Copyright (C) 2010-2011 Red Hat Inc.
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
static pcre *re_aug_seq;
static pcre *re_xdev;
static pcre *re_cciss;
static pcre *re_first_partition;
static pcre *re_freebsd;
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
  COMPILE (re_aug_seq, "/\\d+$", 0);
  COMPILE (re_xdev, "^/dev/(h|s|v|xv)d([a-z]+)(\\d*)$", 0);
  COMPILE (re_cciss, "^/dev/(cciss/c\\d+d\\d+)(?:p(\\d+))?$", 0);
  COMPILE (re_freebsd, "^/dev/ad(\\d+)s(\\d+)([a-z])$", 0);
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
  pcre_free (re_aug_seq);
  pcre_free (re_xdev);
  pcre_free (re_cciss);
  pcre_free (re_freebsd);
  pcre_free (re_netbsd);
}

static void check_architecture (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_unix (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_redhat (guestfs_h *g, struct inspect_fs *fs);
static int check_hostname_freebsd (guestfs_h *g, struct inspect_fs *fs);
static int check_fstab (guestfs_h *g, struct inspect_fs *fs);
static int add_fstab_entry (guestfs_h *g, struct inspect_fs *fs,
                            const char *spec, const char *mp);
static char *resolve_fstab_device (guestfs_h *g, const char *spec);
static int inspect_with_augeas (guestfs_h *g, struct inspect_fs *fs, const char *filename, int (*f) (guestfs_h *, struct inspect_fs *));

/* Set fs->product_name to the first line of the release file. */
static int
parse_release_file (guestfs_h *g, struct inspect_fs *fs,
                    const char *release_filename)
{
  fs->product_name = guestfs___first_line_of_file (g, release_filename);
  if (fs->product_name == NULL)
    return -1;
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
  return r;
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

    fs->product_name = guestfs___first_line_of_file (g, "/etc/ttylinux-target");
    if (fs->product_name == NULL)
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


 skip_release_checks:;

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
  if (inspect_with_augeas (g, fs, "/etc/fstab", check_fstab) == -1)
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
  if (inspect_with_augeas (g, fs, "/etc/fstab", check_fstab) == -1)
    return -1;

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
    }
    else if (guestfs_is_file (g, "/etc/hostname")) {
      fs->hostname = guestfs___first_line_of_file (g, "/etc/hostname");
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
  else if (STREQ (spec, "/dev/root"))
    /* Resolve /dev/root to the current device. */
    device = safe_strdup (g, fs->device);
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

  debug (g, "fstab: device=%s mountpoint=%s", device, mountpoint);

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
  char *device = NULL;
  char *type, *slice, *disk, *part;

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
  else if (match3 (g, spec, re_xdev, &type, &disk, &part)) {
    /* type: (h|s|v|xv)
     * disk: ([a-z]+)
     * part: (\d*) */
    char **devices = guestfs_list_devices (g);
    if (devices == NULL)
      return NULL;

    /* Check any hints we were passed for a non-heuristic mapping */
    char *name = safe_asprintf (g, "%sd%s", type, disk);
    size_t i = 0;
    struct drive *drive = g->drives;
    while (drive) {
      if (drive->name && STREQ(drive->name, name)) {
        device = safe_asprintf (g, "%s%s", devices[i], part);
        break;
      }

      i++; drive = drive->next;
    }
    free (name);

    /* Guess the appliance device name if we didn't find a matching hint */
    if (!device) {
      /* Count how many disks the libguestfs appliance has */
      size_t count;
      for (count = 0; devices[count] != NULL; count++)
        ;

      /* Calculate the numerical index of the disk */
      i = disk[0] - 'a';
      for (char *p = disk + 1; *p != '\0'; p++) {
        i += 1; i *= 26;
        i += *p - 'a';
      }

      /* Check the index makes sense wrt the number of disks the appliance has.
       * If it does, map it to an appliance disk. */
      if (i < count) {
        device = safe_asprintf (g, "%s%s", devices[i], part);
      }
    }

    free (type);
    free (disk);
    free (part);
    guestfs___free_string_list (devices);
  }
  else if (match2 (g, spec, re_cciss, &disk, &part)) {
    /* disk: (cciss/c\d+d\d+)
     * part: (\d+)? */
    char **devices = guestfs_list_devices (g);
    if (devices == NULL)
      return NULL;

    /* Check any hints we were passed for a non-heuristic mapping */
    size_t i = 0;
    struct drive *drive = g->drives;
    while (drive) {
      if (drive->name && STREQ(drive->name, disk)) {
        if (part) {
          device = safe_asprintf (g, "%s%s", devices[i], part);
        } else {
          device = safe_strdup (g, devices[i]);
        }
        break;
      }

      i++; drive = drive->next;
    }

    /* We don't try to guess mappings for cciss devices */

    free (disk);
    free (part);
    guestfs___free_string_list (devices);
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

#endif /* defined(HAVE_HIVEX) */
