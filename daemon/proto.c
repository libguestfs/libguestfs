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
#include <sys/param.h>		/* defines MIN */
#include <sys/select.h>
#include <rpc/types.h>
#include <rpc/xdr.h>

#ifdef HAVE_WINDOWS_H
#include <windows.h>
#endif

#include "c-ctype.h"
#include "ignore-value.h"

#include "daemon.h"
#include "../src/guestfs_protocol.h"

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
  uint32_t len;
  struct guestfs_message_header hdr;
  struct timeval start_t, end_t;
  int64_t start_us, end_us, elapsed_us;

  sock = _sock;

  for (;;) {
    /* Most common errors are leaked memory and leaked file descriptors,
     * so run this between each command:
     */
    if (verbose && 0)
      ignore_value (system ("ls -l /proc/self/fd"));

    /* Read the length word. */
    if (xread (sock, lenbuf, 4) == -1)
      exit (EXIT_FAILURE);

    xdrmem_create (&xdr, lenbuf, 4, XDR_DECODE);
    xdr_u_int (&xdr, &len);
    xdr_destroy (&xdr);

    if (len > GUESTFS_MESSAGE_MAX) {
      fprintf (stderr, "guestfsd: incoming message is too long (%u bytes)\n",
               len);
      exit (EXIT_FAILURE);
    }

    buf = malloc (len);
    if (!buf) {
      reply_with_perror ("malloc");
      continue;
    }

    if (xread (sock, buf, len) == -1)
      exit (EXIT_FAILURE);

#ifdef ENABLE_PACKET_DUMP
    if (verbose) {
      size_t i, j;

      for (i = 0; i < len; i += 16) {
        printf ("%04zx: ", i);
        for (j = i; j < MIN (i+16, len); ++j)
          printf ("%02x ", (unsigned char) buf[j]);
        for (; j < i+16; ++j)
          printf ("   ");
        printf ("|");
        for (j = i; j < MIN (i+16, len); ++j)
          if (c_isprint (buf[j]))
            printf ("%c", buf[j]);
          else
            printf (".");
        for (; j < i+16; ++j)
          printf (" ");
        printf ("|\n");
      }
    }
#endif

    /* In verbose mode, display the time taken to run each command. */
    if (verbose)
      gettimeofday (&start_t, NULL);

    /* Decode the message header. */
    xdrmem_create (&xdr, buf, len, XDR_DECODE);
    if (!xdr_guestfs_message_header (&xdr, &hdr)) {
      fprintf (stderr, "guestfsd: could not decode message header\n");
      exit (EXIT_FAILURE);
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

    proc_nr = hdr.proc;
    serial = hdr.serial;

    /* Clear errors before we call the stub functions.  This is just
     * to ensure that we can accurately report errors in cases where
     * error handling paths don't set errno correctly.
     */
    errno = 0;
#ifdef WIN32
    SetLastError (0);
    WSASetLastError (0);
#endif

    /* Now start to process this message. */
    dispatch_incoming_message (&xdr);
    /* Note that dispatch_incoming_message will also send a reply. */

    /* In verbose mode, display the time taken to run each command. */
    if (verbose) {
      gettimeofday (&end_t, NULL);

      start_us = (int64_t) start_t.tv_sec * 1000000 + start_t.tv_usec;
      end_us = (int64_t) end_t.tv_sec * 1000000 + end_t.tv_usec;
      elapsed_us = end_us - start_us;
      fprintf (stderr, "proc %d (%s) took %d.%02d seconds\n",
               proc_nr,
               proc_nr >= 0 && proc_nr < GUESTFS_PROC_NR_PROCS
               ? function_names[proc_nr] : "UNKNOWN PROCEDURE",
               (int) (elapsed_us / 1000000),
               (int) ((elapsed_us / 10000) % 100));
    }

  cont:
    xdr_destroy (&xdr);
    free (buf);
  }
}

static void send_error (int errnum, const char *msg);

void
reply_with_error (const char *fs, ...)
{
  char err[GUESTFS_ERROR_LEN];
  va_list args;

  va_start (args, fs);
  vsnprintf (err, sizeof err, fs, args);
  va_end (args);

  send_error (0, err);
}

void
reply_with_perror_errno (int err, const char *fs, ...)
{
  char buf1[GUESTFS_ERROR_LEN];
  char buf2[GUESTFS_ERROR_LEN];
  va_list args;

  va_start (args, fs);
  vsnprintf (buf1, sizeof buf1, fs, args);
  va_end (args);

  snprintf (buf2, sizeof buf2, "%s: %s", buf1, strerror (err));

  send_error (err, buf2);
}

static void
send_error (int errnum, const char *msg)
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
    exit (EXIT_FAILURE);
  }

  err.linux_errno = errnum;
  err.error_message = (char *) msg;

  if (!xdr_guestfs_message_error (&xdr, &err)) {
    fprintf (stderr, "guestfsd: failed to encode error message body\n");
    exit (EXIT_FAILURE);
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  xdrmem_create (&xdr, lenbuf, 4, XDR_ENCODE);
  xdr_u_int (&xdr, &len);
  xdr_destroy (&xdr);

  if (xwrite (sock, lenbuf, 4) == -1) {
    fprintf (stderr, "xwrite failed\n");
    exit (EXIT_FAILURE);
  }
  if (xwrite (sock, buf, len) == -1) {
    fprintf (stderr, "xwrite failed\n");
    exit (EXIT_FAILURE);
  }
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
    exit (EXIT_FAILURE);
  }

  if (xdrp) {
    /* This can fail if the reply body is too large, for example
     * if it exceeds the maximum message size.  In that case
     * we want to return an error message instead. (RHBZ#509597).
     */
    if (!(*xdrp) (&xdr, ret)) {
      reply_with_error ("guestfsd: failed to encode reply body\n(maybe the reply exceeds the maximum message size in the protocol?)");
      xdr_destroy (&xdr);
      return;
    }
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  xdrmem_create (&xdr, lenbuf, 4, XDR_ENCODE);
  xdr_u_int (&xdr, &len);
  xdr_destroy (&xdr);

  if (xwrite (sock, lenbuf, 4) == -1) {
    fprintf (stderr, "xwrite failed\n");
    exit (EXIT_FAILURE);
  }
  if (xwrite (sock, buf, len) == -1) {
    fprintf (stderr, "xwrite failed\n");
    exit (EXIT_FAILURE);
  }
}

/* Receive file chunks, repeatedly calling 'cb'. */
int
receive_file (receive_cb cb, void *opaque)
{
  guestfs_chunk chunk;
  char lenbuf[4];
  char *buf;
  XDR xdr;
  int r;
  uint32_t len;

  for (;;) {
    if (verbose)
      fprintf (stderr, "receive_file: reading length word\n");

    /* Read the length word. */
    if (xread (sock, lenbuf, 4) == -1)
      exit (EXIT_FAILURE);

    xdrmem_create (&xdr, lenbuf, 4, XDR_DECODE);
    xdr_u_int (&xdr, &len);
    xdr_destroy (&xdr);

    if (len == GUESTFS_CANCEL_FLAG)
      continue;			/* Just ignore it. */

    if (len > GUESTFS_MESSAGE_MAX) {
      fprintf (stderr, "guestfsd: incoming message is too long (%u bytes)\n",
               len);
      exit (EXIT_FAILURE);
    }

    buf = malloc (len);
    if (!buf) {
      perror ("malloc");
      return -1;
    }

    if (xread (sock, buf, len) == -1)
      exit (EXIT_FAILURE);

    xdrmem_create (&xdr, buf, len, XDR_DECODE);
    memset (&chunk, 0, sizeof chunk);
    if (!xdr_guestfs_chunk (&xdr, &chunk)) {
      xdr_destroy (&xdr);
      free (buf);
      return -1;
    }
    xdr_destroy (&xdr);
    free (buf);

    if (verbose)
      fprintf (stderr, "receive_file: got chunk: cancel = %d, len = %d, buf = %p\n",
               chunk.cancel, chunk.data.data_len, chunk.data.data_val);

    if (chunk.cancel) {
      if (verbose)
        fprintf (stderr, "receive_file: received cancellation from library\n");
      xdr_free ((xdrproc_t) xdr_guestfs_chunk, (char *) &chunk);
      return -2;
    }
    if (chunk.data.data_len == 0) {
      if (verbose)
        fprintf (stderr, "receive_file: end of file, leaving function\n");
      xdr_free ((xdrproc_t) xdr_guestfs_chunk, (char *) &chunk);
      return 0;			/* end of file */
    }

    if (cb)
      r = cb (opaque, chunk.data.data_val, chunk.data.data_len);
    else
      r = 0;

    xdr_free ((xdrproc_t) xdr_guestfs_chunk, (char *) &chunk);
    if (r == -1) {		/* write error */
      if (verbose)
        fprintf (stderr, "receive_file: write error\n");
      return -1;
    }
  }
}

/* Send a cancellation flag back to the library. */
int
cancel_receive (void)
{
  XDR xdr;
  char fbuf[4];
  uint32_t flag = GUESTFS_CANCEL_FLAG;

  xdrmem_create (&xdr, fbuf, sizeof fbuf, XDR_ENCODE);
  xdr_u_int (&xdr, &flag);
  xdr_destroy (&xdr);

  if (xwrite (sock, fbuf, sizeof fbuf) == -1) {
    perror ("write to socket");
    return -1;
  }

  /* Keep receiving chunks and discarding, until library sees cancel. */
  return receive_file (NULL, NULL);
}

static int check_for_library_cancellation (void);
static int send_chunk (const guestfs_chunk *);

/* Also check if the library sends us a cancellation message. */
int
send_file_write (const void *buf, int len)
{
  guestfs_chunk chunk;
  int cancel;

  if (len > GUESTFS_MAX_CHUNK_SIZE) {
    fprintf (stderr, "send_file_write: len (%d) > GUESTFS_MAX_CHUNK_SIZE (%d)\n",
             len, GUESTFS_MAX_CHUNK_SIZE);
    return -1;
  }

  cancel = check_for_library_cancellation ();

  if (cancel) {
    chunk.cancel = 1;
    chunk.data.data_len = 0;
    chunk.data.data_val = NULL;
  } else {
    chunk.cancel = 0;
    chunk.data.data_len = len;
    chunk.data.data_val = (char *) buf;
  }

  if (send_chunk (&chunk) == -1)
    return -1;

  if (cancel) return -2;
  return 0;
}

static int
check_for_library_cancellation (void)
{
  fd_set rset;
  struct timeval tv;
  int r;
  char buf[4];
  uint32_t flag;
  XDR xdr;

  FD_ZERO (&rset);
  FD_SET (sock, &rset);
  tv.tv_sec = 0;
  tv.tv_usec = 0;
  r = select (sock+1, &rset, NULL, NULL, &tv);
  if (r == -1) {
    perror ("select");
    return 0;
  }
  if (r == 0)
    return 0;

  /* Read the message from the daemon. */
  r = xread (sock, buf, sizeof buf);
  if (r == -1)
    return 0;

  xdrmem_create (&xdr, buf, sizeof buf, XDR_DECODE);
  xdr_u_int (&xdr, &flag);
  xdr_destroy (&xdr);

  if (flag != GUESTFS_CANCEL_FLAG) {
    fprintf (stderr, "check_for_library_cancellation: read 0x%x from library, expected 0x%x\n",
             flag, GUESTFS_CANCEL_FLAG);
    return 0;
  }

  return 1;
}

int
send_file_end (int cancel)
{
  guestfs_chunk chunk;

  chunk.cancel = cancel;
  chunk.data.data_len = 0;
  chunk.data.data_val = NULL;
  return send_chunk (&chunk);
}

static int
send_chunk (const guestfs_chunk *chunk)
{
  char buf[GUESTFS_MAX_CHUNK_SIZE + 48];
  char lenbuf[4];
  XDR xdr;
  uint32_t len;

  xdrmem_create (&xdr, buf, sizeof buf, XDR_ENCODE);
  if (!xdr_guestfs_chunk (&xdr, (guestfs_chunk *) chunk)) {
    fprintf (stderr, "send_chunk: failed to encode chunk\n");
    xdr_destroy (&xdr);
    return -1;
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  xdrmem_create (&xdr, lenbuf, 4, XDR_ENCODE);
  xdr_u_int (&xdr, &len);
  xdr_destroy (&xdr);

  int err = (xwrite (sock, lenbuf, 4) == 0
             && xwrite (sock, buf, len) == 0 ? 0 : -1);
  if (err) {
    fprintf (stderr, "send_chunk: write failed\n");
    exit (EXIT_FAILURE);
  }

  return err;
}
