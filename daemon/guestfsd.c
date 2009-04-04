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

#define _BSD_SOURCE		/* for daemon(3) */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <getopt.h>
#include <netdb.h>
#include <sys/param.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "daemon.h"

static void usage (void);

/* Also in guestfs.c */
#define VMCHANNEL_PORT "6666"
#define VMCHANNEL_ADDR "10.0.2.4"

int
main (int argc, char *argv[])
{
  static const char *options = "fh:p:?";
  static struct option long_options[] = {
    { "foreground", 0, 0, 'f' },
    { "help", 0, 0, '?' },
    { "host", 1, 0, 'h' },
    { "port", 1, 0, 'p' },
    { 0, 0, 0, 0 }
  };
  int c, n, r;
  int dont_fork = 0;
  const char *host = NULL;
  const char *port = NULL;
  FILE *fp;
  char buf[4096];
  char *p, *p2;
  int sock;
  struct addrinfo *res, *rr;
  struct addrinfo hints;
  XDR xdr;
  unsigned len;

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case 'f':
      dont_fork = 1;
      break;

    case 'h':
      host = optarg;
      break;

    case 'p':
      port = optarg;
      break;

    case '?':
      usage ();
      exit (0);

    default:
      fprintf (stderr, "guestfsd: unexpected command line option 0x%x\n", c);
      exit (1);
    }
  }

  if (optind < argc) {
    usage ();
    exit (1);
  }

  /* If host and port aren't set yet, try /proc/cmdline. */
  if (!host || !port) {
    fp = fopen ("/proc/cmdline", "r");
    if (fp == NULL) {
      perror ("/proc/cmdline");
      goto next;
    }
    n = fread (buf, 1, sizeof buf - 1, fp);
    fclose (fp);
    buf[n] = '\0';

    p = strstr (buf, "guestfs=");

    if (p) {
      p += 8;
      p2 = strchr (p, ':');
      if (p2) {
	*p2++ = '\0';
	host = p;
	r = strcspn (p2, " \n");
	p2[r] = '\0';
	port = p2;
      }
    }
  }

 next:
  /* Can't parse /proc/cmdline, so use built-in defaults. */
  if (!host || !port) {
    host = VMCHANNEL_ADDR;
    port = VMCHANNEL_PORT;
  }

  /* Resolve the hostname. */
  memset (&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_ADDRCONFIG;
  r = getaddrinfo (host, port, &hints, &res);
  if (r != 0) {
    fprintf (stderr, "%s:%s: %s\n", host, port, gai_strerror (r));
    exit (1);
  }

  /* Connect to the given TCP socket. */
  sock = -1;
  for (rr = res; rr != NULL; rr = rr->ai_next) {
    sock = socket (rr->ai_family, rr->ai_socktype, rr->ai_protocol);
    if (sock != -1) {
      if (connect (sock, rr->ai_addr, rr->ai_addrlen) == 0)
	break;
      perror ("connect");

      close (sock);
      sock = -1;
    }
  }
  freeaddrinfo (res);

  if (sock == -1) {
    fprintf (stderr, "connection to %s:%s failed\n", host, port);
    exit (1);
  }

  /* Send the magic length message which indicates that
   * userspace is up inside the guest.
   */
  len = 0xf5f55ff5;
  xdrmem_create (&xdr, buf, sizeof buf, XDR_ENCODE);
  if (!xdr_uint32_t (&xdr, &len)) {
    fprintf (stderr, "xdr_uint32_t failed\n");
    exit (1);
  }

  xwrite (sock, buf, xdr_getpos (&xdr));

  xdr_destroy (&xdr);

  /* Fork into the background. */
  if (!dont_fork) {
    if (daemon (0, 1) == -1) {
      perror ("daemon");
      exit (1);
    }
  }

  /* Enter the main loop, reading and performing actions. */
  main_loop (sock);

  exit (0);
}

void
xwrite (int sock, const void *buf, size_t len)
{
  int r;

  while (len > 0) {
    r = write (sock, buf, len);
    if (r == -1) {
      perror ("write");
      exit (1);
    }
    buf += r;
    len -= r;
  }
}

void
xread (int sock, void *buf, size_t len)
{
  int r;

  while (len > 0) {
    r = read (sock, buf, len);
    if (r == -1) {
      perror ("read");
      exit (1);
    }
    if (r == 0) {
      fprintf (stderr, "read: unexpected end of file on comms socket\n");
      exit (1);
    }
    buf += r;
    len -= r;
  }
}

static void
usage (void)
{
  fprintf (stderr, "guestfsd [-f] [-h host -p port]\n");
}

int
count_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;
  return argc;
}

void
free_strings (char **argv)
{
  int argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    free (argv[argc]);
  free (argv);
}

/* This is a more sane version of 'system(3)' for running external
 * commands.  It uses fork/execvp, so we don't need to worry about
 * quoting of parameters, and it allows us to capture any error
 * messages in a buffer.
 */
int
command (char **stdoutput, char **stderror, const char *name, ...)
{
  int so_size = 0, se_size = 0;
  int so_fd[2], se_fd[2];
  int pid, r, quit;
  fd_set rset, rset2;
  char buf[256];

  if (stdoutput) *stdoutput = NULL;
  if (stderror) *stderror = NULL;

  if (pipe (so_fd) == -1 || pipe (se_fd) == -1) {
    perror ("pipe");
    return -1;
  }

  pid = fork ();
  if (pid == -1) {
    perror ("fork");
    return -1;
  }

  if (pid == 0) {		/* Child process. */
    va_list args;
    char **argv;
    char *s;
    int i;

    /* Collect the command line arguments into an array. */
    va_start (args, name);

    i = 2;
    argv = malloc (sizeof (char *) * i);
    argv[0] = (char *) name;
    argv[1] = NULL;

    while ((s = va_arg (args, char *)) != NULL) {
      argv = realloc (argv, sizeof (char *) * (++i));
      argv[i-2] = s;
      argv[i-1] = NULL;
    }

    close (0);
    close (so_fd[0]);
    close (se_fd[0]);
    dup2 (so_fd[1], 1);
    dup2 (se_fd[1], 2);
    close (so_fd[1]);
    close (se_fd[1]);

    execvp (name, argv);
    perror (name);
    _exit (1);
  }

  /* Parent process. */
  close (so_fd[1]);
  close (se_fd[1]);

  FD_ZERO (&rset);
  FD_SET (so_fd[0], &rset);
  FD_SET (se_fd[0], &rset);

  quit = 0;
  while (!quit) {
    rset2 = rset;
    r = select (MAX (so_fd[0], se_fd[0]) + 1, &rset2, NULL, NULL, NULL);
    if (r == -1) {
      perror ("select");
      waitpid (pid, NULL, 0);
      return -1;
    }

    if (FD_ISSET (so_fd[0], &rset2)) { /* something on stdout */
      r = read (so_fd[0], buf, sizeof buf);
      if (r == -1) {
	perror ("read");
	waitpid (pid, NULL, 0);
	return -1;
      }
      if (r == 0) quit = 1;

      if (r > 0 && stdoutput) {
	so_size += r;
	*stdoutput = realloc (*stdoutput, so_size);
	if (*stdoutput == NULL) {
	  perror ("realloc");
	  *stdoutput = NULL;
	  continue;
	}
	memcpy (*stdoutput + so_size - r, buf, r);
      }
    }

    if (FD_ISSET (se_fd[0], &rset2)) { /* something on stderr */
      r = read (se_fd[0], buf, sizeof buf);
      if (r == -1) {
	perror ("read");
	waitpid (pid, NULL, 0);
	return -1;
      }
      if (r == 0) quit = 1;

      if (r > 0 && stderror) {
	se_size += r;
	*stderror = realloc (*stderror, se_size);
	if (*stderror == NULL) {
	  perror ("realloc");
	  *stderror = NULL;
	  continue;
	}
	memcpy (*stderror + se_size - r, buf, r);
      }
    }
  }

  /* Make sure the output buffers are \0-terminated.  Also remove any
   * trailing \n characters from the error buffer (not from stdout).
   */
  if (stdoutput) {
    *stdoutput = realloc (*stdoutput, so_size+1);
    if (*stdoutput == NULL) {
      perror ("realloc");
      *stdoutput = NULL;
    } else
      (*stdoutput)[so_size] = '\0';
  }
  if (stderror) {
    *stderror = realloc (*stderror, se_size+1);
    if (*stderror == NULL) {
      perror ("realloc");
      *stderror = NULL;
    } else {
      (*stderror)[se_size] = '\0';
      se_size--;
      while (se_size >= 0 && (*stderror)[se_size] == '\n')
	(*stderror)[se_size--] = '\0';
    }
  }

  /* Get the exit status of the command. */
  waitpid (pid, &r, 0);

  if (WIFEXITED (r)) {
    if (WEXITSTATUS (r) == 0)
      return 0;
    else
      return -1;
  } else
    return -1;
}
