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
#include <iconv.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include <pcre.h>

#include "c-ctype.h"
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
static pcre *re_windows_version;
static pcre *re_boot_ini_os_header;
static pcre *re_boot_ini_os;

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

  COMPILE (re_windows_version, "^(\\d+)\\.(\\d+)", 0);
  COMPILE (re_boot_ini_os_header, "^\\[operating systems\\]\\s*$", 0);
  COMPILE (re_boot_ini_os, "^(multi|scsi)\\((\\d+)\\)disk\\((\\d+)\\)rdisk\\((\\d+)\\)partition\\((\\d+)\\)([^=]+)=", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_windows_version);
  pcre_free (re_boot_ini_os_header);
  pcre_free (re_boot_ini_os);
}

static int check_windows_arch (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_software_registry (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs);
static char *map_registry_disk_blob (guestfs_h *g, const void *blob);

/* XXX Handling of boot.ini in the Perl version was pretty broken.  It
 * essentially didn't do anything for modern Windows guests.
 * Therefore I've omitted all that code.
 */

/* Try to find Windows systemroot using some common locations.
 *
 * Notes:
 *
 * (1) We check for some directories inside to see if it is a real
 * systemroot, and not just a directory that happens to have the same
 * name.
 *
 * (2) If a Windows guest has multiple disks and applications are
 * installed on those other disks, then those other disks will contain
 * "/Program Files" and "/System Volume Information".  Those would
 * *not* be Windows root disks.  (RHBZ#674130)
 */

static int
is_systemroot (guestfs_h *const g, const char *systemroot)
{
  char path[256];

  snprintf (path, sizeof path, "%s/system32", systemroot);
  if (!guestfs_int_is_dir_nocase (g, path))
    return 0;

  snprintf (path, sizeof path, "%s/system32/config", systemroot);
  if (!guestfs_int_is_dir_nocase (g, path))
    return 0;

  snprintf (path, sizeof path, "%s/system32/cmd.exe", systemroot);
  if (!guestfs_int_is_file_nocase (g, path))
    return 0;

  return 1;
}

char *
guestfs_int_get_windows_systemroot (guestfs_h *g)
{
  /* Check a predefined list of common windows system root locations */
  static const char *systemroots[] =
    { "/windows", "/winnt", "/win32", "/win", NULL };

  for (size_t i = 0; i < sizeof systemroots / sizeof systemroots[0]; ++i) {
    char *systemroot =
      guestfs_int_case_sensitive_path_silently (g, systemroots[i]);
    if (!systemroot)
      continue;

    if (is_systemroot (g, systemroot)) {
      debug (g, "windows %%SYSTEMROOT%% = %s", systemroot);

      return systemroot;
    } else {
      free (systemroot);
    }
  }

  /* If the fs contains boot.ini, check it for non-standard
   * systemroot locations */
  CLEANUP_FREE char *boot_ini_path =
    guestfs_int_case_sensitive_path_silently (g, "/boot.ini");
  if (boot_ini_path && guestfs_is_file (g, boot_ini_path) > 0) {
    CLEANUP_FREE_STRING_LIST char **boot_ini =
      guestfs_read_lines (g, boot_ini_path);
    if (!boot_ini) {
      debug (g, "error reading %s", boot_ini_path);
      return NULL;
    }

    int found_os = 0;
    for (char **i = boot_ini; *i != NULL; i++) {
      CLEANUP_FREE char *controller_type = NULL;
      CLEANUP_FREE char *controller = NULL;
      CLEANUP_FREE char *disk = NULL;
      CLEANUP_FREE char *rdisk = NULL;
      CLEANUP_FREE char *partition = NULL;
      CLEANUP_FREE char *path = NULL;

      char *line = *i;

      if (!found_os) {
        if (match (g, line, re_boot_ini_os_header)) {
          found_os = 1;
          continue;
        }
      }

      /* See http://support.microsoft.com/kb/102873 for a discussion
       * of what this line means */
      if (match6 (g, line, re_boot_ini_os, &controller_type,
                  &controller, &disk, &rdisk, &partition, &path))
      {
        /* The Windows system root may be on any disk. However, there
         * are currently (at least) 2 practical problems preventing us
         * from locating it on another disk:
         *
         * 1. We don't have enough metadata about the disks we were
         * given to know if what controller they were on and what
         * index they had.
         *
         * 2. The way inspection of filesystems currently works, we
         * can't mark another filesystem, which we may have already
         * inspected, to be inspected for a specific Windows system
         * root.
         *
         * Solving 1 properly would require a new API at a minimum. We
         * might be able to fudge something practical without this,
         * though, e.g. by looking at the <partition>th partition of
         * every disk for the specific windows root.
         *
         * Solving 2 would probably require a significant refactoring
         * of the way filesystems are inspected. We should probably do
         * this some time.
         *
         * For the moment, we ignore all partition information and
         * assume the system root is on the current partition. In
         * practice, this will normally be correct.
         */

        /* Swap backslashes for forward slashes in the system root
         * path */
        for (char *j = path; *j != '\0'; j++) {
          if (*j == '\\') *j = '/';
        }

        char *systemroot = guestfs_int_case_sensitive_path_silently (g, path);
        if (systemroot && is_systemroot (g, systemroot)) {
          debug (g, "windows %%SYSTEMROOT%% = %s", systemroot);

          return systemroot;
        } else {
          free (systemroot);
        }
      }
    }
  }

  return NULL; /* not found */
}

int
guestfs_int_check_windows_root (guestfs_h *g, struct inspect_fs *fs,
                              char *const systemroot)
{
  fs->type = OS_TYPE_WINDOWS;
  fs->distro = OS_DISTRO_WINDOWS;

  /* Freed by guestfs_int_free_inspect_info. */
  fs->windows_systemroot = systemroot;

  if (check_windows_arch (g, fs) == -1)
    return -1;

  /* Product name and version. */
  if (check_windows_software_registry (g, fs) == -1)
    return -1;

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

  /* Should exist because of previous check above in get_windows_systemroot. */
  CLEANUP_FREE char *cmd_exe_path = guestfs_case_sensitive_path (g, cmd_exe);
  if (!cmd_exe_path)
    return -1;

  char *arch = guestfs_file_architecture (g, cmd_exe_path);

  if (arch)
    fs->arch = arch;        /* freed by guestfs_int_free_inspect_info */

  return 0;
}

/* At the moment, pull just the ProductName and version numbers from
 * the registry.  In future there is a case for making many more
 * registry fields available to callers.
 */
static int
check_windows_software_registry (guestfs_h *g, struct inspect_fs *fs)
{
  int ret = -1;
  int r;

  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  CLEANUP_FREE char *software_path = guestfs_case_sensitive_path (g, software);
  if (!software_path)
    return -1;

  r = guestfs_is_file (g, software_path);
  if (r == -1)
    return -1;
  /* If the software hive doesn't exist, just accept that we cannot
   * find product_name etc.
   */
  if (r == 0)
    return 0;

  int64_t node;
  const char *hivepath[] =
    { "Microsoft", "Windows NT", "CurrentVersion" };
  size_t i;
  CLEANUP_FREE_HIVEX_VALUE_LIST struct guestfs_hivex_value_list *values = NULL;

  if (guestfs_hivex_open (g, software_path,
                          GUESTFS_HIVEX_OPEN_VERBOSE, g->verbose, -1) == -1)
    return -1;

  node = guestfs_hivex_root (g);
  for (i = 0; node > 0 && i < sizeof hivepath / sizeof hivepath[0]; ++i)
    node = guestfs_hivex_node_get_child (g, node, hivepath[i]);

  if (node == -1)
    goto out;

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion");
    goto out;
  }

  values = guestfs_hivex_node_values (g, node);

  for (i = 0; i < values->len; ++i) {
    int64_t value = values->val[i].hivex_value_h;
    CLEANUP_FREE char *key = guestfs_hivex_value_key (g, value);
    if (key == NULL)
      goto out;

    if (STRCASEEQ (key, "ProductName")) {
      fs->product_name = guestfs_hivex_value_utf8 (g, value);
      if (!fs->product_name)
        goto out;
    }
    else if (STRCASEEQ (key, "CurrentVersion")) {
      CLEANUP_FREE char *version = guestfs_hivex_value_utf8 (g, value);
      if (!version)
        goto out;
      char *major, *minor;
      if (match2 (g, version, re_windows_version, &major, &minor)) {
        fs->major_version = guestfs_int_parse_unsigned_int (g, major);
        free (major);
        if (fs->major_version == -1) {
          free (minor);
          goto out;
        }
        fs->minor_version = guestfs_int_parse_unsigned_int (g, minor);
        free (minor);
        if (fs->minor_version == -1)
          goto out;
      }
    }
    else if (STRCASEEQ (key, "InstallationType")) {
      fs->product_variant = guestfs_hivex_value_utf8 (g, value);
      if (!fs->product_variant)
        goto out;
    }
  }

  ret = 0;

 out:
  guestfs_hivex_close (g);

  return ret;
}

static int
check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs)
{
  int r;
  size_t len = strlen (fs->windows_systemroot) + 64;
  char system[len];
  snprintf (system, len, "%s/system32/config/system",
            fs->windows_systemroot);

  CLEANUP_FREE char *system_path = guestfs_case_sensitive_path (g, system);
  if (!system_path)
    return -1;

  r = guestfs_is_file (g, system_path);
  if (r == -1)
    return -1;
  /* If the system hive doesn't exist, just accept that we cannot
   * find hostname etc.
   */
  if (r == 0)
    return 0;

  int ret = -1;
  int64_t root, node, value;
  CLEANUP_FREE_HIVEX_VALUE_LIST struct guestfs_hivex_value_list *values = NULL;
  CLEANUP_FREE_HIVEX_VALUE_LIST struct guestfs_hivex_value_list *values2 = NULL;
  int32_t dword;
  size_t i, count;
  CLEANUP_FREE void *buf = NULL;
  size_t buflen;
  const char *hivepath[] =
    { NULL /* current control set */, "Services", "Tcpip", "Parameters" };

  if (guestfs_hivex_open (g, system_path,
                          GUESTFS_HIVEX_OPEN_VERBOSE, g->verbose, -1) == -1)
    goto out;

  root = guestfs_hivex_root (g);
  if (root == 0)
    goto out;

  /* Get the CurrentControlSet. */
  node = guestfs_hivex_node_get_child (g, root, "Select");
  if (node == -1)
    goto out;

  if (node == 0) {
    error (g, "hivex: could not locate HKLM\\SYSTEM\\Select");
    goto out;
  }

  value = guestfs_hivex_node_get_value (g, node, "Current");
  if (value == -1)
    goto out;

  if (value == 0) {
    error (g, "hivex: HKLM\\System\\Select Default entry not found");
    goto out;
  }

  /* XXX Should check the type. */
  buf = guestfs_hivex_value_value (g, value, &buflen);
  if (buflen != 4) {
    error (g, "hivex: HKLM\\System\\Select\\Current expected to be DWORD");
    goto out;
  }
  dword = le32toh (*(int32_t *)buf);
  fs->windows_current_control_set = safe_asprintf (g, "ControlSet%03d", dword);

  /* Get the drive mappings.
   * This page explains the contents of HKLM\System\MountedDevices:
   * http://www.goodells.net/multiboot/partsigs.shtml
   */
  node = guestfs_hivex_node_get_child (g, root, "MountedDevices");
  if (node == -1)
    goto out;

  if (node == 0)
    /* Not found: skip getting drive letter mappings (RHBZ#803664). */
    goto skip_drive_letter_mappings;

  values = guestfs_hivex_node_values (g, node);

  /* Count how many DOS drive letter mappings there are.  This doesn't
   * ignore removable devices, so it overestimates, but that doesn't
   * matter because it just means we'll allocate a few bytes extra.
   */
  for (i = count = 0; i < values->len; ++i) {
    CLEANUP_FREE char *key =
      guestfs_hivex_value_key (g, values->val[i].hivex_value_h);
    if (key == NULL)
      goto out;
    if (STRCASEEQLEN (key, "\\DosDevices\\", 12) &&
        c_isalpha (key[12]) && key[13] == ':')
      count++;
  }

  fs->drive_mappings = safe_calloc (g, 2*count + 1, sizeof (char *));

  for (i = count = 0; i < values->len; ++i) {
    int64_t v = values->val[i].hivex_value_h;
    CLEANUP_FREE char *key = guestfs_hivex_value_key (g, v);
    if (key == NULL)
      goto out;
    if (STRCASEEQLEN (key, "\\DosDevices\\", 12) &&
        c_isalpha (key[12]) && key[13] == ':') {
      /* Get the binary value.  Is it a fixed disk? */
      CLEANUP_FREE char *blob = NULL;
      char *device;
      size_t len;
      int64_t type;

      type = guestfs_hivex_value_type (g, v);
      blob = guestfs_hivex_value_value (g, v, &len);
      if (blob != NULL && type == 3 && len == 12) {
        /* Try to map the blob to a known disk and partition. */
        device = map_registry_disk_blob (g, blob);
        if (device != NULL) {
          fs->drive_mappings[count++] = safe_strndup (g, &key[12], 1);
          fs->drive_mappings[count++] = device;
        }
      }
    }
  }

 skip_drive_letter_mappings:;
  /* Get the hostname. */
  hivepath[0] = fs->windows_current_control_set;
  for (node = root, i = 0;
       node > 0 && i < sizeof hivepath / sizeof hivepath[0];
       ++i) {
    node = guestfs_hivex_node_get_child (g, node, hivepath[i]);
  }

  if (node == -1)
    goto out;

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SYSTEM\\%s\\Services\\Tcpip\\Parameters",
             fs->windows_current_control_set);
    goto out;
  }

  values2 = guestfs_hivex_node_values (g, node);
  if (values2 == NULL)
    goto out;

  for (i = 0; i < values2->len; ++i) {
    int64_t v = values2->val[i].hivex_value_h;
    CLEANUP_FREE char *key = guestfs_hivex_value_key (g, v);
    if (key == NULL)
      goto out;

    if (STRCASEEQ (key, "Hostname")) {
      fs->hostname = guestfs_hivex_value_utf8 (g, v);
      if (!fs->hostname)
        goto out;
    }
    /* many other interesting fields here ... */
  }

  ret = 0;

 out:
  guestfs_hivex_close (g);

  return ret;
}

/* Windows Registry HKLM\SYSTEM\MountedDevices uses a blob of data
 * to store partitions.  This blob is described here:
 * http://www.goodells.net/multiboot/partsigs.shtml
 * The following function maps this blob to a libguestfs partition
 * name, if possible.
 */
static char *
map_registry_disk_blob (guestfs_h *g, const void *blob)
{
  CLEANUP_FREE_STRING_LIST char **devices = NULL;
  CLEANUP_FREE_PARTITION_LIST struct guestfs_partition_list *partitions = NULL;
  size_t i, j, len;
  uint64_t part_offset;

  /* First 4 bytes are the disk ID.  Search all devices to find the
   * disk with this disk ID.
   */
  devices = guestfs_list_devices (g);
  if (devices == NULL)
    return NULL;

  for (i = 0; devices[i] != NULL; ++i) {
    /* Read the disk ID. */
    CLEANUP_FREE char *diskid =
      guestfs_pread_device (g, devices[i], 4, 0x01b8, &len);
    if (diskid == NULL)
      continue;
    if (len < 4)
      continue;
    if (memcmp (diskid, blob, 4) == 0) /* found it */
      goto found_disk;
  }
  return NULL;

 found_disk:
  /* Next 8 bytes are the offset of the partition in bytes(!) given as
   * a 64 bit little endian number.  Luckily it's easy to get the
   * partition byte offset from guestfs_part_list.
   */
  memcpy (&part_offset, (char *) blob + 4, sizeof (part_offset));
  part_offset = le64toh (part_offset);

  partitions = guestfs_part_list (g, devices[i]);
  if (partitions == NULL)
    return NULL;

  for (j = 0; j < partitions->len; ++j) {
    if (partitions->val[j].part_start == part_offset) /* found it */
      goto found_partition;
  }
  return NULL;

 found_partition:
  /* Construct the full device name. */
  return safe_asprintf (g, "%s%d", devices[i], partitions->val[j].part_num);
}

/* NB: This function DOES NOT test for the existence of the file.  It
 * will return non-NULL even if the file/directory does not exist.
 * You have to call guestfs_is_file{,_opts} etc.
 */
char *
guestfs_int_case_sensitive_path_silently (guestfs_h *g, const char *path)
{
  char *ret;

  guestfs_push_error_handler (g, NULL, NULL);
  ret = guestfs_case_sensitive_path (g, path);
  guestfs_pop_error_handler (g);

  return ret;
}

/* Read the data from 'valueh', assume it is UTF16LE and convert it to
 * UTF8.  This is copied from hivex_value_string which doesn't work in
 * the appliance because it uses iconv_open which doesn't work because
 * we delete all the i18n databases.
 */
static char *utf16_to_utf8 (/* const */ char *input, size_t len);

char *
guestfs_impl_hivex_value_utf8 (guestfs_h *g, int64_t valueh)
{
  char *ret;
  size_t buflen;

  CLEANUP_FREE char *buf = guestfs_hivex_value_value (g, valueh, &buflen);
  if (buf == NULL)
    return NULL;

  ret = utf16_to_utf8 (buf, buflen);
  if (ret == NULL) {
    perrorf (g, "hivex: conversion of registry value to UTF8 failed");
    return NULL;
  }

  return ret;
}

static char *
utf16_to_utf8 (/* const */ char *input, size_t len)
{
  iconv_t ic = iconv_open ("UTF-8", "UTF-16LE");
  if (ic == (iconv_t) -1)
    return NULL;

  /* iconv(3) has an insane interface ... */

  /* Mostly UTF-8 will be smaller, so this is a good initial guess. */
  size_t outalloc = len;

 again:;
  size_t inlen = len;
  size_t outlen = outalloc;
  char *out = malloc (outlen + 1);
  if (out == NULL) {
    int err = errno;
    iconv_close (ic);
    errno = err;
    return NULL;
  }
  char *inp = input;
  char *outp = out;

  size_t r = iconv (ic, &inp, &inlen, &outp, &outlen);
  if (r == (size_t) -1) {
    if (errno == E2BIG) {
      int err = errno;
      size_t prev = outalloc;
      /* Try again with a larger output buffer. */
      free (out);
      outalloc *= 2;
      if (outalloc < prev) {
        iconv_close (ic);
        errno = err;
        return NULL;
      }
      goto again;
    }
    else {
      /* Else some conversion failure, eg. EILSEQ, EINVAL. */
      int err = errno;
      iconv_close (ic);
      free (out);
      errno = err;
      return NULL;
    }
  }

  *outp = '\0';
  iconv_close (ic);

  return out;
}
