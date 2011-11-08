/* guestfish - the filesystem interactive shell
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
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <signal.h>
#include <sys/socket.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#include "fish.h"
#include "rc_protocol.h"

static void
create_sockpath (pid_t pid, char *sockpath, int len, struct sockaddr_un *addr)
{
  char dir[128];
  uid_t euid = geteuid ();

  snprintf (dir, sizeof dir, "/tmp/.guestfish-%d", euid);
  mkdir (dir, 0700);

  snprintf (sockpath, len, "/tmp/.guestfish-%d/socket-%d", euid, pid);

  addr->sun_family = AF_UNIX;
  strcpy (addr->sun_path, sockpath);
}

static const socklen_t controllen = CMSG_LEN (sizeof (int));

static void
receive_stdout (int s)
{
  static struct cmsghdr *cmptr = NULL, *h;
  struct msghdr         msg;
  struct iovec          iov[1];

  /* Our 1 byte buffer */
  char buf[1];

  if (NULL == cmptr) {
    cmptr = malloc (controllen);
    if (NULL == cmptr) {
      perror ("malloc");
      exit (EXIT_FAILURE);
    }
  }

  /* Don't specify a source */
  memset (&msg, 0, sizeof msg);
  msg.msg_name = NULL;
  msg.msg_namelen = 0;

  /* Initialise the msghdr to receive zero byte */
  iov[0].iov_base = buf;
  iov[0].iov_len  = 1;
  msg.msg_iov     = iov;
  msg.msg_iovlen  = 1;

  /* Initialise the control data */
  msg.msg_control     = cmptr;
  msg.msg_controllen  = controllen;

  /* Read a message from the socket */
  ssize_t n = recvmsg (s, &msg, 0);
  if (n < 0) {
    perror ("recvmsg stdout fd");
    exit (EXIT_FAILURE);
  }

  h = CMSG_FIRSTHDR(&msg);
  if (NULL == h) {
    fprintf (stderr, "didn't receive a stdout file descriptor\n");
  }

  else {
    /* Extract the transferred file descriptor from the control data */
    unsigned char *data = CMSG_DATA (h);
    int fd = *(int *)data;

    /* Duplicate the received file descriptor to stdout */
    dup2 (fd, STDOUT_FILENO);
    close (fd);
  }
}

static void
send_stdout (int s)
{
  static struct cmsghdr *cmptr = NULL;
  struct msghdr         msg;
  struct iovec          iov[1];

  /* Our 1 byte dummy buffer */
  char buf[1];

  /* Don't specify a destination */
  memset (&msg, 0, sizeof msg);
  msg.msg_name    = NULL;
  msg.msg_namelen = 0;

  /* Initialise the msghdr to send zero byte */
  iov[0].iov_base = buf;
  iov[0].iov_len  = 1;
  msg.msg_iov     = iov;
  msg.msg_iovlen  = 1;

  /* Initialize the zero byte */
  buf[0] = 0;

  /* Initialize the control data */
  if (NULL == cmptr) {
    cmptr = malloc (controllen);
    if (NULL == cmptr) {
      perror ("malloc");
      exit (EXIT_FAILURE);
    }
  }
  cmptr->cmsg_level = SOL_SOCKET;
  cmptr->cmsg_type  = SCM_RIGHTS;
  cmptr->cmsg_len   = controllen;

  /* Add control header to the message */
  msg.msg_control     = cmptr;
  msg.msg_controllen  = controllen;

  /* Add STDOUT to the control data */
  unsigned char *data = CMSG_DATA (cmptr);
  *(int *)data = STDOUT_FILENO;

  if (sendmsg (s, &msg, 0) != 1) {
    perror ("sendmsg stdout fd");
    exit (EXIT_FAILURE);
  }
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

/* Remote control server. */
void
rc_listen (void)
{
  char sockpath[128];
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

  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    exit (EXIT_FAILURE);
  }

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

  sock = socket (AF_UNIX, SOCK_STREAM, 0);
  if (sock == -1) {
    perror ("socket");
    exit (EXIT_FAILURE);
  }
  unlink (sockpath);
  if (bind (sock, (struct sockaddr *) &addr, sizeof addr) == -1) {
    perror (sockpath);
    exit (EXIT_FAILURE);
  }
  if (listen (sock, 4) == -1) {
    perror ("listen");
    exit (EXIT_FAILURE);
  }

  /* Now close stdout and substitute /dev/null.  This is necessary
   * so that eval `guestfish --listen` doesn't block forever.
   */
  close_stdout();

  /* Read commands and execute them. */
  while (!quit) {
    s = accept (sock, NULL, NULL);
    if (s == -1)
      perror ("accept");
    else {
      receive_stdout(s);

      fp = fdopen (s, "r+");
      xdrstdio_create (&xdr, fp, XDR_DECODE);

      if (!xdr_guestfish_hello (&xdr, &hello)) {
        fprintf (stderr, _("guestfish: protocol error: could not read 'hello' message\n"));
        goto error;
      }

      if (STRNEQ (hello.vers, PACKAGE_VERSION)) {
        fprintf (stderr, _("guestfish: protocol error: version mismatch, server version '%s' does not match client version '%s'.  The two versions must match exactly.\n"),
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
        if (argv == NULL) {
          perror ("realloc");
          exit (EXIT_FAILURE);
        }
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
      close_stdout(); /* Re-close stdout */
    }
  }

  unlink (sockpath);
  exit (EXIT_SUCCESS);
}

/* Remote control client. */
int
rc_remote (int pid, const char *cmd, size_t argc, char *argv[],
           int exit_on_error)
{
  guestfish_hello hello;
  guestfish_call call;
  guestfish_reply reply;
  char sockpath[128];
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

  sock = socket (AF_UNIX, SOCK_STREAM, 0);
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

  send_stdout(sock);

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
