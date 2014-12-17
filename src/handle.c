/* libguestfs
 * Copyright (C) 2009-2014 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#endif

#include <libxml/parser.h>
#include <libxml/xmlversion.h>

#include "glthread/lock.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

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
  gl_lock_lock (init_lock);

#ifdef HAVE_LIBVIRT
  virInitialize ();
#endif

  xmlInitParser ();
  LIBXML_TEST_VERSION;

  gl_lock_unlock (init_lock);
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

  g->conn = NULL;

  guestfs___init_error_handler (g);
  g->abort_cb = abort;

  g->recovery_proc = 1;
  g->autosync = 1;

  g->memsize = DEFAULT_MEMSIZE;

  /* Start with large serial numbers so they are easy to spot
   * inside the protocol.
   */
  g->msg_next_serial = 0x00123400;

  /* Default is uniprocessor appliance. */
  g->smp = 1;

  g->path = strdup (GUESTFS_DEFAULT_PATH);
  if (!g->path) goto error;

#ifdef QEMU
  g->hv = strdup (QEMU);
#else
  /* configure --without-qemu, so set QEMU to something which will
   * definitely fail.  The user is expected to override the hypervisor
   * by setting an environment variable or calling set_hv.
   */
  g->hv = strdup ("false");
#endif
  if (!g->hv) goto error;

  /* Get program name. */
#if HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME == 1
  if (STRPREFIX (program_invocation_short_name, "lt-"))
    /* Remove libtool (lt-*) prefix from short name. */
    g->program = strdup (program_invocation_short_name + 3);
  else
    g->program = strdup (program_invocation_short_name);
#else
  g->program = strdup ("");
#endif
  if (!g->program) goto error;

  if (guestfs___set_backend (g, DEFAULT_BACKEND) == -1) {
    warning (g, _("libguestfs was built with an invalid default backend, using 'direct' instead"));
    if (guestfs___set_backend (g, "direct") == -1) {
      warning (g, _("'direct' backend does not work"));
      goto error;
    }
  }

  if (!(flags & GUESTFS_CREATE_NO_ENVIRONMENT))
    ignore_value (guestfs_parse_environment (g));

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

  debug (g, "create: flags = %u, handle = %p, program = %s",
         flags, g, g->program);

  return g;

 error:
  guestfs___free_string_list (g->backend_settings);
  free (g->backend);
  free (g->program);
  free (g->path);
  free (g->hv);
  free (g->append);
  free (g);
  return NULL;
}

static int
parse_environment (guestfs_h *g,
                   char *(*do_getenv) (const void *data, const char *),
                   const void *data)
{
  int memsize, b;
  char *str;

  /* Don't bother checking the return values of functions
   * that cannot return errors.
   */

  str = do_getenv (data, "LIBGUESTFS_TRACE");
  if (str) {
    b = guestfs___is_true (str);
    if (b == -1) {
      error (g, _("%s=%s: non-boolean value"), "LIBGUESTFS_TRACE", str);
      return -1;
    }
    guestfs_set_trace (g, b);
  }

  str = do_getenv (data, "LIBGUESTFS_DEBUG");
  if (str) {
    b = guestfs___is_true (str);
    if (b == -1) {
      error (g, _("%s=%s: non-boolean value"), "LIBGUESTFS_TRACE", str);
      return -1;
    }
    guestfs_set_verbose (g, b);
  }

  str = do_getenv (data, "LIBGUESTFS_TMPDIR");
  if (str && STRNEQ (str, "")) {
    if (guestfs_set_tmpdir (g, str) == -1)
      return -1;
  }

  str = do_getenv (data, "LIBGUESTFS_CACHEDIR");
  if (str && STRNEQ (str, "")) {
    if (guestfs_set_cachedir (g, str) == -1)
      return -1;
  }

  str = do_getenv (data, "TMPDIR");
  if (guestfs___set_env_tmpdir (g, str) == -1)
    return -1;

  str = do_getenv (data, "LIBGUESTFS_PATH");
  if (str && STRNEQ (str, ""))
    guestfs_set_path (g, str);

  str = do_getenv (data, "LIBGUESTFS_HV");
  if (str && STRNEQ (str, ""))
    guestfs_set_hv (g, str);
  else {
    str = do_getenv (data, "LIBGUESTFS_QEMU");
    if (str && STRNEQ (str, ""))
      guestfs_set_hv (g, str);
  }

  str = do_getenv (data, "LIBGUESTFS_APPEND");
  if (str)
    guestfs_set_append (g, str);

  str = do_getenv (data, "LIBGUESTFS_MEMSIZE");
  if (str && STRNEQ (str, "")) {
    if (sscanf (str, "%d", &memsize) != 1) {
      error (g, _("non-numeric value for LIBGUESTFS_MEMSIZE"));
      return -1;
    }
    if (guestfs_set_memsize (g, memsize) == -1) {
      /* set_memsize produces an error message already. */
      return -1;
    }
  }

  str = do_getenv (data, "LIBGUESTFS_BACKEND");
  if (str && STRNEQ (str, "")) {
    if (guestfs_set_backend (g, str) == -1)
      return -1;
  }
  else {
    str = do_getenv (data, "LIBGUESTFS_ATTACH_METHOD");
    if (str && STRNEQ (str, "")) {
      if (guestfs_set_backend (g, str) == -1)
        return -1;
    }
  }

  str = do_getenv (data, "LIBGUESTFS_BACKEND_SETTINGS");
  if (str) {
    CLEANUP_FREE_STRING_LIST char **settings = guestfs___split_string (':', str);

    if (settings == NULL) {
      perrorf (g, "split_string: malloc");
      return -1;
    }

    if (guestfs_set_backend_settings (g, settings) == -1)
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
      return &strings[i][len+1];
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
  struct hv_param *hp, *hp_next;
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

  if (g->state != CONFIG)
    shutdown_backend (g, 0);

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

  for (hp = g->hv_params; hp; hp = hp_next) {
    free (hp->hv_param);
    free (hp->hv_value);
    hp_next = hp->next;
    free (hp);
  }

  while (g->error_cb_stack)
    guestfs_pop_error_handler (g);

  if (g->pda)
    hash_free (g->pda);
  free (g->tmpdir);
  free (g->env_tmpdir);
  free (g->int_tmpdir);
  free (g->int_cachedir);
  free (g->last_error);
  free (g->program);
  free (g->path);
  free (g->hv);
  free (g->backend);
  free (g->backend_data);
  guestfs___free_string_list (g->backend_settings);
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
#ifdef VALGRIND_DAEMON
    /* When valgrinding the daemon, this causes the daemon to exit
     * properly, so we'll see any valgrind problems.  Don't do this in
     * production builds because it's slow and unnecessary.
     */
    guestfs_internal_exit (g);
    if (g->conn) {
      /* internal_exit above will cause the daemon to close the
       * connection.  The purpose of the read_data here is to read the
       * remaining log messages.
       */
      char buf[1];
      g->conn->ops->read_data (g, g->conn, buf, sizeof buf);
    }
#endif
  }

  /* Shut down the backend. */
  if (g->backend_ops->shutdown (g, g->backend_data, check_for_errors) == -1)
    ret = -1;

  /* Close sockets. */
  if (g->conn) {
    g->conn->ops->free_connection (g, g->conn);
    g->conn = NULL;
  }

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
  char *new_hv;

  /* Only this deprecated set_qemu API supports using NULL as a
   * parameter, to mean set it back to the default QEMU.  The new
   * set_hv API does not allow callers to do this.
   */
  if (qemu == NULL) {
#ifdef QEMU
    new_hv = safe_strdup (g, QEMU);
#else
    error (g, _("configured --without-qemu so calling guestfs_set_qemu with qemu == NULL is an error"));
    return -1;
#endif
  }
  else
    new_hv = safe_strdup (g, qemu);

  free (g->hv);
  g->hv = new_hv;

  return 0;
}

const char *
guestfs__get_qemu (guestfs_h *g)
{
  return g->hv;
}

int
guestfs__set_hv (guestfs_h *g, const char *hv)
{
  free (g->hv);
  g->hv = safe_strdup (g, hv);
  return 0;
}

char *
guestfs__get_hv (guestfs_h *g)
{
  return safe_strdup (g, g->hv);
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
  if (memsize < MIN_MEMSIZE) {
    error (g, _("too small value for memsize (must be at least %d)"), MIN_MEMSIZE);
    return -1;
  }
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
  g->direct_mode = !!d;
  return 0;
}

int
guestfs__get_direct (guestfs_h *g)
{
  return g->direct_mode;
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

int
guestfs__set_program (guestfs_h *g, const char *program)
{
  free (g->program);
  g->program = safe_strdup (g, program);

  return 0;
}

const char *
guestfs__get_program (guestfs_h *g)
{
  return g->program;
}

int
guestfs__set_backend (guestfs_h *g, const char *method)
{
  if (guestfs___set_backend (g, method) == -1) {
    error (g, "invalid backend: %s", method);
    return -1;
  }

  return 0;
}

int
guestfs__set_attach_method (guestfs_h *g, const char *method)
{
  return guestfs_set_backend (g, method);
}

char *
guestfs__get_backend (guestfs_h *g)
{
  return safe_strdup (g, g->backend);
}

char *
guestfs__get_attach_method (guestfs_h *g)
{
  if (STREQ (g->backend, "direct"))
    /* Return 'appliance' here for backwards compatibility. */
    return safe_strdup (g, "appliance");

  return guestfs_get_backend (g);
}

int
guestfs__set_backend_settings (guestfs_h *g, char *const *settings)
{
  char **copy;

  copy = guestfs___copy_string_list (settings);
  if (copy == NULL) {
    perrorf (g, "copy: malloc");
    return -1;
  }

  guestfs___free_string_list (g->backend_settings);
  g->backend_settings = copy;

  return 0;
}

char **
guestfs__get_backend_settings (guestfs_h *g)
{
  char *empty_list[1] = { NULL };
  char **ret;

  if (g->backend_settings == NULL)
    ret = guestfs___copy_string_list (empty_list);
  else
    ret = guestfs___copy_string_list (g->backend_settings);

  if (ret == NULL) {
    perrorf (g, "copy: malloc");
    return NULL;
  }

  return ret;                   /* caller frees */
}

char *
guestfs__get_backend_setting (guestfs_h *g, const char *name)
{
  char **settings = g->backend_settings;
  size_t namelen = strlen (name);
  size_t i;

  if (settings == NULL)
    goto not_found;

  for (i = 0; settings[i] != NULL; ++i) {
    /* "name" is the same as "name=1" */
    if (STREQ (settings[i], name))
      return safe_strdup (g, "1");
    /* "name=...", return value */
    if (STRPREFIX (settings[i], name) && settings[i][namelen] == '=')
      return safe_strdup (g, &settings[i][namelen+1]);
  }

 not_found:
  guestfs___error_errno (g, ESRCH, _("setting not found"));
  return NULL;
}

int
guestfs__clear_backend_setting (guestfs_h *g, const char *name)
{
  char **settings = g->backend_settings;
  size_t namelen = strlen (name);
  size_t i, j;
  int count = 0;

  if (settings == NULL)
    return 0;

  for (i = 0; settings[i] != NULL; ++i) {
    if (STREQ (settings[i], name) ||
        (STRPREFIX (settings[i], name) && settings[i][namelen] == '=')) {
      count++;
      free (settings[i]);

      /* We move all the following strings down one place, including the NULL. */
      for (j = i; settings[j] != NULL; ++j)
        settings[j] = settings[j+1];

      i--;
    }
  }

  return count;
}

int
guestfs__set_backend_setting (guestfs_h *g, const char *name, const char *value)
{
  char *new_setting;
  size_t len;

  new_setting = safe_asprintf (g, "%s=%s", name, value);

  if (g->backend_settings == NULL) {
    g->backend_settings = safe_malloc (g, sizeof (char *));
    g->backend_settings[0] = NULL;
    len = 0;
  }
  else {
    ignore_value (guestfs_clear_backend_setting (g, name));
    len = guestfs___count_strings (g->backend_settings);
  }

  g->backend_settings =
    safe_realloc (g, g->backend_settings, (len+2) * sizeof (char *));
  g->backend_settings[len++] = new_setting;
  g->backend_settings[len++] = NULL;

  return 0;
}

/* This is a convenience function, but we might consider exporting
 * it as an API in future.
 */
int
guestfs___get_backend_setting_bool (guestfs_h *g, const char *name)
{
  CLEANUP_FREE char *value = NULL;
  int b;

  guestfs_push_error_handler (g, NULL, NULL);
  value = guestfs_get_backend_setting (g, name);
  guestfs_pop_error_handler (g);

  if (value == NULL && guestfs_last_errno (g) == ESRCH)
    return 0;

  if (value == NULL)
    return -1;

  b = guestfs___is_true (value);
  if (b == -1)
    return -1;

  return b;
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
