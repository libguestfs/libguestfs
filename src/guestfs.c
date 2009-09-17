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
#include <stddef.h>
#include <unistd.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <dirent.h>

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
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"
#include "ignore-value.h"

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
//#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
//#define N_(str) str
#endif

#define error guestfs_error
#define perrorf guestfs_perrorf
#define safe_malloc guestfs_safe_malloc
#define safe_realloc guestfs_safe_realloc
#define safe_strdup guestfs_safe_strdup
//#define safe_memdup guestfs_safe_memdup

static void default_error_cb (guestfs_h *g, void *data, const char *msg);
static int send_to_daemon (guestfs_h *g, const void *v_buf, size_t n);
static int recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn);
static void close_handles (void);

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

  char *tmpdir;			/* Temporary directory containing socket. */

  char *qemu_help, *qemu_version; /* Output of qemu -help, qemu -version. */

  char **cmdline;		/* Qemu command line. */
  int cmdline_size;

  int verbose;
  int trace;
  int autosync;

  char *path;			/* Path to kernel, initrd. */
  char *qemu;			/* Qemu binary. */
  char *append;			/* Append to kernel command line. */

  int memsize;			/* Size of RAM (megabytes). */

  int selinux;                  /* selinux enabled? */

  char *last_error;

  /* Callbacks. */
  guestfs_abort_cb           abort_cb;
  guestfs_error_handler_cb   error_cb;
  void *                     error_cb_data;
  guestfs_log_message_cb     log_message_cb;
  void *                     log_message_cb_data;
  guestfs_subprocess_quit_cb subprocess_quit_cb;
  void *                     subprocess_quit_cb_data;
  guestfs_launch_done_cb     launch_done_cb;
  void *                     launch_done_cb_data;

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

  g->abort_cb = abort;
  g->error_cb = default_error_cb;
  g->error_cb_data = NULL;

  str = getenv ("LIBGUESTFS_DEBUG");
  g->verbose = str != NULL && strcmp (str, "1") == 0;

  str = getenv ("LIBGUESTFS_TRACE");
  g->trace = str != NULL && strcmp (str, "1") == 0;

  str = getenv ("LIBGUESTFS_PATH");
  g->path = str != NULL ? strdup (str) : strdup (GUESTFS_DEFAULT_PATH);
  if (!g->path) goto error;

  str = getenv ("LIBGUESTFS_QEMU");
  g->qemu = str != NULL ? strdup (str) : strdup (QEMU);
  if (!g->qemu) goto error;

  str = getenv ("LIBGUESTFS_APPEND");
  if (str) {
    g->append = strdup (str);
    if (!g->append) goto error;
  }

  /* Choose a suitable memory size.  Previously we tried to choose
   * a minimal memory size, but this isn't really necessary since
   * recent QEMU and KVM don't do anything nasty like locking
   * memory into core any more.  Thus we can safely choose a
   * large, generous amount of memory, and it'll just get swapped
   * on smaller systems.
   */
  str = getenv ("LIBGUESTFS_MEMSIZE");
  if (str) {
    if (sscanf (str, "%d", &g->memsize) != 1 || g->memsize <= 256) {
      fprintf (stderr, "libguestfs: non-numeric or too small value for LIBGUESTFS_MEMSIZE\n");
      goto error;
    }
  } else
    g->memsize = 500;

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

 error:
  free (g->path);
  free (g->qemu);
  free (g->append);
  free (g);
  return NULL;
}

void
guestfs_close (guestfs_h *g)
{
  int i;
  char filename[256];
  guestfs_h *gg;

  if (g->state == NO_HANDLE) {
    /* Not safe to call 'error' here, so ... */
    fprintf (stderr, _("guestfs_close: called twice on the same handle\n"));
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

  /* Close sockets. */
  if (g->fd[0] >= 0)
    close (g->fd[0]);
  if (g->fd[1] >= 0)
    close (g->fd[1]);
  if (g->sock >= 0)
    close (g->sock);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;

  /* Wait for subprocess(es) to exit. */
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);

  /* Remove tmpfiles. */
  if (g->tmpdir) {
    snprintf (filename, sizeof filename, "%s/sock", g->tmpdir);
    unlink (filename);

    snprintf (filename, sizeof filename, "%s/initrd", g->tmpdir);
    unlink (filename);

    snprintf (filename, sizeof filename, "%s/kernel", g->tmpdir);
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

  free (g->last_error);
  free (g->path);
  free (g->qemu);
  free (g->append);
  free (g->qemu_help);
  free (g->qemu_version);
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
  fprintf (stderr, _("libguestfs: error: %s\n"), msg);
}

void
guestfs_error (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);
  set_last_error (g, msg);

  free (msg);
}

void
guestfs_perrorf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int errnum = errno;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

#ifndef _GNU_SOURCE
  char buf[256];
  strerror_r (errnum, buf, sizeof buf);
#else
  char _buf[256];
  char *buf;
  buf = strerror_r (errnum, _buf, sizeof _buf);
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
  if (nbytes > 0 && !ptr) g->abort_cb ();
  return ptr;
}

/* Return 1 if an array of N objects, each of size S, cannot exist due
   to size arithmetic overflow.  S must be positive and N must be
   nonnegative.  This is a macro, not an inline function, so that it
   works correctly even when SIZE_MAX < N.

   By gnulib convention, SIZE_MAX represents overflow in size
   calculations, so the conservative dividend to use here is
   SIZE_MAX - 1, since SIZE_MAX might represent an overflowed value.
   However, malloc (SIZE_MAX) fails on all known hosts where
   sizeof (ptrdiff_t) <= sizeof (size_t), so do not bother to test for
   exactly-SIZE_MAX allocations on such hosts; this avoids a test and
   branch when S is known to be 1.  */
# define xalloc_oversized(n, s) \
    ((size_t) (sizeof (ptrdiff_t) <= sizeof (size_t) ? -1 : -2) / (s) < (n))

/* Technically we should add an autoconf test for this, testing for the desired
   functionality, like what's done in gnulib, but for now, this is fine.  */
#define HAVE_GNU_CALLOC (__GLIBC__ >= 2)

/* Allocate zeroed memory for N elements of S bytes, with error
   checking.  S must be nonzero.  */
void *
guestfs_safe_calloc (guestfs_h *g, size_t n, size_t s)
{
  /* From gnulib's calloc function in xmalloc.c.  */
  void *p;
  /* Test for overflow, since some calloc implementations don't have
     proper overflow checks.  But omit overflow and size-zero tests if
     HAVE_GNU_CALLOC, since GNU calloc catches overflow and never
     returns NULL if successful.  */
  if ((! HAVE_GNU_CALLOC && xalloc_oversized (n, s))
      || (! (p = calloc (n, s)) && (HAVE_GNU_CALLOC || n != 0)))
    g->abort_cb ();
  return p;
}

void *
guestfs_safe_realloc (guestfs_h *g, void *ptr, int nbytes)
{
  void *p = realloc (ptr, nbytes);
  if (nbytes > 0 && !p) g->abort_cb ();
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
guestfs__set_verbose (guestfs_h *g, int v)
{
  g->verbose = !!v;
  return 0;
}

int
guestfs__get_verbose (guestfs_h *g)
{
  return g->verbose;
}

int
guestfs__set_autosync (guestfs_h *g, int a)
{
  g->autosync = !!a;
  return 0;
}

int
guestfs__get_autosync (guestfs_h *g)
{
  return g->autosync;
}

int
guestfs__set_path (guestfs_h *g, const char *path)
{
  free (g->path);
  g->path = NULL;

  g->path =
    path == NULL ?
    safe_strdup (g, GUESTFS_DEFAULT_PATH) : safe_strdup (g, path);
  return 0;
}

const char *
guestfs__get_path (guestfs_h *g)
{
  return g->path;
}

int
guestfs__set_qemu (guestfs_h *g, const char *qemu)
{
  free (g->qemu);
  g->qemu = NULL;

  g->qemu = qemu == NULL ? safe_strdup (g, QEMU) : safe_strdup (g, qemu);
  return 0;
}

const char *
guestfs__get_qemu (guestfs_h *g)
{
  return g->qemu;
}

int
guestfs__set_append (guestfs_h *g, const char *append)
{
  free (g->append);
  g->append = NULL;

  g->append = append ? safe_strdup (g, append) : NULL;
  return 0;
}

const char *
guestfs__get_append (guestfs_h *g)
{
  return g->append;
}

int
guestfs__set_memsize (guestfs_h *g, int memsize)
{
  g->memsize = memsize;
  return 0;
}

int
guestfs__get_memsize (guestfs_h *g)
{
  return g->memsize;
}

int
guestfs__set_selinux (guestfs_h *g, int selinux)
{
  g->selinux = selinux;
  return 0;
}

int
guestfs__get_selinux (guestfs_h *g)
{
  return g->selinux;
}

int
guestfs__get_pid (guestfs_h *g)
{
  if (g->pid > 0)
    return g->pid;
  else {
    error (g, "get_pid: no qemu subprocess");
    return -1;
  }
}

struct guestfs_version *
guestfs__version (guestfs_h *g)
{
  struct guestfs_version *r;

  r = safe_malloc (g, sizeof *r);
  r->major = PACKAGE_VERSION_MAJOR;
  r->minor = PACKAGE_VERSION_MINOR;
  r->release = PACKAGE_VERSION_RELEASE;
  r->extra = safe_strdup (g, PACKAGE_VERSION_EXTRA);
  return r;
}

int
guestfs__set_trace (guestfs_h *g, int t)
{
  g->trace = !!t;
  return 0;
}

int
guestfs__get_trace (guestfs_h *g)
{
  return g->trace;
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
    error (g,
        _("command line cannot be altered after qemu subprocess launched"));
    return -1;
  }

  incr_cmdline_size (g);
  g->cmdline[g->cmdline_size-1] = safe_strdup (g, str);
  return 0;
}

int
guestfs__config (guestfs_h *g,
                 const char *qemu_param, const char *qemu_value)
{
  if (qemu_param[0] != '-') {
    error (g, _("guestfs_config: parameter must begin with '-' character"));
    return -1;
  }

  /* A bit fascist, but the user will probably break the extra
   * parameters that we add if they try to set any of these.
   */
  if (strcmp (qemu_param, "-kernel") == 0 ||
      strcmp (qemu_param, "-initrd") == 0 ||
      strcmp (qemu_param, "-nographic") == 0 ||
      strcmp (qemu_param, "-serial") == 0 ||
      strcmp (qemu_param, "-full-screen") == 0 ||
      strcmp (qemu_param, "-std-vga") == 0 ||
      strcmp (qemu_param, "-vnc") == 0) {
    error (g, _("guestfs_config: parameter '%s' isn't allowed"), qemu_param);
    return -1;
  }

  if (add_cmdline (g, qemu_param) != 0) return -1;

  if (qemu_value != NULL) {
    if (add_cmdline (g, qemu_value) != 0) return -1;
  }

  return 0;
}

int
guestfs__add_drive (guestfs_h *g, const char *filename)
{
  size_t len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  /* cache=off improves reliability in the event of a host crash.
   *
   * However this option causes qemu to try to open the file with
   * O_DIRECT.  This fails on some filesystem types (notably tmpfs).
   * So we check if we can open the file with or without O_DIRECT,
   * and use cache=off (or not) accordingly.
   *
   * This test also checks for the presence of the file, which
   * is a documented semantic of this interface.
   */
  int fd = open (filename, O_RDONLY|O_DIRECT);
  if (fd >= 0) {
    close (fd);
    snprintf (buf, len, "file=%s,cache=off,if=" DRIVE_IF, filename);
  } else {
    fd = open (filename, O_RDONLY);
    if (fd >= 0) {
      close (fd);
      snprintf (buf, len, "file=%s,if=" DRIVE_IF, filename);
    } else {
      perrorf (g, "%s", filename);
      return -1;
    }
  }

  return guestfs__config (g, "-drive", buf);
}

int
guestfs__add_drive_ro (guestfs_h *g, const char *filename)
{
  size_t len = strlen (filename) + 64;
  char buf[len];

  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  snprintf (buf, len, "file=%s,snapshot=on,if=%s", filename, DRIVE_IF);

  return guestfs__config (g, "-drive", buf);
}

int
guestfs__add_cdrom (guestfs_h *g, const char *filename)
{
  if (strchr (filename, ',') != NULL) {
    error (g, _("filename cannot contain ',' (comma) character"));
    return -1;
  }

  if (access (filename, F_OK) == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  return guestfs__config (g, "-cdrom", filename);
}

/* Returns true iff file is contained in dir. */
static int
dir_contains_file (const char *dir, const char *file)
{
  int dirlen = strlen (dir);
  int filelen = strlen (file);
  int len = dirlen+filelen+2;
  char path[len];

  snprintf (path, len, "%s/%s", dir, file);
  return access (path, F_OK) == 0;
}

/* Returns true iff every listed file is contained in 'dir'. */
static int
dir_contains_files (const char *dir, ...)
{
  va_list args;
  const char *file;

  va_start (args, dir);
  while ((file = va_arg (args, const char *)) != NULL) {
    if (!dir_contains_file (dir, file)) {
      va_end (args);
      return 0;
    }
  }
  va_end (args);
  return 1;
}

static int build_supermin_appliance (guestfs_h *g, const char *path, char **kernel, char **initrd);
static int test_qemu (guestfs_h *g);
static int qemu_supports (guestfs_h *g, const char *option);
static void print_cmdline (guestfs_h *g);

static const char *kernel_name = "vmlinuz." REPO "." host_cpu;
static const char *initrd_name = "initramfs." REPO "." host_cpu ".img";
static const char *supermin_name =
  "initramfs." REPO "." host_cpu ".supermin.img";
static const char *supermin_hostfiles_name =
  "initramfs." REPO "." host_cpu ".supermin.hostfiles";

int
guestfs__launch (guestfs_h *g)
{
  const char *tmpdir;
  char dir_template[PATH_MAX];
  int r, pmore;
  size_t len;
  int wfd[2], rfd[2];
  int tries;
  char *path, *pelem, *pend;
  char *kernel = NULL, *initrd = NULL;
  char unixsock[256];
  struct sockaddr_un addr;

#ifdef P_tmpdir
  tmpdir = P_tmpdir;
#else
  tmpdir = "/tmp";
#endif

  tmpdir = getenv ("TMPDIR") ? : tmpdir;
  snprintf (dir_template, sizeof dir_template, "%s/libguestfsXXXXXX", tmpdir);

  /* Configured? */
  if (!g->cmdline) {
    error (g, _("you must call guestfs_add_drive before guestfs_launch"));
    return -1;
  }

  if (g->state != CONFIG) {
    error (g, _("qemu has already been launched"));
    return -1;
  }

  /* Make the temporary directory. */
  if (!g->tmpdir) {
    g->tmpdir = safe_strdup (g, dir_template);
    if (mkdtemp (g->tmpdir) == NULL) {
      perrorf (g, _("%s: cannot create temporary directory"), dir_template);
      goto cleanup0;
    }
  }

  /* First search g->path for the supermin appliance, and try to
   * synthesize a kernel and initrd from that.  If it fails, we
   * try the path search again looking for a backup ordinary
   * appliance.
   */
  pelem = path = safe_strdup (g, g->path);
  do {
    pend = strchrnul (pelem, ':');
    pmore = *pend == ':';
    *pend = '\0';
    len = pend - pelem;

    /* Empty element of "." means cwd. */
    if (len == 0 || (len == 1 && *pelem == '.')) {
      if (g->verbose)
        fprintf (stderr,
                 "looking for supermin appliance in current directory\n");
      if (dir_contains_files (".",
                              supermin_name, supermin_hostfiles_name,
                              "kmod.whitelist", NULL)) {
        if (build_supermin_appliance (g, ".", &kernel, &initrd) == -1)
          return -1;
        break;
      }
    }
    /* Look at <path>/supermin* etc. */
    else {
      if (g->verbose)
        fprintf (stderr, "looking for supermin appliance in %s\n", pelem);

      if (dir_contains_files (pelem,
                              supermin_name, supermin_hostfiles_name,
                              "kmod.whitelist", NULL)) {
        if (build_supermin_appliance (g, pelem, &kernel, &initrd) == -1)
          return -1;
        break;
      }
    }

    pelem = pend + 1;
  } while (pmore);

  free (path);

  if (kernel == NULL || initrd == NULL) {
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
                   "looking for appliance in current directory\n");
        if (dir_contains_files (".", kernel_name, initrd_name, NULL)) {
          kernel = safe_strdup (g, kernel_name);
          initrd = safe_strdup (g, initrd_name);
          break;
        }
      }
      /* Look at <path>/kernel etc. */
      else {
        if (g->verbose)
          fprintf (stderr, "looking for appliance in %s\n", pelem);

        if (dir_contains_files (pelem, kernel_name, initrd_name, NULL)) {
          kernel = safe_malloc (g, len + strlen (kernel_name) + 2);
          initrd = safe_malloc (g, len + strlen (initrd_name) + 2);
          sprintf (kernel, "%s/%s", pelem, kernel_name);
          sprintf (initrd, "%s/%s", pelem, initrd_name);
          break;
        }
      }

      pelem = pend + 1;
    } while (pmore);

    free (path);
  }

  if (kernel == NULL || initrd == NULL) {
    error (g, _("cannot find %s or %s on LIBGUESTFS_PATH (current path = %s)"),
           kernel_name, initrd_name, g->path);
    goto cleanup0;
  }

  /* Get qemu help text and version. */
  if (test_qemu (g) == -1)
    goto cleanup0;

  /* Make the vmchannel socket. */
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
    g->cmdline[0] = g->qemu;

#define LINUX_CMDLINE							\
    "panic=1 "         /* force kernel to panic if daemon exits */	\
    "console=ttyS0 "   /* serial console */				\
    "udevtimeout=300 " /* good for very slow systems (RHBZ#480319) */	\
    "noapic "          /* workaround for RHBZ#502058 - ok if not SMP */ \
    "acpi=off "        /* we don't need ACPI, turn it off */		\
    "cgroup_disable=memory " /* saves us about 5 MB of RAM */

    /* Linux kernel command line. */
    snprintf (append, sizeof append,
              LINUX_CMDLINE
              "guestfs=%s:%d "
              "%s"              /* (selinux) */
              "%s"              /* (verbose) */
              "%s",             /* (append) */
              VMCHANNEL_ADDR, VMCHANNEL_PORT,
              g->selinux ? "selinux=1 enforcing=0 " : "selinux=0 ",
              g->verbose ? "guestfs_verbose=1 " : " ",
              g->append ? g->append : "");

    snprintf (memsize_str, sizeof memsize_str, "%d", g->memsize);

    add_cmdline (g, "-m");
    add_cmdline (g, memsize_str);
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

#if 0
    /* Doesn't work.  See:
     * http://lists.gnu.org/archive/html/qemu-devel/2009-07/threads.html
     * Subject "guestfwd option doesn't allow supplementary ,server,nowait"
     */
    if (qemu_supports (g, "guestfwd")) {
      /* New-style -net user,guestfwd=... syntax for vmchannel.  See:
       * http://git.savannah.gnu.org/cgit/qemu.git/commit/?id=c92ef6a22d3c71538fcc48fb61ad353f7ba03b62
       */
      snprintf (vmchannel, sizeof vmchannel,
                "user,vlan=0,net=10.0.2.0/8,guestfwd=tcp:%s:%d-unix:%s,server,nowait",
                VMCHANNEL_ADDR, VMCHANNEL_PORT, unixsock);

      add_cmdline (g, "-net");
      add_cmdline (g, vmchannel);
    } else {
#endif
      /* Not guestfwd.  HOPEFULLY this qemu uses the older -net channel
       * syntax, or if not then we'll get a quick failure.
       */
      snprintf (vmchannel, sizeof vmchannel,
                "channel,%d:unix:%s,server,nowait",
                VMCHANNEL_PORT, unixsock);

      add_cmdline (g, "-net");
      add_cmdline (g, vmchannel);
      add_cmdline (g, "-net");
      add_cmdline (g, "user,vlan=0,net=10.0.2.0/8");
#if 0
    }
#endif
    add_cmdline (g, "-net");
    add_cmdline (g, "nic,model=" NET_IF ",vlan=0");

    /* These options recommended by KVM developers to improve reliability. */
    if (qemu_supports (g, "-no-hpet"))
      add_cmdline (g, "-no-hpet");

    if (qemu_supports (g, "-rtc-td-hack"))
      add_cmdline (g, "-rtc-td-hack");

    /* Finish off the command line. */
    incr_cmdline_size (g);
    g->cmdline[g->cmdline_size-1] = NULL;

    if (g->verbose)
      print_cmdline (g);

    /* Set up stdin, stdout. */
    close (0);
    close (1);
    close (wfd[1]);
    close (rfd[0]);

    if (dup (wfd[0]) == -1) {
    dup_failed:
      perror ("dup failed");
      _exit (1);
    }
    if (dup (rfd[1]) == -1)
      goto dup_failed;

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

  error (g, _("failed to connect to vmchannel socket"));
  goto cleanup2;

 connected:
  g->state = LAUNCHING;
  return 0;

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

 cleanup0:
  free (kernel);
  free (initrd);
  return -1;
}

/* This function is used to print the qemu command line before it gets
 * executed, when in verbose mode.
 */
static void
print_cmdline (guestfs_h *g)
{
  int i = 0;
  int needs_quote;

  while (g->cmdline[i]) {
    if (g->cmdline[i][0] == '-') /* -option starts a new line */
      fprintf (stderr, " \\\n   ");

    if (i > 0) fputc (' ', stderr);

    /* Does it need shell quoting?  This only deals with simple cases. */
    needs_quote = strcspn (g->cmdline[i], " ") != strlen (g->cmdline[i]);

    if (needs_quote) fputc ('\'', stderr);
    fprintf (stderr, "%s", g->cmdline[i]);
    if (needs_quote) fputc ('\'', stderr);
    i++;
  }

  fputc ('\n', stderr);
}

/* This function does the hard work of building the supermin appliance
 * on the fly.  'path' is the directory containing the control files.
 * 'kernel' and 'initrd' are where we will return the names of the
 * kernel and initrd (only initrd is built).  The work is done by
 * an external script.  We just tell it where to put the result.
 */
static int
build_supermin_appliance (guestfs_h *g, const char *path,
                          char **kernel, char **initrd)
{
  char cmd[4096];
  int r, len;

  len = strlen (g->tmpdir);
  *kernel = safe_malloc (g, len + 8);
  snprintf (*kernel, len+8, "%s/kernel", g->tmpdir);
  *initrd = safe_malloc (g, len + 8);
  snprintf (*initrd, len+8, "%s/initrd", g->tmpdir);

  snprintf (cmd, sizeof cmd,
            "PATH='%s':$PATH "
            "libguestfs-supermin-helper '%s' %s %s",
            path,
            path, *kernel, *initrd);

  r = system (cmd);
  if (r == -1 || WEXITSTATUS(r) != 0) {
    error (g, _("external command failed: %s"), cmd);
    free (*kernel);
    free (*initrd);
    *kernel = *initrd = NULL;
    return -1;
  }

  return 0;
}

static int read_all (guestfs_h *g, FILE *fp, char **ret);

/* Test qemu binary (or wrapper) runs, and do 'qemu -help' and
 * 'qemu -version' so we know what options this qemu supports and
 * the version.
 */
static int
test_qemu (guestfs_h *g)
{
  char cmd[1024];
  FILE *fp;

  free (g->qemu_help);
  free (g->qemu_version);
  g->qemu_help = NULL;
  g->qemu_version = NULL;

  snprintf (cmd, sizeof cmd, "'%s' -help", g->qemu);

  fp = popen (cmd, "r");
  /* qemu -help should always work (qemu -version OTOH wasn't
   * supported by qemu 0.9).  If this command doesn't work then it
   * probably indicates that the qemu binary is missing.
   */
  if (!fp) {
    /* XXX This error is never printed, even if the qemu binary
     * doesn't exist.  Why?
     */
  error:
    perrorf (g, _("%s: command failed: If qemu is located on a non-standard path, try setting the LIBGUESTFS_QEMU environment variable."), cmd);
    return -1;
  }

  if (read_all (g, fp, &g->qemu_help) == -1)
    goto error;

  if (pclose (fp) == -1)
    goto error;

  snprintf (cmd, sizeof cmd, "'%s' -version 2>/dev/null", g->qemu);

  fp = popen (cmd, "r");
  if (fp) {
    /* Intentionally ignore errors. */
    read_all (g, fp, &g->qemu_version);
    pclose (fp);
  }

  return 0;
}

static int
read_all (guestfs_h *g, FILE *fp, char **ret)
{
  int r, n = 0;
  char *p;

 again:
  if (feof (fp)) {
    *ret = safe_realloc (g, *ret, n + 1);
    (*ret)[n] = '\0';
    return n;
  }

  *ret = safe_realloc (g, *ret, n + BUFSIZ);
  p = &(*ret)[n];
  r = fread (p, 1, BUFSIZ, fp);
  if (ferror (fp)) {
    perrorf (g, "read");
    return -1;
  }
  n += r;
  goto again;
}

/* Test if option is supported by qemu command line (just by grepping
 * the help text).
 */
static int
qemu_supports (guestfs_h *g, const char *option)
{
  return g->qemu_help && strstr (g->qemu_help, option) != NULL;
}

int
guestfs__wait_ready (guestfs_h *g)
{
  int r;
  uint32_t size;
  void *buf = NULL;

  if (g->state == READY) return 0;

  if (g->state == BUSY) {
    error (g, _("qemu has finished launching already"));
    return -1;
  }

  if (g->state != LAUNCHING) {
    error (g, _("qemu has not been launched yet"));
    return -1;
  }

  r = recv_from_daemon (g, &size, &buf);
  free (buf);

  if (r == -1) return -1;

  if (size != GUESTFS_LAUNCH_FLAG) {
    error (g, _("guestfs_wait_ready failed, see earlier error messages"));
    return -1;
  }

  /* This is possible in some really strange situations, such as
   * guestfsd starts up OK but then qemu immediately exits.  Check for
   * it because the caller is probably expecting to be able to send
   * commands after this function returns.
   */
  if (g->state != READY) {
    error (g, _("qemu launched and contacted daemon, but state != READY"));
    return -1;
  }

  return 0;
}

int
guestfs__kill_subprocess (guestfs_h *g)
{
  if (g->state == CONFIG) {
    error (g, _("no subprocess to kill"));
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
guestfs__is_config (guestfs_h *g)
{
  return g->state == CONFIG;
}

int
guestfs__is_launching (guestfs_h *g)
{
  return g->state == LAUNCHING;
}

int
guestfs__is_ready (guestfs_h *g)
{
  return g->state == READY;
}

int
guestfs__is_busy (guestfs_h *g)
{
  return g->state == BUSY;
}

int
guestfs__get_state (guestfs_h *g)
{
  return g->state;
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

/*----------------------------------------------------------------------*/

/* This is the code used to send and receive RPC messages and (for
 * certain types of message) to perform file transfers.  This code is
 * driven from the generated actions (src/guestfs-actions.c).  There
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
  if (g->verbose)
    fprintf (stderr, "child_cleanup: %p: child process died\n", g);

  /*kill (g->pid, SIGTERM);*/
  if (g->recoverypid > 0) kill (g->recoverypid, 9);
  waitpid (g->pid, NULL, 0);
  if (g->recoverypid > 0) waitpid (g->recoverypid, NULL, 0);
  close (g->fd[0]);
  close (g->fd[1]);
  close (g->sock);
  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;
  g->pid = 0;
  g->recoverypid = 0;
  g->start_t = 0;
  g->state = CONFIG;
  if (g->subprocess_quit_cb)
    g->subprocess_quit_cb (g, g->subprocess_quit_cb_data);
}

static int
read_log_message_or_eof (guestfs_h *g, int fd)
{
  char buf[BUFSIZ];
  int n;

#if 0
  if (g->verbose)
    fprintf (stderr,
             "read_log_message_or_eof: %p g->state = %d, fd = %d\n",
             g, g->state, fd);
#endif

  /* QEMU's console emulates a 16550A serial port.  The real 16550A
   * device has a small FIFO buffer (16 bytes) which means here we see
   * lots of small reads of 1-16 bytes in length, usually single
   * bytes.
   */
  n = read (fd, buf, sizeof buf);
  if (n == 0) {
    /* Hopefully this indicates the qemu child process has died. */
    child_cleanup (g);
    return -1;
  }

  if (n == -1) {
    if (errno == EINTR || errno == EAGAIN)
      return 0;

    perrorf (g, "read");
    return -1;
  }

  /* In verbose mode, copy all log messages to stderr. */
  if (g->verbose)
    ignore_value (write (STDERR_FILENO, buf, n));

  /* It's an actual log message, send it upwards if anyone is listening. */
  if (g->log_message_cb)
    g->log_message_cb (g, g->log_message_cb_data, buf, n);

  return 0;
}

static int
check_for_daemon_cancellation_or_eof (guestfs_h *g, int fd)
{
  char buf[4];
  int n;
  uint32_t flag;
  XDR xdr;

  if (g->verbose)
    fprintf (stderr,
             "check_for_daemon_cancellation_or_eof: %p g->state = %d, fd = %d\n",
             g, g->state, fd);

  n = read (fd, buf, 4);
  if (n == 0) {
    /* Hopefully this indicates the qemu child process has died. */
    child_cleanup (g);
    return -1;
  }

  if (n == -1) {
    if (errno == EINTR || errno == EAGAIN)
      return 0;

    perrorf (g, "read");
    return -1;
  }

  xdrmem_create (&xdr, buf, 4, XDR_DECODE);
  xdr_uint32_t (&xdr, &flag);
  xdr_destroy (&xdr);

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
static int
send_to_daemon (guestfs_h *g, const void *v_buf, size_t n)
{
  const char *buf = v_buf;
  fd_set rset, rset2;
  fd_set wset, wset2;

  if (g->verbose)
    fprintf (stderr,
             "send_to_daemon: %p g->state = %d, n = %zu\n", g, g->state, n);

  FD_ZERO (&rset);
  FD_ZERO (&wset);

  FD_SET (g->fd[1], &rset);     /* Read qemu stdout for log messages & EOF. */
  FD_SET (g->sock, &rset);      /* Read socket for cancellation & EOF. */
  FD_SET (g->sock, &wset);      /* Write to socket to send the data. */

  int max_fd = g->sock > g->fd[1] ? g->sock : g->fd[1];

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

    if (FD_ISSET (g->fd[1], &rset2)) {
      if (read_log_message_or_eof (g, g->fd[1]) == -1)
        return -1;
    }
    if (FD_ISSET (g->sock, &rset2)) {
      r = check_for_daemon_cancellation_or_eof (g, g->sock);
      if (r < 0)
        return r;
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
 */
static int
recv_from_daemon (guestfs_h *g, uint32_t *size_rtn, void **buf_rtn)
{
  fd_set rset, rset2;

  if (g->verbose)
    fprintf (stderr,
             "recv_from_daemon: %p g->state = %d, size_rtn = %p, buf_rtn = %p\n",
             g, g->state, size_rtn, buf_rtn);

  FD_ZERO (&rset);

  FD_SET (g->fd[1], &rset);     /* Read qemu stdout for log messages & EOF. */
  FD_SET (g->sock, &rset);      /* Read socket for data & EOF. */

  int max_fd = g->sock > g->fd[1] ? g->sock : g->fd[1];

  *size_rtn = 0;
  *buf_rtn = NULL;

  char lenbuf[4];
  /* nr is the size of the message, but we prime it as -4 because we
   * have to read the message length word first.
   */
  ssize_t nr = -4;

  while (nr < (ssize_t) *size_rtn) {
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

    if (FD_ISSET (g->fd[1], &rset2)) {
      if (read_log_message_or_eof (g, g->fd[1]) == -1) {
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
          error (g, _("unexpected end of file when reading from daemon"));
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

        if (*size_rtn == GUESTFS_LAUNCH_FLAG) {
          if (g->state != LAUNCHING)
            error (g, _("received magic signature from guestfsd, but in state %d"),
                   g->state);
          else {
            g->state = READY;
            if (g->launch_done_cb)
              g->launch_done_cb (g, g->launch_done_cb_data);
          }
          return 0;
        }
        else if (*size_rtn == GUESTFS_CANCEL_FLAG)
          return 0;
        /* If this happens, it's pretty bad and we've probably lost
         * synchronization.
         */
        else if (*size_rtn > GUESTFS_MESSAGE_MAX) {
          error (g, _("message length (%u) > maximum possible size (%d)"),
                 (unsigned) *size_rtn, GUESTFS_MESSAGE_MAX);
          return -1;
        }

        /* Allocate the complete buffer, size now known. */
        *buf_rtn = safe_malloc (g, *size_rtn);
        /*FALLTHROUGH*/
      }

      size_t sizetoread = *size_rtn - nr;
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
        error (g, _("unexpected end of file when reading from daemon"));
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
        if (isprint ((*(char **)buf_rtn)[j]))
          printf ("%c", (*(char **)buf_rtn)[j]);
        else
          printf (".");
      for (; j < i+16; ++j)
        printf (" ");
      printf ("|\n");
    }
  }
#endif

  return 0;
}

int
guestfs___send (guestfs_h *g, int proc_nr, xdrproc_t xdrp, char *args)
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
  r = send_to_daemon (g, msg_out, msg_out_size);
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

static int cancel = 0; /* XXX Implement file cancellation. */
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
  int fd, r, err;

  fd = open (filename, O_RDONLY);
  if (fd == -1) {
    perrorf (g, "open: %s", filename);
    send_file_cancellation (g);
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
    err = send_file_data (g, buf, r);
    if (err < 0) {
      if (err == -2)		/* daemon sent cancellation */
        send_file_cancellation (g);
      return err;
    }
  }

  if (cancel) {			/* cancel from either end */
    send_file_cancellation (g);
    return -1;
  }

  if (r == -1) {
    perrorf (g, "read: %s", filename);
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

  r = send_to_daemon (g, msg_out, msg_out_size);

  /* Did the daemon send a cancellation message? */
  if (r == -2) {
    if (g->verbose)
      fprintf (stderr, "got daemon cancellation\n");
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
  r = recv_from_daemon (g, &size, &buf);
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

/* Receive a file. */

/* Returns -1 = error, 0 = EOF, > 0 = more data */
static ssize_t receive_file_data (guestfs_h *g, void **buf);

int
guestfs___recv_file (guestfs_h *g, const char *filename)
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
  while ((r = receive_file_data (g, &buf)) > 0) {
    if (xwrite (fd, buf, r) == -1) {
      perrorf (g, "%s: write", filename);
      free (buf);
      goto cancel;
    }
    free (buf);
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

  if (g->verbose)
    fprintf (stderr, "%s: waiting for daemon to acknowledge cancellation\n",
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

  r = recv_from_daemon (g, &len, &buf);
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
