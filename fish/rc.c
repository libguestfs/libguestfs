/* guestfish - guest filesystem shell
 * Copyright (C) 2009-2023 Red Hat Inc.
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
 * This file implements guestfish remote (command) support.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <libintl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <signal.h>
#include <sys/socket.h>
#include <errno.h>
#include <error.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "fish.h"
#include "rc_protocol.h"

/* Because this is a Unix domain socket, the total path length must be
 * under 108 bytes.
 */
#define SOCKET_DIR "/tmp/.guestfish-%ju" /* euid */
#define SOCKET_PATH "/tmp/.guestfish-%ju/socket-%ju" /* euid, pid */

static void
create_sockdir (void)
{
  uid_t euid = geteuid ();
  char dir[128];
  int r;
  struct stat statbuf;

  /* Create the directory, and ensure it is owned by the user. */
  snprintf (dir, sizeof dir, SOCKET_DIR, (uintmax_t) euid);
  r = mkdir (dir, 0700);
  if (r == -1 && errno != EEXIST)
  error:
    error (EXIT_FAILURE, errno, "%s", dir);
  if (lstat (dir, &statbuf) == -1)
    goto error;
  if (!S_ISDIR (statbuf.st_mode) ||
      (statbuf.st_mode & 0777) != 0700 ||
      statbuf.st_uid != euid)
    error (EXIT_FAILURE, 0,
           _("‘%s’ is not a directory or has insecure owner or permissions"),
           dir);
}

static void
create_sockpath (pid_t pid, char *sockpath, size_t len,
                 struct sockaddr_un *addr)
{
  uid_t euid = geteuid ();

  create_sockdir ();

  snprintf (sockpath, len, SOCKET_PATH, (uintmax_t) euid, (uintmax_t) pid);

  addr->sun_family = AF_UNIX;
  strcpy (addr->sun_path, sockpath);
}

/* http://man7.org/tlpi/code/online/dist/sockets/scm_rights_recv.c.html */
static void
receive_stdout (int s)
{
  union {
    struct cmsghdr cmh;
    char control[CMSG_SPACE (sizeof (int))]; /* space for 1 fd */
  } control_un;
  struct cmsghdr *cmptr;
  struct msghdr msg;
  struct iovec iov;
  ssize_t n;
  int fd;
  char buf[1];

  memset (&msg, 0, sizeof msg);

  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  iov.iov_base = buf;
  iov.iov_len = sizeof buf;

  msg.msg_control = control_un.control;
  msg.msg_controllen = sizeof (control_un.control);

  control_un.cmh.cmsg_len = CMSG_LEN (sizeof (int));
  control_un.cmh.cmsg_level = SOL_SOCKET;
  control_un.cmh.cmsg_type = SCM_RIGHTS;

  /* Read a message from the socket */
  n = recvmsg (s, &msg, 0);
  if (n < 0)
    error (EXIT_FAILURE, errno, "recvmsg stdout fd");

  cmptr = CMSG_FIRSTHDR (&msg);
  if (cmptr == NULL) {
    error (EXIT_FAILURE, errno, "didn't receive a stdout file descriptor");
    /* Makes GCC happy.  error() cannot be declared as noreturn, so
     * GCC doesn't know that the subsequent dereference of cmptr isn't
     * reachable when cmptr is NULL.
     */
    abort ();
  }
  if (cmptr->cmsg_len != CMSG_LEN (sizeof (int)))
    error (EXIT_FAILURE, 0, "cmsg_len != CMSG_LEN (sizeof (int))");
  if (cmptr->cmsg_level != SOL_SOCKET)
    error (EXIT_FAILURE, 0, "cmsg_level != SOL_SOCKET");
  if (cmptr->cmsg_type != SCM_RIGHTS)
    error (EXIT_FAILURE, 0, "cmsg_type != SCM_RIGHTS");

  /* Extract the transferred file descriptor from the control data */
  memcpy (&fd, CMSG_DATA (cmptr), sizeof fd);

  /* Duplicate the received file descriptor to stdout */
  dup2 (fd, STDOUT_FILENO);
  close (fd);
}

/* http://man7.org/tlpi/code/online/dist/sockets/scm_rights_send.c.html */
static void
send_stdout (int s)
{
  union {
    struct cmsghdr cmh;
    char control[CMSG_SPACE (sizeof (int))]; /* space for 1 fd */
  } control_un;
  struct cmsghdr *cmptr;
  struct msghdr msg;
  struct iovec iov;
  char buf[1];
  int fd;

  /* This suppresses a valgrind warning about uninitialized data.
   * It's unclear if this is hiding a real problem or not.  XXX
   */
  memset (&control_un, 0, sizeof control_un);
  memset (&msg, 0, sizeof msg);

  /* On Linux you have to transmit at least 1 byte of real data. */
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  buf[0] = 0;
  iov.iov_base = buf;
  iov.iov_len = sizeof buf;

  msg.msg_control = control_un.control;
  msg.msg_controllen = sizeof (control_un.control);

  cmptr = CMSG_FIRSTHDR (&msg);
  cmptr->cmsg_len = CMSG_LEN (sizeof (int));
  cmptr->cmsg_level = SOL_SOCKET;
  cmptr->cmsg_type  = SCM_RIGHTS;

  /* Add STDOUT to the control data */
  fd = STDOUT_FILENO;
  memcpy (CMSG_DATA (cmptr), &fd, sizeof fd);

  if (sendmsg (s, &msg, 0) != 1)
    error (EXIT_FAILURE, errno, "sendmsg stdout fd");
}

static void
close_stdout (void)
{
  int fd;

  fd = open ("/dev/null", O_WRONLY);
  if (fd == -1)
    perror ("/dev/null");
  else {
    dup2 (fd, STDOUT_FILENO);
    close (fd);
  }
}

/**
 * The remote control server (ie. C<guestfish --listen>).
 */
void
rc_listen (void)
{
  char sockpath[UNIX_PATH_MAX];
  pid_t pid;
  struct sockaddr_un addr;
  int sock, s;
  size_t i;
  FILE *fp;
  XDR xdr, xdr2;
  guestfish_hello hello;
  guestfish_call call;
  guestfish_reply reply;
  char **argv;
  size_t argc;

  memset (&hello, 0, sizeof hello);
  memset (&call, 0, sizeof call);

  create_sockdir ();

  pid = fork ();
  if (pid == -1)
    error (EXIT_FAILURE, errno, "fork");

  if (pid > 0) {
    /* Parent process. */

    if (!remote_control_csh)
      printf ("GUESTFISH_PID=%d; export GUESTFISH_PID\n", pid);
    else
      printf ("setenv GUESTFISH_PID %d\n", pid);

    fflush (stdout);
    _exit (0);
  }

  /* Child process.
   *
   * Create the listening socket for accepting commands.
   *
   * Unfortunately there is a small but unavoidable race here.  We
   * don't know the PID until after we've forked, so we cannot be
   * sure the socket is created from the point of view of the parent
   * (if the child is very slow).
   */
  pid = getpid ();
  create_sockpath (pid, sockpath, sizeof sockpath, &addr);

  sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (sock == -1)
    error (EXIT_FAILURE, errno, "socket");
  unlink (sockpath);
  if (bind (sock, (struct sockaddr *) &addr, sizeof addr) == -1)
    error (EXIT_FAILURE, errno, "bind: %s", sockpath);
  if (listen (sock, 4) == -1)
    error (EXIT_FAILURE, errno, "listen: %s", sockpath);

  /* Read commands and execute them. */
  while (!quit) {
    /* Before waiting, close stdout and substitute /dev/null.  This is
     * necessary so that eval `guestfish --listen` doesn't block
     * forever.
     */
    close_stdout ();

    s = accept4 (sock, NULL, NULL, SOCK_CLOEXEC);
    if (s == -1)
      perror ("accept");
    else {
      receive_stdout (s);

      fp = fdopen (s, "r+");
      xdrstdio_create (&xdr, fp, XDR_DECODE);

      if (!xdr_guestfish_hello (&xdr, &hello)) {
        fprintf (stderr, _("guestfish: protocol error: could not read ‘hello’ message\n"));
        goto error;
      }

      if (STRNEQ (hello.vers, PACKAGE_VERSION)) {
        fprintf (stderr, _("guestfish: protocol error: version mismatch, server version ‘%s’ does not match client version ‘%s’.  The two versions must match exactly.\n"),
                 PACKAGE_VERSION,
                 hello.vers);
        xdr_free ((xdrproc_t) xdr_guestfish_hello, (char *) &hello);
        goto error;
      }
      xdr_free ((xdrproc_t) xdr_guestfish_hello, (char *) &hello);

      while (xdr_guestfish_call (&xdr, &call)) {
        /* We have to extend and NULL-terminate the argv array. */
        argc = call.args.args_len;
        argv = realloc (call.args.args_val, (argc+1) * sizeof (char *));
        if (argv == NULL)
          error (EXIT_FAILURE, errno, "realloc");
        call.args.args_val = argv;
        argv[argc] = NULL;

        if (verbose) {
          fprintf (stderr, "guestfish(%d): %s", pid, call.cmd);
          for (i = 0; i < argc; ++i)
            fprintf (stderr, " %s", argv[i]);
          fprintf (stderr, "\n");
        }

        /* Run the command. */
        reply.r = issue_command (call.cmd, argv, NULL, 0);

        xdr_free ((xdrproc_t) xdr_guestfish_call, (char *) &call);

        /* RHBZ#802389: If the command is quit, close the handle right
         * away.  Note that the main while loop will exit preventing
         * 'g' from being reused.
         */
        if (quit) {
          guestfs_close (g);
          g = NULL;
        }

        /* Send the reply. */
        xdrstdio_create (&xdr2, fp, XDR_ENCODE);
        (void) xdr_guestfish_reply (&xdr2, &reply);
        xdr_destroy (&xdr2);

        /* Exit on error? */
        if (call.exit_on_error && reply.r == -1) {
          unlink (sockpath);
          exit (EXIT_FAILURE);
        }
      }

    error:
      xdr_destroy (&xdr);	/* NB. This doesn't close 'fp'. */
      fclose (fp);		/* Closes the underlying socket 's'. */
    }
  }

  unlink (sockpath);
  close (sock);

  /* This returns to 'fish.c', where it jumps to global cleanups and exits. */
}

/**
 * The remote control client (ie. C<guestfish --remote>).
 */
int
rc_remote (int pid, const char *cmd, size_t argc, char *argv[],
           int exit_on_error)
{
  guestfish_hello hello;
  guestfish_call call;
  guestfish_reply reply;
  char sockpath[UNIX_PATH_MAX];
  struct sockaddr_un addr;
  int sock;
  FILE *fp;
  XDR xdr;

  memset (&reply, 0, sizeof reply);

  /* This is fine as long as we never try to xdr_free this struct. */
  hello.vers = (char *) PACKAGE_VERSION;

  /* Check the other end is still running. */
  if (kill (pid, 0) == -1) {
    fprintf (stderr, _("guestfish: remote: looks like the server is not running\n"));
    return -1;
  }

  create_sockpath (pid, sockpath, sizeof sockpath, &addr);

  sock = socket (AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0);
  if (sock == -1) {
    perror ("socket");
    return -1;
  }

  if (connect (sock, (struct sockaddr *) &addr, sizeof addr) == -1) {
    perror (sockpath);
    fprintf (stderr, _("guestfish: remote: looks like the server is not running\n"));
    close (sock);
    return -1;
  }

  send_stdout (sock);

  /* Send the greeting. */
  fp = fdopen (sock, "r+");
  xdrstdio_create (&xdr, fp, XDR_ENCODE);

  if (!xdr_guestfish_hello (&xdr, &hello)) {
    fprintf (stderr, _("guestfish: protocol error: could not send initial greeting to server\n"));
    xdr_destroy (&xdr);
    fclose (fp);
    return -1;
  }

  /* Send the command.  The server supports reading multiple commands
   * per connection, but this code only ever sends one command.
   */
  call.cmd = (char *) cmd;
  call.args.args_len = argc;
  call.args.args_val = argv;
  call.exit_on_error = exit_on_error;
  if (!xdr_guestfish_call (&xdr, &call)) {
    fprintf (stderr, _("guestfish: protocol error: could not send initial greeting to server\n"));
    xdr_destroy (&xdr);
    fclose (fp);
    return -1;
  }
  xdr_destroy (&xdr);

  /* Wait for the reply. */
  xdrstdio_create (&xdr, fp, XDR_DECODE);

  if (!xdr_guestfish_reply (&xdr, &reply)) {
    fprintf (stderr, _("guestfish: protocol error: could not decode reply from server\n"));
    xdr_destroy (&xdr);
    fclose (fp);
    return -1;
  }

  xdr_destroy (&xdr);
  fclose (fp);

  return reply.r;
}
