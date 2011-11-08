/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2011 Red Hat Inc.
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
#include <sys/stat.h>
#include <dirent.h>

#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"
#include "optgroups.h"

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
  char **r = NULL;
  int size = 0, alloc = 0;
  int len;
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

    if (add_string (&r, &size, &alloc, str) == -1) {
      free (out);
      return NULL;
    }

    p = pend;
  }

  free (out);

  if (add_string (&r, &size, &alloc, NULL) == -1)
    return NULL;

  sort_strings (r, size-1);
  return r;
}

char **
do_pvs (void)
{
  char *out, *err;
  int r;

  r = command (&out, &err,
               "lvm", "pvs", "-o", "pv_name", "--noheadings", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return convert_lvm_output (out, NULL);
}

char **
do_vgs (void)
{
  char *out, *err;
  int r;

  r = command (&out, &err,
               "lvm", "vgs", "-o", "vg_name", "--noheadings", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return convert_lvm_output (out, NULL);
}

char **
do_lvs (void)
{
  char *out, *err;
  int r;

  r = command (&out, &err,
               "lvm", "lvs",
               "-o", "vg_name,lv_name", "--noheadings",
               "--separator", "/", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  return convert_lvm_output (out, "/dev/");
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
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "pvcreate", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_vgcreate (const char *volgroup, char *const *physvols)
{
  char *err;
  int r, argc, i;
  const char **argv;

  argc = count_strings (physvols) + 3;
  argv = malloc (sizeof (char *) * (argc + 1));
  if (argv == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }
  argv[0] = "lvm";
  argv[1] = "vgcreate";
  argv[2] = volgroup;
  for (i = 3; i <= argc; ++i)
    argv[i] = physvols[i-3];

  r = commandv (NULL, &err, (const char * const*) argv);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    free (argv);
    return -1;
  }

  free (err);
  free (argv);

  udev_settle ();

  return 0;
}

int
do_lvcreate (const char *logvol, const char *volgroup, int mbytes)
{
  char *err;
  int r;
  char size[64];

  snprintf (size, sizeof size, "%d", mbytes);

  r = command (NULL, &err,
               "lvm", "lvcreate",
               "-L", size, "-n", logvol, volgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_lvresize (const char *logvol, int mbytes)
{
  char *err;
  int r;
  char size[64];

  snprintf (size, sizeof size, "%d", mbytes);

  r = command (NULL, &err,
               "lvm", "lvresize",
               "--force", "-L", size, logvol, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_lvresize_free (const char *logvol, int percent)
{
  char *err;
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
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

/* Super-dangerous command used for testing.  It removes all
 * LVs, VGs and PVs permanently.
 */
int
do_lvm_remove_all (void)
{
  char **xs;
  int i, r;
  char *err;

  /* Remove LVs. */
  xs = do_lvs ();
  if (xs == NULL)
    return -1;

  for (i = 0; xs[i] != NULL; ++i) {
    /* Deactivate the LV first.  On Ubuntu, lvremove '-f' option
     * does not remove active LVs reliably.
     */
    (void) command (NULL, NULL, "lvm", "lvchange", "-an", xs[i], NULL);
    udev_settle ();

    r = command (NULL, &err, "lvm", "lvremove", "-f", xs[i], NULL);
    if (r == -1) {
      reply_with_error ("lvremove: %s: %s", xs[i], err);
      free (err);
      free_strings (xs);
      return -1;
    }
    free (err);
  }
  free_strings (xs);

  /* Remove VGs. */
  xs = do_vgs ();
  if (xs == NULL)
    return -1;

  for (i = 0; xs[i] != NULL; ++i) {
    /* Deactivate the VG first, see note above. */
    (void) command (NULL, NULL, "lvm", "vgchange", "-an", xs[i], NULL);
    udev_settle ();

    r = command (NULL, &err, "lvm", "vgremove", "-f", xs[i], NULL);
    if (r == -1) {
      reply_with_error ("vgremove: %s: %s", xs[i], err);
      free (err);
      free_strings (xs);
      return -1;
    }
    free (err);
  }
  free_strings (xs);

  /* Remove PVs. */
  xs = do_pvs ();
  if (xs == NULL)
    return -1;

  for (i = 0; xs[i] != NULL; ++i) {
    r = command (NULL, &err, "lvm", "pvremove", "-f", xs[i], NULL);
    if (r == -1) {
      reply_with_error ("pvremove: %s: %s", xs[i], err);
      free (err);
      free_strings (xs);
      return -1;
    }
    free (err);
  }
  free_strings (xs);

  udev_settle ();

  /* There, that was easy, sorry about your data. */
  return 0;
}

int
do_lvremove (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "lvremove", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_vgremove (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "vgremove", "-f", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_pvremove (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "pvremove", "-ff", device, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_pvresize (const char *device)
{
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "pvresize", device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_pvresize_size (const char *device, int64_t size)
{
  char *err;
  int r;

  char buf[32];
  snprintf (buf, sizeof buf, "%" PRIi64 "b", size);

  r = command (NULL, &err,
               "lvm", "pvresize",
               "--setphysicalvolumesize", buf,
               device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_vg_activate (int activate, char *const *volgroups)
{
  char *err;
  int r, i, argc;
  const char **argv;

  argc = count_strings (volgroups) + 4;
  argv = malloc (sizeof (char *) * (argc+1));
  if (argv == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  argv[0] = "lvm";
  argv[1] = "vgchange";
  argv[2] = "-a";
  argv[3] = activate ? "y" : "n";
  for (i = 4; i <= argc; ++i)
    argv[i] = volgroups[i-4];

  r = commandv (NULL, &err, (const char * const*) argv);
  if (r == -1) {
    reply_with_error ("vgchange: %s", err);
    free (err);
    free (argv);
    return -1;
  }

  free (err);
  free (argv);

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
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "lvrename",
               logvol, newlogvol, NULL);
  if (r == -1) {
    reply_with_error ("%s -> %s: %s", logvol, newlogvol, err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

int
do_vgrename (const char *volgroup, const char *newvolgroup)
{
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "vgrename",
               volgroup, newvolgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s -> %s: %s", volgroup, newvolgroup, err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}

static char *
get_lvm_field (const char *cmd, const char *field, const char *device)
{
  char *out;
  char *err;
  int r = command (&out, &err,
                   "lvm", cmd,
                   "--unbuffered", "--noheadings", "-o", field,
                   device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

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
  char *out;
  char *err;
  int r = command (&out, &err,
                   "lvm", cmd,
                   "--unbuffered", "--noheadings", "-o", field,
                   device, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", device, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  char **ret = split_lines (out);
  free (out);

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
  char *err;
  int r;

  r = command (NULL, &err,
               "lvm", "vgscan", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    free (err);
    return -1;
  }

  free (err);
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

  char **lvs = do_lvs ();
  if (lvs == NULL)
    return -1;

  size_t i;
  for (i = 0; lvs[i] != NULL; ++i) {
    r = stat (lvs[i], &stat2);
    if (r == -1) {
      reply_with_perror ("stat: %s", lvs[i]);
      free_strings (lvs);
      return -1;
    }
    if (stat1.st_rdev == stat2.st_rdev) { /* found it */
      if (ret) {
        *ret = strdup (lvs[i]);
        if (*ret == NULL) {
          reply_with_perror ("strdup");
          free_strings (lvs);
          return -1;
        }
      }
      free_strings (lvs);
      return 1;
    }
  }

  /* not found */
  free_strings (lvs);
  return 0;
}

/* Test if a device is a logical volume (RHBZ#619793). */
int
do_is_lv (const char *device)
{
  return lv_canonical (device, NULL);
}

/* Return canonical name of LV to caller (RHBZ#638899). */
char *
do_lvm_canonical_lv_name (const char *device)
{
  char *canonical;
  int r = lv_canonical (device, &canonical);
  if (r == -1)
    return NULL;

  if (r == 0) {
    reply_with_error ("%s: not a logical volume", device);
    return NULL;
  }

  return canonical;             /* caller frees */
}

/* List everything in /dev/mapper which *isn't* an LV (RHBZ#688062). */
char **
do_list_dm_devices (void)
{
  char **ret = NULL;
  int size = 0, alloc = 0;
  struct dirent *d;
  DIR *dir;
  int r;

  dir = opendir ("/dev/mapper");
  if (!dir) {
    reply_with_perror ("opendir: /dev/mapper");
    return NULL;
  }

  while (1) {
    errno = 0;
    d = readdir (dir);
    if (d == NULL) break;

    /* Ignore . and .. */
    if (STREQ (d->d_name, ".") || STREQ (d->d_name, ".."))
      continue;

    /* Ignore /dev/mapper/control which is used internally by dm. */
    if (STREQ (d->d_name, "control"))
      continue;

    size_t len = strlen (d->d_name);
    char devname[len+64];

    snprintf (devname, len+64, "/dev/mapper/%s", d->d_name);

    /* Ignore dm devices which are LVs. */
    r = lv_canonical (devname, NULL);
    if (r == -1) {
      free_stringslen (ret, size);
      closedir (dir);
      return NULL;
    }
    if (r)
      continue;

    /* Not an LV, so add it. */
    if (add_string (&ret, &size, &alloc, devname) == -1) {
      closedir (dir);
      return NULL;
    }
  }

  /* Did readdir fail? */
  if (errno != 0) {
    reply_with_perror ("readdir: /dev/mapper");
    free_stringslen (ret, size);
    closedir (dir);
    return NULL;
  }

  /* Close the directory handle. */
  if (closedir (dir) == -1) {
    reply_with_perror ("closedir: /dev/mapper");
    free_stringslen (ret, size);
    return NULL;
  }

  /* Sort the output (may be empty). */
  if (ret != NULL)
    sort_strings (ret, size);

  /* NULL-terminate the list. */
  if (add_string (&ret, &size, &alloc, NULL) == -1)
    return NULL;

  return ret;
}
