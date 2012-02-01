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

#ifdef HAVE_SELINUX_SELINUX_H
#include <selinux/selinux.h>
#endif

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if defined(HAVE_LIBSELINUX)

int
optgroup_selinux_available (void)
{
  return 1;
}

/* setcon is only valid under the following circumstances:
 * - single threaded
 * - enforcing=0
 */
int
do_setcon (const char *context)
{
#if defined(HAVE_SETCON)
  if (setcon ((char *) context) == -1) {
    reply_with_perror ("setcon");
    return -1;
  }

  return 0;
#else
  reply_with_error ("function not available");
  return -1;
#endif
}

char *
do_getcon (void)
{
#if defined(HAVE_GETCON)
  security_context_t context;
  char *r;

  if (getcon (&context) == -1) {
    reply_with_perror ("getcon");
    return NULL;
  }

  r = strdup (context);
  freecon (context);
  if (r == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  return r;                     /* caller frees */
#else
  reply_with_error ("function not available");
  return NULL;
#endif
}

#else /* !HAVE_LIBSELINUX */

int
optgroup_selinux_available (void)
{
  return 0;
}

int
do_setcon (const char *context)
{
  abort ();
}

char *
do_getcon (void)
{
  abort ();
}

#endif /* !HAVE_LIBSELINUX */
