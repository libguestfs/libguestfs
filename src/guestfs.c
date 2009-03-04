/* libguestfs
 * Copyright (C) 2009 Red Hat Inc. 
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
#include <unistd.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>

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

#include "guestfs.h"

static int error (guestfs_h *g, const char *fs, ...);
static int perrorf (guestfs_h *g, const char *fs, ...);
static void *safe_malloc (guestfs_h *g, int nbytes);
static void *safe_realloc (guestfs_h *g, void *ptr, int nbytes);
static char *safe_strdup (guestfs_h *g, const char *str);

#define VMCHANNEL_PORT 6666
#define VMCHANNEL_ADDR "10.0.2.4"

/* GuestFS handle and connection. */
struct guestfs_h
{
  /* All these socks/pids are -1 if not connected. */
  int sock;			/* Daemon communications socket. */
  int pid;			/* Qemu PID. */
  time_t start_t;		/* The time when we started qemu. */
  int daemon_up;		/* Received hello message from daemon. */

  char *tmpdir;			/* Temporary directory containing logfile
				 * and socket.  Cleaned up unless there is
				 * an error.
				 */

  char **cmdline;		/* Qemu command line. */
  int cmdline_size;

  guestfs_abort_fn abort_fn;
  int exit_on_error;
  int verbose;
};

guestfs_h *
guestfs_create (void)
{
  guestfs_h *g;

  g = malloc (sizeof (*g));
  if (!g) return NULL;

  g->sock = -1;
  g->pid = -1;

  g->start_t = 0;
  g->daemon_up = 0;

  g->tmpdir = NULL;

  g->abort_fn = abort;		/* Have to set these before safe_malloc. */
  g->exit_on_error = 0;
  g->verbose = getenv ("LIBGUESTFS_VERBOSE") != NULL;

  g->cmdline = safe_malloc (g, sizeof (char *) * 1);
  g->cmdline_size = 1;
  g->cmdline[0] = NULL;		/* This is chosen by guestfs_launch. */

  return g;
}

void
guestfs_free (guestfs_h *g)
{
  int i;
  char filename[256];

  if (g->pid) guestfs_kill_subprocess (g);

  /* The assumption is that programs calling this have successfully
   * used qemu, so delete the logfile and socket directory.
   */
  if (g->tmpdir) {
    snprintf (filename, sizeof filename, "%s/sock", g->tmpdir);
    unlink (filename);

    snprintf (filename, sizeof filename, "%s/qemu.log", g->tmpdir);
    unlink (filename);

    rmdir (g->tmpdir);

    free (g->tmpdir);
  }

  for (i = 0; i < g->cmdline_size; ++i)
    free (g->cmdline[i]);
  free (g->cmdline);

  free (g);
}

/* Cleanup fds and sockets, assuming the subprocess is dead already. */
static void
cleanup_fds (guestfs_h *g)
{
  if (g->sock >= 0) close (g->sock);
  g->sock = -1;
}

/* Wait for subprocess to exit. */
static void
wait_subprocess (guestfs_h *g)
{
  if (g->pid >= 0) waitpid (g->pid, NULL, 0);
  g->pid = -1;
}

static int
error (guestfs_h *g, const char *fs, ...)
{
  va_list args;

  fprintf (stderr, "libguestfs: ");
  va_start (args, fs);
  vfprintf (stderr, fs, args);
  va_end (args);
  fputc ('\n', stderr);

  if (g->exit_on_error) {
    guestfs_kill_subprocess (g);
    exit (1);
  }
  return -1;
}

static int
perrorf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char buf[256];
  int err = errno;

  fprintf (stderr, "libguestfs: ");
  va_start (args, fs);
  vfprintf (stderr, fs, args);
  va_end (args);
  strerror_r (err, buf, sizeof buf);
  fprintf (stderr, ": %s\n", buf);

  if (g->exit_on_error) {
    guestfs_kill_subprocess (g);
    exit (1);
  }
  return -1;
}

static void *
safe_malloc (guestfs_h *g, int nbytes)
{
  void *ptr = malloc (nbytes);
  if (!ptr) g->abort_fn ();
  return ptr;
}

static void *
safe_realloc (guestfs_h *g, void *ptr, int nbytes)
{
  void *p = realloc (ptr, nbytes);
  if (!p) g->abort_fn ();
  return p;
}

static char *
safe_strdup (guestfs_h *g, const char *str)
{
  char *s = strdup (str);
  if (!s) g->abort_fn ();
  return s;
}

void
guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_fn a)
{
  g->abort_fn = a;
}

guestfs_abort_fn
guestfs_get_out_of_memory_handler (guestfs_h *g)
{
  return g->abort_fn;
}

void
guestfs_set_exit_on_error (guestfs_h *g, int e)
{
  g->exit_on_error = e;
}

int
guestfs_get_exit_on_error (guestfs_h *g)
{
  return g->exit_on_error;
}

void
guestfs_set_verbose (guestfs_h *g, int v)
{
  g->verbose = v;
}

int
guestfs_get_verbose (guestfs_h *g)
{
  return g->verbose;
}

/* Add an escaped string to the current command line. */
static int
add_cmdline (guestfs_h *g, const char *str)
{
  if (g->pid >= 0)
    return error (g, "command line cannot be altered after qemu subprocess launched");

  g->cmdline_size++;
  g->cmdline = safe_realloc (g, g->cmdline, sizeof (char *) * g->cmdline_size);
  g->cmdline[g->cmdline_size-1] = safe_strdup (g, str);

  return 0;
}

int
guestfs_config (guestfs_h *g,
		const char *qemu_param, const char *qemu_value)
{
  if (qemu_param[0] != '-')
    return error (g, "guestfs_config: parameter must begin with '-' character");

  /* A bit fascist, but the user will probably break the extra
   * parameters that we add if they try to set any of these.
   */
  if (strcmp (qemu_param, "-kernel") == 0 ||
      strcmp (qemu_param, "-initrd") == 0 ||
      strcmp (qemu_param, "-nographic") == 0 ||
      strcmp (qemu_param, "-serial") == 0 ||
      strcmp (qemu_param, "-vnc") == 0 ||
      strcmp (qemu_param, "-full-screen") == 0 ||
      strcmp (qemu_param, "-std-vga") == 0 ||
      strcmp (qemu_param, "-vnc") == 0)
    return error (g, "guestfs_config: parameter '%s' isn't allowed");

  if (add_cmdline (g, qemu_param) != 0) return -1;

  if (qemu_value != NULL) {
    if (add_cmdline (g, qemu_value) != 0) return -1;
  }

  return 0;
}

int
guestfs_add_drive (guestfs_h *g, const char *filename)
{
  int len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL)
    return error (g, "filename cannot contain ',' (comma) character");

  snprintf (buf, len, "file=%s,media=disk", filename);

  return guestfs_config (g, "-drive", buf);
}

int
guestfs_add_cdrom (guestfs_h *g, const char *filename)
{
  int len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL)
    return error (g, "filename cannot contain ',' (comma) character");

  snprintf (buf, len, "file=%s,if=ide,index=1,media=cdrom", filename);

  return guestfs_config (g, "-drive", buf);
}

int
guestfs_launch (guestfs_h *g)
{
  static const char *dir_template = "/tmp/libguestfsXXXXXX";
  int r, i;
  /*const char *qemu = QEMU;*/	/* XXX */
  const char *qemu = "/home/rjones/d/redhat/libguestfs/qemu";
  const char *kernel = "/boot/vmlinuz-2.6.27.15-170.2.24.fc10.x86_64";
  const char *initrd = "/tmp/initrd-2.6.27.15-170.2.24.fc10.x86_64.img";
  char unixsock[256];

  /* XXX Choose which qemu to run. */
  /* XXX Choose initrd, etc. */

  /* Make the temporary directory containing the logfile and socket. */
  if (!g->tmpdir) {
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL)
      return perrorf (g, "%s: cannot create temporary directory", dir_template);

    snprintf (unixsock, sizeof unixsock, "%s/sock", g->tmpdir);
  }

  r = fork ();
  if (r == -1)
    return perrorf (g, "fork");

  if (r > 0) {			/* Parent (library). */
    g->pid = r;

    /* If qemu is going to die during startup, give it a tiny amount
     * of time to print the error message.
     */
    usleep (10000);

    /* Start the clock ... */
    time (&g->start_t);
  }
  else {			/* Child (qemu). */
    char vmchannel[256];
    char logfile[256];
    char append[256];

    /* Set up the full command line.  Do this in the subprocess so we
     * don't need to worry about cleaning up.
     */
    g->cmdline[0] = (char *) qemu;

    g->cmdline =
      realloc (g->cmdline, sizeof (char *) * (g->cmdline_size + 16));
    if (g->cmdline == NULL) {
      perror ("realloc");
      _exit (1);
    }

    /* Construct the -net channel parameter for qemu. */
    snprintf (vmchannel, sizeof vmchannel,
	      "channel,%d:unix:%s,server,nowait", VMCHANNEL_PORT, unixsock);

    /* Linux kernel command line. */
    snprintf (append, sizeof append,
	      "console=ttyS0 guestfs=%s:%d", VMCHANNEL_ADDR, VMCHANNEL_PORT);

    /* XXX -m */

    g->cmdline[g->cmdline_size   ] = "-kernel";
    g->cmdline[g->cmdline_size+ 1] = (char *) kernel;
    g->cmdline[g->cmdline_size+ 2] = "-initrd";
    g->cmdline[g->cmdline_size+ 3] = (char *) initrd;
    g->cmdline[g->cmdline_size+ 4] = "-append";
    g->cmdline[g->cmdline_size+ 5] = append;
    g->cmdline[g->cmdline_size+ 6] = "-nographic";
    g->cmdline[g->cmdline_size+ 7] = "-serial";
    g->cmdline[g->cmdline_size+ 8] = "stdio";
    g->cmdline[g->cmdline_size+ 9] = "-net";
    g->cmdline[g->cmdline_size+10] = vmchannel;
    g->cmdline[g->cmdline_size+11] = "-net";
    g->cmdline[g->cmdline_size+12] = "user,vlan=0";
    g->cmdline[g->cmdline_size+13] = "-net";
    g->cmdline[g->cmdline_size+14] = "nic,vlan=0";
    g->cmdline[g->cmdline_size+15] = NULL;

    if (g->verbose) {
      fprintf (stderr, "Running %s", qemu);
      for (i = 0; g->cmdline[i]; ++i)
	fprintf (stderr, " %s", g->cmdline[i]);
      fprintf (stderr, "\n");
    }

    /* Set up stdin, stdout.  Messages should go to the logfile. */
    close (0);
    close (1);
    open ("/dev/null", O_RDONLY);
    snprintf (logfile, sizeof logfile, "%s/qemu.log", g->tmpdir);
    open (logfile, O_WRONLY|O_CREAT|O_APPEND, 0644);
    /*dup2 (1, 2);*/

    /* Set up a new process group, so we can signal this process
     * and all subprocesses (eg. if qemu is really a shell script).
     */
    setpgid (0, 0);

    execv (qemu, g->cmdline);	/* Run qemu. */
    perror (qemu);
    _exit (1);
  }

  return 0;
}

/* A peculiarity of qemu's vmchannel implementation is that both sides
 * connect to qemu, ie:
 *
 *   libguestfs  --- connect --> qemu <-- connect --- daemon
 *    (host)                                          (guest)
 *
 * This has several implications: (1) qemu creates the Unix socket, so
 * we have to wait for it to do that.  (2) we have to arrange for the
 * daemon to send a "hello" message which we also wait for.
 *
 * At any time during this, the qemu subprocess might run slowly, die
 * or hang (it's very prone to just hanging if the BIOS fails for any
 * reason or if the kernel cannot be found to boot from).
 *
 * The only realistic way to handle this is, unfortunately, using
 * timeouts, also checking if the qemu subprocess is still alive.
 *
 * We could do better here by monitoring the Linux kernel log messages
 * (via the serial console, which is currently just redirected to a
 * log file) and seeing if the Linux guest is making progress. (XXX)
 */

#define QEMU_SOCKET_TIMEOUT 5	/* How long we wait for qemu to make
				 * the socket.  This should be very quick.
				 */
#define DAEMON_TIMEOUT 60	/* How long we wait for guest to boot
				 * and start the daemon.  This could take
				 * a potentially long time, and is very
				 * sensitive to the overall load on the host.
				 */

static int wait_ready (guestfs_h *g);

int
guestfs_wait_ready (guestfs_h *g)
{
  int r;

  /* Launch the subprocess, if there isn't one already. */
  if (g->pid == -1) {
    if (guestfs_launch (g) != 0)
      return -1;
  }

  for (;;) {
    r = wait_ready (g);
    if (r == -1) {		/* Error. */
      guestfs_kill_subprocess (g);
      return -1;
    }
    else if (r > 0) {		/* Keep waiting. */
      sleep (1);
      continue;
    }
    else if (r == 0)		/* Daemon is ready. */
      break;
  }

  return 0;
}

#define UNIX_PATH_MAX 108

/* This function is called repeatedly until the qemu subprocess and
 * daemon is ready.  It returns:
 *   -1 : error
 *    0 : done, daemon is ready
 *   >0 : not ready, keep waiting
 */
static int
wait_ready (guestfs_h *g)
{
  int r, i, sock;
  time_t now;
  double elapsed;
  struct sockaddr_un addr;
  unsigned char m;

  if (g->pid == -1) abort ();	/* Internal state error. */

  /* Check the daemon is still around. */
  r = waitpid (g->pid, NULL, WNOHANG);

  if (r > 0 || (r == -1 && errno == ECHILD)) {
    g->pid = -1;
    return error (g,
		  "qemu subprocess exited unexpectedly during initialization");
  }

  time (&now);
  elapsed = difftime (now, g->start_t);

  if (g->sock == -1) {
    /* Create the socket. */
    sock = socket (AF_UNIX, SOCK_STREAM, 0);
    if (sock == -1)
      return perrorf (g, "socket");

    addr.sun_family = AF_UNIX;
    snprintf (addr.sun_path, UNIX_PATH_MAX, "%s/sock", g->tmpdir);

    if (connect (sock, (struct sockaddr *) &addr, sizeof addr) == -1) {
      if (elapsed <= QEMU_SOCKET_TIMEOUT) {
	close (sock);
	return 1;		/* Keep waiting for the socket ... */
      }
      perrorf (g, "qemu process hanging before making vmchannel socket");
      close (sock);
      return -1;
    }

    if (fcntl (sock, F_SETFL, O_NONBLOCK) == -1) {
      perrorf (g, "set socket non-blocking");
      close (sock);
      return -1;
    }

    g->sock = sock;
  }

  if (!g->daemon_up) {
    /* Wait for the daemon to say hello. */
    errno = 0;
    r = read (g->sock, &m, 1);
    if (r == 1) {
      if (m == 0xF5) {
	g->daemon_up = 1;
	return 0;
      } else {
	error (g, "unexpected message from qemu vmchannel or daemon");
	return -1;
      }
    }
    if (errno == EAGAIN) {
      if (elapsed <= DAEMON_TIMEOUT)
	return 1;		/* Keep waiting for the daemon ... */
      error (g, "timeout waiting for guest to become ready");
      return -1;
    }

    perrorf (g, "read");
    return -1;
  }

  return 0;
}

void
guestfs_kill_subprocess (guestfs_h *g)
{
  if (g->pid >= 0) {
    if (g->verbose)
      fprintf (stderr, "sending SIGTERM to pgid %d\n", g->pid);

    kill (- g->pid, SIGTERM);
    wait_subprocess (g);
  }

  cleanup_fds (g);
}
