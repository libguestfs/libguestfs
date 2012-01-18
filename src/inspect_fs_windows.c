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

  COMPILE (re_windows_version, "^(\\d+)\\.(\\d+)", 0);
}

static void
free_regexps (void)
{
  pcre_free (re_windows_version);
}

static int check_windows_arch (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_software_registry (guestfs_h *g, struct inspect_fs *fs);
static int check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs);
static char *map_registry_disk_blob (guestfs_h *g, const char *blob);

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
static const char *systemroots[] =
  { "/windows", "/winnt", "/win32", "/win", NULL };

int
guestfs___has_windows_systemroot (guestfs_h *g)
{
  size_t i;
  char *systemroot, *p;
  char path[256];

  for (i = 0; i < sizeof systemroots / sizeof systemroots[0]; ++i) {
    systemroot = guestfs___case_sensitive_path_silently (g, systemroots[i]);
    if (!systemroot)
      continue;

    snprintf (path, sizeof path, "%s/system32", systemroot);
    if (!guestfs___is_dir_nocase (g, path)) {
      free (systemroot);
      continue;
    }

    snprintf (path, sizeof path, "%s/system32/config", systemroot);
    if (!guestfs___is_dir_nocase (g, path)) {
      free (systemroot);
      continue;
    }

    snprintf (path, sizeof path, "%s/system32/cmd.exe", systemroot);
    if (!guestfs___is_file_nocase (g, path)) {
      free (systemroot);
      continue;
    }

    free (systemroot);

    return (int)i;
  }

  return -1; /* not found */
}

int
guestfs___check_windows_root (guestfs_h *g, struct inspect_fs *fs)
{
  int i;
  char *systemroot;

  fs->type = OS_TYPE_WINDOWS;
  fs->distro = OS_DISTRO_WINDOWS;

  i = guestfs___has_windows_systemroot (g);
  if (i == -1) {
    error (g, "check_windows_root: has_windows_systemroot unexpectedly returned -1");
    return -1;
  }

  systemroot = guestfs___case_sensitive_path_silently (g, systemroots[i]);
  if (!systemroot) {
    error (g, _("cannot resolve Windows %%SYSTEMROOT%%"));
    return -1;
  }

  debug (g, "windows %%SYSTEMROOT%% = %s", systemroot);

  /* Freed by guestfs___free_inspect_info. */
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

  char *cmd_exe_path = guestfs___case_sensitive_path_silently (g, cmd_exe);
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
  size_t len = strlen (fs->windows_systemroot) + 64;
  char software[len];
  snprintf (software, len, "%s/system32/config/software",
            fs->windows_systemroot);

  char *software_path = guestfs___case_sensitive_path_silently (g, software);
  if (!software_path)
    /* If the software hive doesn't exist, just accept that we cannot
     * find product_name etc.
     */
    return 0;

  char *software_hive = NULL;
  int ret = -1;
  hive_h *h = NULL;
  hive_value_h *values = NULL;

  software_hive = guestfs___download_to_tmp (g, fs, software_path, "software",
                                             MAX_REGISTRY_SIZE);
  if (software_hive == NULL)
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
        fs->major_version = guestfs___parse_unsigned_int (g, major);
        free (major);
        if (fs->major_version == -1) {
          free (minor);
          free (key);
          free (version);
          goto out;
        }
        fs->minor_version = guestfs___parse_unsigned_int (g, minor);
        free (minor);
        if (fs->minor_version == -1) {
          free (key);
          free (version);
          goto out;
        }
      }

      free (version);
    }
    else if (STRCASEEQ (key, "InstallationType")) {
      fs->product_variant = hivex_value_string (h, values[i]);
      if (!fs->product_variant) {
        perrorf (g, "hivex_value_string");
        free (key);
        goto out;
      }
    }

    free (key);
  }

  ret = 0;

 out:
  if (h) hivex_close (h);
  free (values);
  free (software_path);
  free (software_hive);

  return ret;
}

static int
check_windows_system_registry (guestfs_h *g, struct inspect_fs *fs)
{
  size_t len = strlen (fs->windows_systemroot) + 64;
  char system[len];
  snprintf (system, len, "%s/system32/config/system",
            fs->windows_systemroot);

  char *system_path = guestfs___case_sensitive_path_silently (g, system);
  if (!system_path)
    /* If the system hive doesn't exist, just accept that we cannot
     * find hostname etc.
     */
    return 0;

  char *system_hive = NULL;
  int ret = -1;
  hive_h *h = NULL;
  hive_node_h root, node;
  hive_value_h value, *values = NULL;
  int32_t dword;
  size_t i, count;

  system_hive =
    guestfs___download_to_tmp (g, fs, system_path, "system",
                               MAX_REGISTRY_SIZE);
  if (system_hive == NULL)
    goto out;

  h = hivex_open (system_hive, g->verbose ? HIVEX_OPEN_VERBOSE : 0);
  if (h == NULL) {
    perrorf (g, "hivex_open");
    goto out;
  }

  root = hivex_root (h);
  if (root == 0) {
    perrorf (g, "hivex_root");
    goto out;
  }

  /* Get the CurrentControlSet. */
  errno = 0;
  node = hivex_node_get_child (h, root, "Select");
  if (node == 0) {
    if (errno != 0)
      perrorf (g, "hivex_node_get_child");
    else
      error (g, "hivex: could not locate HKLM\\SYSTEM\\Select");
    goto out;
  }

  errno = 0;
  value = hivex_node_get_value (h, node, "Current");
  if (value == 0) {
    if (errno != 0)
      perrorf (g, "hivex_node_get_value");
    else
      error (g, "hivex: HKLM\\System\\Select Default entry not found.");
    goto out;
  }

  /* XXX Should check the type. */
  dword = hivex_value_dword (h, value);
  fs->windows_current_control_set = safe_asprintf (g, "ControlSet%03d", dword);

  /* Get the drive mappings.
   * This page explains the contents of HKLM\System\MountedDevices:
   * http://www.goodells.net/multiboot/partsigs.shtml
   */
  errno = 0;
  node = hivex_node_get_child (h, root, "MountedDevices");
  if (node == 0) {
    if (errno != 0)
      perrorf (g, "hivex_node_get_child");
    else
      error (g, "hivex: could not locate HKLM\\SYSTEM\\MountedDevices");
    goto out;
  }

  values = hivex_node_values (h, node);

  /* Count how many DOS drive letter mappings there are.  This doesn't
   * ignore removable devices, so it overestimates, but that doesn't
   * matter because it just means we'll allocate a few bytes extra.
   */
  for (i = count = 0; values[i] != 0; ++i) {
    char *key = hivex_value_key (h, values[i]);
    if (key == NULL) {
      perrorf (g, "hivex_value_key");
      goto out;
    }
    if (STRCASEEQLEN (key, "\\DosDevices\\", 12) &&
        c_isalpha (key[12]) && key[13] == ':')
      count++;
    free (key);
  }

  fs->drive_mappings = calloc (2*count + 1, sizeof (char *));
  if (fs->drive_mappings == NULL) {
    perrorf (g, "calloc");
    goto out;
  }

  for (i = count = 0; values[i] != 0; ++i) {
    char *key = hivex_value_key (h, values[i]);
    if (key == NULL) {
      perrorf (g, "hivex_value_key");
      goto out;
    }
    if (STRCASEEQLEN (key, "\\DosDevices\\", 12) &&
        c_isalpha (key[12]) && key[13] == ':') {
      /* Get the binary value.  Is it a fixed disk? */
      char *blob, *device;
      size_t len;
      hive_type type;

      blob = hivex_value_value (h, values[i], &type, &len);
      if (blob != NULL && type == 3 && len == 12) {
        /* Try to map the blob to a known disk and partition. */
        device = map_registry_disk_blob (g, blob);
        if (device != NULL) {
          fs->drive_mappings[count++] = safe_strndup (g, &key[12], 1);
          fs->drive_mappings[count++] = device;
        }
      }
      free (blob);
    }
    free (key);
  }

  /* Get the hostname. */
  const char *hivepath[] =
    { fs->windows_current_control_set, "Services", "Tcpip", "Parameters" };
  for (node = root, i = 0;
       node != 0 && i < sizeof hivepath / sizeof hivepath[0];
       ++i) {
    node = hivex_node_get_child (h, node, hivepath[i]);
  }

  if (node == 0) {
    perrorf (g, "hivex: cannot locate HKLM\\SYSTEM\\%s\\Services\\Tcpip\\Parameters",
             fs->windows_current_control_set);
    goto out;
  }

  free (values);
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
  free (system_hive);

  return ret;
}

/* Windows Registry HKLM\SYSTEM\MountedDevices uses a blob of data
 * to store partitions.  This blob is described here:
 * http://www.goodells.net/multiboot/partsigs.shtml
 * The following function maps this blob to a libguestfs partition
 * name, if possible.
 */
static char *
map_registry_disk_blob (guestfs_h *g, const char *blob)
{
  char **devices = NULL;
  struct guestfs_partition_list *partitions = NULL;
  char *diskid;
  size_t i, j, len;
  char *ret = NULL;
  uint64_t part_offset;

  /* First 4 bytes are the disk ID.  Search all devices to find the
   * disk with this disk ID.
   */
  devices = guestfs_list_devices (g);
  if (devices == NULL)
    goto out;

  for (i = 0; devices[i] != NULL; ++i) {
    /* Read the disk ID. */
    diskid = guestfs_pread_device (g, devices[i], 4, 0x01b8, &len);
    if (diskid == NULL)
      continue;
    if (len < 4) {
      free (diskid);
      continue;
    }
    if (memcmp (diskid, blob, 4) == 0) { /* found it */
      free (diskid);
      goto found_disk;
    }
    free (diskid);
  }
  goto out;

 found_disk:
  /* Next 8 bytes are the offset of the partition in bytes(!) given as
   * a 64 bit little endian number.  Luckily it's easy to get the
   * partition byte offset from guestfs_part_list.
   */
  part_offset = le64toh (* (uint64_t *) &blob[4]);

  partitions = guestfs_part_list (g, devices[i]);
  if (partitions == NULL)
    goto out;

  for (j = 0; j < partitions->len; ++j) {
    if (partitions->val[j].part_start == part_offset) /* found it */
      goto found_partition;
  }
  goto out;

 found_partition:
  /* Construct the full device name. */
  ret = safe_asprintf (g, "%s%d", devices[i], partitions->val[j].part_num);

 out:
  if (devices)
    guestfs___free_string_list (devices);
  if (partitions)
    guestfs_free_partition_list (partitions);
  return ret;
}

#endif /* defined(HAVE_HIVEX) */

char *
guestfs___case_sensitive_path_silently (guestfs_h *g, const char *path)
{
  guestfs_error_handler_cb old_error_cb = g->error_cb;
  g->error_cb = NULL;
  char *ret = guestfs_case_sensitive_path (g, path);
  g->error_cb = old_error_cb;
  return ret;
}
