/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
#include <string.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

int
do_internal_feature_available (const char *group)
{
  size_t i;

  for (i = 0; optgroups[i].group != NULL; ++i) {
    if (STREQ (group, optgroups[i].group)) {
      const int av = optgroups[i].available ();
      return av ? 0 : 1;
    }
  }

  /* Unknown group */
  return 2;
}

char **
do_available_all_groups (void)
{
  size_t i;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (groups);

  for (i = 0; optgroups[i].group != NULL; ++i) {
    if (add_string (&groups, optgroups[i].group) == -1)
      return NULL;
  }

  if (end_stringsbuf (&groups) == -1)
    return NULL;

  return take_stringsbuf (&groups);           /* caller frees */
}

/* Search for filesystem in /proc/filesystems, ignoring "nodev". */
static int
test_proc_filesystems (const char *filesystem)
{
  CLEANUP_FREE char *regex = NULL;
  CLEANUP_FREE char *err = NULL;
  int r;

  if (asprintf (&regex, "^[[:space:]]*%s$", filesystem) == -1) {
    perror ("asprintf");
    return -1;
  }

  r = commandr (NULL, &err, "grep", regex, "/proc/filesystems", NULL);
  if (r == -1 || r >= 2) {
    fprintf (stderr, "grep /proc/filesystems: %s", err);
    return -1;
  }

  return r == 0;
}

/* Do modprobe, ignore any errors. */
static void
modprobe (const char *module)
{
  ignore_value (command (NULL, NULL, "modprobe", module, NULL));
}

/* Internal function for testing if a filesystem is available.  Note
 * this must not call reply_with_error functions.
 */
int
filesystem_available (const char *filesystem)
{
  int r;

  r = test_proc_filesystems (filesystem);
  if (r == -1 || r > 0)
    return r;

  /* Not found: try to modprobe the module, then test again. */
  if (optgroup_linuxmodules_available ()) {
    modprobe (filesystem);

    r = test_proc_filesystems (filesystem);
    if (r == -1)
      return -1;
  }

  return r;
}

int
do_filesystem_available (const char *filesystem)
{
  size_t i;
  const size_t len = strlen (filesystem);
  int r;

  for (i = 0; i < len; ++i) {
    if (!c_isalnum (filesystem[i]) && filesystem[i] != '_') {
      reply_with_error ("filesystem name contains non-alphanumeric characters");
      return -1;
    }
  }

  r = filesystem_available (filesystem);
  if (r == -1) {
    reply_with_error ("error testing for filesystem availability; "
                      "enable verbose mode and look at preceding output");
    return -1;
  }

  return r;
}
