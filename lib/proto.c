/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/**
 * This is the code used to send and receive RPC messages and (for
 * certain types of message) to perform file transfers.  This code is
 * driven from the generated actions (F<lib/actions-*.c>).  There
 * are five different cases to consider:
 *
 * =over 4
 *
 * =item 1.
 *
 * A non-daemon function (eg. L<guestfs(3)/guestfs_set_verbose>).
 * There is no RPC involved at all, it's all handled inside the
 * library.
 *
 * =item 2.
 *
 * A simple RPC (eg. L<guestfs(3)/guestfs_mount>).  We write the
 * request, then read the reply.  The sequence of calls is:
 *
 *   guestfs_int_send
 *   guestfs_int_recv
 *
 * =item 3.
 *
 * An RPC with C<FileIn> parameters
 * (eg. L<guestfs(3)/guestfs_upload>).  We write the request, then
 * write the file(s), then read the reply.  The sequence of calls is:
 *
 *   guestfs_int_send
 *   guestfs_int_send_file  (possibly multiple times)
 *   guestfs_int_recv
 *
 * =item 4.
 *
 * An RPC with C<FileOut> parameters
 * (eg. L<guestfs(3)/guestfs_download>).  We write the request, then
 * read the reply, then read the file(s).  The sequence of calls is:
 *
 *   guestfs_int_send
 *   guestfs_int_recv
 *   guestfs_int_recv_file  (possibly multiple times)
 *
 * =item 5.
 *
 * Both C<FileIn> and C<FileOut> parameters.  There are no calls like
 * this in the current API, but they would be implemented as a
 * combination of cases 3 and 4.
 *
 * =back
 *
 * All read/write/etc operations are performed using the current
 * connection module (C<g-E<gt>conn>).  During operations the
 * connection module transparently handles log messages that appear on
 * the console.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <assert.h>
#include <libintl.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "c-ctype.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

/* Size of guestfs_progress message on the wire. */
#define PROGRESS_MESSAGE_SIZE 24

/**
 * This is called if we detect EOF, ie. qemu died.
 */
static void
child_cleanup (guestfs_h *g)
{
  debug (g, "child_cleanup: %p: child process died", g);

  g->backend_ops->shutdown (g, g->backend_data, 0);
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
  }
  memset (&g->launch_t, 0, sizeof g->launch_t);
  guestfs_int_free_drives (g);
  g->state = CONFIG;
  guestfs_int_call_callbacks_void (g, GUESTFS_EVENT_SUBPROCESS_QUIT);
}

/**
 * Convenient wrapper to generate a progress message callback.
 */
void
guestfs_int_progress_message_callback (guestfs_h *g,
				       const guestfs_progress *message)
{
  uint64_t array[4];

  array[0] = message->proc;
  array[1] = message->serial;
  array[2] = message->position;
  array[3] = message->total;

  guestfs_int_call_callbacks_array (g, GUESTFS_EVENT_PROGRESS,
				    array, sizeof array / sizeof array[0]);
}

/**
 * Connection modules call us back here when they get a log message.
 */
void
guestfs_int_log_message_callback (guestfs_h *g, const char *buf, size_t len)
{
  /* Send the log message upwards to anyone who is listening. */
  guestfs_int_call_callbacks_message (g, GUESTFS_EVENT_APPLIANCE, buf, len);

  /* This is used to generate launch progress messages.  See comment
   * above guestfs_int_launch_send_progress.
   */
  if (g->state == LAUNCHING) {
    const char *sentinel;
    size_t slen;

    /* Since 2016-03, if !verbose, then we add the "quiet" flag to the
     * kernel, so the following sentinel will never be produced. XXX
     */
    sentinel = "Linux version"; /* kernel up */
    slen = strlen (sentinel);
    if (memmem (buf, len, sentinel, slen) != NULL)
      guestfs_int_launch_send_progress (g, 6);

    sentinel = "Starting /init script"; /* /init running */
    slen = strlen (sentinel);
    if (memmem (buf, len, sentinel, slen) != NULL)
      guestfs_int_launch_send_progress (g, 9);
  }
}

/**
 * Before writing to the daemon socket, check the read side of the
 * daemon socket for any of these conditions:
 *
 * =over 4
 *
 * =item error
 *
 * return -1
 *
 * =item daemon cancellation message
 *
 * return -2
 *
 * =item progress message
 *
 * handle it here
 *
 * =item end of input or appliance exited unexpectedly
 *
 * return 0
 *
 * =item anything else
 *
 * return 1
 *
 * =back
 */
static ssize_t
check_daemon_socket (guestfs_h *g)
{
  char buf[4];
  ssize_t n;
  uint32_t flag;
  XDR xdr;

  assert (g->conn); /* callers must check this */

 again:
  if (! g->conn->ops->can_read_data (g, g->conn))
    return 1;

  n = g->conn->ops->read_data (g, g->conn, buf, 4);
  if (n <= 0) /* 0 or -1 */
    return n;

  xdrmem_create (&xdr, buf, 4, XDR_DECODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

  /* Read and process progress messages that happen during FileIn. */
  if (flag == GUESTFS_PROGRESS_FLAG) {
    char mbuf[PROGRESS_MESSAGE_SIZE];
    guestfs_progress message;

    n = g->conn->ops->read_data (g, g->conn, mbuf, PROGRESS_MESSAGE_SIZE);
    if (n <= 0) /* 0 or -1 */
      return n;

    xdrmem_create (&xdr, mbuf, PROGRESS_MESSAGE_SIZE, XDR_DECODE);
    xdr_guestfs_progress (&xdr, &message);
    xdr_destroy (&xdr);

    guestfs_int_progress_message_callback (g, &message);

    goto again;
  }

  if (flag != GUESTFS_CANCEL_FLAG) {
    error (g, _("check_daemon_socket: read 0x%x from daemon, expected 0x%x.  Lost protocol synchronization (bad!)\n"),
           flag, GUESTFS_CANCEL_FLAG);
    return -1;
  }

  return -2;
}

int
guestfs_int_send (guestfs_h *g, int proc_nr,
		  uint64_t progress_hint, uint64_t optargs_bitmask,
		  xdrproc_t xdrp, char *args)
{
  struct guestfs_message_header hdr;
  XDR xdr;
  uint32_t len;
  const int serial = g->msg_next_serial++;
  ssize_t r;
  CLEANUP_FREE char *msg_out = NULL;
  size_t msg_out_size;

  if (!g->conn) {
    guestfs_int_unexpected_close_error (g);
    return -1;
  }

  /* We have to allocate this message buffer on the heap because
   * it is quite large (although will be mostly unused).  We
   * can't allocate it on the stack because in some environments
   * we have quite limited stack space available, notably when
   * running in the JVM.
   */
  msg_out = safe_malloc (g, GUESTFS_MESSAGE_MAX + 4);
  xdrmem_create (&xdr, msg_out + 4, GUESTFS_MESSAGE_MAX, XDR_ENCODE);

  /* Serialize the header. */
  hdr.prog = GUESTFS_PROGRAM;
  hdr.vers = GUESTFS_PROTOCOL_VERSION;
  hdr.proc = proc_nr;
  hdr.direction = GUESTFS_DIRECTION_CALL;
  hdr.serial = serial;
  hdr.status = GUESTFS_STATUS_OK;
  hdr.progress_hint = progress_hint;
  hdr.optargs_bitmask = optargs_bitmask;

  if (!xdr_guestfs_message_header (&xdr, &hdr)) {
    error (g, _("xdr_guestfs_message_header failed"));
    return -1;
  }

  /* Serialize the args.  If any, because some message types
   * have no parameters.
   */
  if (xdrp) {
    if (!(*xdrp) (&xdr, args, 0)) {
      error (g, _("dispatch failed to marshal args"));
      return -1;
    }
  }

  /* Get the actual length of the message, resize the buffer to match
   * the actual length, and write the length word at the beginning.
   */
  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  msg_out = safe_realloc (g, msg_out, len + 4);
  msg_out_size = len + 4;

  xdrmem_create (&xdr, msg_out, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);

  /* Look for stray daemon cancellation messages from earlier calls
   * and ignore them.
   */
  r = check_daemon_socket (g);
  /* r == -2 (cancellation) is ignored */
  if (r == -1)
    return -1;
  if (r == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    return -1;
  }

  /* Send the message. */
  r = g->conn->ops->write_data (g, g->conn, msg_out, msg_out_size);
  if (r == -1)
    return -1;
  if (r == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    return -1;
  }

  return serial;
}

static int send_file_chunk (guestfs_h *g, int cancel, const char *buf, size_t len);
static int send_file_data (guestfs_h *g, const char *buf, size_t len);
static int send_file_cancellation (guestfs_h *g);
static int send_file_complete (guestfs_h *g);

/**
 * Send a file.
 *
 * Returns C<0> on success, C<-1> for error, C<-2> if the daemon
 * cancelled (we must read the error message).
 */
int
guestfs_int_send_file (guestfs_h *g, const char *filename)
{
  CLEANUP_FREE char *buf = safe_malloc (g, GUESTFS_MAX_CHUNK_SIZE);
  int fd, r = 0, err;

  g->user_cancel = 0;

  fd = open (filename, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    send_file_cancellation (g);
    return -1;
  }

  guestfs_int_fadvise_sequential (fd);

  /* Send file in chunked encoding. */
  while (!g->user_cancel) {
    r = read (fd, buf, GUESTFS_MAX_CHUNK_SIZE);
    if (r == -1 && (errno == EINTR || errno == EAGAIN))
      continue;
    if (r <= 0) break;
    err = send_file_data (g, buf, r);
    if (err < 0) {
      if (err == -2)		/* daemon sent cancellation */
        send_file_cancellation (g);
      close (fd);
      return err;
    }
  }

  if (r == -1) {
    perrorf (g, "read: %s", filename);
    send_file_cancellation (g);
    close (fd);
    return -1;
  }

  if (g->user_cancel) {
    guestfs_int_error_errno (g, EINTR, _("operation cancelled by user"));
    send_file_cancellation (g);
    close (fd);
    return -1;
  }

  /* End of file, but before we send that, we need to close
   * the file and check for errors.
   */
  if (close (fd) == -1) {
    perrorf (g, "close: %s", filename);
    send_file_cancellation (g);
    return -1;
  }

  err = send_file_complete (g);
  if (err < 0) {
    if (err == -2)              /* daemon sent cancellation */
      send_file_cancellation (g);
    return err;
  }

  return 0;
}

/**
 * Send a chunk of file data.
 */
static int
send_file_data (guestfs_h *g, const char *buf, size_t len)
{
  return send_file_chunk (g, 0, buf, len);
}

/**
 * Send a cancellation message.
 */
static int
send_file_cancellation (guestfs_h *g)
{
  return send_file_chunk (g, 1, NULL, 0);
}

/**
 * Send a file complete chunk.
 */
static int
send_file_complete (guestfs_h *g)
{
  char buf[1] = { '\0' };
  return send_file_chunk (g, 0, buf, 0);
}

static int
send_file_chunk (guestfs_h *g, int cancel, const char *buf, size_t buflen)
{
  uint32_t len;
  ssize_t r;
  guestfs_chunk chunk;
  XDR xdr;
  CLEANUP_FREE char *msg_out = NULL;
  size_t msg_out_size;

  /* Allocate the chunk buffer.  Don't use the stack to avoid
   * excessive stack usage and unnecessary copies.
   */
  msg_out = safe_malloc (g, GUESTFS_MAX_CHUNK_SIZE + 4 + 48);
  xdrmem_create (&xdr, msg_out + 4, GUESTFS_MAX_CHUNK_SIZE + 48, XDR_ENCODE);

  /* Serialize the chunk. */
  chunk.cancel = cancel;
  chunk.data.data_len = buflen;
  chunk.data.data_val = (char *) buf;

  if (!xdr_guestfs_chunk (&xdr, &chunk)) {
    error (g, _("xdr_guestfs_chunk failed (buf = %p, buflen = %zu)"),
           buf, buflen);
    xdr_destroy (&xdr);
    return -1;
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  /* Reduce the size of the outgoing message buffer to the real length. */
  msg_out = safe_realloc (g, msg_out, len + 4);
  msg_out_size = len + 4;

  xdrmem_create (&xdr, msg_out, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);

  /* Did the daemon send a cancellation message? */
  r = check_daemon_socket (g);
  if (r == -2) {
    debug (g, "got daemon cancellation");
    return -2;
  }
  if (r == -1)
    return -1;
  if (r == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    return -1;
  }

  /* Send the chunk. */
  r = g->conn->ops->write_data (g, g->conn, msg_out, msg_out_size);
  if (r == -1)
    return -1;
  if (r == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    return -1;
  }

  return 0;
}

/**
 * This function reads a single message, file chunk, launch flag or
 * cancellation flag from the daemon.  If something was read, it
 * returns C<0>, otherwise C<-1>.
 *
 * Both C<size_rtn> and C<buf_rtn> must be passed by the caller as
 * non-NULL.
 *
 * C<*size_rtn> returns the size of the returned message or it may be
 * C<GUESTFS_LAUNCH_FLAG> or C<GUESTFS_CANCEL_FLAG>.
 *
 * C<*buf_rtn> is returned containing the message (if any) or will be
 * set to C<NULL>.  C<*buf_rtn> must be freed by the caller.
 *
 * This checks for EOF (appliance died) and passes that up through the
 * child_cleanup function above.
 *
 * Log message, progress messages are handled transparently here.
 */
static int
recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn)
{
  char lenbuf[4];
  ssize_t n;
  XDR xdr;
  size_t message_size;

  *size_rtn = 0;
  *buf_rtn = NULL;

  /* RHBZ#914931: Along some (rare) paths, we might have closed the
   * socket connection just before this function is called, so just
   * return an error if this happens.
   */
  if (!g->conn) {
    guestfs_int_unexpected_close_error (g);
    return -1;
  }

  /* Read the 4 byte size / flag. */
  n = g->conn->ops->read_data (g, g->conn, lenbuf, 4);
  if (n == -1)
    return -1;
  if (n == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    return -1;
  }

  xdrmem_create (&xdr, lenbuf, 4, XDR_DECODE);
  xdr_uint32_t (&xdr, size_rtn);
  xdr_destroy (&xdr);

  if (*size_rtn == GUESTFS_LAUNCH_FLAG) {
    if (g->state != LAUNCHING)
      error (g, _("received magic signature from guestfsd, but in state %d"),
             (int) g->state);
    else {
      g->state = READY;
      guestfs_int_call_callbacks_void (g, GUESTFS_EVENT_LAUNCH_DONE);
    }
    debug (g, "recv_from_daemon: received GUESTFS_LAUNCH_FLAG");
    return 0;
  }
  else if (*size_rtn == GUESTFS_CANCEL_FLAG) {
    debug (g, "recv_from_daemon: received GUESTFS_CANCEL_FLAG");
    return 0;
  }
  else if (*size_rtn == GUESTFS_PROGRESS_FLAG)
    /*FALLTHROUGH*/;
  else if (*size_rtn > GUESTFS_MESSAGE_MAX) {
    /* If this happens, it's pretty bad and we've probably lost
     * synchronization.
     */
    error (g, _("message length (%u) > maximum possible size (%d)"),
           (unsigned) *size_rtn, GUESTFS_MESSAGE_MAX);
    return -1;
  }

  /* Calculate the message size. */
  message_size =
    *size_rtn != GUESTFS_PROGRESS_FLAG ? *size_rtn : PROGRESS_MESSAGE_SIZE;

  /* Allocate the complete buffer, size now known. */
  *buf_rtn = safe_malloc (g, message_size);

  /* Read the message. */
  n = g->conn->ops->read_data (g, g->conn, *buf_rtn, message_size);
  if (n == -1) {
    free (*buf_rtn);
    *buf_rtn = NULL;
    return -1;
  }
  if (n == 0) {
    guestfs_int_unexpected_close_error (g);
    child_cleanup (g);
    free (*buf_rtn);
    *buf_rtn = NULL;
    return -1;
  }

  /* ... it's a normal message (not progress/launch/cancel) so display
   * it if we're debugging.
   */
#ifdef ENABLE_PACKET_DUMP
  if (g->verbose)
    guestfs_int_hexdump (buf_rtn, n, stdout);
#endif

  return 0;
}

int
guestfs_int_recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn)
{
  int r;

 again:
  r = recv_from_daemon (g, size_rtn, buf_rtn);
  if (r == -1)
    return -1;

  if (*size_rtn == GUESTFS_PROGRESS_FLAG) {
    guestfs_progress message;
    XDR xdr;

    xdrmem_create (&xdr, *buf_rtn, PROGRESS_MESSAGE_SIZE, XDR_DECODE);
    xdr_guestfs_progress (&xdr, &message);
    xdr_destroy (&xdr);

    guestfs_int_progress_message_callback (g, &message);

    free (*buf_rtn);
    *buf_rtn = NULL;

    /* Process next message. */
    goto again;
  }

  if (*size_rtn == GUESTFS_LAUNCH_FLAG || *size_rtn == GUESTFS_CANCEL_FLAG)
    return 0;

  /* Got the full message, caller can start processing it. */
  assert (*buf_rtn != NULL);

  return 0;
}

/**
 * Receive a reply.
 */
int
guestfs_int_recv (guestfs_h *g, const char *fn,
		  guestfs_message_header *hdr,
		  guestfs_message_error *err,
		  xdrproc_t xdrp, char *ret)
{
  XDR xdr;
  CLEANUP_FREE void *buf = NULL;
  uint32_t size;
  int r;

 again:
  r = guestfs_int_recv_from_daemon (g, &size, &buf);
  if (r == -1)
    return -1;

  /* This can happen if a cancellation happens right at the end
   * of us sending a FileIn parameter to the daemon.  Discard.  The
   * daemon should send us an error message next.
   */
  if (size == GUESTFS_CANCEL_FLAG)
    goto again;

  if (size == GUESTFS_LAUNCH_FLAG) {
    error (g, "%s: received unexpected launch flag from daemon when expecting reply", fn);
    return -1;
  }

  xdrmem_create (&xdr, buf, size, XDR_DECODE);

  if (!xdr_guestfs_message_header (&xdr, hdr)) {
    error (g, "%s: failed to parse reply header", fn);
    xdr_destroy (&xdr);
    return -1;
  }
  if (hdr->status == GUESTFS_STATUS_ERROR) {
    if (!xdr_guestfs_message_error (&xdr, err)) {
      error (g, "%s: failed to parse reply error", fn);
      xdr_destroy (&xdr);
      return -1;
    }
  } else {
    if (xdrp && ret && !xdrp (&xdr, ret, 0)) {
      error (g, "%s: failed to parse reply", fn);
      xdr_destroy (&xdr);
      return -1;
    }
  }
  xdr_destroy (&xdr);

  return 0;
}

/**
 * Same as C<guestfs_int_recv>, but it discards the reply message.
 *
 * Notes (XXX):
 *
 * =over 4
 *
 * =item *
 *
 * This returns an int, but all current callers ignore it.
 *
 * =item *
 *
 * The error string may end up being set twice on error paths.
 *
 * =back
 */
int
guestfs_int_recv_discard (guestfs_h *g, const char *fn)
{
  CLEANUP_FREE void *buf = NULL;
  uint32_t size;
  int r;

 again:
  r = guestfs_int_recv_from_daemon (g, &size, &buf);
  if (r == -1)
    return -1;

  /* This can happen if a cancellation happens right at the end
   * of us sending a FileIn parameter to the daemon.  Discard.  The
   * daemon should send us an error message next.
   */
  if (size == GUESTFS_CANCEL_FLAG)
    goto again;

  if (size == GUESTFS_LAUNCH_FLAG) {
    error (g, "%s: received unexpected launch flag from daemon when expecting reply", fn);
    return -1;
  }

  return 0;
}

/* Receive a file. */

static int
xwrite (int fd, const void *v_buf, size_t len)
{
  const char *buf = v_buf;
  int r;

  while (len > 0) {
    r = write (fd, buf, len);
    if (r == -1)
      return -1;

    buf += r;
    len -= r;
  }

  return 0;
}

static ssize_t receive_file_data (guestfs_h *g, void **buf);

/**
 * Returns C<-1> = error, C<0> = EOF, C<E<gt>0> = more data
 */
int
guestfs_int_recv_file (guestfs_h *g, const char *filename)
{
  void *buf;
  int fd, r;

  g->user_cancel = 0;

  /* If downloading to /dev/stdout or /dev/stderr, dup the file
   * descriptor instead of reopening the file, so that redirected
   * stdout/stderr work properly.
   */
  if (STREQ (filename, "/dev/stdout"))
    fd = dup (1);
  else if (STREQ (filename, "/dev/stderr"))
    fd = dup (2);
  else
    fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    perrorf (g, "%s", filename);
    goto cancel;
  }

  guestfs_int_fadvise_sequential (fd);

  /* Receive the file in chunked encoding. */
  while ((r = receive_file_data (g, &buf)) > 0) {
    if (xwrite (fd, buf, r) == -1) {
      perrorf (g, "%s: write", filename);
      free (buf);
      close (fd);
      goto cancel;
    }
    free (buf);

    if (g->user_cancel) {
      close (fd);
      goto cancel;
    }
  }

  if (r == -1) {
    close (fd);
    return -1;
  }

  if (close (fd) == -1) {
    perrorf (g, "close: %s", filename);
    return -1;
  }

  return 0;

 cancel: ;
  /* Send cancellation message to daemon, then wait until it
   * cancels (just throwing away data).
   */
  XDR xdr;
  char fbuf[4];
  uint32_t flag = GUESTFS_CANCEL_FLAG;

  debug (g, "%s: waiting for daemon to acknowledge cancellation",
         __func__);

  xdrmem_create (&xdr, fbuf, sizeof fbuf, XDR_ENCODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

  if (g->conn->ops->write_data (g, g->conn, fbuf, sizeof fbuf) == -1) {
    perrorf (g, _("write to daemon socket"));
    return -1;
  }

  while (receive_file_data (g, NULL) > 0)
    ;                           /* just discard it */

  return -1;
}

/**
 * Receive a chunk of file data.
 *
 * Returns C<-1> = error, C<0> = EOF, C<E<gt>0> = more data
 */
static ssize_t
receive_file_data (guestfs_h *g, void **buf_r)
{
  int r;
  CLEANUP_FREE void *buf = NULL;
  uint32_t len;
  XDR xdr;
  guestfs_chunk chunk;

  r = guestfs_int_recv_from_daemon (g, &len, &buf);
  if (r == -1)
    return -1;

  if (len == GUESTFS_LAUNCH_FLAG || len == GUESTFS_CANCEL_FLAG) {
    error (g, _("receive_file_data: unexpected flag received when reading file chunks"));
    return -1;
  }

  memset (&chunk, 0, sizeof chunk);

  xdrmem_create (&xdr, buf, len, XDR_DECODE);
  if (!xdr_guestfs_chunk (&xdr, &chunk)) {
    error (g, _("failed to parse file chunk"));
    return -1;
  }
  xdr_destroy (&xdr);

  if (chunk.cancel) {
    if (g->user_cancel)
      guestfs_int_error_errno (g, EINTR, _("operation cancelled by user"));
    else
      error (g, _("file receive cancelled by daemon"));
    free (chunk.data.data_val);
    return -1;
  }

  if (chunk.data.data_len == 0) { /* end of transfer */
    free (chunk.data.data_val);
    return 0;
  }

  if (buf_r) *buf_r = chunk.data.data_val;
  else free (chunk.data.data_val); /* else caller frees */

  return chunk.data.data_len;
}

int
guestfs_user_cancel (guestfs_h *g)
{
  g->user_cancel = 1;
  return 0;
}
