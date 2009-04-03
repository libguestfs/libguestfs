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
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <getopt.h>
#include <netdb.h>

static void xwrite (int sock, const void *buf, size_t len);
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

  /* XXX Fork into the background. */









  sleep (1000000);

  exit (0);
}

static void
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

static void
usage (void)
{
  fprintf (stderr, "guestfsd [-f] [-h host -p port]\n");
}
