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

#include "c-ctype.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

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
  fs->product_name = guestfs_int_first_line_of_file (g, "/.disk/info");
  if (!fs->product_name)
    return -1;

  fs->type = OS_TYPE_LINUX;
  if (STRPREFIX (fs->product_name, "Ubuntu"))
    fs->distro = OS_DISTRO_UBUNTU;
  else if (STRPREFIX (fs->product_name, "Debian"))
    fs->distro = OS_DISTRO_DEBIAN;

  (void) guestfs_int_parse_major_minor (g, fs);

  if (guestfs_is_file (g, "/.disk/cd_type") > 0) {
    CLEANUP_FREE char *cd_type =
      guestfs_int_first_line_of_file (g, "/.disk/cd_type");
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

/* RHEL 5 has a DVD.iso and several CD-sized -discX-ftp.iso alternatives.
 *
 * The DVD.iso contains:
 *   /.treeinfo:
 *     [general]
 *     family = Red Hat Enterprise Linux Server
 *     timestamp = 1328200566.61
 *     totaldiscs = 1
 *     version = 5.8
 *     discnum = 1
 *     packagedir = Server
 *     arch = x86_64
 *     [...]
 *
 *   /.discinfo:
 *     1328205744.315196
 *     Red Hat Enterprise Linux Server 5.8  # product name
 *     x86_64                               # arch
 *     1                                    # disk number
 *     Server/base
 *     Server/RPMS
 *     Server/pixmaps
 *
 * The alternative CD-sized ISOs contain:
 *
 * disc1:
 *   /.treeinfo:
 *     [general]
 *     family = Red Hat Enterprise Linux Server
 *     timestamp = 1328200566.61
 *     totaldiscs = 1
 *     version = 5.8
 *     discnum = 1
 *     packagedir = Server
 *     arch = x86_64
 *     [...]
 *
 *   /.discinfo:
 *     1328205744.315196
 *     Red Hat Enterprise Linux Server 5.8  # product name
 *     x86_64                               # arch
 *     1                                    # disk number
 *     Server/base
 *     Server/RPMS
 *     Server/pixmaps
 *
 * discN (N > 1):
 *   /.discinfo:
 *     1328205744.315196
 *     Red Hat Enterprise Linux Server 5.8  # product name
 *     x86_64                               # arch
 *     2                                    # disk number
 *     Server/base
 *     Server/RPMS
 *     Server/pixmaps
 */

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

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^family = Fedora$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_FEDORA;
    free (str);
  }

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^family = Red Hat Enterprise Linux$",
                                     0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_RHEL;
    free (str);
  }

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^family = Oracle Linux Server$",
                                     0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_ORACLE_LINUX;
    free (str);
  }

  /* XXX should do major.minor before this */
  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^version = [[:digit:]]+", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    fs->major_version = guestfs_int_parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^arch = [-_[:alnum:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    fs->arch = safe_strdup (g, v);
    free (str);
  }

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^discnum = [[:digit:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    discnum = guestfs_int_parse_unsigned_int (g, v);
    free (str);
    if (discnum == -1)
      return -1;
  }

  r = guestfs_int_first_egrep_of_file (g, "/.treeinfo",
                                     "^totaldiscs = [[:digit:]]+$", 0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    v = find_value (str);
    totaldiscs = guestfs_int_parse_unsigned_int (g, v);
    free (str);
    if (totaldiscs == -1)
      return -1;
  }

  fs->is_multipart_disk = totaldiscs > 1;
  /* and what about discnum? */

  return 0;
}

/* Linux with /isolinux/isolinux.cfg.
 *
 * This file is not easily parsable so we have to do our best.
 * Look for the "menu title" line which contains:
 *   menu title Welcome to Fedora 14!   # since at least Fedora 10
 *   menu title Welcome to Red Hat Enterprise Linux 6.0!
 *   menu title Welcome to RHEL6.2-20111117.0-Workstation-x!
 */
static int
check_isolinux_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  char *str;
  int r;

  fs->type = OS_TYPE_LINUX;

  r = guestfs_int_first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                                     "^menu title Welcome to Fedora [[:digit:]]+",
                                     0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_FEDORA;
    fs->major_version =
      guestfs_int_parse_unsigned_int_ignore_trailing (g, &str[29]);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  /* XXX parse major.minor */
  r = guestfs_int_first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                                     "^menu title Welcome to Red Hat Enterprise Linux [[:digit:]]+",
                           0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_RHEL;
    fs->major_version =
      guestfs_int_parse_unsigned_int_ignore_trailing (g, &str[47]);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  /* XXX parse major.minor */
  r = guestfs_int_first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                                     "^menu title Welcome to RHEL[[:digit:]]+",
                           0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_RHEL;
    fs->major_version =
      guestfs_int_parse_unsigned_int_ignore_trailing (g, &str[26]);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  /* XXX parse major.minor */
  r = guestfs_int_first_egrep_of_file (g, "/isolinux/isolinux.cfg",
                                     "^menu title Welcome to Oracle Linux Server [[:digit:]]+",
                           0, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    fs->distro = OS_DISTRO_ORACLE_LINUX;
    fs->major_version =
      guestfs_int_parse_unsigned_int_ignore_trailing (g, &str[42]);
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

  r = guestfs_int_first_egrep_of_file (g, txtsetup,
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

  r = guestfs_int_first_egrep_of_file (g, txtsetup,
                                     "^majorversion[[:space:]]*=[[:space:]]*[[:digit:]]+",
                                     1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    v = find_value (str);
    fs->major_version = guestfs_int_parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->major_version == -1)
      return -1;
  }

  r = guestfs_int_first_egrep_of_file (g, txtsetup,
                                     "^minorversion[[:space:]]*=[[:space:]]*[[:digit:]]+",
                                     1, &str);
  if (r == -1)
    return -1;
  if (r > 0) {
    trim_cr (str);
    v = find_value (str);
    fs->minor_version = guestfs_int_parse_unsigned_int_ignore_trailing (g, v);
    free (str);
    if (fs->minor_version == -1)
      return -1;
  }

  /* This is the windows systemroot that would be chosen on
   * installation by default, although not necessarily the one that
   * the user will finally choose.
   */
  r = guestfs_int_first_egrep_of_file (g, txtsetup,
                                     "^defaultpath[[:space:]]*=[[:space:]]*",
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
int
guestfs_int_check_installer_root (guestfs_h *g, struct inspect_fs *fs)
{
  /* The presence of certain files indicates a live CD.
   *
   * XXX Fedora netinst contains a ~120MB squashfs called
   * /images/install.img.  However this is not a live CD (unlike the
   * Fedora live CDs which contain the same, but larger file).  We
   * need to unpack this and look inside to tell the difference.
   */
  if (guestfs_is_file (g, "/casper/filesystem.squashfs") > 0 ||
      guestfs_is_file (g, "/live/filesystem.squashfs") > 0 ||
      guestfs_is_file (g, "/mfsroot.gz") > 0)
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

  /* FreeDOS install CD. */
  else if (guestfs_is_file (g, "/freedos/freedos.ico") > 0 &&
           guestfs_is_file (g, "/setup.bat") > 0) {
    fs->type = OS_TYPE_DOS;
    fs->distro = OS_DISTRO_FREEDOS;
    fs->arch = safe_strdup (g, "i386");
  }

  /* Linux with /isolinux/isolinux.cfg (note that non-Linux can use
   * ISOLINUX too, eg. FreeDOS).
   */
  else if (guestfs_is_file (g, "/isolinux/isolinux.cfg") > 0) {
    if (check_isolinux_installer_root (g, fs) == -1)
      return -1;
  }

  /* FreeBSD with /boot/loader.rc. */
  else if (guestfs_is_file (g, "/boot/loader.rc") > 0) {
    fs->type = OS_TYPE_FREEBSD;
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

/* This is called for whole block devices.  See if the device is an
 * ISO and we are able to read the ISO info from it.  In that case,
 * try using libosinfo to map from the volume ID and other strings
 * directly to the operating system type.
 */
int
guestfs_int_check_installer_iso (guestfs_h *g, struct inspect_fs *fs,
                               const char *device)
{
  CLEANUP_FREE_ISOINFO struct guestfs_isoinfo *isoinfo = NULL;
  const struct osinfo *osinfo;
  int r;

  guestfs_push_error_handler (g, NULL, NULL);
  isoinfo = guestfs_isoinfo_device (g, device);
  guestfs_pop_error_handler (g);
  if (!isoinfo)
    return 0;

  r = guestfs_int_osinfo_map (g, isoinfo, &osinfo);
  if (r == -1)                  /* Fatal error. */
    return -1;
  if (r == 0)                   /* Could not locate any matching ISO. */
    return 0;

  /* Otherwise we matched an ISO, so fill in the fs fields. */
  fs->mountable = safe_strdup (g, device);
  fs->is_root = 1;
  fs->format = OS_FORMAT_INSTALLER;
  fs->type = osinfo->type;
  fs->distro = osinfo->distro;
  fs->product_name =
    osinfo->product_name ? safe_strdup (g, osinfo->product_name) : NULL;
  fs->major_version = osinfo->major_version;
  fs->minor_version = osinfo->minor_version;
  fs->arch = osinfo->arch ? safe_strdup (g, osinfo->arch) : NULL;
  fs->is_live_disk = osinfo->is_live_disk;

  guestfs_int_check_package_format (g, fs);
  guestfs_int_check_package_management (g, fs);

  return 1;
}
