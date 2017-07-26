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
#include <errno.h>
#include <error.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <augeas.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "daemon.h"
#include "actions.h"

/* This runs during daemon start up and creates a fresh LVM
 * configuration which we can modify as we desire.  LVM allows
 * configuration to be completely empty (meaning "all defaults").
 *
 * The final directory layout is:
 *
 *   /tmp/lvmXXXXXX                 (lvm_system_dir set to this)
 *   /tmp/lvmXXXXXX/lvm             ($LVM_SYSTEM_DIR set to this)
 *   /tmp/lvmXXXXXX/lvm/lvm.conf    (configuration file - initially empty)
 */
static char lvm_system_dir[] = "/tmp/lvmXXXXXX";

static void rm_lvm_system_dir (void);
static void debug_lvm_config (void);

void
clean_lvm_config (void)
{
  char env[64], conf[64];
  FILE *fp;

  if (mkdtemp (lvm_system_dir) == NULL)
    error (EXIT_FAILURE, errno, "mkdtemp: %s", lvm_system_dir);

  snprintf (env, sizeof env, "%s/lvm", lvm_system_dir);
  mkdir (env, 0755);
  snprintf (conf, sizeof conf, "%s/lvm/lvm.conf", lvm_system_dir);
  fp = fopen (conf, "w");
  if (fp == NULL) {
    perror ("clean_lvm_config: cannot create empty lvm.conf");
    exit (EXIT_FAILURE);
  }
  fclose (fp);

  /* Set environment variable so we use the clean configuration. */
  setenv ("LVM_SYSTEM_DIR", env, 1);

  /* Set a handler to remove the temporary directory at exit. */
  atexit (rm_lvm_system_dir);

  debug_lvm_config ();
}

/* Try to run lvmetad, without failing if it couldn't. */
void
start_lvmetad (void)
{
  int r;

  if (verbose)
    printf ("%s\n", "lvmetad");
  r = system ("lvmetad");
  if (r == -1)
    perror ("system/lvmetad");
  else if (!WIFEXITED (r) || WEXITSTATUS (r) != 0)
    fprintf (stderr, "warning: lvmetad command failed\n");
}

static void
rm_lvm_system_dir (void)
{
  char cmd[64];

  snprintf (cmd, sizeof cmd, "rm -rf %s", lvm_system_dir);
  ignore_value (system (cmd));
}

/* Rewrite the 'filter = [ ... ]' line in lvm.conf. */
static int
set_filter (char *const *filters)
{
  const char *filter_types[] = { "filter", "global_filter", NULL };
  CLEANUP_FREE char *conf = NULL;
  FILE *fp;
  size_t i, j;

  if (asprintf (&conf, "%s/lvm/lvm.conf", lvm_system_dir) == -1) {
    reply_with_perror ("asprintf");
    return -1;
  }
  fp = fopen (conf, "we");
  if (fp == NULL) {
    reply_with_perror ("open: %s", conf);
    return -1;
  }

  fprintf (fp, "devices {\n");
  for (j = 0; filter_types[j] != NULL; ++j) {
    fprintf (fp, "    %s = [\n", filter_types[j]);
    fprintf (fp, "        ");

    for (i = 0; filters[i] != NULL; ++i) {
      if (i > 0)
        fprintf (fp, ",\n        ");
      fprintf (fp, "\"%s\"", filters[i]);
    }

    fprintf (fp, "\n");
    fprintf (fp, "    ]\n");
  }
  fprintf (fp, "}\n");

  fclose (fp);

  debug_lvm_config ();

  return 0;
}

static int
vgchange (const char *vgchange_flag)
{
  CLEANUP_FREE char *err = NULL;
  int r = command (NULL, &err, "lvm", "vgchange", vgchange_flag, NULL);
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
  int r = command (NULL, &err, "lvm", "vgscan", NULL);
  if (r == -1) {
    reply_with_error ("vgscan: %s", err);
    return -1;
  }

  return 0;
}

/* Show what lvm thinks is the current config.  Useful for debugging. */
static void
debug_lvm_config (void)
{
  if (verbose) {
    fprintf (stderr, "lvm config:\n");
    ignore_value (system ("lvm config"));
  }
}

/* Construct the new, specific filter strings.  We can assume that
 * the 'devices' array does not contain any regexp metachars,
 * because it's already been checked by the stub code.
 */
static char **
make_filter_strings (char *const *devices)
{
  size_t i;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (ret);

  for (i = 0; devices[i] != NULL; ++i) {
    /* Because of the way matching works in LVM (yes, they wrote their
     * own regular expression engine!), each match clause should be either:
     *
     *   for single partitions:
     *     "a|^/dev/sda1$|",
     *   for whole block devices:
     *     "a|^/dev/sda$|", "a|^/dev/sda[0-9]|",
     */
    const size_t slen = strlen (devices[i]);

    if (add_sprintf (&ret, "a|^%s$|", devices[i]) == -1)
      return NULL;

    if (!c_isdigit (devices[i][slen-1])) {
      /* whole block device */
      if (add_sprintf (&ret, "a|^%s[0-9]|", devices[i]) == -1)
        return NULL;
    }
  }
  if (add_string (&ret, "r|.*|") == -1)
    return NULL;

  if (end_stringsbuf (&ret) == -1)
    return NULL;

  return take_stringsbuf (&ret);
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
