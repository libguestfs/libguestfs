/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010-2012 Red Hat Inc.
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

#include <augeas.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "daemon.h"
#include "actions.h"

GUESTFSD_EXT_CMD(str_lvm, lvm);
GUESTFSD_EXT_CMD(str_cp, cp);
GUESTFSD_EXT_CMD(str_rm, rm);

/* This runs during daemon start up and creates a complete copy of
 * /etc/lvm so that we can modify it as we desire.  We set
 * LVM_SYSTEM_DIR to point to the copy.  Note that the final directory
 * layout is:
 *   /tmp/lvmXXXXXX                 (lvm_system_dir set to this)
 *   /tmp/lvmXXXXXX/lvm             ($LVM_SYSTEM_DIR set to this)
 *   /tmp/lvmXXXXXX/lvm/lvm.conf    (configuration file)
 *   /tmp/lvmXXXXXX/lvm/cache
 *   etc.
 */
static char lvm_system_dir[] = "/tmp/lvmXXXXXX";

static void rm_lvm_system_dir (void);

void
copy_lvm (void)
{
  struct stat statbuf;
  char cmd[64], env[64];
  int r;

  /* If /etc/lvm directory doesn't exist (or isn't a directory) assume
   * that this system doesn't support LVM and do nothing.
   */
  r = stat ("/etc/lvm", &statbuf);
  if (r == -1) {
    perror ("copy_lvm: stat: /etc/lvm");
    return;
  }
  if (! S_ISDIR (statbuf.st_mode)) {
    fprintf (stderr, "copy_lvm: warning: /etc/lvm is not a directory\n");
    return;
  }

  if (mkdtemp (lvm_system_dir) == NULL) {
    fprintf (stderr, "mkdtemp: %s: %m\n", lvm_system_dir);
    exit (EXIT_FAILURE);
  }

  /* Copy the entire directory */
  snprintf (cmd, sizeof cmd, "%s -a /etc/lvm/ %s", str_cp, lvm_system_dir);
  r = system (cmd);
  if (r == -1) {
    perror (cmd);
    rmdir (lvm_system_dir);
    exit (EXIT_FAILURE);
  }

  if (WEXITSTATUS (r) != 0) {
    fprintf (stderr, "cp command failed with return code %d\n",
             WEXITSTATUS (r));
    rmdir (lvm_system_dir);
    exit (EXIT_FAILURE);
  }

  /* Set environment variable so we use the copy. */
  snprintf (env, sizeof env, "%s/lvm", lvm_system_dir);
  setenv ("LVM_SYSTEM_DIR", env, 1);

  /* Set a handler to remove the temporary directory at exit. */
  atexit (rm_lvm_system_dir);
}

static void
rm_lvm_system_dir (void)
{
  char cmd[64];

  snprintf (cmd, sizeof cmd, "%s -rf %s", str_rm, lvm_system_dir);
  ignore_value (system (cmd));
}

/* Rewrite the 'filter = [ ... ]' line in lvm.conf. */
static int
set_filter (char *const *filters)
{
  CLEANUP_AUG_CLOSE augeas *aug = NULL;
  int r;
  int count;

  /* Small optimization: do not load the files at init time,
   * but do that only after having applied the transformation.
   */
  const int flags = AUG_NO_ERR_CLOSE | AUG_NO_LOAD;
  aug = aug_init (lvm_system_dir, NULL, flags);
  if (!aug) {
    reply_with_error ("augeas initialization failed");
    return -1;
  }

  if (aug_error (aug) != AUG_NOERROR) {
    AUGEAS_ERROR ("aug_init");
    return -1;
  }

  r = aug_transform (aug, "lvm", "/lvm/lvm.conf",
                     0 /* = included */);
  if (r == -1) {
    AUGEAS_ERROR ("aug_transform");
    return -1;
  }

  if (aug_load (aug) == -1) {
    AUGEAS_ERROR ("aug_load");
    return -1;
  }

  /* Remove all the old filters ... */
  r = aug_rm (aug, "/files/lvm/lvm.conf/devices/dict/filter/list/*");
  if (r == -1) {
    AUGEAS_ERROR ("aug_rm");
    return -1;
  }

  /* ... and add the new ones. */
  for (count = 0; filters[count] != NULL; ++count) {
    char buf[128];

    snprintf (buf, sizeof buf,
              "/files/lvm/lvm.conf/devices/dict/filter/list/%d/str",
              count + 1);

    if (aug_set (aug, buf, filters[count]) == -1) {
      AUGEAS_ERROR ("aug_set: %d: %s", count, filters[count]);
      return -1;
    }
  }

  /* Safety check for the written filter nodes. */
  r = aug_match (aug, "/files/lvm/lvm.conf/devices/dict/filter/list/*/str",
                 NULL);
  if (r == -1) {
    AUGEAS_ERROR ("aug_match");
    return -1;
  }
  if (r != count) {
    reply_with_error ("filters# vs matches mismatch: %d vs %d", count, r);
    return -1;
  }

  if (aug_save (aug) == -1) {
    AUGEAS_ERROR ("aug_save");
    return -1;
  }

  return 0;
}

static int
vgchange (const char *vgchange_flag)
{
  CLEANUP_FREE char *err = NULL;
  int r = command (NULL, &err, str_lvm, "vgchange", vgchange_flag, NULL);
  if (r == -1) {
    reply_with_error ("vgchange %s: %s", vgchange_flag, err);
    return -1;
  }

  return 0;
}

/* Deactivate all VGs. */
static int
deactivate (void)
{
  return vgchange ("-an");
}

/* Reactivate all VGs. */
static int
reactivate (void)
{
  return vgchange ("-ay");
}

/* Clear the cache and rescan. */
static int
rescan (void)
{
  char lvm_cache[64];
  snprintf (lvm_cache, sizeof lvm_cache, "%s/lvm/cache/.cache", lvm_system_dir);

  unlink (lvm_cache);

  CLEANUP_FREE char *err = NULL;
  int r = command (NULL, &err, str_lvm, "vgscan", NULL);
  if (r == -1) {
    reply_with_error ("vgscan: %s", err);
    return -1;
  }

  return 0;
}

/* Construct the new, specific filter strings.  We can assume that
 * the 'devices' array does not contain any regexp metachars,
 * because it's already been checked by the stub code.
 */
static char **
make_filter_strings (char *const *devices)
{
  size_t i;
  DECLARE_STRINGSBUF (ret);

  for (i = 0; devices[i] != NULL; ++i) {
    /* Because of the way matching works in LVM (yes, they wrote their
     * own regular expression engine!), each match clause should be either:
     *
     *   for single partitions:
     *     "a|^/dev/sda1$|",
     *   for whole block devices:
     *     "a|^/dev/sda$|", "a|^/dev/sda[0-9]|",
     */
    size_t slen = strlen (devices[i]);

    if (add_sprintf (&ret, "a|^%s$|", devices[i]) == -1)
      goto error;

    if (!c_isdigit (devices[i][slen-1])) {
      /* whole block device */
      if (add_sprintf (&ret, "a|^%s[0-9]|", devices[i]) == -1)
        goto error;
    }
  }
  if (add_string (&ret, "r|.*|") == -1)
    goto error;

  if (end_stringsbuf (&ret) == -1)
    goto error;

  return ret.argv;

error:
  if (ret.argv)
    free_stringslen (ret.argv, ret.size);
  return NULL;
}

int
do_lvm_set_filter (char *const *devices)
{
  CLEANUP_FREE_STRING_LIST char **filters = make_filter_strings (devices);
  if (filters == NULL)
    return -1;

  if (deactivate () == -1)
    return -1;

  int r = set_filter (filters);
  if (r == -1)
    return -1;

  if (rescan () == -1)
    return -1;

  return reactivate ();
}

int
do_lvm_clear_filter (void)
{
  const char *const filters[2] = { "a/.*/", NULL };

  if (deactivate () == -1)
    return -1;

  if (set_filter ((char *const *) filters) == -1)
    return -1;

  if (rescan () == -1)
    return -1;

  return reactivate ();
}
