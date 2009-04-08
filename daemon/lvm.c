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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>

#include "daemon.h"
#include "actions.h"

/* LVM actions.  Keep an eye on liblvm, although at the time
 * of writing it hasn't progressed very far.
 */

static char **
convert_lvm_output (char *out, char *prefix)
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

    while (*p && isspace (*p))	/* Skip any leading whitespace. */
      p++;

    /* Sigh, skip trailing whitespace too.  "pvs", I'm looking at you. */
    len = strlen (p)-1;
    while (*p && isspace (p[len]))
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
	       "/sbin/lvm", "pvs", "-o", "pv_name", "--noheadings", NULL);
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
	       "/sbin/lvm", "vgs", "-o", "vg_name", "--noheadings", NULL);
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
	       "/sbin/lvm", "lvs",
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
guestfs_lvm_int_pv_list *
do_pvs_full (void)
{
  return parse_command_line_pvs ();
}

guestfs_lvm_int_vg_list *
do_vgs_full (void)
{
  return parse_command_line_vgs ();
}

guestfs_lvm_int_lv_list *
do_lvs_full (void)
{
  return parse_command_line_lvs ();
}
