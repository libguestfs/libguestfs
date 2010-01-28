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

#include "daemon.h"
#include "c-ctype.h"
#include "actions.h"
#include "optgroups.h"

int
optgroup_lvm2_available (void)
{
  int r = access ("/sbin/lvm", X_OK);
  return r == 0;
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
               "/sbin/lvm", "pvcreate", device, NULL);
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
  argv[0] = "/sbin/lvm";
  argv[1] = "vgcreate";
  argv[2] = volgroup;
  for (i = 3; i <= argc; ++i)
    argv[i] = physvols[i-3];

  r = commandv (NULL, &err, (const char * const*) argv);
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
do_lvcreate (const char *logvol, const char *volgroup, int mbytes)
{
  char *err;
  int r;
  char size[64];

  snprintf (size, sizeof size, "%d", mbytes);

  r = command (NULL, &err,
               "/sbin/lvm", "lvcreate",
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
               "/sbin/lvm", "lvresize",
               "-L", size, logvol, NULL);
  if (r == -1) {
    reply_with_error ("lvresize: %s", err);
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
    r = command (NULL, &err, "/sbin/lvm", "lvremove", "-f", xs[i], NULL);
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
    r = command (NULL, &err, "/sbin/lvm", "vgremove", "-f", xs[i], NULL);
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
    r = command (NULL, &err, "/sbin/lvm", "pvremove", "-f", xs[i], NULL);
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
               "/sbin/lvm", "lvremove", "-f", device, NULL);
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
               "/sbin/lvm", "vgremove", "-f", device, NULL);
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
               "/sbin/lvm", "pvremove", "-ff", device, NULL);
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
               "/sbin/lvm", "pvresize", device, NULL);
  if (r == -1) {
    reply_with_error ("pvresize: %s: %s", device, err);
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

  argv[0] = "/sbin/lvm";
  argv[1] = "vgchange";
  argv[2] = "-a";
  argv[3] = activate ? "y" : "n";
  for (i = 4; i <= argc; ++i)
    argv[i] = volgroups[i-4];

  r = commandv (NULL, &err, (const char * const*) argv);
  if (r == -1) {
    reply_with_error ("vgchange: %s", err);
    free (err);
    return -1;
  }

  free (err);

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
               "/sbin/lvm", "lvrename",
               logvol, newlogvol, NULL);
  if (r == -1) {
    reply_with_error ("lvrename: %s -> %s: %s", logvol, newlogvol, err);
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
               "/sbin/lvm", "vgrename",
               volgroup, newvolgroup, NULL);
  if (r == -1) {
    reply_with_error ("vgrename: %s -> %s: %s", volgroup, newvolgroup, err);
    free (err);
    return -1;
  }

  free (err);

  udev_settle ();

  return 0;
}
