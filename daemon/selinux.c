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

#ifdef HAVE_SELINUX_SELINUX_H
#include <selinux/selinux.h>
#endif

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

#ifdef HAVE_LIBSELINUX

/* setcon is only valid under the following circumstances:
 * - single threaded
 * - enforcing=0
 */
int
do_setcon (char *context)
{
#ifdef HAVE_SETCON
  if (setcon ((char *) context) == -1) {
    reply_with_perror ("setcon");
    return -1;
  }

  return 0;
#else
  reply_with_error ("%s is not available", __func__);
  return -1;
#endif
}

char *
do_getcon (void)
{
#ifdef HAVE_GETCON
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
  reply_with_error ("%s is not available", __func__);
  return -1;
#endif
}

#endif /* HAVE_LIBSELINUX */
