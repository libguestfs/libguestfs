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

#include "../src/guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

static char *
checksum (const char *csumtype, const char *path)
{
  const char *program;
  char *out, *err;
  int r;
  int len;

  if (STRCASEEQ (csumtype, "crc"))
    program = "cksum";
  else if (STRCASEEQ (csumtype, "md5"))
    program = "md5sum";
  else if (STRCASEEQ (csumtype, "sha1"))
    program = "sha1sum";
  else if (STRCASEEQ (csumtype, "sha224"))
    program = "sha224sum";
  else if (STRCASEEQ (csumtype, "sha256"))
    program = "sha256sum";
  else if (STRCASEEQ (csumtype, "sha384"))
    program = "sha384sum";
  else if (STRCASEEQ (csumtype, "sha512"))
    program = "sha512sum";
  else {
    reply_with_error ("unknown checksum type, expecting crc|md5|sha1|sha224|sha256|sha384|sha512");
    return NULL;
  }

  r = command (&out, &err, program, path, NULL);
  if (r == -1) {
    reply_with_error ("%s: %s", program, err);
    free (out);
    free (err);
    return NULL;
  }

  free (err);

  /* Split it at the first whitespace. */
  len = strcspn (out, " \t\n");
  out[len] = '\0';

  return out;			/* Caller frees. */
}

char *
do_checksum (const char *csumtype, const char *path)
{
  /* Make the path relative to /sysroot. */
  char *buf = sysroot_path (path);
  if (!buf) {
    reply_with_perror ("malloc");
    return NULL;
  }

  char *r = checksum (csumtype, buf);
  free (buf);
  return r;
}

char *
do_checksum_device (const char *csumtype, const char *device)
{
  return checksum (csumtype, device);
}
