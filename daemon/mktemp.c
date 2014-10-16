/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 FUJITSU LTD.
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

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

char *
do_mkdtemp (const char *template)
{
  char *writable = strdup (template);
  if (writable == NULL) {
    reply_with_perror ("strdup");
    return NULL;
  }

  CHROOT_IN;
  char *r = mkdtemp (writable);
  CHROOT_OUT;

  if (r == NULL) {
    reply_with_perror ("%s", template);
    free (writable);
  }

  return r;
}

char *
do_mktemp (const char *template,
           const char *suffix)
{
  char *dest_name = NULL;
  size_t suffix_len = 0;
  int fd;
  size_t len;

  if (optargs_bitmask & GUESTFS_MKTEMP_SUFFIX_BITMASK) {
    if (suffix) {
      len = strlen (template);
      if (len == 0 || template[len - 1] != 'X') {
        reply_with_error ("template %s must end in X", template);
        return NULL;
      }

      /* Append suffix to template. */
      suffix_len = strlen (suffix);
      if (asprintf (&dest_name, "%s%s", template, suffix) == -1) {
        reply_with_perror ("asprintf");
        return NULL;
      }
    }
  }

  if (dest_name == NULL) {
    dest_name = strdup (template);
    if (dest_name == NULL) {
      reply_with_perror ("strdup");
      return NULL;
    }
  }

  CHROOT_IN;
  fd = mkstemps (dest_name, (int) suffix_len);
  CHROOT_OUT;

  if (fd == -1) {
    reply_with_perror ("%s", dest_name);
    free (dest_name);
    return NULL;
  }

  close (fd);

  return dest_name;
}
