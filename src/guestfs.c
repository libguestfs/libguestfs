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
#include <assert.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>

#include <rpc/types.h>
#include <rpc/xdr.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#endif

#ifdef HAVE_LIBXML2
#include <libxml/parser.h>
#include <libxml/xmlversion.h>
#endif

#include "c-ctype.h"
#include "glthread/lock.h"
#include "hash.h"
#include "hash-pjw.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int parse_attach_method (guestfs_h *g, const char *method);
static void default_error_cb (guestfs_h *g, void *data, const char *msg);
static int shutdown_backend (guestfs_h *g, int check_for_errors);
static void close_handles (void);

gl_lock_define_initialized (static, handles_lock);
static guestfs_h *handles = NULL;
static int atexit_handler_set = 0;

gl_lock_define_initialized (static, init_lock);

/* No initialization is required by libguestfs, but libvirt and
 * libxml2 require initialization if they might be called from
 * multiple threads.  Hence this constructor function which is called
 * when libguestfs is first loaded.
 */
static void init_libguestfs (void) __attribute__((constructor));

static void
init_libguestfs (void)
{
#if defined(HAVE_LIBVIRT) || defined(HAVE_LIBXML2)
  gl_lock_lock (init_lock);
#endif
#ifdef HAVE_LIBVIRT
  virInitialize ();
#endif
#ifdef HAVE_LIBXML2
  xmlInitParser ();
  LIBXML_TEST_VERSION;
#endif
#if defined(HAVE_LIBVIRT) || defined(HAVE_LIBXML2)
  gl_lock_unlock (init_lock);
#endif
}

guestfs_h *
guestfs_create (void)
{
  return guestfs_create_flags (0);
}

guestfs_h *
guestfs_create_flags (unsigned flags, ...)
{
  guestfs_h *g;

  g = calloc (1, sizeof (*g));
  if (!g) return NULL;

  g->state = CONFIG;

  g->fd[0] = -1;
  g->fd[1] = -1;
  g->sock = -1;

  g->abort_cb = abort;
  g->error_cb = default_error_cb;
  g->error_cb_data = NULL;

  g->recovery_proc = 1;
  g->autosync = 1;

  g->memsize = 500;

  /* Start with large serial numbers so they are easy to spot
   * inside the protocol.
   */
  g->msg_next_serial = 0x00123400;

  /* Default is uniprocessor appliance. */
  g->smp = 1;

  g->path = strdup (GUESTFS_DEFAULT_PATH);
  if (!g->path) goto error;

  g->qemu = strdup (QEMU);
  if (!g->qemu) goto error;

  if (parse_attach_method (g, DEFAULT_ATTACH_METHOD) == -1) {
    warning (g, _("libguestfs was built with an invalid default attach-method, using 'appliance' instead"));
    g->attach_method = ATTACH_METHOD_APPLIANCE;
  }

  if (!(flags & GUESTFS_CREATE_NO_ENVIRONMENT))
    guestfs_parse_environment (g);

  if (!(flags & GUESTFS_CREATE_NO_CLOSE_ON_EXIT)) {
    g->close_on_exit = true;

    /* Link the handles onto a global list. */
    gl_lock_lock (handles_lock);
    g->next = handles;
    handles = g;
    if (!atexit_handler_set) {
      atexit (close_handles);
      atexit_handler_set = 1;
    }
    gl_lock_unlock (handles_lock);
  }

  debug (g, "create: flags = %u, handle = %p", flags, g);

  return g;

 error:
  free (g->attach_method_arg);
  free (g->path);
  free (g->qemu);
  free (g->append);
  free (g);
  return NULL;
}

static int
parse_environment (guestfs_h *g,
                   char *(*do_getenv) (const void *data, const char *),
                   const void *data)
{
  int memsize;
  char *str;

  /* Don't bother checking the return values of functions
   * that cannot return errors.
   */

  str = do_getenv (data, "LIBGUESTFS_TRACE");
  if (str != NULL && STREQ (str, "1"))
    guestfs_set_trace (g, 1);

  str = do_getenv (data, "LIBGUESTFS_DEBUG");
  if (str != NULL && STREQ (str, "1"))
    guestfs_set_verbose (g, 1);

  str = do_getenv (data, "LIBGUESTFS_TMPDIR");
  if (str)
    guestfs_set_tmpdir (g, str);

  str = do_getenv (data, "LIBGUESTFS_CACHEDIR");
  if (str)
    guestfs_set_cachedir (g, str);

  free (g->env_tmpdir);
  str = do_getenv (data, "TMPDIR");
  g->env_tmpdir = str ? safe_strdup (g, str) : NULL;

  str = do_getenv (data, "LIBGUESTFS_PATH");
  if (str)
    guestfs_set_path (g, str);

  str = do_getenv (data, "LIBGUESTFS_QEMU");
  if (str)
    guestfs_set_qemu (g, str);

  str = do_getenv (data, "LIBGUESTFS_APPEND");
  if (str)
    guestfs_set_append (g, str);

  str = do_getenv (data, "LIBGUESTFS_MEMSIZE");
  if (str) {
    if (sscanf (str, "%d", &memsize) != 1 || memsize < 128) {
      error (g, "non-numeric or too small value for LIBGUESTFS_MEMSIZE");
      return -1;
    }
    guestfs_set_memsize (g, memsize);
  }

  str = do_getenv (data, "LIBGUESTFS_ATTACH_METHOD");
  if (str) {
    if (guestfs_set_attach_method (g, str) == -1)
      return -1;
  }

  return 0;
}

static char *
call_getenv (const void *data, const char *name)
{
  return getenv (name);
}

int
guestfs__parse_environment (guestfs_h *g)
{
  return parse_environment (g, call_getenv, NULL);
}

static char *
getenv_from_strings (const void *stringsv, const char *name)
{
  char **strings = (char **) stringsv;
  size_t len = strlen (name);
  size_t i;

  for (i = 0; strings[i] != NULL; ++i)
    if (STRPREFIX (strings[i], name) && strings[i][len] == '=')
      return (char *) &strings[i][len+1];
  return NULL;
}

int
guestfs__parse_environment_list (guestfs_h *g, char * const *strings)
{
  return parse_environment (g, getenv_from_strings, strings);
}

void
guestfs_close (guestfs_h *g)
{
  struct qemu_param *qp, *qp_next;
  guestfs_h **gg;

  if (g->state == NO_HANDLE) {
    /* Not safe to call ANY callbacks here, so ... */
    fprintf (stderr, _("guestfs_close: called twice on the same handle\n"));
    return;
  }

  /* Remove the handle from the handles list. */
  if (g->close_on_exit) {
    gl_lock_lock (handles_lock);
    for (gg = &handles; *gg != g; gg = &(*gg)->next)
      ;
    *gg = g->next;
    gl_lock_unlock (handles_lock);
  }

  if (g->trace) {
    const char trace_msg[] = "close";

    guestfs___call_callbacks_message (g, GUESTFS_EVENT_TRACE,
                                      trace_msg, strlen (trace_msg));
  }

  debug (g, "closing guestfs handle %p (state %d)", g, g->state);

  /* If we are valgrinding the daemon, then we *don't* want to kill
   * the subprocess because we want the final valgrind messages sent
   * when we close sockets below.  However for normal production use,
   * killing the subprocess is the right thing to do (in case the
   * daemon or qemu is not responding).
   */
#ifndef VALGRIND_DAEMON
  if (g->state != CONFIG)
    shutdown_backend (g, 0);
#endif

  /* Run user close callbacks. */
  guestfs___call_callbacks_void (g, GUESTFS_EVENT_CLOSE);

  /* Test output file used by bindtests. */
  if (g->test_fp != NULL)
    fclose (g->test_fp);

  /* Remove temporary directory. */
  guestfs___remove_tmpdir (g);

  /* Mark the handle as dead and then free up all memory. */
  g->state = NO_HANDLE;

  free (g->events);
  g->nr_events = 0;
  g->events = NULL;

#if HAVE_FUSE
  guestfs___free_fuse (g);
#endif

  guestfs___free_inspect_info (g);
  guestfs___free_drives (g);

  for (qp = g->qemu_params; qp; qp = qp_next) {
    free (qp->qemu_param);
    free (qp->qemu_value);
    qp_next = qp->next;
    free (qp);
  }

  if (g->pda)
    hash_free (g->pda);
  free (g->tmpdir);
  free (g->last_error);
  free (g->path);
  free (g->qemu);
  free (g->append);
  free (g);
}

int
guestfs__shutdown (guestfs_h *g)
{
  return shutdown_backend (g, 1);
}

/* guestfs_shutdown calls shutdown_backend with check_for_errors = 1.
 * guestfs_close calls shutdown_backend with check_for_errors = 0.
 *
 * 'check_for_errors' is a hint to the backend about whether we care
 * about errors or not.  In the libvirt case it can be used to
 * optimize the shutdown for speed when we don't care.
 */
static int
shutdown_backend (guestfs_h *g, int check_for_errors)
{
  int ret = 0;

  if (g->state == CONFIG)
    return 0;

  /* Try to sync if autosync flag is set. */
  if (g->autosync && g->state == READY) {
    if (guestfs_internal_autosync (g) == -1)
      ret = -1;
  }

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

  if (g->attach_ops->shutdown (g, check_for_errors) == -1)
    ret = -1;

  guestfs___free_drives (g);

  g->state = CONFIG;

  return ret;
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

int
guestfs_last_errno (guestfs_h *g)
{
  return g->last_errnum;
}

static void
set_last_error (guestfs_h *g, int errnum, const char *msg)
{
  free (g->last_error);
  g->last_error = strdup (msg);
  g->last_errnum = errnum;
}

/* Warning are printed unconditionally.  We try to make these rare.
 * Generally speaking, a warning should either be an error, or if it's
 * not important for end users then it should be a debug message.
 */
void
guestfs___warning (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg, *msg2;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  len = asprintf (&msg2, _("warning: %s"), msg);
  free (msg);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, msg2, len);

  free (msg2);
}

/* Debug messages. */
void
guestfs___debug (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;

  /* The cpp macro "debug" has already checked that g->verbose is true
   * before calling this function, but we check it again just in case
   * anyone calls this function directly.
   */
  if (!g->verbose)
    return;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_LIBRARY, msg, len);

  free (msg);
}

/* Call trace messages.  These are enabled by setting g->trace, and
 * calls to this function should only happen from the generated code
 * in src/actions.c
 */
void
guestfs___trace (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;
  int len;

  va_start (args, fs);
  len = vasprintf (&msg, fs, args);
  va_end (args);

  if (len < 0) return;

  guestfs___call_callbacks_message (g, GUESTFS_EVENT_TRACE, msg, len);

  free (msg);
}

static void
default_error_cb (guestfs_h *g, void *data, const char *msg)
{
  fprintf (stderr, _("libguestfs: error: %s\n"), msg);
}

void
guestfs_error_errno (guestfs_h *g, int errnum, const char *fs, ...)
{
  va_list args;
  char *msg;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  /* set_last_error first so that the callback can access the error
   * message and errno through the handle if it wishes.
   */
  set_last_error (g, errnum, msg);
  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);

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

  char buf[256];
  strerror_r (errnum, buf, sizeof buf);

  msg = safe_realloc (g, msg, strlen (msg) + 2 + strlen (buf) + 1);
  strcat (msg, ": ");
  strcat (msg, buf);

  /* set_last_error first so that the callback can access the error
   * message and errno through the handle if it wishes.
   */
  set_last_error (g, errnum, msg);
  if (g->error_cb) g->error_cb (g, g->error_cb_data, msg);

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
#if defined(__GLIBC__)
#define HAVE_GNU_CALLOC (__GLIBC__ >= 2)
#else
#define HAVE_GNU_CALLOC 0
#endif

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
guestfs_safe_realloc (guestfs_h *g, void *ptr, size_t nbytes)
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

char *
guestfs_safe_strndup (guestfs_h *g, const char *str, size_t n)
{
  char *s = strndup (str, n);
  if (!s) g->abort_cb ();
  return s;
}

void *
guestfs_safe_memdup (guestfs_h *g, const void *ptr, size_t size)
{
  void *p = malloc (size);
  if (!p) g->abort_cb ();
  memcpy (p, ptr, size);
  return p;
}

char *
guestfs_safe_asprintf (guestfs_h *g, const char *fs, ...)
{
  va_list args;
  char *msg;

  va_start (args, fs);
  int err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err == -1)
    g->abort_cb ();

  return msg;
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
guestfs_set_error_handler (guestfs_h *g,
                           guestfs_error_handler_cb cb, void *data)
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

void
guestfs_user_cancel (guestfs_h *g)
{
  g->user_cancel = 1;
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

int
guestfs__set_direct (guestfs_h *g, int d)
{
  g->direct = !!d;
  return 0;
}

int
guestfs__get_direct (guestfs_h *g)
{
  return g->direct;
}

int
guestfs__set_recovery_proc (guestfs_h *g, int f)
{
  g->recovery_proc = !!f;
  return 0;
}

int
guestfs__get_recovery_proc (guestfs_h *g)
{
  return g->recovery_proc;
}

int
guestfs__set_network (guestfs_h *g, int v)
{
  g->enable_network = !!v;
  return 0;
}

int
guestfs__get_network (guestfs_h *g)
{
  return g->enable_network;
}

static int
parse_attach_method (guestfs_h *g, const char *method)
{
  if (STREQ (method, "appliance")) {
    g->attach_method = ATTACH_METHOD_APPLIANCE;
    free (g->attach_method_arg);
    g->attach_method_arg = NULL;
    return 0;
  }

  if (STREQ (method, "libvirt")) {
    g->attach_method = ATTACH_METHOD_LIBVIRT;
    free (g->attach_method_arg);
    g->attach_method_arg = NULL;
    return 0;
  }

  if (STRPREFIX (method, "libvirt:") && strlen (method) > 8) {
    g->attach_method = ATTACH_METHOD_LIBVIRT;
    free (g->attach_method_arg);
    g->attach_method_arg = safe_strdup (g, method + 8);
    return 0;
  }

  if (STRPREFIX (method, "unix:") && strlen (method) > 5) {
    g->attach_method = ATTACH_METHOD_UNIX;
    free (g->attach_method_arg);
    g->attach_method_arg = safe_strdup (g, method + 5);
    /* Note that we don't check the path exists until launch is called. */
    return 0;
  }

  return -1;
}

int
guestfs__set_attach_method (guestfs_h *g, const char *method)
{
  if (parse_attach_method (g, method) == -1) {
    error (g, "invalid attach method: %s", method);
    return -1;
  }

  return 0;
}

char *
guestfs__get_attach_method (guestfs_h *g)
{
  char *ret;

  switch (g->attach_method) {
  case ATTACH_METHOD_APPLIANCE:
    ret = safe_strdup (g, "appliance");
    break;

  case ATTACH_METHOD_LIBVIRT:
    if (g->attach_method_arg == NULL)
      ret = safe_strdup (g, "libvirt");
    else
      ret = safe_asprintf (g, "libvirt:%s", g->attach_method_arg);
    break;

  case ATTACH_METHOD_UNIX:
    ret = safe_asprintf (g, "unix:%s", g->attach_method_arg);
    break;

  default: /* keep GCC happy - this is not reached */
    abort ();
  }

  return ret;
}

int
guestfs__set_pgroup (guestfs_h *g, int v)
{
  g->pgroup = !!v;
  return 0;
}

int
guestfs__get_pgroup (guestfs_h *g)
{
  return g->pgroup;
}

int
guestfs__set_smp (guestfs_h *g, int v)
{
  if (v > 255) {
    error (g, "unsupported number of smp vcpus: %d", v);
    return -1;
  } else if (v >= 1) {
    g->smp = v;
    return 0;
  } else {
    error (g, "invalid smp parameter: %d", v);
    return -1;
  }
}

int
guestfs__get_smp (guestfs_h *g)
{
  return g->smp;
}

/* Note the private data area is allocated lazily, since the vast
 * majority of callers will never use it.  This means g->pda is
 * likely to be NULL.
 */
struct pda_entry {
  char *key;                    /* key */
  void *data;                   /* opaque user data pointer */
};

static size_t
hasher (void const *x, size_t table_size)
{
  struct pda_entry const *p = x;
  return hash_pjw (p->key, table_size);
}

static bool
comparator (void const *x, void const *y)
{
  struct pda_entry const *a = x;
  struct pda_entry const *b = y;
  return STREQ (a->key, b->key);
}

static void
freer (void *x)
{
  if (x) {
    struct pda_entry *p = x;
    free (p->key);
    free (p);
  }
}

void
guestfs_set_private (guestfs_h *g, const char *key, void *data)
{
  if (g->pda == NULL) {
    g->pda = hash_initialize (16, NULL, hasher, comparator, freer);
    if (g->pda == NULL)
      g->abort_cb ();
  }

  struct pda_entry *new_entry = safe_malloc (g, sizeof *new_entry);
  new_entry->key = safe_strdup (g, key);
  new_entry->data = data;

  struct pda_entry *old_entry = hash_delete (g->pda, new_entry);
  freer (old_entry);

  struct pda_entry *entry = hash_insert (g->pda, new_entry);
  if (entry == NULL)
    g->abort_cb ();
  assert (entry == new_entry);
}

static inline char *
bad_cast (char const *s)
{
  return (char *) s;
}

void *
guestfs_get_private (guestfs_h *g, const char *key)
{
  if (g->pda == NULL)
    return NULL;                /* no keys have been set */

  const struct pda_entry k = { .key = bad_cast (key) };
  struct pda_entry *entry = hash_lookup (g->pda, &k);
  if (entry)
    return entry->data;
  else
    return NULL;
}

/* Iterator. */
void *
guestfs_first_private (guestfs_h *g, const char **key_rtn)
{
  if (g->pda == NULL)
    return NULL;

  g->pda_next = hash_get_first (g->pda);

  /* Ignore any keys with NULL data pointers. */
  while (g->pda_next && g->pda_next->data == NULL)
    g->pda_next = hash_get_next (g->pda, g->pda_next);

  if (g->pda_next == NULL)
    return NULL;

  *key_rtn = g->pda_next->key;
  return g->pda_next->data;
}

void *
guestfs_next_private (guestfs_h *g, const char **key_rtn)
{
  if (g->pda == NULL)
    return NULL;

  if (g->pda_next == NULL)
    return NULL;

  /* Walk to the next key with a non-NULL data pointer. */
  do {
    g->pda_next = hash_get_next (g->pda, g->pda_next);
  } while (g->pda_next && g->pda_next->data == NULL);

  if (g->pda_next == NULL)
    return NULL;

  *key_rtn = g->pda_next->key;
  return g->pda_next->data;
}

/* When tracing, be careful how we print BufferIn parameters which
 * usually contain large amounts of binary data (RHBZ#646822).
 */
void
guestfs___print_BufferIn (FILE *out, const char *buf, size_t buf_size)
{
  size_t i;
  size_t orig_size = buf_size;

  if (buf_size > 256)
    buf_size = 256;

  fputc ('"', out);

  for (i = 0; i < buf_size; ++i) {
    if (c_isprint (buf[i]))
      fputc (buf[i], out);
    else
      fprintf (out, "\\x%02x", (unsigned char) buf[i]);
  }

  fputc ('"', out);

  if (orig_size > buf_size)
    fprintf (out,
             _("<truncated, original size %zu bytes>"), orig_size);
}

void
guestfs___print_BufferOut (FILE *out, const char *buf, size_t buf_size)
{
  guestfs___print_BufferIn (out, buf, buf_size);
}

void
guestfs___free_string_list (char **argv)
{
  size_t i;
  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

char *
guestfs__canonical_device_name (guestfs_h *g, const char *device)
{
  char *ret;

  if (STRPREFIX (device, "/dev/hd") ||
      STRPREFIX (device, "/dev/vd")) {
    ret = safe_strdup (g, device);
    ret[5] = 's';
  }
  else if (STRPREFIX (device, "/dev/mapper/") ||
           STRPREFIX (device, "/dev/dm-")) {
    /* XXX hide errors */
    ret = guestfs_lvm_canonical_lv_name (g, device);
    if (ret == NULL)
      ret = safe_strdup (g, device);
  }
  else
    ret = safe_strdup (g, device);

  return ret;                   /* caller frees */
}
