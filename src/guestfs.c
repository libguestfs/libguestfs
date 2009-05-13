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
#define _GNU_SOURCE /* for vasprintf, GNU strerror_r, strchrnul */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>

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

#include "guestfs.h"
#include "guestfs_protocol.h"

#define error guestfs_error
#define perrorf guestfs_perrorf
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
#define safe_strdup guestfs_safe_strdup
#define safe_memdup guestfs_safe_memdup

static void default_error_cb (guestfs_h *g, void *data, const char *msg);
static void stdout_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data, int watch, int fd, int events);
static void sock_read_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data, int watch, int fd, int events);
static void sock_write_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data, int watch, int fd, int events);

static void close_handles (void);

static int select_add_handle (guestfs_main_loop *ml, guestfs_h *g, int fd, int events, guestfs_handle_event_cb cb, void *data);
static int select_remove_handle (guestfs_main_loop *ml, guestfs_h *g, int watch);
static int select_add_timeout (guestfs_main_loop *ml, guestfs_h *g, int interval, guestfs_handle_timeout_cb cb, void *data);
static int select_remove_timeout (guestfs_main_loop *ml, guestfs_h *g, int timer);
static int select_main_loop_run (guestfs_main_loop *ml, guestfs_h *g);
static int select_main_loop_quit (guestfs_main_loop *ml, guestfs_h *g);

/* Default select-based main loop. */
struct select_handle_cb_data {
  guestfs_handle_event_cb cb;
  guestfs_h *g;
  void *data;
};

struct select_main_loop {
  /* NB. These fields must be the same as in struct guestfs_main_loop: */
  guestfs_add_handle_cb add_handle;
  guestfs_remove_handle_cb remove_handle;
  guestfs_add_timeout_cb add_timeout;
  guestfs_remove_timeout_cb remove_timeout;
  guestfs_main_loop_run_cb main_loop_run;
  guestfs_main_loop_quit_cb main_loop_quit;

  /* Additional private data: */
  int is_running;

  fd_set rset;
  fd_set wset;
  fd_set xset;

  int max_fd;
  int nr_fds;
  struct select_handle_cb_data *handle_cb_data;
};

/* Default main loop. */
static struct select_main_loop default_main_loop = {
  .add_handle = select_add_handle,
  .remove_handle = select_remove_handle,
  .add_timeout = select_add_timeout,
  .remove_timeout = select_remove_timeout,
  .main_loop_run = select_main_loop_run,
  .main_loop_quit = select_main_loop_quit,

  /* XXX hopefully .rset, .wset, .xset are initialized to the empty
   * set by the normal action of everything being initialized to zero.
   */
  .is_running = 0,
  .max_fd = -1,
  .nr_fds = 0,
  .handle_cb_data = NULL,
};

#define UNIX_PATH_MAX 108

/* Also in guestfsd.c */
#define VMCHANNEL_PORT 6666
#define VMCHANNEL_ADDR "10.0.2.4"

/* GuestFS handle and connection. */
enum state { CONFIG, LAUNCHING, READY, BUSY, NO_HANDLE };

struct guestfs_h
{
  struct guestfs_h *next;	/* Linked list of open handles. */

  /* State: see the state machine diagram in the man page guestfs(3). */
  enum state state;

  int fd[2];			/* Stdin/stdout of qemu. */
  int sock;			/* Daemon communications socket. */
  pid_t pid;			/* Qemu PID. */
  pid_t recoverypid;		/* Recovery process PID. */
  time_t start_t;		/* The time when we started qemu. */

  int stdout_watch;		/* Watches qemu stdout for log messages. */
  int sock_watch;		/* Watches daemon comm socket. */

  char *tmpdir;			/* Temporary directory containing socket. */

  char **cmdline;		/* Qemu command line. */
  int cmdline_size;

  int verbose;
  int autosync;

  const char *path;
  const char *qemu;

  char *last_error;

  /* Callbacks. */
  guestfs_abort_cb           abort_cb;
  guestfs_error_handler_cb   error_cb;
  void *                     error_cb_data;
  guestfs_send_cb            send_cb;
  void *                     send_cb_data;
  guestfs_reply_cb           reply_cb;
  void *                     reply_cb_data;
  guestfs_log_message_cb     log_message_cb;
  void *                     log_message_cb_data;
  guestfs_subprocess_quit_cb subprocess_quit_cb;
  void *                     subprocess_quit_cb_data;
  guestfs_launch_done_cb     launch_done_cb;
  void *                     launch_done_cb_data;

  /* Main loop used by this handle. */
  guestfs_main_loop *main_loop;

  /* Messages sent and received from the daemon. */
  char *msg_in;
  int msg_in_size, msg_in_allocated;
  char *msg_out;
  int msg_out_size, msg_out_pos;

  int msg_next_serial;
};

static guestfs_h *handles = NULL;
static int atexit_handler_set = 0;

guestfs_h *
guestfs_create (void)
{
  guestfs_h *g;
  const char *str;

  g = malloc (sizeof (*g));
  if (!g) return NULL;

  memset (g, 0, sizeof (*g));

  g->state = CONFIG;

  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;
  g->stdout_watch = -1;
  g->sock_watch = -1;

  g->abort_cb = abort;
  g->error_cb = default_error_cb;
  g->error_cb_data = NULL;

  str = getenv ("LIBGUESTFS_DEBUG");
  g->verbose = str != NULL && strcmp (str, "1") == 0;

  str = getenv ("LIBGUESTFS_PATH");
  g->path = str != NULL ? str : GUESTFS_DEFAULT_PATH;

  str = getenv ("LIBGUESTFS_QEMU");
  g->qemu = str != NULL ? str : QEMU;

  g->main_loop = guestfs_get_default_main_loop ();

  /* Start with large serial numbers so they are easy to spot
   * inside the protocol.
   */
  g->msg_next_serial = 0x00123400;

  /* Link the handles onto a global list.  This is the one area
   * where the library needs to be made thread-safe. (XXX)
   */
  /* acquire mutex (XXX) */
  g->next = handles;
  handles = g;
  if (!atexit_handler_set) {
    atexit (close_handles);
    atexit_handler_set = 1;
  }
  /* release mutex (XXX) */

  if (g->verbose)
    fprintf (stderr, "new guestfs handle %p\n", g);

  return g;
}

void
guestfs_close (guestfs_h *g)
{
  int i;
  char filename[256];
  guestfs_h *gg;

  if (g->state == NO_HANDLE) {
    /* Not safe to call 'error' here, so ... */
    fprintf (stderr, "guestfs_close: called twice on the same handle\n");
    return;
  }

  if (g->verbose)
    fprintf (stderr, "closing guestfs handle %p (state %d)\n", g, g->state);

  /* Try to sync if autosync flag is set. */
  if (g->autosync && g->state == READY) {
    guestfs_umount_all (g);
    guestfs_sync (g);
  }

  /* Remove any handlers that might be called back before we kill the
   * subprocess.
   */
  g->log_message_cb = NULL;

  if (g->state != CONFIG)
    guestfs_kill_subprocess (g);

  if (g->tmpdir) {
    snprintf (filename, sizeof filename, "%s/sock", g->tmpdir);
    unlink (filename);

    rmdir (g->tmpdir);

    free (g->tmpdir);
  }

  if (g->cmdline) {
    for (i = 0; i < g->cmdline_size; ++i)
      free (g->cmdline[i]);
    free (g->cmdline);
  }

  /* Mark the handle as dead before freeing it. */
  g->state = NO_HANDLE;

  /* acquire mutex (XXX) */
  if (handles == g)
    handles = g->next;
  else {
    for (gg = handles; gg->next != g; gg = gg->next)
      ;
    gg->next = g->next;
  }
  /* release mutex (XXX) */

  free (g->msg_in);
  free (g->msg_out);
  free (g->last_error);
  free (g);
}

/* Close all open handles (called from atexit(3)). */
static void
close_handles (void)
{
  while (handles) guestfs_close (handles);
}

const char *
guestfs_last_error (guestfs_h *g)
{
  return g->last_error;
}

static void
set_last_error (guestfs_h *g, const char *msg)
{
  free (g->last_error);
  g->last_error = strdup (msg);
}

static void
default_error_cb (guestfs_h *g, void *data, const char *msg)
{
  fprintf (stderr, "libguestfs: error: %s\n", msg);
}

void
guestfs_error (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;

  va_start (args, fs);
  vasprintf (&msg, fs, args);
  va_end (args);

  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
  set_last_error (g, msg);

  free (msg);
}

void
guestfs_perrorf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int err = errno;

  va_start (args, fs);
  vasprintf (&msg, fs, args);
  va_end (args);

#ifndef _GNU_SOURCE
  char buf[256];
  strerror_r (err, buf, sizeof buf);
#else
  char _buf[256];
  char *buf;
  buf = strerror_r (err, _buf, sizeof _buf);
#endif

  msg = safe_realloc (g, msg, strlen (msg) + 2 + strlen (buf) + 1);
  strcat (msg, ": ");
  strcat (msg, buf);

  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
  set_last_error (g, msg);

  free (msg);
}

void *
guestfs_safe_malloc (guestfs_h *g, size_t nbytes)
{
  void *ptr = malloc (nbytes);
  if (!ptr) g->abort_cb ();
  return ptr;
}

void *
guestfs_safe_realloc (guestfs_h *g, void *ptr, int nbytes)
{
  void *p = realloc (ptr, nbytes);
  if (!p) g->abort_cb ();
  return p;
}

char *
guestfs_safe_strdup (guestfs_h *g, const char *str)
{
  char *s = strdup (str);
  if (!s) g->abort_cb ();
  return s;
}

void *
guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size)
{
  void *p = malloc (size);
  if (!p) g->abort_cb ();
  memcpy (p, ptr, size);
  return p;
}

static int
xwrite (int fd, const void *buf, size_t len)
{
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

static int
xread (int fd, void *buf, size_t len)
{
  int r;

  while (len > 0) {
    r = read (fd, buf, len);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
	continue;
      return -1;
    }

    buf += r;
    len -= r;
  }

  return 0;
}

void
guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb cb)
{
  g->abort_cb = cb;
}

guestfs_abort_cb
guestfs_get_out_of_memory_handler (guestfs_h *g)
{
  return g->abort_cb;
}

void
guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *data)
{
  g->error_cb = cb;
  g->error_cb_data = data;
}

guestfs_error_handler_cb
guestfs_get_error_handler (guestfs_h *g, void **data_rtn)
{
  if (data_rtn) *data_rtn = g->error_cb_data;
  return g->error_cb;
}

int
guestfs_set_verbose (guestfs_h *g, int v)
{
  g->verbose = !!v;
  return 0;
}

int
guestfs_get_verbose (guestfs_h *g)
{
  return g->verbose;
}

int
guestfs_set_autosync (guestfs_h *g, int a)
{
  g->autosync = !!a;
  return 0;
}

int
guestfs_get_autosync (guestfs_h *g)
{
  return g->autosync;
}

int
guestfs_set_path (guestfs_h *g, const char *path)
{
  if (path == NULL)
    g->path = GUESTFS_DEFAULT_PATH;
  else
    g->path = path;
  return 0;
}

const char *
guestfs_get_path (guestfs_h *g)
{
  return g->path;
}

int
guestfs_set_qemu (guestfs_h *g, const char *qemu)
{
  if (qemu == NULL)
    g->qemu = QEMU;
  else
    g->qemu = qemu;
  return 0;
}

const char *
guestfs_get_qemu (guestfs_h *g)
{
  return g->qemu;
}

/* Add a string to the current command line. */
static void
incr_cmdline_size (guestfs_h *g)
{
  if (g->cmdline == NULL) {
    /* g->cmdline[0] is reserved for argv[0], set in guestfs_launch. */
    g->cmdline_size = 1;
    g->cmdline = safe_malloc (g, sizeof (char *));
    g->cmdline[0] = NULL;
  }

  g->cmdline_size++;
  g->cmdline = safe_realloc (g, g->cmdline, sizeof (char *) * g->cmdline_size);
}

static int
add_cmdline (guestfs_h *g, const char *str)
{
  if (g->state != CONFIG) {
    error (g, "command line cannot be altered after qemu subprocess launched");
    return -1;
  }

  incr_cmdline_size (g);
  g->cmdline[g->cmdline_size-1] = safe_strdup (g, str);
  return 0;
}

int
guestfs_config (guestfs_h *g,
		const char *qemu_param, const char *qemu_value)
{
  if (qemu_param[0] != '-') {
    error (g, "guestfs_config: parameter must begin with '-' character");
    return -1;
  }

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
      strcmp (qemu_param, "-vnc") == 0) {
    error (g, "guestfs_config: parameter '%s' isn't allowed", qemu_param);
    return -1;
  }

  if (add_cmdline (g, qemu_param) != 0) return -1;

  if (qemu_value != NULL) {
    if (add_cmdline (g, qemu_value) != 0) return -1;
  }

  return 0;
}

int
guestfs_add_drive (guestfs_h *g, const char *filename)
{
  size_t len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL) {
    error (g, "filename cannot contain ',' (comma) character");
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  snprintf (buf, len, "file=%s", filename);

  return guestfs_config (g, "-drive", buf);
}

int
guestfs_add_cdrom (guestfs_h *g, const char *filename)
{
  if (strchr (filename, ',') != NULL) {
    error (g, "filename cannot contain ',' (comma) character");
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  return guestfs_config (g, "-cdrom", filename);
}

int
guestfs_launch (guestfs_h *g)
{
  static const char *dir_template = "/tmp/libguestfsXXXXXX";
  int r, i, pmore, memsize;
  size_t len;
  int wfd[2], rfd[2];
  int tries;
  const char *kernel_name = "vmlinuz." REPO "." host_cpu;
  const char *initrd_name = "initramfs." REPO "." host_cpu ".img";
  char *path, *pelem, *pend;
  char *kernel = NULL, *initrd = NULL;
  char unixsock[256];
  struct sockaddr_un addr;

  /* Configured? */
  if (!g->cmdline) {
    error (g, "you must call guestfs_add_drive before guestfs_launch");
    return -1;
  }

  if (g->state != CONFIG) {
    error (g, "qemu has already been launched");
    return -1;
  }

  /* Search g->path for the kernel and initrd. */
  pelem = path = safe_strdup (g, g->path);
  do {
    pend = strchrnul (pelem, ':');
    pmore = *pend == ':';
    *pend = '\0';
    len = pend - pelem;

    /* Empty element or "." means cwd. */
    if (len == 0 || (len == 1 && *pelem == '.')) {
      if (g->verbose)
	fprintf (stderr,
		 "looking for kernel and initrd in current directory\n");
      if (access (kernel_name, F_OK) == 0 && access (initrd_name, F_OK) == 0) {
	kernel = safe_strdup (g, kernel_name);
	initrd = safe_strdup (g, initrd_name);
	break;
      }
    }
    /* Look at <path>/kernel etc. */
    else {
      kernel = safe_malloc (g, len + strlen (kernel_name) + 2);
      initrd = safe_malloc (g, len + strlen (initrd_name) + 2);
      sprintf (kernel, "%s/%s", pelem, kernel_name);
      sprintf (initrd, "%s/%s", pelem, initrd_name);

      if (g->verbose)
	fprintf (stderr, "looking for %s and %s\n", kernel, initrd);

      if (access (kernel, F_OK) == 0 && access (initrd, F_OK) == 0)
	break;
      free (kernel);
      free (initrd);
      kernel = initrd = NULL;
    }

    pelem = pend + 1;
  } while (pmore);

  free (path);

  if (kernel == NULL || initrd == NULL) {
    error (g, "cannot find %s or %s on LIBGUESTFS_PATH (current path = %s)",
	   kernel_name, initrd_name, g->path);
    goto cleanup0;
  }

  /* Choose a suitable memory size.  Previously we tried to choose
   * a minimal memory size, but this isn't really necessary since
   * recent QEMU and KVM don't do anything nasty like locking
   * memory into core any more.  This we can safely choose a
   * large, generous amount of memory, and it'll just get swapped
   * on smaller systems.
   */
  memsize = 384;

  /* Make the temporary directory containing the socket. */
  if (!g->tmpdir) {
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, "%s: cannot create temporary directory", dir_template);
      goto cleanup0;
    }
  }

  snprintf (unixsock, sizeof unixsock, "%s/sock", g->tmpdir);
  unlink (unixsock);

  if (pipe (wfd) == -1 || pipe (rfd) == -1) {
    perrorf (g, "pipe");
    goto cleanup0;
  }

  r = fork ();
  if (r == -1) {
    perrorf (g, "fork");
    close (wfd[0]);
    close (wfd[1]);
    close (rfd[0]);
    close (rfd[1]);
    goto cleanup0;
  }

  if (r == 0) {			/* Child (qemu). */
    char vmchannel[256];
    char append[256];
    char memsize_str[256];

    /* Set up the full command line.  Do this in the subprocess so we
     * don't need to worry about cleaning up.
     */
    g->cmdline[0] = (char *) g->qemu;

    /* Construct the -net channel parameter for qemu. */
    snprintf (vmchannel, sizeof vmchannel,
	      "channel,%d:unix:%s,server,nowait",
	      VMCHANNEL_PORT, unixsock);

    /* Linux kernel command line. */
    snprintf (append, sizeof append,
	      "panic=1 console=ttyS0 guestfs=%s:%d%s",
	      VMCHANNEL_ADDR, VMCHANNEL_PORT,
	      g->verbose ? " guestfs_verbose=1" : "");

    snprintf (memsize_str, sizeof memsize_str, "%d", memsize);

    add_cmdline (g, "-m");
    add_cmdline (g, memsize_str);
#if 0
    add_cmdline (g, "-no-kqemu"); /* Avoids a warning. */
#endif
    add_cmdline (g, "-no-reboot"); /* Force exit instead of reboot on panic */
    add_cmdline (g, "-kernel");
    add_cmdline (g, (char *) kernel);
    add_cmdline (g, "-initrd");
    add_cmdline (g, (char *) initrd);
    add_cmdline (g, "-append");
    add_cmdline (g, append);
    add_cmdline (g, "-nographic");
    add_cmdline (g, "-serial");
    add_cmdline (g, "stdio");
    add_cmdline (g, "-net");
    add_cmdline (g, vmchannel);
    add_cmdline (g, "-net");
    add_cmdline (g, "user,vlan=0");
    add_cmdline (g, "-net");
    add_cmdline (g, "nic,model=virtio,vlan=0");
    incr_cmdline_size (g);
    g->cmdline[g->cmdline_size-1] = NULL;

    if (g->verbose) {
      fprintf (stderr, "%s", g->qemu);
      for (i = 0; g->cmdline[i]; ++i)
	fprintf (stderr, " %s", g->cmdline[i]);
      fprintf (stderr, "\n");
    }

    /* Set up stdin, stdout. */
    close (0);
    close (1);
    close (wfd[1]);
    close (rfd[0]);
    dup (wfd[0]);
    dup (rfd[1]);
    close (wfd[0]);
    close (rfd[1]);

#if 0
    /* Set up a new process group, so we can signal this process
     * and all subprocesses (eg. if qemu is really a shell script).
     */
    setpgid (0, 0);
#endif

    execv (g->qemu, g->cmdline); /* Run qemu. */
    perror (g->qemu);
    _exit (1);
  }

  /* Parent (library). */
  g->pid = r;

  free (kernel);
  kernel = NULL;
  free (initrd);
  initrd = NULL;

  /* Fork the recovery process off which will kill qemu if the parent
   * process fails to do so (eg. if the parent segfaults).
   */
  r = fork ();
  if (r == 0) {
    pid_t qemu_pid = g->pid;
    pid_t parent_pid = getppid ();

    /* Writing to argv is hideously complicated and error prone.  See:
     * http://anoncvs.postgresql.org/cvsweb.cgi/pgsql/src/backend/utils/misc/ps_status.c?rev=1.33.2.1;content-type=text%2Fplain
     */

    /* Loop around waiting for one or both of the other processes to
     * disappear.  It's fair to say this is very hairy.  The PIDs that
     * we are looking at might be reused by another process.  We are
     * effectively polling.  Is the cure worse than the disease?
     */
    for (;;) {
      if (kill (qemu_pid, 0) == -1) /* qemu's gone away, we aren't needed */
	_exit (0);
      if (kill (parent_pid, 0) == -1) {
	/* Parent's gone away, qemu still around, so kill qemu. */
	kill (qemu_pid, 9);
	_exit (0);
      }
      sleep (2);
    }
  }

  /* Don't worry, if the fork failed, this will be -1.  The recovery
   * process isn't essential.
   */
  g->recoverypid = r;

  /* Start the clock ... */
  time (&g->start_t);

  /* Close the other ends of the pipe. */
  close (wfd[0]);
  close (rfd[1]);

  if (fcntl (wfd[1], F_SETFL, O_NONBLOCK) == -1 ||
      fcntl (rfd[0], F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup1;
  }

  g->fd[0] = wfd[1];		/* stdin of child */
  g->fd[1] = rfd[0];		/* stdout of child */

  /* Open the Unix socket.  The vmchannel implementation that got
   * merged with qemu sucks in a number of ways.  Both ends do
   * connect(2), which means that no one knows what, if anything, is
   * connected to the other end, or if it becomes disconnected.  Even
   * worse, we have to wait some indeterminate time for qemu to create
   * the socket and connect to it (which happens very early in qemu's
   * start-up), so any code that uses vmchannel is inherently racy.
   * Hence this silly loop.
   */
  g->sock = socket (AF_UNIX, SOCK_STREAM, 0);
  if (g->sock == -1) {
    perrorf (g, "socket");
    goto cleanup1;
  }

  if (fcntl (g->sock, F_SETFL, O_NONBLOCK) == -1) {
    perrorf (g, "fcntl");
    goto cleanup2;
  }

  addr.sun_family = AF_UNIX;
  strncpy (addr.sun_path, unixsock, UNIX_PATH_MAX);
  addr.sun_path[UNIX_PATH_MAX-1] = '\0';

  tries = 100;
  /* Always sleep at least once to give qemu a small chance to start up. */
  usleep (10000);
  while (tries > 0) {
    r = connect (g->sock, (struct sockaddr *) &addr, sizeof addr);
    if ((r == -1 && errno == EINPROGRESS) || r == 0)
      goto connected;

    if (errno != ENOENT)
      perrorf (g, "connect");
    tries--;
    usleep (100000);
  }

  error (g, "failed to connect to vmchannel socket");
  goto cleanup2;

 connected:
  /* Watch the file descriptors. */
  free (g->msg_in);
  g->msg_in = NULL;
  g->msg_in_size = g->msg_in_allocated = 0;

  free (g->msg_out);
  g->msg_out = NULL;
  g->msg_out_size = 0;
  g->msg_out_pos = 0;

  g->stdout_watch =
    g->main_loop->add_handle (g->main_loop, g, g->fd[1],
			      GUESTFS_HANDLE_READABLE,
			      stdout_event, NULL);
  if (g->stdout_watch == -1) {
    error (g, "could not watch qemu stdout");
    goto cleanup3;
  }

  if (guestfs__switch_to_receiving (g) == -1)
    goto cleanup3;

  g->state = LAUNCHING;
  return 0;

 cleanup3:
  if (g->stdout_watch >= 0)
    g->main_loop->remove_handle (g->main_loop, g, g->stdout_watch);
  if (g->sock_watch >= 0)
    g->main_loop->remove_handle (g->main_loop, g, g->sock_watch);

 cleanup2:
  close (g->sock);

 cleanup1:
  close (wfd[1]);
  close (rfd[0]);
  kill (g->pid, 9);
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;
  g->pid = 0;
  g->recoverypid = 0;
  g->start_t = 0;
  g->stdout_watch = -1;
  g->sock_watch = -1;

 cleanup0:
  free (kernel);
  free (initrd);
  return -1;
}

static void
finish_wait_ready (guestfs_h *g, void *vp)
{
  if (g->verbose)
    fprintf (stderr, "finish_wait_ready called, %p, vp = %p\n", g, vp);

  *((int *)vp) = 1;
  g->main_loop->main_loop_quit (g->main_loop, g);
}

int
guestfs_wait_ready (guestfs_h *g)
{
  int finished = 0, r;

  if (g->state == READY) return 0;

  if (g->state == BUSY) {
    error (g, "qemu has finished launching already");
    return -1;
  }

  if (g->state != LAUNCHING) {
    error (g, "qemu has not been launched yet");
    return -1;
  }

  g->launch_done_cb = finish_wait_ready;
  g->launch_done_cb_data = &finished;
  r = g->main_loop->main_loop_run (g->main_loop, g);
  g->launch_done_cb = NULL;
  g->launch_done_cb_data = NULL;

  if (r == -1) return -1;

  if (finished != 1) {
    error (g, "guestfs_wait_ready failed, see earlier error messages");
    return -1;
  }

  /* This is possible in some really strange situations, such as
   * guestfsd starts up OK but then qemu immediately exits.  Check for
   * it because the caller is probably expecting to be able to send
   * commands after this function returns.
   */
  if (g->state != READY) {
    error (g, "qemu launched and contacted daemon, but state != READY");
    return -1;
  }

  return 0;
}

int
guestfs_kill_subprocess (guestfs_h *g)
{
  if (g->state == CONFIG) {
    error (g, "no subprocess to kill");
    return -1;
  }

  if (g->verbose)
    fprintf (stderr, "sending SIGTERM to process %d\n", g->pid);

  kill (g->pid, SIGTERM);
  if (g->recoverypid > 0) kill (g->recoverypid, 9);

  return 0;
}

/* Access current state. */
int
guestfs_is_config (guestfs_h *g)
{
  return g->state == CONFIG;
}

int
guestfs_is_launching (guestfs_h *g)
{
  return g->state == LAUNCHING;
}

int
guestfs_is_ready (guestfs_h *g)
{
  return g->state == READY;
}

int
guestfs_is_busy (guestfs_h *g)
{
  return g->state == BUSY;
}

int
guestfs_get_state (guestfs_h *g)
{
  return g->state;
}

int
guestfs_set_ready (guestfs_h *g)
{
  if (g->state != BUSY) {
    error (g, "guestfs_set_ready: called when in state %d != BUSY", g->state);
    return -1;
  }
  g->state = READY;
  return 0;
}

int
guestfs_set_busy (guestfs_h *g)
{
  if (g->state != READY) {
    error (g, "guestfs_set_busy: called when in state %d != READY", g->state);
    return -1;
  }
  g->state = BUSY;
  return 0;
}

int
guestfs_end_busy (guestfs_h *g)
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
      error (g, "guestfs_end_busy: called when in state %d", g->state);
      return -1;
    }
  return 0;
}

/* Structure-freeing functions.  These rely on the fact that the
 * structure format is identical to the XDR format.  See note in
 * generator.ml.
 */
void
guestfs_free_int_bool (struct guestfs_int_bool *x)
{
  free (x);
}

void
guestfs_free_lvm_pv_list (struct guestfs_lvm_pv_list *x)
{
  xdr_free ((xdrproc_t) xdr_guestfs_lvm_int_pv_list, (char *) x);
  free (x);
}

void
guestfs_free_lvm_vg_list (struct guestfs_lvm_vg_list *x)
{
  xdr_free ((xdrproc_t) xdr_guestfs_lvm_int_vg_list, (char *) x);
  free (x);
}

void
guestfs_free_lvm_lv_list (struct guestfs_lvm_lv_list *x)
{
  xdr_free ((xdrproc_t) xdr_guestfs_lvm_int_lv_list, (char *) x);
  free (x);
}

/* We don't know if stdout_event or sock_read_event will be the
 * first to receive EOF if the qemu process dies.  This function
 * has the common cleanup code for both.
 */
static void
child_cleanup (guestfs_h *g)
{
  if (g->verbose)
    fprintf (stderr, "stdout_event: %p: child process died\n", g);
  /*kill (g->pid, SIGTERM);*/
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);
  if (g->stdout_watch >= 0)
    g->main_loop->remove_handle (g->main_loop, g, g->stdout_watch);
  if (g->sock_watch >= 0)
    g->main_loop->remove_handle (g->main_loop, g, g->sock_watch);
  close (g->fd[0]);
  close (g->fd[1]);
  close (g->sock);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;
  g->pid = 0;
  g->recoverypid = 0;
  g->start_t = 0;
  g->stdout_watch = -1;
  g->sock_watch = -1;
  g->state = CONFIG;
  if (g->subprocess_quit_cb)
    g->subprocess_quit_cb (g, g->subprocess_quit_cb_data);
}

/* This function is called whenever qemu prints something on stdout.
 * Qemu's stdout is also connected to the guest's serial console, so
 * we see kernel messages here too.
 */
static void
stdout_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data,
	      int watch, int fd, int events)
{
  char buf[4096];
  int n;

#if 0
  if (g->verbose)
    fprintf (stderr,
	     "stdout_event: %p g->state = %d, fd = %d, events = 0x%x\n",
	     g, g->state, fd, events);
#endif

  if (g->fd[1] != fd) {
    error (g, "stdout_event: internal error: %d != %d", g->fd[1], fd);
    return;
  }

  n = read (fd, buf, sizeof buf);
  if (n == 0) {
    /* Hopefully this indicates the qemu child process has died. */
    child_cleanup (g);
    return;
  }

  if (n == -1) {
    if (errno != EINTR && errno != EAGAIN)
      perrorf (g, "read");
    return;
  }

  /* In verbose mode, copy all log messages to stderr. */
  if (g->verbose)
    write (2, buf, n);

  /* It's an actual log message, send it upwards if anyone is listening. */
  if (g->log_message_cb)
    g->log_message_cb (g, g->log_message_cb_data, buf, n);
}

/* The function is called whenever we can read something on the
 * guestfsd (daemon inside the guest) communication socket.
 */
static void
sock_read_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data,
		 int watch, int fd, int events)
{
  XDR xdr;
  u_int32_t len;
  int n;

  if (g->verbose)
    fprintf (stderr,
	     "sock_read_event: %p g->state = %d, fd = %d, events = 0x%x\n",
	     g, g->state, fd, events);

  if (g->sock != fd) {
    error (g, "sock_read_event: internal error: %d != %d", g->sock, fd);
    return;
  }

  if (g->msg_in_size <= g->msg_in_allocated) {
    g->msg_in_allocated += 4096;
    g->msg_in = safe_realloc (g, g->msg_in, g->msg_in_allocated);
  }
  n = read (g->sock, g->msg_in + g->msg_in_size,
	    g->msg_in_allocated - g->msg_in_size);
  if (n == 0) {
    /* Disconnected. */
    child_cleanup (g);
    return;
  }

  if (n == -1) {
    if (errno != EINTR && errno != EAGAIN)
      perrorf (g, "read");
    return;
  }

  g->msg_in_size += n;

  /* Have we got enough of a message to be able to process it yet? */
 again:
  if (g->msg_in_size < 4) return;

  xdrmem_create (&xdr, g->msg_in, g->msg_in_size, XDR_DECODE);
  if (!xdr_uint32_t (&xdr, &len)) {
    error (g, "can't decode length word");
    goto cleanup;
  }

  /* Length is normally the length of the message, but when guestfsd
   * starts up it sends a "magic" value (longer than any possible
   * message).  Check for this.
   */
  if (len == GUESTFS_LAUNCH_FLAG) {
    if (g->state != LAUNCHING)
      error (g, "received magic signature from guestfsd, but in state %d",
	     g->state);
    else if (g->msg_in_size != 4)
      error (g, "received magic signature from guestfsd, but msg size is %d",
	     g->msg_in_size);
    else {
      g->state = READY;
      if (g->launch_done_cb)
	g->launch_done_cb (g, g->launch_done_cb_data);
    }

    goto cleanup;
  }

  /* This can happen if a cancellation happens right at the end
   * of us sending a FileIn parameter to the daemon.  Discard.  The
   * daemon should send us an error message next.
   */
  if (len == GUESTFS_CANCEL_FLAG) {
    g->msg_in_size -= 4;
    memmove (g->msg_in, g->msg_in+4, g->msg_in_size);
    goto again;
  }

  /* If this happens, it's pretty bad and we've probably lost
   * synchronization.
   */
  if (len > GUESTFS_MESSAGE_MAX) {
    error (g, "message length (%u) > maximum possible size (%d)",
	   len, GUESTFS_MESSAGE_MAX);
    goto cleanup;
  }

  if (g->msg_in_size-4 < len) return; /* Need more of this message. */

  /* Got the full message, begin processing it. */
#if 0
  if (g->verbose) {
    int i, j;

    for (i = 0; i < g->msg_in_size; i += 16) {
      printf ("%04x: ", i);
      for (j = i; j < MIN (i+16, g->msg_in_size); ++j)
	printf ("%02x ", (unsigned char) g->msg_in[j]);
      for (; j < i+16; ++j)
	printf ("   ");
      printf ("|");
      for (j = i; j < MIN (i+16, g->msg_in_size); ++j)
	if (isprint (g->msg_in[j]))
	  printf ("%c", g->msg_in[j]);
	else
	  printf (".");
      for (; j < i+16; ++j)
	printf (" ");
      printf ("|\n");
    }
  }
#endif

  /* Not in the expected state. */
  if (g->state != BUSY)
    error (g, "state %d != BUSY", g->state);

  /* Push the message up to the higher layer. */
  if (g->reply_cb)
    g->reply_cb (g, g->reply_cb_data, &xdr);
  else
    /* This message (probably) should never be printed. */
    fprintf (stderr, "libguesfs: sock_read_event: !!! dropped message !!!\n");

  g->msg_in_size -= len + 4;
  memmove (g->msg_in, g->msg_in+len+4, g->msg_in_size);
  if (g->msg_in_size > 0) goto again;

 cleanup:
  /* Free the message buffer if it's grown excessively large. */
  if (g->msg_in_allocated > 65536) {
    free (g->msg_in);
    g->msg_in = NULL;
    g->msg_in_size = g->msg_in_allocated = 0;
  } else
    g->msg_in_size = 0;

  xdr_destroy (&xdr);
}

/* The function is called whenever we can write something on the
 * guestfsd (daemon inside the guest) communication socket.
 */
static void
sock_write_event (struct guestfs_main_loop *ml, guestfs_h *g, void *data,
		  int watch, int fd, int events)
{
  int n;

  if (g->verbose)
    fprintf (stderr,
	     "sock_write_event: %p g->state = %d, fd = %d, events = 0x%x\n",
	     g, g->state, fd, events);

  if (g->sock != fd) {
    error (g, "sock_write_event: internal error: %d != %d", g->sock, fd);
    return;
  }

  if (g->state != BUSY) {
    error (g, "sock_write_event: state %d != BUSY", g->state);
    return;
  }

  if (g->verbose)
    fprintf (stderr, "sock_write_event: writing %d bytes ...\n",
	     g->msg_out_size - g->msg_out_pos);

  n = write (g->sock, g->msg_out + g->msg_out_pos,
	     g->msg_out_size - g->msg_out_pos);
  if (n == -1) {
    if (errno != EAGAIN)
      perrorf (g, "write");
    return;
  }

  if (g->verbose)
    fprintf (stderr, "sock_write_event: wrote %d bytes\n", n);

  g->msg_out_pos += n;

  /* More to write? */
  if (g->msg_out_pos < g->msg_out_size)
    return;

  if (g->verbose)
    fprintf (stderr, "sock_write_event: done writing, calling send_cb\n");

  free (g->msg_out);
  g->msg_out = NULL;
  g->msg_out_pos = g->msg_out_size = 0;

  /* Done writing, call the higher layer. */
  if (g->send_cb)
    g->send_cb (g, g->send_cb_data);
}

void
guestfs_set_send_callback (guestfs_h *g,
			   guestfs_send_cb cb, void *opaque)
{
  g->send_cb = cb;
  g->send_cb_data = opaque;
}

void
guestfs_set_reply_callback (guestfs_h *g,
			    guestfs_reply_cb cb, void *opaque)
{
  g->reply_cb = cb;
  g->reply_cb_data = opaque;
}

void
guestfs_set_log_message_callback (guestfs_h *g,
				  guestfs_log_message_cb cb, void *opaque)
{
  g->log_message_cb = cb;
  g->log_message_cb_data = opaque;
}

void
guestfs_set_subprocess_quit_callback (guestfs_h *g,
				      guestfs_subprocess_quit_cb cb, void *opaque)
{
  g->subprocess_quit_cb = cb;
  g->subprocess_quit_cb_data = opaque;
}

void
guestfs_set_launch_done_callback (guestfs_h *g,
				  guestfs_launch_done_cb cb, void *opaque)
{
  g->launch_done_cb = cb;
  g->launch_done_cb_data = opaque;
}

/* Access to the handle's main loop and the default main loop. */
void
guestfs_set_main_loop (guestfs_h *g, guestfs_main_loop *main_loop)
{
  g->main_loop = main_loop;
}

guestfs_main_loop *
guestfs_get_main_loop (guestfs_h *g)
{
  return g->main_loop;
}

guestfs_main_loop *
guestfs_get_default_main_loop (void)
{
  return (guestfs_main_loop *) &default_main_loop;
}

/* Change the daemon socket handler so that we are now writing.
 * This sets the handle to sock_write_event.
 */
int
guestfs__switch_to_sending (guestfs_h *g)
{
  if (g->sock_watch >= 0) {
    if (g->main_loop->remove_handle (g->main_loop, g, g->sock_watch) == -1) {
      error (g, "remove_handle failed");
      g->sock_watch = -1;
      return -1;
    }
  }

  g->sock_watch =
    g->main_loop->add_handle (g->main_loop, g, g->sock,
			      GUESTFS_HANDLE_WRITABLE,
			      sock_write_event, NULL);
  if (g->sock_watch == -1) {
    error (g, "add_handle failed");
    return -1;
  }

  return 0;
}

int
guestfs__switch_to_receiving (guestfs_h *g)
{
  if (g->sock_watch >= 0) {
    if (g->main_loop->remove_handle (g->main_loop, g, g->sock_watch) == -1) {
      error (g, "remove_handle failed");
      g->sock_watch = -1;
      return -1;
    }
  }

  g->sock_watch =
    g->main_loop->add_handle (g->main_loop, g, g->sock,
			      GUESTFS_HANDLE_READABLE,
			      sock_read_event, NULL);
  if (g->sock_watch == -1) {
    error (g, "add_handle failed");
    return -1;
  }

  return 0;
}

/* Dispatch a call (len + header + args) to the remote daemon,
 * synchronously (ie. using the guest's main loop to wait until
 * it has been sent).  Returns -1 for error, or the serial
 * number of the message.
 */
static void
send_cb (guestfs_h *g, void *data)
{
  guestfs_main_loop *ml = guestfs_get_main_loop (g);

  *((int *)data) = 1;
  ml->main_loop_quit (ml, g);
}

int
guestfs__send_sync (guestfs_h *g, int proc_nr,
		    xdrproc_t xdrp, char *args)
{
  struct guestfs_message_header hdr;
  XDR xdr;
  u_int32_t len;
  int serial = g->msg_next_serial++;
  int sent;
  guestfs_main_loop *ml = guestfs_get_main_loop (g);

  if (g->state != BUSY) {
    error (g, "guestfs__send_sync: state %d != BUSY", g->state);
    return -1;
  }

  /* This is probably an internal error.  Or perhaps we should just
   * free the buffer anyway?
   */
  if (g->msg_out != NULL) {
    error (g, "guestfs__send_sync: msg_out should be NULL");
    return -1;
  }

  /* We have to allocate this message buffer on the heap because
   * it is quite large (although will be mostly unused).  We
   * can't allocate it on the stack because in some environments
   * we have quite limited stack space available, notably when
   * running in the JVM.
   */
  g->msg_out = safe_malloc (g, GUESTFS_MESSAGE_MAX + 4);
  xdrmem_create (&xdr, g->msg_out + 4, GUESTFS_MESSAGE_MAX, XDR_ENCODE);

  /* Serialize the header. */
  hdr.prog = GUESTFS_PROGRAM;
  hdr.vers = GUESTFS_PROTOCOL_VERSION;
  hdr.proc = proc_nr;
  hdr.direction = GUESTFS_DIRECTION_CALL;
  hdr.serial = serial;
  hdr.status = GUESTFS_STATUS_OK;

  if (!xdr_guestfs_message_header (&xdr, &hdr)) {
    error (g, "xdr_guestfs_message_header failed");
    goto cleanup1;
  }

  /* Serialize the args.  If any, because some message types
   * have no parameters.
   */
  if (xdrp) {
    if (!(*xdrp) (&xdr, args)) {
      error (g, "dispatch failed to marshal args");
      goto cleanup1;
    }
  }

  /* Get the actual length of the message, resize the buffer to match
   * the actual length, and write the length word at the beginning.
   */
  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  g->msg_out = safe_realloc (g, g->msg_out, len + 4);
  g->msg_out_size = len + 4;
  g->msg_out_pos = 0;

  xdrmem_create (&xdr, g->msg_out, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);

  if (guestfs__switch_to_sending (g) == -1)
    goto cleanup1;

  sent = 0;
  guestfs_set_send_callback (g, send_cb, &sent);
  if (ml->main_loop_run (ml, g) == -1)
    goto cleanup1;
  if (sent != 1) {
    error (g, "send failed, see earlier error messages");
    goto cleanup1;
  }

  return serial;

 cleanup1:
  free (g->msg_out);
  g->msg_out = NULL;
  g->msg_out_size = 0;
  return -1;
}

static int cancel = 0; /* XXX Implement file cancellation. */
static int send_file_chunk_sync (guestfs_h *g, int cancel, const char *buf, size_t len);
static int send_file_data_sync (guestfs_h *g, const char *buf, size_t len);
static int send_file_cancellation_sync (guestfs_h *g);
static int send_file_complete_sync (guestfs_h *g);

/* Synchronously send a file.
 * Returns:
 *   0 OK
 *   -1 error
 *   -2 daemon cancelled (we must read the error message)
 */
int
guestfs__send_file_sync (guestfs_h *g, const char *filename)
{
  char buf[GUESTFS_MAX_CHUNK_SIZE];
  int fd, r, err;

  fd = open (filename, O_RDONLY);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    send_file_cancellation_sync (g);
    /* Daemon sees cancellation and won't reply, so caller can
     * just return here.
     */
    return -1;
  }

  /* Send file in chunked encoding. */
  while (!cancel) {
    r = read (fd, buf, sizeof buf);
    if (r == -1 && (errno == EINTR || errno == EAGAIN))
      continue;
    if (r <= 0) break;
    err = send_file_data_sync (g, buf, r);
    if (err < 0) {
      if (err == -2)		/* daemon sent cancellation */
	send_file_cancellation_sync (g);
      return err;
    }
  }

  if (cancel) {			/* cancel from either end */
    send_file_cancellation_sync (g);
    return -1;
  }

  if (r == -1) {
    perrorf (g, "read: %s", filename);
    send_file_cancellation_sync (g);
    return -1;
  }

  /* End of file, but before we send that, we need to close
   * the file and check for errors.
   */
  if (close (fd) == -1) {
    perrorf (g, "close: %s", filename);
    send_file_cancellation_sync (g);
    return -1;
  }

  return send_file_complete_sync (g);
}

/* Send a chunk of file data. */
static int
send_file_data_sync (guestfs_h *g, const char *buf, size_t len)
{
  return send_file_chunk_sync (g, 0, buf, len);
}

/* Send a cancellation message. */
static int
send_file_cancellation_sync (guestfs_h *g)
{
  return send_file_chunk_sync (g, 1, NULL, 0);
}

/* Send a file complete chunk. */
static int
send_file_complete_sync (guestfs_h *g)
{
  char buf[1];
  return send_file_chunk_sync (g, 0, buf, 0);
}

/* Send a chunk, cancellation or end of file, synchronously (ie. wait
 * for it to go).
 */
static int check_for_daemon_cancellation (guestfs_h *g);

static int
send_file_chunk_sync (guestfs_h *g, int cancel, const char *buf, size_t buflen)
{
  u_int32_t len;
  int sent;
  guestfs_chunk chunk;
  XDR xdr;
  guestfs_main_loop *ml = guestfs_get_main_loop (g);

  if (g->state != BUSY) {
    error (g, "send_file_chunk_sync: state %d != READY", g->state);
    return -1;
  }

  /* This is probably an internal error.  Or perhaps we should just
   * free the buffer anyway?
   */
  if (g->msg_out != NULL) {
    error (g, "guestfs__send_sync: msg_out should be NULL");
    return -1;
  }

  /* Did the daemon send a cancellation message? */
  if (check_for_daemon_cancellation (g)) {
    if (g->verbose)
      fprintf (stderr, "got daemon cancellation\n");
    return -2;
  }

  /* Allocate the chunk buffer.  Don't use the stack to avoid
   * excessive stack usage and unnecessary copies.
   */
  g->msg_out = safe_malloc (g, GUESTFS_MAX_CHUNK_SIZE + 4 + 48);
  xdrmem_create (&xdr, g->msg_out + 4, GUESTFS_MAX_CHUNK_SIZE + 48, XDR_ENCODE);

  /* Serialize the chunk. */
  chunk.cancel = cancel;
  chunk.data.data_len = buflen;
  chunk.data.data_val = (char *) buf;

  if (!xdr_guestfs_chunk (&xdr, &chunk)) {
    error (g, "xdr_guestfs_chunk failed (buf = %p, buflen = %zu)",
	   buf, buflen);
    xdr_destroy (&xdr);
    goto cleanup1;
  }

  len = xdr_getpos (&xdr);
  xdr_destroy (&xdr);

  /* Reduce the size of the outgoing message buffer to the real length. */
  g->msg_out = safe_realloc (g, g->msg_out, len + 4);
  g->msg_out_size = len + 4;
  g->msg_out_pos = 0;

  xdrmem_create (&xdr, g->msg_out, 4, XDR_ENCODE);
  xdr_uint32_t (&xdr, &len);

  if (guestfs__switch_to_sending (g) == -1)
    goto cleanup1;

  sent = 0;
  guestfs_set_send_callback (g, send_cb, &sent);
  if (ml->main_loop_run (ml, g) == -1)
    goto cleanup1;
  if (sent != 1) {
    error (g, "send file chunk failed, see earlier error messages");
    goto cleanup1;
  }

  return 0;

 cleanup1:
  free (g->msg_out);
  g->msg_out = NULL;
  g->msg_out_size = 0;
  return -1;
}

/* At this point we are sending FileIn file(s) to the guest, and not
 * expecting to read anything, so if we do read anything, it must be
 * a cancellation message.  This checks for this case without blocking.
 */
static int
check_for_daemon_cancellation (guestfs_h *g)
{
  fd_set rset;
  struct timeval tv;
  int r;
  char buf[4];
  uint32_t flag;
  XDR xdr;

  FD_ZERO (&rset);
  FD_SET (g->sock, &rset);
  tv.tv_sec = 0;
  tv.tv_usec = 0;
  r = select (g->sock+1, &rset, NULL, NULL, &tv);
  if (r == -1) {
    perrorf (g, "select");
    return 0;
  }
  if (r == 0)
    return 0;

  /* Read the message from the daemon. */
  r = xread (g->sock, buf, sizeof buf);
  if (r == -1) {
    perrorf (g, "read");
    return 0;
  }

  xdrmem_create (&xdr, buf, sizeof buf, XDR_DECODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

  if (flag != GUESTFS_CANCEL_FLAG) {
    error (g, "check_for_daemon_cancellation: read 0x%x from daemon, expected 0x%x\n",
	   flag, GUESTFS_CANCEL_FLAG);
    return 0;
  }

  return 1;
}

/* Synchronously receive a file. */

/* Returns -1 = error, 0 = EOF, 1 = more data */
static int receive_file_data_sync (guestfs_h *g, void **buf, size_t *len);

int
guestfs__receive_file_sync (guestfs_h *g, const char *filename)
{
  void *buf;
  int fd, r;
  size_t len;

  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    goto cancel;
  }

  /* Receive the file in chunked encoding. */
  while ((r = receive_file_data_sync (g, &buf, &len)) >= 0) {
    if (xwrite (fd, buf, len) == -1) {
      perrorf (g, "%s: write", filename);
      free (buf);
      goto cancel;
    }
    free (buf);
    if (r == 0) break; /* End of file. */
  }

  if (r == -1) {
    error (g, "%s: error in chunked encoding", filename);
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

  xdrmem_create (&xdr, fbuf, sizeof fbuf, XDR_ENCODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

  if (xwrite (g->sock, fbuf, sizeof fbuf) == -1) {
    perrorf (g, "write to daemon socket");
    return -1;
  }

  while ((r = receive_file_data_sync (g, NULL, NULL)) > 0)
    ;				/* just discard it */

  return -1;
}

/* Note that the reply callback can be called multiple times before
 * the main loop quits and we get back to the synchronous code.  So
 * we have to be prepared to save multiple chunks on a list here.
 */
struct receive_file_ctx {
  int count;			/* 0 if receive_file_cb not called, or
				 * else count number of chunks.
				 */
  guestfs_chunk *chunks;	/* Array of chunks. */
};

static void
free_chunks (struct receive_file_ctx *ctx)
{
  int i;

  for (i = 0; i < ctx->count; ++i)
    free (ctx->chunks[i].data.data_val);

  free (ctx->chunks);
}

static void
receive_file_cb (guestfs_h *g, void *data, XDR *xdr)
{
  guestfs_main_loop *ml = guestfs_get_main_loop (g);
  struct receive_file_ctx *ctx = (struct receive_file_ctx *) data;
  guestfs_chunk chunk;

  if (ctx->count == -1)		/* Parse error occurred previously. */
    return;

  ml->main_loop_quit (ml, g);

  memset (&chunk, 0, sizeof chunk);

  if (!xdr_guestfs_chunk (xdr, &chunk)) {
    error (g, "failed to parse file chunk");
    free_chunks (ctx);
    ctx->chunks = NULL;
    ctx->count = -1;
    return;
  }

  /* Copy the chunk to the list. */
  ctx->chunks = safe_realloc (g, ctx->chunks,
			      sizeof (guestfs_chunk) * (ctx->count+1));
  ctx->chunks[ctx->count] = chunk;
  ctx->count++;
}

/* Receive a chunk of file data. */
/* Returns -1 = error, 0 = EOF, 1 = more data */
static int
receive_file_data_sync (guestfs_h *g, void **buf, size_t *len_r)
{
  struct receive_file_ctx ctx;
  guestfs_main_loop *ml = guestfs_get_main_loop (g);
  int i;
  size_t len;

  ctx.count = 0;
  ctx.chunks = NULL;

  guestfs_set_reply_callback (g, receive_file_cb, &ctx);
  (void) ml->main_loop_run (ml, g);
  guestfs_set_reply_callback (g, NULL, NULL);

  if (ctx.count == 0) {
    error (g, "receive_file_data_sync: reply callback not called\n");
    return -1;
  }

  if (ctx.count == -1) {
    error (g, "receive_file_data_sync: parse error in reply callback\n");
    /* callback already freed the chunks */
    return -1;
  }

  if (g->verbose)
    fprintf (stderr, "receive_file_data_sync: got %d chunks\n", ctx.count);

  /* Process each chunk in the list. */
  if (buf) *buf = NULL;		/* Accumulate data in this buffer. */
  len = 0;

  for (i = 0; i < ctx.count; ++i) {
    if (ctx.chunks[i].cancel) {
      error (g, "file receive cancelled by daemon");
      free_chunks (&ctx);
      if (buf) free (*buf);
      if (len_r) *len_r = 0;
      return -1;
    }

    if (ctx.chunks[i].data.data_len == 0) { /* end of transfer */
      free_chunks (&ctx);
      if (len_r) *len_r = len;
      return 0;
    }

    if (buf) {
      *buf = safe_realloc (g, *buf, len + ctx.chunks[i].data.data_len);
      memcpy (*buf+len, ctx.chunks[i].data.data_val,
	      ctx.chunks[i].data.data_len);
    }
    len += ctx.chunks[i].data.data_len;
  }

  if (len_r) *len_r = len;
  free_chunks (&ctx);
  return 1;
}

/* This is the default main loop implementation, using select(2). */

static int
select_add_handle (guestfs_main_loop *mlv, guestfs_h *g, int fd, int events,
		   guestfs_handle_event_cb cb, void *data)
{
  struct select_main_loop *ml = (struct select_main_loop *) mlv;

  if (fd < 0 || fd >= FD_SETSIZE) {
    error (g, "fd %d is out of range", fd);
    return -1;
  }

  if ((events & ~(GUESTFS_HANDLE_READABLE |
		  GUESTFS_HANDLE_WRITABLE |
		  GUESTFS_HANDLE_HANGUP |
		  GUESTFS_HANDLE_ERROR)) != 0) {
    error (g, "set of events (0x%x) contains unknown events", events);
    return -1;
  }

  if (events == 0) {
    error (g, "set of events is empty");
    return -1;
  }

  if (FD_ISSET (fd, &ml->rset) ||
      FD_ISSET (fd, &ml->wset) ||
      FD_ISSET (fd, &ml->xset)) {
    error (g, "fd %d is already registered", fd);
    return -1;
  }

  if (cb == NULL) {
    error (g, "callback is NULL");
    return -1;
  }

  if ((events & GUESTFS_HANDLE_READABLE))
    FD_SET (fd, &ml->rset);
  if ((events & GUESTFS_HANDLE_WRITABLE))
    FD_SET (fd, &ml->wset);
  if ((events & GUESTFS_HANDLE_HANGUP) || (events & GUESTFS_HANDLE_ERROR))
    FD_SET (fd, &ml->xset);

  if (fd > ml->max_fd) {
    ml->max_fd = fd;
    ml->handle_cb_data =
      safe_realloc (g, ml->handle_cb_data,
		    sizeof (struct select_handle_cb_data) * (ml->max_fd+1));
  }
  ml->handle_cb_data[fd].cb = cb;
  ml->handle_cb_data[fd].g = g;
  ml->handle_cb_data[fd].data = data;

  ml->nr_fds++;

  /* Any integer >= 0 can be the handle, and this is as good as any ... */
  return fd;
}

static int
select_remove_handle (guestfs_main_loop *mlv, guestfs_h *g, int fd)
{
  struct select_main_loop *ml = (struct select_main_loop *) mlv;

  if (fd < 0 || fd >= FD_SETSIZE) {
    error (g, "fd %d is out of range", fd);
    return -1;
  }

  if (!FD_ISSET (fd, &ml->rset) &&
      !FD_ISSET (fd, &ml->wset) &&
      !FD_ISSET (fd, &ml->xset)) {
    error (g, "fd %d was not registered", fd);
    return -1;
  }

  FD_CLR (fd, &ml->rset);
  FD_CLR (fd, &ml->wset);
  FD_CLR (fd, &ml->xset);

  if (fd == ml->max_fd) {
    ml->max_fd--;
    ml->handle_cb_data =
      safe_realloc (g, ml->handle_cb_data,
		    sizeof (struct select_handle_cb_data) * (ml->max_fd+1));
  }

  ml->nr_fds--;

  return 0;
}

static int
select_add_timeout (guestfs_main_loop *mlv, guestfs_h *g, int interval,
		    guestfs_handle_timeout_cb cb, void *data)
{
  //struct select_main_loop *ml = (struct select_main_loop *) mlv;

  abort ();			/* XXX not implemented yet */
}

static int
select_remove_timeout (guestfs_main_loop *mlv, guestfs_h *g, int timer)
{
  //struct select_main_loop *ml = (struct select_main_loop *) mlv;

  abort ();			/* XXX not implemented yet */
}

/* The 'g' parameter is just used for error reporting.  Events
 * for multiple handles can be dispatched by running the main
 * loop.
 */
static int
select_main_loop_run (guestfs_main_loop *mlv, guestfs_h *g)
{
  struct select_main_loop *ml = (struct select_main_loop *) mlv;
  int fd, r, events;
  fd_set rset2, wset2, xset2;

  if (ml->is_running) {
    error (g, "select_main_loop_run: this cannot be called recursively");
    return -1;
  }

  ml->is_running = 1;

  while (ml->is_running) {
    if (ml->nr_fds == 0)
      break;

    rset2 = ml->rset;
    wset2 = ml->wset;
    xset2 = ml->xset;
    r = select (ml->max_fd+1, &rset2, &wset2, &xset2, NULL);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
	continue;
      perrorf (g, "select");
      ml->is_running = 0;
      return -1;
    }

    for (fd = 0; r > 0 && fd <= ml->max_fd; ++fd) {
      events = 0;
      if (FD_ISSET (fd, &rset2))
	events |= GUESTFS_HANDLE_READABLE;
      if (FD_ISSET (fd, &wset2))
	events |= GUESTFS_HANDLE_WRITABLE;
      if (FD_ISSET (fd, &xset2))
	events |= GUESTFS_HANDLE_ERROR | GUESTFS_HANDLE_HANGUP;
      if (events) {
	r--;
	ml->handle_cb_data[fd].cb ((guestfs_main_loop *) ml,
				   ml->handle_cb_data[fd].g,
				   ml->handle_cb_data[fd].data,
				   fd, fd, events);
      }
    }
  }

  ml->is_running = 0;
  return 0;
}

static int
select_main_loop_quit (guestfs_main_loop *mlv, guestfs_h *g)
{
  struct select_main_loop *ml = (struct select_main_loop *) mlv;

  /* Note that legitimately ml->is_running can be zero when
   * this function is called.
   */

  ml->is_running = 0;
  return 0;
}
