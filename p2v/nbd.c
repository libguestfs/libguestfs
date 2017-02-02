/* virt-p2v
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * This file handles the virt-p2v I<--nbd> command line option
 * and running either L<qemu-nbd(8)> or L<nbdkit(1)>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <netdb.h>
#include <errno.h>
#include <error.h>
#include <libintl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <assert.h>

#include "getprogname.h"

#include "p2v.h"

/* How long to wait for the NBD server to start (seconds). */
#define WAIT_NBD_TIMEOUT 10

/* List of servers specified by the --nbd option. */
enum nbd_server {
  /* 0 is reserved for "end of list" */
  QEMU_NBD = 1,
  NBDKIT = 2,
};
static enum nbd_server *cmdline_servers = NULL;

/* If no --nbd option is passed, we use this standard list instead.
 * Must match the documentation in virt-p2v(1).
 */
static const enum nbd_server standard_servers[] =
  { QEMU_NBD, NBDKIT, 0 };

/* After testing the list of servers passed by the user, this is
 * server we decide to use.
 */
static enum nbd_server use_server;

static pid_t start_qemu_nbd (int nbd_local_port, const char *device);
static pid_t start_nbdkit (int nbd_local_port, const char *device);
static int connect_with_source_port (const char *hostname, int dest_port, int source_port);
static int bind_source_port (int sockfd, int family, int source_port);

static char *nbd_error;

static void set_nbd_error (const char *fs, ...)
  __attribute__((format(printf,1,2)));

static void
set_nbd_error (const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0)
    error (EXIT_FAILURE, errno,
           "vasprintf (original error format string: %s)", fs);

  free (nbd_error);
  nbd_error = msg;
}

const char *
get_nbd_error (void)
{
  return nbd_error;
}

/**
 * The main program calls this to set the I<--nbd> option.
 */
void
set_nbd_option (const char *opt)
{
  size_t i, len;
  CLEANUP_FREE_STRING_LIST char **strs = NULL;

  if (cmdline_servers != NULL)
    error (EXIT_FAILURE, 0, _("--nbd option appears multiple times"));

  strs = guestfs_int_split_string (',', opt);

  if (strs == NULL)
    error (EXIT_FAILURE, errno, _("malloc"));

  len = guestfs_int_count_strings (strs);
  if (len == 0)
    error (EXIT_FAILURE, 0, _("--nbd option cannot be empty"));

  cmdline_servers = malloc (sizeof (enum nbd_server) * (len + 1));
  if (cmdline_servers == NULL)
    error (EXIT_FAILURE, errno, _("malloc"));

  for (i = 0; strs[i] != NULL; ++i) {
    if (STREQ (strs[i], "qemu-nbd") || STREQ (strs[i], "qemu"))
      cmdline_servers[i] = QEMU_NBD;
    else if (STREQ (strs[i], "nbdkit"))
      cmdline_servers[i] = NBDKIT;
    else
      error (EXIT_FAILURE, 0, _("--nbd: unknown server: %s"), strs[i]);
  }

  assert (i == len);
  cmdline_servers[i] = 0;       /* marks the end of the list */
}

/**
 * Test the I<--nbd> option (or built-in default list) to see which
 * servers are actually installed and appear to be working.
 *
 * Set the C<use_server> global accordingly.
 */
void
test_nbd_servers (void)
{
  size_t i;
  int r;
  const enum nbd_server *servers;

  if (cmdline_servers != NULL)
    servers = cmdline_servers;
  else
    servers = standard_servers;

  use_server = 0;

  for (i = 0; servers[i] != 0; ++i) {
    switch (servers[i]) {
    case QEMU_NBD:
      r = system ("qemu-nbd --version"
#ifndef DEBUG_STDERR
                  " >/dev/null 2>&1"
#endif
                  );
      if (r == 0) {
        use_server = servers[i];
        goto finish;
      }
      break;

    case NBDKIT:
      r = system ("nbdkit file --version"
#ifndef DEBUG_STDERR
                  " >/dev/null 2>&1"
#endif
                  );
      if (r == 0) {
        use_server = servers[i];
        goto finish;
      }
      break;

    default:
      abort ();
    }
  }

 finish:
  if (use_server == 0) {
    fprintf (stderr,
             _("%s: no working NBD server was found, cannot continue.\n"
               "Please check the --nbd option in the virt-p2v(1) man page.\n"),
             getprogname ());
    exit (EXIT_FAILURE);
  }

  /* Release memory used by the --nbd option. */
  free (cmdline_servers);
  cmdline_servers = NULL;
}

/**
 * Start the NBD server.
 *
 * We previously tested all NBD servers (see C<test_nbd_servers>) and
 * hopefully found one which will work.
 *
 * Returns the process ID (E<gt> 0) or C<0> if there is an error.
 */
pid_t
start_nbd_server (int port, const char *device)
{
  switch (use_server) {
  case QEMU_NBD:
    return start_qemu_nbd (port, device);

  case NBDKIT:
    return start_nbdkit (port, device);

  default:
    abort ();
  }
}

/**
 * Start a local L<qemu-nbd(1)> process.
 *
 * Returns the process ID (E<gt> 0) or C<0> if there is an error.
 */
static pid_t
start_qemu_nbd (int port, const char *device)
{
  pid_t pid;
  char port_str[64];

#if DEBUG_STDERR
  fprintf (stderr, "starting qemu-nbd for %s on port %d\n", device, port);
#endif

  snprintf (port_str, sizeof port_str, "%d", port);

  pid = fork ();
  if (pid == -1) {
    set_nbd_error ("fork: %m");
    return 0;
  }

  if (pid == 0) {               /* Child. */
    close (0);
    open ("/dev/null", O_RDONLY);

    execlp ("qemu-nbd",
            "qemu-nbd",
            "-r",               /* readonly (vital!) */
            "-p", port_str,     /* listening port */
            "-t",               /* persistent */
            "-f", "raw",        /* force raw format */
            "-b", "localhost",  /* listen only on loopback interface */
            "--cache=unsafe",   /* use unsafe caching for speed */
            device,             /* a device like /dev/sda */
            NULL);
    perror ("qemu-nbd");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  return pid;
}

/**
 * Start a local L<nbdkit(1)> process using the
 * L<nbdkit-file-plugin(1)>.
 *
 * Returns the process ID (E<gt> 0) or C<0> if there is an error.
 */
static pid_t
start_nbdkit (int port, const char *device)
{
  pid_t pid;
  char port_str[64];
  CLEANUP_FREE char *file_str = NULL;

#if DEBUG_STDERR
  fprintf (stderr, "starting nbdkit for %s on port %d\n", device, port);
#endif

  snprintf (port_str, sizeof port_str, "%d", port);

  if (asprintf (&file_str, "file=%s", device) == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  pid = fork ();
  if (pid == -1) {
    set_nbd_error ("fork: %m");
    return 0;
  }

  if (pid == 0) {               /* Child. */
    close (0);
    open ("/dev/null", O_RDONLY);

    execlp ("nbdkit",
            "nbdkit",
            "-r",               /* readonly (vital!) */
            "-p", port_str,     /* listening port */
            "-i", "localhost",  /* listen only on loopback interface */
            "-f",               /* don't fork */
            "file",             /* file plugin */
            file_str,           /* a device like file=/dev/sda */
            NULL);
    perror ("nbdkit");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  return pid;
}

/**
 * Wait for a local NBD server to start and be listening for
 * connections.
 */
int
wait_for_nbd_server_to_start (int nbd_local_port)
{
  int sockfd = -1;
  int result = -1;
  time_t start_t, now_t;
  struct timespec half_sec = { .tv_sec = 0, .tv_nsec = 500000000 };
  struct timeval timeout = { .tv_usec = 0 };
  char magic[8]; /* NBDMAGIC */
  size_t bytes_read = 0;
  ssize_t recvd;

  time (&start_t);

  for (;;) {
    time (&now_t);

    if (now_t - start_t >= WAIT_NBD_TIMEOUT) {
      set_nbd_error ("timed out waiting for NBD server to start");
      goto cleanup;
    }

    /* Source port for probing NBD server should be one greater than
     * nbd_local_port.  It's not guaranteed to always bind to this
     * port, but it will hint the kernel to start there and try
     * incrementally higher ports if needed.  This avoids the case
     * where the kernel selects nbd_local_port as our source port, and
     * we immediately connect to ourself.  See:
     * https://bugzilla.redhat.com/show_bug.cgi?id=1167774#c9
     */
    sockfd = connect_with_source_port ("localhost", nbd_local_port,
                                       nbd_local_port+1);
    if (sockfd >= 0)
      break;

    nanosleep (&half_sec, NULL);
  }

  time (&now_t);
  timeout.tv_sec = (start_t + WAIT_NBD_TIMEOUT) - now_t;
  setsockopt (sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);

  do {
    recvd = recv (sockfd, magic, sizeof magic - bytes_read, 0);

    if (recvd == -1) {
      set_nbd_error ("waiting for NBD server to start: recv: %m");
      goto cleanup;
    }

    bytes_read += recvd;
  } while (bytes_read < sizeof magic);

  if (memcmp (magic, "NBDMAGIC", sizeof magic) != 0) {
    set_nbd_error ("waiting for NBD server to start: "
                   "'NBDMAGIC' was not received from NBD server");
    goto cleanup;
  }

  result = 0;
 cleanup:
  close (sockfd);

  return result;
}

/**
 * Connect to C<hostname:dest_port>, resolving the address using
 * L<getaddrinfo(3)>.
 *
 * This also sets the source port of the connection to the first free
 * port number E<ge> C<source_port>.
 *
 * This may involve multiple connections - to IPv4 and IPv6 for
 * instance.
 */
static int
connect_with_source_port (const char *hostname, int dest_port, int source_port)
{
  struct addrinfo hints;
  struct addrinfo *results, *rp;
  char dest_port_str[16];
  int r, sockfd = -1;
  int reuseaddr = 1;

  snprintf (dest_port_str, sizeof dest_port_str, "%d", dest_port);

  memset (&hints, 0, sizeof hints);
  hints.ai_family = AF_UNSPEC;     /* allow IPv4 or IPv6 */
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_NUMERICSERV; /* numeric dest port number */
  hints.ai_protocol = 0;           /* any protocol */

  r = getaddrinfo (hostname, dest_port_str, &hints, &results);
  if (r != 0) {
    set_nbd_error ("getaddrinfo: %s/%s: %s",
                   hostname, dest_port_str, gai_strerror (r));
    return -1;
  }

  for (rp = results; rp != NULL; rp = rp->ai_next) {
    sockfd = socket (rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (sockfd == -1)
      continue;

    /* If we run p2v repeatedly (say, running the tests in a loop),
     * there's a decent chance we'll end up trying to bind() to a port
     * that is in TIME_WAIT from a prior run.  Handle that gracefully
     * with SO_REUSEADDR.
     */
    if (setsockopt (sockfd, SOL_SOCKET, SO_REUSEADDR,
                    &reuseaddr, sizeof reuseaddr) == -1)
      perror ("warning: setsockopt");

    /* Need to bind the source port. */
    if (bind_source_port (sockfd, rp->ai_family, source_port) == -1) {
      close (sockfd);
      sockfd = -1;
      continue;
    }

    /* Connect. */
    if (connect (sockfd, rp->ai_addr, rp->ai_addrlen) == -1) {
      set_nbd_error ("waiting for NBD server to start: "
                     "connect to %s/%s: %m",
                     hostname, dest_port_str);
      close (sockfd);
      sockfd = -1;
      continue;
    }

    break;
  }

  freeaddrinfo (results);
  return sockfd;
}

static int
bind_source_port (int sockfd, int family, int source_port)
{
  struct addrinfo hints;
  struct addrinfo *results, *rp;
  char source_port_str[16];
  int r;

  snprintf (source_port_str, sizeof source_port_str, "%d", source_port);

  memset (&hints, 0, sizeof (hints));
  hints.ai_family = family;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE | AI_NUMERICSERV; /* numeric port number */
  hints.ai_protocol = 0;                        /* any protocol */

  r = getaddrinfo ("localhost", source_port_str, &hints, &results);
  if (r != 0) {
    set_nbd_error ("getaddrinfo (bind): localhost/%s: %s",
                   source_port_str, gai_strerror (r));
    return -1;
  }

  for (rp = results; rp != NULL; rp = rp->ai_next) {
    if (bind (sockfd, rp->ai_addr, rp->ai_addrlen) == 0)
      goto bound;
  }

  set_nbd_error ("waiting for NBD server to start: "
                 "bind to source port %d: %m",
                 source_port);
  freeaddrinfo (results);
  return -1;

 bound:
  freeaddrinfo (results);
  return 0;
}
