/* libguestfs
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#include <config.h>

#define _BSD_SOURCE /* for mkdtemp, usleep */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <dirent.h>
#include <signal.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#ifdef HAVE_ERRNO_H
#include <errno.h>
#endif

#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif

#ifdef HAVE_SYS_WAIT_H
#include <sys/wait.h>
#endif

#ifdef HAVE_SYS_SOCKET_H
#include <sys/socket.h>
#endif

#ifdef HAVE_SYS_UN_H
#include <sys/un.h>
#endif

#include <arpa/inet.h>
#include <netinet/in.h>

#include "c-ctype.h"
#include "glthread/lock.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Size of guestfs_progress message on the wire. */
#define PROGRESS_MESSAGE_SIZE 24

/* This is the code used to send and receive RPC messages and (for
 * certain types of message) to perform file transfers.  This code is
 * driven from the generated actions (src/actions.c).  There
 * are five different cases to consider:
 *
 * (1) A non-daemon function.  There is no RPC involved at all, it's
 * all handled inside the library.
 *
 * (2) A simple RPC (eg. "mount").  We write the request, then read
 * the reply.  The sequence of calls is:
 *
 *   guestfs___set_busy
 *   guestfs___send
 *   guestfs___recv
 *   guestfs___end_busy
 *
 * (3) An RPC with FileOut parameters (eg. "upload").  We write the
 * request, then write the file(s), then read the reply.  The sequence
 * of calls is:
 *
 *   guestfs___set_busy
 *   guestfs___send
 *   guestfs___send_file  (possibly multiple times)
 *   guestfs___recv
 *   guestfs___end_busy
 *
 * (4) An RPC with FileIn parameters (eg. "download").  We write the
 * request, then read the reply, then read the file(s).  The sequence
 * of calls is:
 *
 *   guestfs___set_busy
 *   guestfs___send
 *   guestfs___recv
 *   guestfs___recv_file  (possibly multiple times)
 *   guestfs___end_busy
 *
 * (5) Both FileOut and FileIn parameters.  There are no calls like
 * this in the current API, but they would be implemented as a
 * combination of cases (3) and (4).
 *
 * During all writes and reads, we also select(2) on qemu stdout
 * looking for messages (guestfsd stderr and guest kernel dmesg), and
 * anything received is passed up through the log_message_cb.  This is
 * also the reason why all the sockets are non-blocking.  We also have
 * to check for EOF (qemu died).  All of this is handled by the
 * functions send_to_daemon and recv_from_daemon.
 */

/* This is only used on the debug path, to generate a one-line
 * printable summary of a protocol message.  'workspace' is scratch
 * space used to format the message, and it must be at least
 * MAX_MESSAGE_SUMMARY bytes in size.
 */
#define MAX_MESSAGE_SUMMARY 200 /* >= 5 * (4 * 3 + 2) + a few bytes overhead */

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

static const char *
message_summary (const void *buf, size_t n, char *workspace)
{
  const unsigned char *cbuf = buf;
  size_t i = 0;
  char *p = workspace;
  int truncate = 0;

  /* Print only up to 5 x 32 bits of the message.  That is enough to
   * cover the message length, and the first four fields of the
   * message header (prog, vers, proc, direction).
   */
  if (n > 5 * 4) {
    n = 5 * 4;
    truncate = 1;
  }

  while (n > 0) {
    sprintf (p, "%02x ", cbuf[i]);
    p += 3;
    n--;
    i++;

    if ((i & 3) == 0) {
      strcpy (p, "| ");
      p += 2;
    }
  }

  if (truncate)
    strcpy (p, "...");

  return workspace;
}

int
guestfs___set_busy (guestfs_h *g)
{
  if (g->state != READY) {
    error (g, _("guestfs_set_busy: called when in state %d != READY"),
           g->state);
    return -1;
  }
  g->state = BUSY;
  return 0;
}

int
guestfs___end_busy (guestfs_h *g)
{
  switch (g->state)
    {
    case BUSY:
      g->state = READY;
      break;
    case CONFIG:
    case READY:
      break;

    case LAUNCHING:
    case NO_HANDLE:
    default:
      error (g, _("guestfs_end_busy: called when in state %d"), g->state);
      return -1;
    }
  return 0;
}

/* This is called if we detect EOF, ie. qemu died. */
static void
child_cleanup (guestfs_h *g)
{
  debug (g, "child_cleanup: %p: child process died", g);

  /*if (g->pid > 0) kill (g->pid, SIGTERM);*/
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);
  if (g->fd[0] >= 0) close (g->fd[0]);
  if (g->fd[1] >= 0) close (g->fd[1]);
  close (g->sock);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;
  g->pid = 0;
  g->recoverypid = 0;
  memset (&g->launch_t, 0, sizeof g->launch_t);
  g->state = CONFIG;
  guestfs___call_callbacks_void (g, GUESTFS_EVENT_SUBPROCESS_QUIT);
}

static int
read_log_message_or_eof (guestfs_h *g, int fd, int error_if_eof)
{
  char buf[BUFSIZ];
  int n;

#if 0
  debug (g, "read_log_message_or_eof: %p g->state = %d, fd = %d",
         g, g->state, fd);
#endif

  /* QEMU's console emulates a 16550A serial port.  The real 16550A
   * device has a small FIFO buffer (16 bytes) which means here we see
   * lots of small reads of 1-16 bytes in length, usually single
   * bytes.  Sleeping here for a very brief period groups reads
   * together (so we usually get a few lines of output at once) and
   * improves overall throughput, as well as making the event
   * interface a bit more sane for callers.  With a virtio-serial
   * based console (not yet implemented) we may be able to remove
   * this.  XXX
   */
  usleep (1000);

  n = read (fd, buf, sizeof buf);
  if (n == 0) {
    /* Hopefully this indicates the qemu child process has died. */
    child_cleanup (g);

    if (error_if_eof) {
      /* We weren't expecting eof here (called from launch) so place
       * something in the error buffer.  RHBZ#588851.
       */
      error (g, "child process died unexpectedly");
    }
    return -1;
  }

  if (n == -1) {
    if (errno == EINTR || errno == EAGAIN)
      return 0;

    perrorf (g, "read");
    return -1;
  }

  /* It's an actual log message, send it upwards if anyone is listening. */
  guestfs___call_callbacks_message (g, GUESTFS_EVENT_APPLIANCE, buf, n);

  /* This is a gross hack.  See the comment above
   * guestfs___launch_send_progress.
   */
  if (g->state == LAUNCHING) {
    const char *sentinel;
    size_t len;

    sentinel = "Linux version"; /* kernel up */
    len = strlen (sentinel);
    if (memmem (buf, n, sentinel, len) != NULL)
      guestfs___launch_send_progress (g, 6);

    sentinel = "Starting /init script"; /* /init running */
    len = strlen (sentinel);
    if (memmem (buf, n, sentinel, len) != NULL)
      guestfs___launch_send_progress (g, 9);
  }

  return 0;
}

/* Read 'n' bytes, setting the socket to blocking temporarily so
 * that we really read the number of bytes requested.
 * Returns:  0 == EOF while reading
 *          -1 == error, error() function has been called
 *           n == read 'n' bytes in full
 */
static ssize_t
really_read_from_socket (guestfs_h *g, int sock, char *buf, size_t n)
{
  long flags;
  ssize_t r;
  size_t got;

  /* Set socket to blocking. */
  flags = fcntl (sock, F_GETFL);
  if (flags == -1) {
    perrorf (g, "fcntl");
    return -1;
  }
  if (fcntl (sock, F_SETFL, flags & ~O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    return -1;
  }

  got = 0;
  while (got < n) {
    r = read (sock, &buf[got], n-got);
    if (r == -1) {
      perrorf (g, "read");
      return -1;
    }
    if (r == 0)
      return 0; /* EOF */
    got += r;
  }

  /* Restore original socket flags. */
  if (fcntl (sock, F_SETFL, flags) == -1) {
    perrorf (g, "fcntl");
    return -1;
  }

  return (ssize_t) got;
}

/* Convenient wrapper to generate a progress message callback. */
void
guestfs___progress_message_callback (guestfs_h *g,
                                     const guestfs_progress *message)
{
  uint64_t array[4];

  array[0] = message->proc;
  array[1] = message->serial;
  array[2] = message->position;
  array[3] = message->total;

  guestfs___call_callbacks_array (g, GUESTFS_EVENT_PROGRESS,
                                  array, sizeof array / sizeof array[0]);
}

static int
check_for_daemon_cancellation_or_eof (guestfs_h *g, int fd)
{
  char summary[MAX_MESSAGE_SUMMARY];
  char buf[4];
  ssize_t n;
  uint32_t flag;
  XDR xdr;

  n = really_read_from_socket (g, fd, buf, 4);
  if (n == -1)
    return -1;
  if (n == 0) {
    /* Hopefully this indicates the qemu child process has died. */
    child_cleanup (g);
    return -1;
  }

  debug (g, "check_for_daemon_cancellation_or_eof: %s",
         message_summary (buf, 4, summary));

  xdrmem_create (&xdr, buf, 4, XDR_DECODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

  /* Read and process progress messages that happen during FileIn. */
  if (flag == GUESTFS_PROGRESS_FLAG) {
    char buf[PROGRESS_MESSAGE_SIZE];

    n = really_read_from_socket (g, fd, buf, PROGRESS_MESSAGE_SIZE);
    if (n == -1)
      return -1;
    if (n == 0) {
      child_cleanup (g);
      return -1;
    }

    if (g->state == BUSY) {
      guestfs_progress message;

      xdrmem_create (&xdr, buf, PROGRESS_MESSAGE_SIZE, XDR_DECODE);
      xdr_guestfs_progress (&xdr, &message);
      xdr_destroy (&xdr);

      guestfs___progress_message_callback (g, &message);
    }

    return 0;
  }

  if (flag != GUESTFS_CANCEL_FLAG) {
    error (g, _("check_for_daemon_cancellation_or_eof: read 0x%x from daemon, expected 0x%x\n"),
           flag, GUESTFS_CANCEL_FLAG);
    return -1;
  }

  return -2;
}

/* This writes the whole N bytes of BUF to the daemon socket.
 *
 * If the whole write is successful, it returns 0.
 * If there was an error, it returns -1.
 * If the daemon sent a cancellation message, it returns -2.
 *
 * It also checks qemu stdout for log messages and passes those up
 * through log_message_cb.
 *
 * It also checks for EOF (qemu died) and passes that up through the
 * child_cleanup function above.
 */
int
guestfs___send_to_daemon (guestfs_h *g, const void *v_buf, size_t n)
{
  const char *buf = v_buf;
  fd_set rset, rset2;
  fd_set wset, wset2;
  char summary[MAX_MESSAGE_SUMMARY];

  debug (g, "send_to_daemon: %zu bytes: %s", n,
         message_summary (v_buf, n, summary));

  FD_ZERO (&rset);
  FD_ZERO (&wset);

  if (g->fd[1] >= 0)            /* Read qemu stdout for log messages & EOF. */
    FD_SET (g->fd[1], &rset);
  FD_SET (g->sock, &rset);      /* Read socket for cancellation & EOF. */
  FD_SET (g->sock, &wset);      /* Write to socket to send the data. */

  int max_fd = MAX (g->sock, g->fd[1]);

  while (n > 0) {
    rset2 = rset;
    wset2 = wset;
    int r = select (max_fd+1, &rset2, &wset2, NULL, NULL);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
        continue;
      perrorf (g, "select");
      return -1;
    }

    if (g->fd[1] >= 0 && FD_ISSET (g->fd[1], &rset2)) {
      if (read_log_message_or_eof (g, g->fd[1], 0) == -1)
        return -1;
    }
    if (FD_ISSET (g->sock, &rset2)) {
      r = check_for_daemon_cancellation_or_eof (g, g->sock);
      if (r == -1)
	return r;
      if (r == -2) {
	/* Daemon sent cancel message.  But to maintain
	 * synchronization we must write out the remainder of the
	 * write buffer before we return (RHBZ#576879).
	 */
	if (xwrite (g->sock, buf, n) == -1) {
	  perrorf (g, "write");
	  return -1;
	}
	return -2; /* cancelled */
      }
    }
    if (FD_ISSET (g->sock, &wset2)) {
      r = write (g->sock, buf, n);
      if (r == -1) {
        if (errno == EINTR || errno == EAGAIN)
          continue;
        perrorf (g, "write");
        if (errno == EPIPE) /* Disconnected from guest (RHBZ#508713). */
          child_cleanup (g);
        return -1;
      }
      buf += r;
      n -= r;
    }
  }

  return 0;
}

/* This reads a single message, file chunk, launch flag or
 * cancellation flag from the daemon.  If something was read, it
 * returns 0, otherwise -1.
 *
 * Both size_rtn and buf_rtn must be passed by the caller as non-NULL.
 *
 * *size_rtn returns the size of the returned message or it may be
 * GUESTFS_LAUNCH_FLAG or GUESTFS_CANCEL_FLAG.
 *
 * *buf_rtn is returned containing the message (if any) or will be set
 * to NULL.  *buf_rtn must be freed by the caller.
 *
 * It also checks qemu stdout for log messages and passes those up
 * through log_message_cb.
 *
 * It also checks for EOF (qemu died) and passes that up through the
 * child_cleanup function above.
 *
 * Progress notifications are handled transparently by this function.
 * If the callback exists, it is called.  The caller of this function
 * will not see GUESTFS_PROGRESS_FLAG.
 */

static inline void
unexpected_end_of_file_from_daemon_error (guestfs_h *g)
{
#define UNEXPEOF_ERROR "unexpected end of file when reading from daemon.\n"
#define UNEXPEOF_TEST_TOOL \
  "Or you can run 'libguestfs-test-tool' and post the complete output into\n" \
  "a bug report or message to the libguestfs mailing list."
  if (!g->verbose)
    error (g, _(UNEXPEOF_ERROR
"This usually means the libguestfs appliance failed to start up.  Please\n"
"enable debugging (LIBGUESTFS_DEBUG=1) and rerun the command, then look at\n"
"the debug messages output prior to this error.\n"
UNEXPEOF_TEST_TOOL));
  else
    error (g, _(UNEXPEOF_ERROR
"See earlier debug messages.\n"
UNEXPEOF_TEST_TOOL));
}

int
guestfs___recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn)
{
  char summary[MAX_MESSAGE_SUMMARY];
  fd_set rset, rset2;

  FD_ZERO (&rset);

  if (g->fd[1] >= 0)            /* Read qemu stdout for log messages & EOF. */
    FD_SET (g->fd[1], &rset);
  FD_SET (g->sock, &rset);      /* Read socket for data & EOF. */

  int max_fd = MAX (g->sock, g->fd[1]);

  *size_rtn = 0;
  *buf_rtn = NULL;

  char lenbuf[4];
  /* nr is the size of the message, but we prime it as -4 because we
   * have to read the message length word first.
   */
  ssize_t nr = -4;

  for (;;) {
    ssize_t message_size =
      *size_rtn != GUESTFS_PROGRESS_FLAG ?
      *size_rtn : PROGRESS_MESSAGE_SIZE;
    if (nr >= message_size)
      break;

    rset2 = rset;
    int r = select (max_fd+1, &rset2, NULL, NULL, NULL);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
        continue;
      perrorf (g, "select");
      free (*buf_rtn);
      *buf_rtn = NULL;
      return -1;
    }

    if (g->fd[1] >= 0 && FD_ISSET (g->fd[1], &rset2)) {
      if (read_log_message_or_eof (g, g->fd[1], 0) == -1) {
        free (*buf_rtn);
        *buf_rtn = NULL;
        return -1;
      }
    }
    if (FD_ISSET (g->sock, &rset2)) {
      if (nr < 0) {    /* Have we read the message length word yet? */
        r = read (g->sock, lenbuf+nr+4, -nr);
        if (r == -1) {
          if (errno == EINTR || errno == EAGAIN)
            continue;
          int err = errno;
          perrorf (g, "read");
          /* Under some circumstances we see "Connection reset by peer"
           * here when the child dies suddenly.  Catch this and call
           * the cleanup function, same as for EOF.
           */
          if (err == ECONNRESET)
            child_cleanup (g);
          return -1;
        }
        if (r == 0) {
          unexpected_end_of_file_from_daemon_error (g);
          child_cleanup (g);
          return -1;
        }
        nr += r;

        if (nr < 0)         /* Still not got the whole length word. */
          continue;

        XDR xdr;
        xdrmem_create (&xdr, lenbuf, 4, XDR_DECODE);
        xdr_uint32_t (&xdr, size_rtn);
        xdr_destroy (&xdr);

        /* *size_rtn changed, recalculate message_size */
        message_size =
          *size_rtn != GUESTFS_PROGRESS_FLAG ?
          *size_rtn : PROGRESS_MESSAGE_SIZE;

        if (*size_rtn == GUESTFS_LAUNCH_FLAG) {
          if (g->state != LAUNCHING)
            error (g, _("received magic signature from guestfsd, but in state %d"),
                   g->state);
          else {
            g->state = READY;
            guestfs___call_callbacks_void (g, GUESTFS_EVENT_LAUNCH_DONE);
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
        /* If this happens, it's pretty bad and we've probably lost
         * synchronization.
         */
        else if (*size_rtn > GUESTFS_MESSAGE_MAX) {
          error (g, _("message length (%u) > maximum possible size (%d)"),
                 (unsigned) *size_rtn, GUESTFS_MESSAGE_MAX);
          return -1;
        }

        /* Allocate the complete buffer, size now known. */
        *buf_rtn = safe_malloc (g, message_size);
        /*FALLTHROUGH*/
      }

      size_t sizetoread = message_size - nr;
      if (sizetoread > BUFSIZ) sizetoread = BUFSIZ;

      r = read (g->sock, (char *) (*buf_rtn) + nr, sizetoread);
      if (r == -1) {
        if (errno == EINTR || errno == EAGAIN)
          continue;
        perrorf (g, "read");
        free (*buf_rtn);
        *buf_rtn = NULL;
        return -1;
      }
      if (r == 0) {
        unexpected_end_of_file_from_daemon_error (g);
        child_cleanup (g);
        free (*buf_rtn);
        *buf_rtn = NULL;
        return -1;
      }
      nr += r;
    }
  }

  /* Got the full message, caller can start processing it. */
#ifdef ENABLE_PACKET_DUMP
  if (g->verbose) {
    ssize_t i, j;

    for (i = 0; i < nr; i += 16) {
      printf ("%04zx: ", i);
      for (j = i; j < MIN (i+16, nr); ++j)
        printf ("%02x ", (*(unsigned char **)buf_rtn)[j]);
      for (; j < i+16; ++j)
        printf ("   ");
      printf ("|");
      for (j = i; j < MIN (i+16, nr); ++j)
        if (c_isprint ((*(char **)buf_rtn)[j]))
          printf ("%c", (*(char **)buf_rtn)[j]);
        else
          printf (".");
      for (; j < i+16; ++j)
        printf (" ");
      printf ("|\n");
    }
  }
#endif

  if (*size_rtn == GUESTFS_PROGRESS_FLAG) {
    if (g->state == BUSY) {
      guestfs_progress message;
      XDR xdr;
      xdrmem_create (&xdr, *buf_rtn, PROGRESS_MESSAGE_SIZE, XDR_DECODE);
      xdr_guestfs_progress (&xdr, &message);
      xdr_destroy (&xdr);

      guestfs___progress_message_callback (g, &message);
    }

    free (*buf_rtn);
    *buf_rtn = NULL;

    /* Process next message. */
    return guestfs___recv_from_daemon (g, size_rtn, buf_rtn);
  }

  debug (g, "recv_from_daemon: %" PRIu32 " bytes: %s", *size_rtn,
         message_summary (*buf_rtn, *size_rtn, summary));

  return 0;
}

/* This is very much like recv_from_daemon above, but g->sock is
 * a listening socket and we are accepting a new connection on
 * that socket instead of reading anything.  Returns the newly
 * accepted socket.
 */
int
guestfs___accept_from_daemon (guestfs_h *g)
{
  fd_set rset, rset2;

  debug (g, "accept_from_daemon: %p g->state = %d", g, g->state);

  FD_ZERO (&rset);

  if (g->fd[1] >= 0)            /* Read qemu stdout for log messages & EOF. */
    FD_SET (g->fd[1], &rset);
  FD_SET (g->sock, &rset);      /* Read socket for accept. */

  int max_fd = MAX (g->sock, g->fd[1]);
  int sock = -1;

  while (sock == -1) {
    /* If the qemu process has died, clean up the zombie (RHBZ#579155).
     * By partially polling in the select below we ensure that this
     * function will be called eventually.
     */
    waitpid (g->pid, NULL, WNOHANG);

    rset2 = rset;

    struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
    int r = select (max_fd+1, &rset2, NULL, NULL, &tv);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
        continue;
      perrorf (g, "select");
      return -1;
    }

    if (g->fd[1] >= 0 && FD_ISSET (g->fd[1], &rset2)) {
      if (read_log_message_or_eof (g, g->fd[1], 1) == -1)
        return -1;
    }
    if (FD_ISSET (g->sock, &rset2)) {
      sock = accept (g->sock, NULL, NULL);
      if (sock == -1) {
        if (errno == EINTR || errno == EAGAIN)
          continue;
        perrorf (g, "accept");
        return -1;
      }
    }
  }

  return sock;
}

int
guestfs___send (guestfs_h *g, int proc_nr,
                uint64_t progress_hint, uint64_t optargs_bitmask,
                xdrproc_t xdrp, char *args)
{
  struct guestfs_message_header hdr;
  XDR xdr;
  u_int32_t len;
  int serial = g->msg_next_serial++;
  int r;
  char *msg_out;
  size_t msg_out_size;

  if (g->state != BUSY) {
    error (g, _("guestfs___send: state %d != BUSY"), g->state);
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
    goto cleanup1;
  }

  /* Serialize the args.  If any, because some message types
   * have no parameters.
   */
  if (xdrp) {
    if (!(*xdrp) (&xdr, args)) {
      error (g, _("dispatch failed to marshal args"));
      goto cleanup1;
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

 again:
  r = guestfs___send_to_daemon (g, msg_out, msg_out_size);
  if (r == -2)                  /* Ignore stray daemon cancellations. */
    goto again;
  if (r == -1)
    goto cleanup1;
  free (msg_out);

  return serial;

 cleanup1:
  free (msg_out);
  return -1;
}

static int send_file_chunk (guestfs_h *g, int cancel, const char *buf, size_t len);
static int send_file_data (guestfs_h *g, const char *buf, size_t len);
static int send_file_cancellation (guestfs_h *g);
static int send_file_complete (guestfs_h *g);

/* Send a file.
 * Returns:
 *   0 OK
 *   -1 error
 *   -2 daemon cancelled (we must read the error message)
 */
int
guestfs___send_file (guestfs_h *g, const char *filename)
{
  char buf[GUESTFS_MAX_CHUNK_SIZE];
  int fd, r = 0, err;

  g->user_cancel = 0;

  fd = open (filename, O_RDONLY);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    send_file_cancellation (g);
    return -1;
  }

  /* Send file in chunked encoding. */
  while (!g->user_cancel) {
    r = read (fd, buf, sizeof buf);
    if (r == -1 && (errno == EINTR || errno == EAGAIN))
      continue;
    if (r <= 0) break;
    err = send_file_data (g, buf, r);
    if (err < 0) {
      if (err == -2)		/* daemon sent cancellation */
        send_file_cancellation (g);
      return err;
    }
  }

  if (r == -1) {
    perrorf (g, "read: %s", filename);
    send_file_cancellation (g);
    return -1;
  }

  if (g->user_cancel) {
    error (g, _("operation cancelled by user"));
    g->last_errnum = EINTR;
    send_file_cancellation (g);
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

  return send_file_complete (g);
}

/* Send a chunk of file data. */
static int
send_file_data (guestfs_h *g, const char *buf, size_t len)
{
  return send_file_chunk (g, 0, buf, len);
}

/* Send a cancellation message. */
static int
send_file_cancellation (guestfs_h *g)
{
  return send_file_chunk (g, 1, NULL, 0);
}

/* Send a file complete chunk. */
static int
send_file_complete (guestfs_h *g)
{
  char buf[1];
  return send_file_chunk (g, 0, buf, 0);
}

static int
send_file_chunk (guestfs_h *g, int cancel, const char *buf, size_t buflen)
{
  u_int32_t len;
  int r;
  guestfs_chunk chunk;
  XDR xdr;
  char *msg_out;
  size_t msg_out_size;

  if (g->state != BUSY) {
    error (g, _("send_file_chunk: state %d != READY"), g->state);
    return -1;
  }

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
    goto cleanup1;
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  /* Reduce the size of the outgoing message buffer to the real length. */
  msg_out = safe_realloc (g, msg_out, len + 4);
  msg_out_size = len + 4;

  xdrmem_create (&xdr, msg_out, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);

  r = guestfs___send_to_daemon (g, msg_out, msg_out_size);

  /* Did the daemon send a cancellation message? */
  if (r == -2) {
    debug (g, "got daemon cancellation");
    return -2;
  }

  if (r == -1)
    goto cleanup1;

  free (msg_out);

  return 0;

 cleanup1:
  free (msg_out);
  return -1;
}

/* Receive a reply. */
int
guestfs___recv (guestfs_h *g, const char *fn,
                guestfs_message_header *hdr,
                guestfs_message_error *err,
                xdrproc_t xdrp, char *ret)
{
  XDR xdr;
  void *buf;
  uint32_t size;
  int r;

 again:
  r = guestfs___recv_from_daemon (g, &size, &buf);
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
    free (buf);
    return -1;
  }
  if (hdr->status == GUESTFS_STATUS_ERROR) {
    if (!xdr_guestfs_message_error (&xdr, err)) {
      error (g, "%s: failed to parse reply error", fn);
      xdr_destroy (&xdr);
      free (buf);
      return -1;
    }
  } else {
    if (xdrp && ret && !xdrp (&xdr, ret)) {
      error (g, "%s: failed to parse reply", fn);
      xdr_destroy (&xdr);
      free (buf);
      return -1;
    }
  }
  xdr_destroy (&xdr);
  free (buf);

  return 0;
}

/* Same as guestfs___recv, but it discards the reply message. */
int
guestfs___recv_discard (guestfs_h *g, const char *fn)
{
  void *buf;
  uint32_t size;
  int r;

 again:
  r = guestfs___recv_from_daemon (g, &size, &buf);
  free (buf);
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

/* Returns -1 = error, 0 = EOF, > 0 = more data */
static ssize_t receive_file_data (guestfs_h *g, void **buf);

int
guestfs___recv_file (guestfs_h *g, const char *filename)
{
  void *buf;
  int fd, r;

  g->user_cancel = 0;

  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    goto cancel;
  }

  /* Receive the file in chunked encoding. */
  while ((r = receive_file_data (g, &buf)) > 0) {
    if (xwrite (fd, buf, r) == -1) {
      perrorf (g, "%s: write", filename);
      free (buf);
      goto cancel;
    }
    free (buf);

    if (g->user_cancel)
      goto cancel;
  }

  if (r == -1) {
    error (g, _("%s: error in chunked encoding"), filename);
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

  if (xwrite (g->sock, fbuf, sizeof fbuf) == -1) {
    perrorf (g, _("write to daemon socket"));
    return -1;
  }

  while (receive_file_data (g, NULL) > 0)
    ;                           /* just discard it */

  return -1;
}

/* Receive a chunk of file data. */
/* Returns -1 = error, 0 = EOF, > 0 = more data */
static ssize_t
receive_file_data (guestfs_h *g, void **buf_r)
{
  int r;
  void *buf;
  uint32_t len;
  XDR xdr;
  guestfs_chunk chunk;

  r = guestfs___recv_from_daemon (g, &len, &buf);
  if (r == -1) {
    error (g, _("receive_file_data: parse error in reply callback"));
    return -1;
  }

  if (len == GUESTFS_LAUNCH_FLAG || len == GUESTFS_CANCEL_FLAG) {
    error (g, _("receive_file_data: unexpected flag received when reading file chunks"));
    return -1;
  }

  memset (&chunk, 0, sizeof chunk);

  xdrmem_create (&xdr, buf, len, XDR_DECODE);
  if (!xdr_guestfs_chunk (&xdr, &chunk)) {
    error (g, _("failed to parse file chunk"));
    free (buf);
    return -1;
  }
  xdr_destroy (&xdr);
  /* After decoding, the original buffer is no longer used. */
  free (buf);

  if (chunk.cancel) {
    if (g->user_cancel) {
      error (g, _("operation cancelled by user"));
      g->last_errnum = EINTR;
    }
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
