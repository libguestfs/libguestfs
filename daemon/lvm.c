/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2023 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <dirent.h>

#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"
#include "optgroups.h"

#define MAX_ARGS 64

int
optgroup_lvm2_available (void)
{
  return prog_exists ("lvm");
}

/* LVM actions.  Keep an eye on liblvm, although at the time
 * of writing it hasn't progressed very far.
 */

static char **
convert_lvm_output (char *out, const char *prefix)
{
  char *p, *pend;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);
  size_t len;
  char buf[256];
  char *str;

  p = out;
  while (p) {
    pend = strchr (p, '\n');	/* Get the next line of output. */
    if (pend) {
      *pend = '\0';
      pend++;
    }

    while (*p && c_isspace (*p))	/* Skip any leading whitespace. */
      p++;

    /* Sigh, skip trailing whitespace too.  "pvs", I'm looking at you. */
    len = strlen (p)-1;
    while (*p && c_isspace (p[len]))
      p[len--] = '\0';

    if (!*p) {			/* Empty line?  Skip it. */
      p = pend;
      continue;
    }

    /* Prefix? */
    if (prefix) {
      snprintf (buf, sizeof buf, "%s%s", prefix, p);
      str = buf;
    } else
      str = p;

    /* Ignore "unknown device" message (RHBZ#1054761). */
    if (STRNEQ (str, "unknown device")) {
      if (add_string (&ret, str) == -1) {
        free (out);
        return NULL;
      }
    }

    p = pend;
  }

  free (out);

  if (ret.size > 0)
    sort_strings (ret.argv, ret.size);

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret);
}

char **
do_pvs (void)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (&out, &err,
               "lvm", "pvs", "-o", "pv_name", "--noheadings", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  return convert_lvm_output (out, NULL);
}

char **
do_vgs (void)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (&out, &err,
               "lvm", "vgs", "-o", "vg_name", "--noheadings", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    return NULL;
  }

  return convert_lvm_output (out, NULL);
}

/* These were so complex to implement that I ended up auto-generating
 * the code.  That code is in stubs.c, and it is generated as usual
 * by generator.ml.
 */
guestfs_int_lvm_pv_list *
do_pvs_full (void)
{
  return parse_command_line_pvs ();
}

guestfs_int_lvm_vg_list *
do_vgs_full (void)
{
  return parse_command_line_vgs ();
}

guestfs_int_lvm_lv_list *
do_lvs_full (void)
{
  return parse_command_line_lvs ();
}

int
do_pvcreate (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "pvcreate", "--force", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vgcreate (const char *volgroup, char *const *physvols)
{
  int r, argc, i;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE const char **argv = NULL;

  argc = guestfs_int_count_strings (physvols) + 3;
  argv = malloc (sizeof (char *) * (argc + 1));
  if (argv == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }
  argv[0] = "lvm";
  argv[1] = "vgcreate";
  argv[2] = volgroup;
  for (i = 3; i < argc+1; ++i)
    argv[i] = physvols[i-3];

  r = commandv (NULL, &err, (const char * const*) argv);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_lvcreate (const char *logvol, const char *volgroup, int mbytes)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  char size[64];

  snprintf (size, sizeof size, "%d", mbytes);

  r = command (NULL, &err,
               "lvm", "lvcreate", "--yes",
               "-L", size, "-n", logvol, volgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_lvcreate_free (const char *logvol, const char *volgroup, int percent)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (percent < 0 || percent > 100) {
    reply_with_error ("percentage must be [0..100] (was %d)", percent);
    return -1;
  }

  char size[64];
  snprintf (size, sizeof size, "%d%%FREE", percent);

  r = command (NULL, &err,
               "lvm", "lvcreate",
               "-l", size, "-n", logvol, volgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

/* The lvresize command unnecessarily gives an error if you don't
 * change the size of the LV.  Suppress this error.
 * https://bugzilla.redhat.com/show_bug.cgi?id=834712
 */
static int
ignore_same_size_error (const char *err)
{
  return strstr (err, "New size (") != NULL &&
    strstr (err, "extents) matches existing size (") != NULL;
}

int
do_lvresize (const char *logvol, int mbytes)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  char size[64];

  snprintf (size, sizeof size, "%d", mbytes);

  r = command (NULL, &err,
               "lvm", "lvresize",
               "--force", "-L", size, logvol, NULL);
  if (r == -1) {
    if (!ignore_same_size_error (err)) {
      reply_with_error ("%s", err);
      return -1;
    }
  }

  return 0;
}

int
do_lvresize_free (const char *logvol, int percent)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  if (percent < 0 || percent > 100) {
    reply_with_error ("percentage must be [0..100] (was %d)", percent);
    return -1;
  }

  char size[64];
  snprintf (size, sizeof size, "+%d%%FREE", percent);

  r = command (NULL, &err,
               "lvm", "lvresize", "-l", size, logvol, NULL);
  if (r == -1) {
    if (!ignore_same_size_error (err)) {
      reply_with_error ("%s", err);
      return -1;
    }
  }

  return 0;
}

/* Super-dangerous command used for testing.  It removes all
 * LVs, VGs and PVs permanently.
 */
int
do_lvm_remove_all (void)
{
  size_t i;
  int r;

  {
    /* Remove LVs. */
    CLEANUP_FREE_STRING_LIST char **xs = do_lvs ();
    if (xs == NULL)
      return -1;

    for (i = 0; xs[i] != NULL; ++i) {
      CLEANUP_FREE char *err = NULL;

      /* Deactivate the LV first.  On Ubuntu, lvremove '-f' option
       * does not remove active LVs reliably.
       */
      (void) command (NULL, NULL, "lvm", "lvchange", "-an", xs[i], NULL);
      udev_settle ();

      r = command (NULL, &err, "lvm", "lvremove", "-f", xs[i], NULL);
      if (r == -1) {
        reply_with_error ("lvremove: %s: %s", xs[i], err);
        return -1;
      }
    }
  }

  {
    /* Remove VGs. */
    CLEANUP_FREE_STRING_LIST char **xs = do_vgs ();
    if (xs == NULL)
      return -1;

    for (i = 0; xs[i] != NULL; ++i) {
      CLEANUP_FREE char *err = NULL;

      /* Deactivate the VG first, see note above. */
      (void) command (NULL, NULL, "lvm", "vgchange", "-an", xs[i], NULL);
      udev_settle ();

      r = command (NULL, &err, "lvm", "vgremove", "-f", xs[i], NULL);
      if (r == -1) {
        reply_with_error ("vgremove: %s: %s", xs[i], err);
        return -1;
      }
    }
  }

  {
    /* Remove PVs. */
    CLEANUP_FREE_STRING_LIST char **xs = do_pvs ();
    if (xs == NULL)
      return -1;

    for (i = 0; xs[i] != NULL; ++i) {
      CLEANUP_FREE char *err = NULL;

      r = command (NULL, &err, "lvm", "pvremove", "-f", xs[i], NULL);
      if (r == -1) {
        reply_with_error ("pvremove: %s: %s", xs[i], err);
        return -1;
      }
    }
  }

  udev_settle ();

  /* There, that was easy, sorry about your data. */
  return 0;
}

int
do_lvremove (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "lvremove", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vgremove (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "vgremove", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_pvremove (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "pvremove", "-ff", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_pvresize (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "pvresize", device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_pvresize_size (const char *device, int64_t size)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  char buf[32];
  snprintf (buf, sizeof buf, "%" PRIi64 "b", size);

  r = command (NULL, &err,
               "lvm", "pvresize",
               "--yes",
               "--setphysicalvolumesize", buf,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  return 0;
}

int
do_vg_activate (int activate, char *const *volgroups)
{
  int r, i, argc;
  CLEANUP_FREE char *err = NULL;
  CLEANUP_FREE const char **argv = NULL;

  argc = guestfs_int_count_strings (volgroups) + 4;
  argv = malloc (sizeof (char *) * (argc+1));
  if (argv == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  argv[0] = "lvm";
  argv[1] = "vgchange";
  argv[2] = "-a";
  argv[3] = activate ? "y" : "n";
  for (i = 4; i < argc+1; ++i)
    argv[i] = volgroups[i-4];

  r = commandv (NULL, &err, (const char * const*) argv);
  if (r == -1) {
    reply_with_error ("vgchange: %s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vg_activate_all (int activate)
{
  char *empty[] = { NULL };
  return do_vg_activate (activate, empty);
}

int
do_lvrename (const char *logvol, const char *newlogvol)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "lvrename",
               logvol, newlogvol, NULL);
  if (r == -1) {
    reply_with_error ("%s -> %s: %s", logvol, newlogvol, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vgrename (const char *volgroup, const char *newvolgroup)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "vgrename",
               volgroup, newvolgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s -> %s: %s", volgroup, newvolgroup, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

static char *
get_lvm_field (const char *cmd, const char *field, const char *device)
{
  char *out;
  CLEANUP_FREE char *err = NULL;
  int r = command (&out, &err,
                   "lvm", cmd,
                   "--unbuffered", "--noheadings", "-o", field,
                   device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (out);
    return NULL;
  }

  trim (out);
  return out;                   /* Caller frees. */
}

char *
do_pvuuid (const char *device)
{
  return get_lvm_field ("pvs", "pv_uuid", device);
}

char *
do_vguuid (const char *vgname)
{
  return get_lvm_field ("vgs", "vg_uuid", vgname);
}

char *
do_lvuuid (const char *device)
{
  return get_lvm_field ("lvs", "lv_uuid", device);
}

static char **
get_lvm_fields (const char *cmd, const char *field, const char *device)
{
  CLEANUP_FREE char *out = NULL, *err = NULL;

  int r = command (&out, &err,
                   "lvm", cmd,
                   "--unbuffered", "--noheadings", "-o", field,
                   device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return NULL;
  }

  char **ret = split_lines (out);

  if (ret == NULL)
    return NULL;

  size_t i;
  for (i = 0; ret[i] != NULL; ++i)
    trim (ret[i]);

  return ret;
}

char **
do_vgpvuuids (const char *vgname)
{
  return get_lvm_fields ("vgs", "pv_uuid", vgname);
}

char **
do_vglvuuids (const char *vgname)
{
  return get_lvm_fields ("vgs", "lv_uuid", vgname);
}

int
do_vgscan (void)
{
  return do_lvm_scan (0);
}

int
do_lvm_scan (int activate)
{
  CLEANUP_FREE char *err = NULL;
  int r;
  const char *argv[MAX_ARGS];
  size_t i = 0;

  /* Historically this call was never added to the "lvm2" optgroup.
   * Rather than changing that and have the small risk of breaking
   * callers, just make it into a no-op if LVM is not available.
   */
  if (optgroup_lvm2_available () == 0)
    return 0;

  ADD_ARG (argv, i, "lvm");
  ADD_ARG (argv, i, "pvscan");
  ADD_ARG (argv, i, "--cache");
  if (activate) {
    ADD_ARG (argv, i, "--activate");
    ADD_ARG (argv, i, "ay");
  }
  ADD_ARG (argv, i, NULL);

  r = commandv (NULL, &err, (const char * const *) argv);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  return 0;
}

/* Convert a non-canonical LV path like /dev/mapper/vg-lv or /dev/dm-0
 * to a canonical one.
 *
 * This is harder than it should be.  A LV device like /dev/VG/LV is
 * really a symlink to a device-mapper device like /dev/dm-0.  However
 * at the device-mapper (kernel) level, nothing is really known about
 * LVM (a userspace concept).  Therefore we use a convoluted method to
 * determine this, by listing out known LVs and checking whether the
 * rdev (major/minor) of the device we are passed matches any of them.
 *
 * Note use of 'stat' instead of 'lstat' so that symlinks are fully
 * resolved.
 *
 * Returns:
 *   1  =  conversion was successful, path is an LV
 *         '*ret' is set to the updated path if 'ret' is non-NULL.
 *   0  =  path is not an LV
 *  -1  =  error, reply_with_* has been called
 *
 */
int
lv_canonical (const char *device, char **ret)
{
  struct stat stat1, stat2;

  int r = stat (device, &stat1);
  if (r == -1) {
    reply_with_perror ("stat: %s", device);
    return -1;
  }

  CLEANUP_FREE_STRING_LIST char **lvs = do_lvs ();
  if (lvs == NULL)
    return -1;

  size_t i;
  for (i = 0; lvs[i] != NULL; ++i) {
    r = stat (lvs[i], &stat2);
    if (r == -1) {
      reply_with_perror ("stat: %s", lvs[i]);
      return -1;
    }
    if (stat1.st_rdev == stat2.st_rdev) { /* found it */
      if (ret) {
        *ret = strdup (lvs[i]);
        if (*ret == NULL) {
          reply_with_perror ("strdup");
          return -1;
        }
      }
      return 1;
    }
  }

  /* not found */
  return 0;
}

/* Test if a device is a logical volume (RHBZ#619793). */
int
do_is_lv (const mountable_t *mountable)
{
  if (mountable->type != MOUNTABLE_DEVICE)
    return 0;
  return lv_canonical (mountable->device, NULL);
}

/* Return canonical name of LV to caller (RHBZ#638899). */
char *
do_lvm_canonical_lv_name (const char *device)
{
  char *canonical;
  int r;

  /* The device parameter is passed as PlainString because we can't
   * really be sure that the device name will exist (especially for
   * "/dev/mapper/..." names).  Do some sanity checking on it here.
   */
  if (!STRPREFIX (device, "/dev/")) {
    reply_with_error ("%s: not a device name", device);
    return NULL;
  }

  r = lv_canonical (device, &canonical);
  if (r == -1)
    return NULL;

  if (r == 0) {
    reply_with_error_errno (EINVAL, "%s: not a logical volume", device);
    return NULL;
  }

  return canonical;             /* caller frees */
}

char *
do_vgmeta (const char *vg, size_t *size_r)
{
  CLEANUP_FREE char *err = NULL;
  int fd, r;
  char tmp[] = "/tmp/vgmetaXXXXXX";
  size_t alloc, size, max;
  ssize_t rs;
  char *buf, *buf2;

  /* Make a temporary file. */
  fd = mkstemp (tmp);
  if (fd == -1) {
    reply_with_perror ("mkstemp");
    return NULL;
  }

  close (fd);

  r = command (NULL, &err, "lvm", "vgcfgbackup", "-f", tmp, vg, NULL);
  if (r == -1) {
    reply_with_error ("vgcfgbackup: %s", err);
    return NULL;
  }

  /* Now read back the temporary file. */
  fd = open (tmp, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_error ("%s", tmp);
    return NULL;
  }

  /* Read up to GUESTFS_MESSAGE_MAX - <overhead> bytes.  If it's
   * larger than that, we need to return an error instead (for
   * correctness).
   */
  max = GUESTFS_MESSAGE_MAX - 1000;
  buf = NULL;
  size = alloc = 0;

  for (;;) {
    if (size >= alloc) {
      alloc += 8192;
      if (alloc > max) {
        reply_with_error ("metadata is too large for message buffer");
        free (buf);
        close (fd);
        return NULL;
      }
      buf2 = realloc (buf, alloc);
      if (buf2 == NULL) {
        reply_with_perror ("realloc");
        free (buf);
        close (fd);
        return NULL;
      }
      buf = buf2;
    }

    rs = read (fd, buf + size, alloc - size);
    if (rs == -1) {
      reply_with_perror ("read: %s", tmp);
      free (buf);
      close (fd);
      return NULL;
    }
    if (rs == 0)
      break;
    if (rs > 0)
      size += rs;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s", tmp);
    free (buf);
    return NULL;
  }

  unlink (tmp);

  *size_r = size;

  return buf;			/* caller will free */
}

int
do_pvchange_uuid (const char *device)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "pvchange", "-u", device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_pvchange_uuid_all (void)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "pvchange", "-u", "-a", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vgchange_uuid (const char *vg)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "vgchange", "-u", vg, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", vg, err);
    return -1;
  }

  udev_settle ();

  return 0;
}

int
do_vgchange_uuid_all (void)
{
  CLEANUP_FREE char *err = NULL;
  int r;

  r = command (NULL, &err,
               "lvm", "vgchange", "-u", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }

  udev_settle ();

  return 0;
}
