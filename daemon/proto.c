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
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#include "daemon.h"
#include "../src/guestfs_protocol.h"

/* XXX We should make this configurable from /proc/cmdline so that the
 * verbose setting of the guestfs_h can be inherited here.
 */
#define DEBUG 1

/* The message currently being processed. */
int proc_nr;
int serial;

/* The daemon communications socket. */
static int sock;

void
main_loop (int _sock)
{
  XDR xdr;
  char *buf;
  char lenbuf[4];
  unsigned len;
  struct guestfs_message_header hdr;

  sock = _sock;

  for (;;) {
    /* Read the length word. */
    xread (sock, lenbuf, 4);
    xdrmem_create (&xdr, lenbuf, 4, XDR_DECODE);
    xdr_uint32_t (&xdr, &len);
    xdr_destroy (&xdr);

    if (len > GUESTFS_MESSAGE_MAX) {
      fprintf (stderr, "guestfsd: incoming message is too long (%u bytes)\n",
	       len);
      exit (1);
    }

    buf = malloc (len);
    if (!buf) {
      reply_with_perror ("malloc");
      continue;
    }

    xread (sock, buf, len);

#if DEBUG
    int i, j;

#define MIN(a,b) ((a)<(b)?(a):(b))

    for (i = 0; i < len; i += 16) {
      printf ("%04x: ", i);
      for (j = i; j < MIN (i+16, len); ++j)
	printf ("%02x ", (unsigned char) buf[j]);
      for (; j < i+16; ++j)
	printf ("   ");
      printf ("|");
      for (j = i; j < MIN (i+16, len); ++j)
	if (isprint (buf[j]))
	  printf ("%c", buf[j]);
	else
	  printf (".");
      for (; j < i+16; ++j)
	printf (" ");
      printf ("|\n");
    }
#endif

    /* Decode the message header. */
    xdrmem_create (&xdr, buf, len, XDR_DECODE);
    if (!xdr_guestfs_message_header (&xdr, &hdr)) {
      fprintf (stderr, "guestfsd: could not decode message header\n");
      exit (1);
    }

    /* Check the version etc. */
    if (hdr.prog != GUESTFS_PROGRAM) {
      reply_with_error ("wrong program (%d)", hdr.prog);
      goto cont;
    }
    if (hdr.vers != GUESTFS_PROTOCOL_VERSION) {
      reply_with_error ("wrong protocol version (%d)", hdr.vers);
      goto cont;
    }
    if (hdr.direction != GUESTFS_DIRECTION_CALL) {
      reply_with_error ("unexpected message direction (%d)", hdr.direction);
      goto cont;
    }
    if (hdr.status != GUESTFS_STATUS_OK) {
      reply_with_error ("unexpected message status (%d)", hdr.status);
      goto cont;
    }

    /* Now start to process this message. */
    proc_nr = hdr.proc;
    serial = hdr.serial;
    dispatch_incoming_message (&xdr);
    /* Note that dispatch_incoming_message will also send a reply. */

  cont:
    xdr_destroy (&xdr);
    free (buf);
  }
}

static void send_error (const char *msg);

void
reply_with_error (const char *fs, ...)
{
  char err[GUESTFS_ERROR_LEN];
  va_list args;

  va_start (args, fs);
  vsnprintf (err, sizeof err, fs, args);
  va_end (args);

  send_error (err);
}

void
reply_with_perror (const char *fs, ...)
{
  char buf1[GUESTFS_ERROR_LEN];
  char buf2[GUESTFS_ERROR_LEN];
  va_list args;
  int err = errno;

  va_start (args, fs);
  vsnprintf (buf1, sizeof buf1, fs, args);
  va_end (args);

  snprintf (buf2, sizeof buf2, "%s: %s", buf1, strerror (err));

  send_error (buf2);
}

static void
send_error (const char *msg)
{
  XDR xdr;
  char buf[GUESTFS_ERROR_LEN + 200];
  char lenbuf[4];
  struct guestfs_message_header hdr;
  struct guestfs_message_error err;
  unsigned len;

  fprintf (stderr, "guestfsd: error: %s\n", msg);

  xdrmem_create (&xdr, buf, sizeof buf, XDR_ENCODE);

  hdr.prog = GUESTFS_PROGRAM;
  hdr.vers = GUESTFS_PROTOCOL_VERSION;
  hdr.direction = GUESTFS_DIRECTION_REPLY;
  hdr.status = GUESTFS_STATUS_ERROR;
  hdr.proc = proc_nr;
  hdr.serial = serial;

  if (!xdr_guestfs_message_header (&xdr, &hdr)) {
    fprintf (stderr, "guestfsd: failed to encode error message header\n");
    exit (1);
  }

  err.error = (char *) msg;

  if (!xdr_guestfs_message_error (&xdr, &err)) {
    fprintf (stderr, "guestfsd: failed to encode error message body\n");
    exit (1);
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  xdrmem_create (&xdr, lenbuf, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);
  xdr_destroy (&xdr);

  xwrite (sock, lenbuf, 4);
  xwrite (sock, buf, len);
}

void
reply (xdrproc_t xdrp, char *ret)
{
  XDR xdr;
  char buf[GUESTFS_MESSAGE_MAX];
  char lenbuf[4];
  struct guestfs_message_header hdr;
  unsigned len;

  xdrmem_create (&xdr, buf, sizeof buf, XDR_ENCODE);

  hdr.prog = GUESTFS_PROGRAM;
  hdr.vers = GUESTFS_PROTOCOL_VERSION;
  hdr.direction = GUESTFS_DIRECTION_REPLY;
  hdr.status = GUESTFS_STATUS_OK;
  hdr.proc = proc_nr;
  hdr.serial = serial;

  if (!xdr_guestfs_message_header (&xdr, &hdr)) {
    fprintf (stderr, "guestfsd: failed to encode reply header\n");
    exit (1);
  }

  if (xdrp) {
    if (!(*xdrp) (&xdr, ret)) {
      fprintf (stderr, "guestfsd: failed to encode reply body\n");
      exit (1);
    }
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  xdrmem_create (&xdr, lenbuf, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);
  xdr_destroy (&xdr);

  xwrite (sock, lenbuf, 4);
  xwrite (sock, buf, len);
}
