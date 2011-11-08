/* libguestfs - the guestfsd daemon
 * Copyright (C) 2010-2011 Red Hat Inc.
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

#include "c-ctype.h"
#include "ignore-value.h"

#include "daemon.h"
#include "actions.h"

/* This runs during daemon start up and creates a complete copy of
 * /etc/lvm so that we can modify it as we desire.  We set
 * LVM_SYSTEM_DIR to point to the copy.
 */
static char lvm_system_dir[] = "/tmp/lvmXXXXXX";

static void rm_lvm_system_dir (void);

void
copy_lvm (void)
{
  struct stat statbuf;
  char cmd[64];
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
    perror (lvm_system_dir);
    exit (EXIT_FAILURE);
  }

  /* Hopefully no dotfiles in there ... XXX */
  snprintf (cmd, sizeof cmd, "cp -a /etc/lvm/* %s", lvm_system_dir);
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
  setenv ("LVM_SYSTEM_DIR", lvm_system_dir, 1);

  /* Set a handler to remove the temporary directory at exit. */
  atexit (rm_lvm_system_dir);
}

static void
rm_lvm_system_dir (void)
{
  char cmd[64];

  snprintf (cmd, sizeof cmd, "rm -rf %s", lvm_system_dir);
  ignore_value (system (cmd));
}

/* Does the current line match the regexp /^\s*filter\s*=/ */
static int
is_filter_line (const char *line)
{
  while (*line && c_isspace (*line))
    line++;
  if (!*line)
    return 0;

  if (! STRPREFIX (line, "filter"))
    return 0;
  line += 6;

  while (*line && c_isspace (*line))
    line++;
  if (!*line)
    return 0;

  if (*line != '=')
    return 0;

  return 1;
}

/* Rewrite the 'filter = [ ... ]' line in lvm.conf. */
static int
set_filter (const char *filter)
{
  char lvm_conf[64];
  snprintf (lvm_conf, sizeof lvm_conf, "%s/lvm.conf", lvm_system_dir);

  char lvm_conf_new[64];
  snprintf (lvm_conf_new, sizeof lvm_conf, "%s/lvm.conf.new", lvm_system_dir);

  FILE *ifp = fopen (lvm_conf, "r");
  if (ifp == NULL) {
    reply_with_perror ("open: %s", lvm_conf);
    return -1;
  }
  FILE *ofp = fopen (lvm_conf_new, "w");
  if (ofp == NULL) {
    reply_with_perror ("open: %s", lvm_conf_new);
    fclose (ifp);
    return -1;
  }

  char *line = NULL;
  size_t len = 0;
  while (getline (&line, &len, ifp) != -1) {
    int r;
    if (is_filter_line (line)) {
      r = fprintf (ofp, "    filter = [ %s ]\n", filter);
    } else {
      r = fprintf (ofp, "%s", line);
    }
    if (r < 0) {
      /* NB. fprintf doesn't set errno on error. */
      reply_with_error ("%s: write failed", lvm_conf_new);
      fclose (ifp);
      fclose (ofp);
      free (line);
      unlink (lvm_conf_new);
      return -1;
    }
  }

  free (line);

  if (fclose (ifp) == EOF) {
    reply_with_perror ("close: %s", lvm_conf);
    unlink (lvm_conf_new);
    fclose (ofp);
    return -1;
  }
  if (fclose (ofp) == EOF) {
    reply_with_perror ("close: %s", lvm_conf_new);
    unlink (lvm_conf_new);
    return -1;
  }

  if (rename (lvm_conf_new, lvm_conf) == -1) {
    reply_with_perror ("rename: %s", lvm_conf);
    unlink (lvm_conf_new);
    return -1;
  }

  return 0;
}

static int
vgchange (const char *vgchange_flag)
{
  char *err;
  int r = command (NULL, &err, "lvm", "vgchange", vgchange_flag, NULL);
  if (r == -1) {
    reply_with_error ("vgchange: %s", err);
    free (err);
    return -1;
  }

  free (err);
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
  snprintf (lvm_cache, sizeof lvm_cache, "%s/cache/.cache", lvm_system_dir);

  unlink (lvm_cache);

  char *err;
  int r = command (NULL, &err, "lvm", "vgscan", NULL);
  if (r == -1) {
    reply_with_error ("vgscan: %s", err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

/* Construct the new, specific filter string.  We can assume that
 * the 'devices' array does not contain any regexp metachars,
 * because it's already been checked by the stub code.
 */
static char *
make_filter_string (char *const *devices)
{
  size_t i;
  size_t len = 64;
  for (i = 0; devices[i] != NULL; ++i)
    len += strlen (devices[i]) + 16;

  char *filter = malloc (len);
  if (filter == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  char *p = filter;
  for (i = 0; devices[i] != NULL; ++i) {
    /* Because of the way matching works in LVM, each match clause
     * should be either:
     *   "a|^/dev/sda|",      for whole block devices, or
     *   "a|^/dev/sda1$|",    for single partitions
     * (the assumption being we have <= 26 block devices XXX).
     */
    size_t slen = strlen (devices[i]);
    char str[slen+16];

    if (c_isdigit (devices[i][slen-1]))
      snprintf (str, slen+16, "\"a|^%s$|\", ", devices[i]);
    else
      snprintf (str, slen+16, "\"a|^%s|\", ", devices[i]);

    strcpy (p, str);
    p += strlen (str);
  }
  strcpy (p, "\"r|.*|\"");

  return filter;                /* Caller must free. */
}

int
do_lvm_set_filter (char *const *devices)
{
  char *filter = make_filter_string (devices);
  if (filter == NULL)
    return -1;

  if (deactivate () == -1) {
    free (filter);
    return -1;
  }

  int r = set_filter (filter);
  free (filter);
  if (r == -1)
    return -1;

  if (rescan () == -1)
    return -1;

  return reactivate ();
}

int
do_lvm_clear_filter (void)
{
  if (deactivate () == -1)
    return -1;

  if (set_filter ("\"a/.*/\"") == -1)
    return -1;

  if (rescan () == -1)
    return -1;

  return reactivate ();
}
