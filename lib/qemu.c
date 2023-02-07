/* libguestfs
 * Copyright (C) 2009-2023 Red Hat Inc.
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

/**
 * Functions to handle qemu versions and features.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>
#include <libintl.h>

#include <libxml/uri.h>

#include <jansson.h>

#include "full-write.h"
#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs_protocol.h"

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_JSON_T_DECREF __attribute__((cleanup(cleanup_json_t_decref)))

static void
cleanup_json_t_decref (void *ptr)
{
  json_decref (* (json_t **) ptr);
}

#else
#define CLEANUP_JSON_T_DECREF
#endif

struct qemu_data {
  int generation;               /* MEMO_GENERATION read from qemu.stat */
  uint64_t prev_size;           /* Size of qemu binary when cached. */
  uint64_t prev_mtime;          /* mtime of qemu binary when cached. */

  char *qemu_help;              /* Output of qemu -help. */
  char *qemu_devices;           /* Output of qemu -device ? */
  char *qmp_schema;             /* Output of QMP query-qmp-schema. */
  char *query_kvm;              /* Output of QMP query-kvm. */

  /* The following fields are derived from the fields above. */
  struct version qemu_version;  /* Parsed qemu version number. */
  json_t *qmp_schema_tree;      /* qmp_schema parsed into a JSON tree */
  bool has_kvm;                 /* If KVM is available. */
};

static char *cache_filename (guestfs_h *g, const char *cachedir, const struct stat *, const char *suffix);
static int test_qemu_help (guestfs_h *g, struct qemu_data *data);
static int read_cache_qemu_help (guestfs_h *g, struct qemu_data *data, const char *filename);
static int write_cache_qemu_help (guestfs_h *g, const struct qemu_data *data, const char *filename);
static int test_qemu_devices (guestfs_h *g, struct qemu_data *data);
static int read_cache_qemu_devices (guestfs_h *g, struct qemu_data *data, const char *filename);
static int write_cache_qemu_devices (guestfs_h *g, const struct qemu_data *data, const char *filename);
static int test_qmp_schema (guestfs_h *g, struct qemu_data *data);
static int read_cache_qmp_schema (guestfs_h *g, struct qemu_data *data, const char *filename);
static int write_cache_qmp_schema (guestfs_h *g, const struct qemu_data *data, const char *filename);
static int test_query_kvm (guestfs_h *g, struct qemu_data *data);
static int read_cache_query_kvm (guestfs_h *g, struct qemu_data *data, const char *filename);
static int write_cache_query_kvm (guestfs_h *g, const struct qemu_data *data, const char *filename);
static int read_cache_qemu_stat (guestfs_h *g, struct qemu_data *data, const char *filename);
static int write_cache_qemu_stat (guestfs_h *g, const struct qemu_data *data, const char *filename);
static void parse_qemu_version (guestfs_h *g, const char *, struct version *qemu_version);
static void parse_json (guestfs_h *g, const char *, json_t **);
static void parse_has_kvm (guestfs_h *g, const char *, bool *);
static void read_all (guestfs_h *g, void *retv, const char *buf, size_t len);
static int generic_read_cache (guestfs_h *g, const char *filename, char **strp);
static int generic_write_cache (guestfs_h *g, const char *filename, const char *str);
static int generic_qmp_test (guestfs_h *g, struct qemu_data *data, const char *qmp_command, char **outp);

/* This structure abstracts the data we are reading from qemu and how
 * we get it.
 */
static const struct qemu_fields {
  const char *name;

  /* Function to perform the test on g->hv.  This must set the correct
   * data->[field] to non-NULL, or else return an error.
   */
  int (*test) (guestfs_h *g, struct qemu_data *data);

  /* Functions to read and write the cache file.
   * read_cache returns -1 = error, 0 = no cache, 1 = cache data read.
   * write_cache returns -1 = error, 0 = success.
   */
  int (*read_cache) (guestfs_h *g, struct qemu_data *data,
                     const char *filename);
  int (*write_cache) (guestfs_h *g, const struct qemu_data *data,
                      const char *filename);
} qemu_fields[] = {
  { "help",
    test_qemu_help, read_cache_qemu_help, write_cache_qemu_help },
  { "devices",
    test_qemu_devices, read_cache_qemu_devices, write_cache_qemu_devices },
  { "qmp-schema",
    test_qmp_schema, read_cache_qmp_schema, write_cache_qmp_schema },
  { "query-kvm",
    test_query_kvm, read_cache_query_kvm, write_cache_query_kvm },
};
#define NR_FIELDS (sizeof qemu_fields / sizeof qemu_fields[0])

/* This is saved in the qemu-*.stat file, so if we decide to change the
 * test_qemu memoization format/data in future, we should increment
 * this to discard any memoized data cached by previous versions of
 * libguestfs.
 */
#define MEMO_GENERATION 3

/**
 * Test that the qemu binary (or wrapper) runs, and do C<qemu -help>
 * and other commands so we can find out the version of qemu and what
 * options this qemu supports.
 *
 * This caches the results in the cachedir so that as long as the qemu
 * binary does not change, calling this is effectively free.
 */
struct qemu_data *
guestfs_int_test_qemu (guestfs_h *g)
{
  struct stat statbuf;
  struct qemu_data *data;
  CLEANUP_FREE char *cachedir = NULL;
  CLEANUP_FREE char *stat_filename = NULL;
  int r;
  size_t i;

  if (stat (g->hv, &statbuf) == -1) {
    perrorf (g, "stat: %s", g->hv);
    return NULL;
  }

  cachedir = guestfs_int_lazy_make_supermin_appliance_dir (g);
  if (cachedir == NULL)
    return NULL;

  /* Did we previously test the same version of qemu? */
  debug (g, "checking for previously cached test results of %s, in %s",
         g->hv, cachedir);

  data = safe_calloc (g, 1, sizeof *data);

  stat_filename = cache_filename (g, cachedir, &statbuf, "stat");
  r = read_cache_qemu_stat (g, data, stat_filename);
  if (r == -1)
    goto error;
  if (r == 0)
    goto do_test;

  if (data->generation != MEMO_GENERATION ||
      data->prev_size != (uint64_t) statbuf.st_size ||
      data->prev_mtime != (uint64_t) statbuf.st_mtime)
    goto do_test;

  debug (g, "loading previously cached test results");

  for (i = 0; i < NR_FIELDS; ++i) {
    CLEANUP_FREE char *filename =
      cache_filename (g, cachedir, &statbuf, qemu_fields[i].name);
    r = qemu_fields[i].read_cache (g, data, filename);
    if (r == -1)
      goto error;
    if (r == 0) {
      /* Cache gone, maybe deleted by the tmp cleaner, so we must run
       * the full tests.  We will have a partially filled qemu_data
       * structure.  The safest way to deal with that is to free
       * it and start again.
       */
      guestfs_int_free_qemu_data (data);
      data = safe_calloc (g, 1, sizeof *data);
      goto do_test;
    }
  }

  goto out;

 do_test:
  for (i = 0; i < NR_FIELDS; ++i) {
    if (qemu_fields[i].test (g, data) == -1)
      goto error;
  }

  /* Now memoize the qemu output in the cache directory. */
  debug (g, "saving test results");

  for (i = 0; i < NR_FIELDS; ++i) {
    CLEANUP_FREE char *filename =
      cache_filename (g, cachedir, &statbuf, qemu_fields[i].name);
    if (qemu_fields[i].write_cache (g, data, filename) == -1)
      goto error;
  }

  /* Write the qemu.stat file last so that its presence indicates that
   * the qemu.help and qemu.devices files ought to exist.
   */
  data->generation = MEMO_GENERATION;
  data->prev_size = statbuf.st_size;
  data->prev_mtime = statbuf.st_mtime;
  if (write_cache_qemu_stat (g, data, stat_filename) == -1)
    goto error;

 out:
  /* Derived fields. */
  parse_qemu_version (g, data->qemu_help, &data->qemu_version);
  parse_json (g, data->qmp_schema, &data->qmp_schema_tree);
  parse_has_kvm (g, data->query_kvm, &data->has_kvm);

  return data;

 error:
  guestfs_int_free_qemu_data (data);
  return NULL;
}

/**
 * Generate the filenames, for the stat file and the other cache
 * files.
 *
 * By including the size and mtime in the filename we also ensure that
 * the same user can use multiple versions of qemu without conflicts.
 */
static char *
cache_filename (guestfs_h *g, const char *cachedir,
                const struct stat *statbuf, const char *suffix)
{
  return safe_asprintf (g, "%s/qemu-%" PRIu64 "-%" PRIu64 ".%s",
                        cachedir,
                        (uint64_t) statbuf->st_size,
                        (uint64_t) statbuf->st_mtime,
                        suffix);
}

static int
test_qemu_help (guestfs_h *g, struct qemu_data *data)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  guestfs_int_cmd_add_arg (cmd, g->hv);
  guestfs_int_cmd_add_arg (cmd, "-display");
  guestfs_int_cmd_add_arg (cmd, "none");
  guestfs_int_cmd_add_arg (cmd, "-help");
  guestfs_int_cmd_set_stdout_callback (cmd, read_all, &data->qemu_help,
                                       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, g->hv, NULL);
    return -1;
  }
  return 0;
}

static int
read_cache_qemu_help (guestfs_h *g, struct qemu_data *data,
                      const char *filename)
{
  return generic_read_cache (g, filename, &data->qemu_help);
}

static int
write_cache_qemu_help (guestfs_h *g, const struct qemu_data *data,
                       const char *filename)
{
  return generic_write_cache (g, filename, data->qemu_help);
}

static int
test_qemu_devices (guestfs_h *g, struct qemu_data *data)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  guestfs_int_cmd_add_arg (cmd, g->hv);
  guestfs_int_cmd_add_arg (cmd, "-display");
  guestfs_int_cmd_add_arg (cmd, "none");
  guestfs_int_cmd_add_arg (cmd, "-machine");
  guestfs_int_cmd_add_arg (cmd,
#ifdef MACHINE_TYPE
                           MACHINE_TYPE ","
#endif
                           "accel=kvm:tcg");
  guestfs_int_cmd_add_arg (cmd, "-device");
  guestfs_int_cmd_add_arg (cmd, "?");
  guestfs_int_cmd_clear_capture_errors (cmd);
  guestfs_int_cmd_set_stderr_to_stdout (cmd);
  guestfs_int_cmd_set_stdout_callback (cmd, read_all, &data->qemu_devices,
                                       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, g->hv, NULL);
    return -1;
  }
  return 0;
}

static int
read_cache_qemu_devices (guestfs_h *g, struct qemu_data *data,
                         const char *filename)
{
  return generic_read_cache (g, filename, &data->qemu_devices);
}

static int
write_cache_qemu_devices (guestfs_h *g, const struct qemu_data *data,
                          const char *filename)
{
  return generic_write_cache (g, filename, data->qemu_devices);
}

static int
test_qmp_schema (guestfs_h *g, struct qemu_data *data)
{
  return generic_qmp_test (g, data, "query-qmp-schema", &data->qmp_schema);
}

static int
read_cache_qmp_schema (guestfs_h *g, struct qemu_data *data,
                       const char *filename)
{
  return generic_read_cache (g, filename, &data->qmp_schema);
}

static int
write_cache_qmp_schema (guestfs_h *g, const struct qemu_data *data,
                        const char *filename)
{
  return generic_write_cache (g, filename, data->qmp_schema);
}

static int
test_query_kvm (guestfs_h *g, struct qemu_data *data)
{
  return generic_qmp_test (g, data, "query-kvm", &data->query_kvm);
}

static int
read_cache_query_kvm (guestfs_h *g, struct qemu_data *data,
                      const char *filename)
{
  return generic_read_cache (g, filename, &data->query_kvm);
}

static int
write_cache_query_kvm (guestfs_h *g, const struct qemu_data *data,
                       const char *filename)
{
  return generic_write_cache (g, filename, data->query_kvm);
}

static int
read_cache_qemu_stat (guestfs_h *g, struct qemu_data *data,
                      const char *filename)
{
  CLEANUP_FCLOSE FILE *fp = fopen (filename, "r");
  if (fp == NULL) {
    if (errno == ENOENT)
      return 0;                 /* no cache, run the test instead */
    perrorf (g, "%s", filename);
    return -1;
  }

  if (fscanf (fp, "%d %" SCNu64 " %" SCNu64,
              &data->generation,
              &data->prev_size,
              &data->prev_mtime) != 3)
    return 0;

  return 1;
}

static int
write_cache_qemu_stat (guestfs_h *g, const struct qemu_data *data,
                       const char *filename)
{
  CLEANUP_FCLOSE FILE *fp = fopen (filename, "w");
  if (fp == NULL) {
    perrorf (g, "%s", filename);
    return -1;
  }
  /* The path to qemu is stored for information only, it is not
   * used when we parse the file.
   */
  if (fprintf (fp, "%d %" PRIu64 " %" PRIu64 " %s\n",
               data->generation,
               data->prev_size,
               data->prev_mtime,
               g->hv) == -1) {
    perrorf (g, "%s: write", filename);
    return -1;
  }

  return 0;
}

/**
 * Parse the first line of C<qemu_help> into the major and minor
 * version of qemu, but don't fail if parsing is not possible.
 */
static void
parse_qemu_version (guestfs_h *g, const char *qemu_help,
                    struct version *qemu_version)
{
  version_init_null (qemu_version);

  if (guestfs_int_version_from_x_y (g, qemu_version, qemu_help) < 1) {
    debug (g, "%s: failed to parse qemu version string from the first line of the output of '%s -help'.  When reporting this bug please include the -help output.",
           __func__, g->hv);
    return;
  }
}

/**
 * Parse the json output from QMP.  But don't fail if parsing
 * is not possible.
 */
static void
parse_json (guestfs_h *g, const char *json, json_t **treep)
{
  json_error_t err;

  if (!json)
    return;

  *treep = json_loads (json, 0, &err);
  if (*treep == NULL) {
    if (strlen (err.text) > 0)
      debug (g, "QMP parse error: %s (ignored)", err.text);
    else
      debug (g, "QMP unknown parse error (ignored)");
  }
}

/**
 * Parse the json output from QMP query-kvm to find out if KVM is
 * enabled on this machine.  Don't fail if parsing is not possible,
 * assume KVM is available.
 *
 * The JSON output looks like:
 * {"return": {"enabled": true, "present": true}}
 */
static void
parse_has_kvm (guestfs_h *g, const char *json, bool *ret)
{
  CLEANUP_JSON_T_DECREF json_t *tree = NULL;
  json_error_t err;
  json_t *return_node, *enabled_node;

  *ret = true;                  /* Assume KVM is enabled. */

  if (!json)
    return;

  tree = json_loads (json, 0, &err);
  if (tree == NULL) {
    if (strlen (err.text) > 0)
      debug (g, "QMP parse error: %s (ignored)", err.text);
    else
      debug (g, "QMP unknown parse error (ignored)");
    return;
  }

  return_node = json_object_get (tree, "return");
  if (!json_is_object (return_node)) {
    debug (g, "QMP query-kvm: no \"return\" node (ignored)");
    return;
  }
  enabled_node = json_object_get (return_node, "enabled");
  /* Note that json_is_boolean will check that enabled_node != NULL. */
  if (!json_is_boolean (enabled_node)) {
    debug (g, "QMP query-kvm: no \"enabled\" node or not a boolean (ignored)");
    return;
  }

  *ret = json_is_true (enabled_node);
}

/**
 * Generic functions for reading and writing the cache files, used
 * where we are just reading and writing plain text strings.
 */
static int
generic_read_cache (guestfs_h *g, const char *filename, char **strp)
{
  if (access (filename, R_OK) == -1 && errno == ENOENT)
    return 0;                   /* no cache, run the test instead */
  if (guestfs_int_read_whole_file (g, filename, strp, NULL) == -1)
    return -1;
  return 1;
}

static int
generic_write_cache (guestfs_h *g, const char *filename, const char *str)
{
  CLEANUP_CLOSE int fd = -1;
  size_t len;

  fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY|O_CLOEXEC, 0666);
  if (fd == -1) {
    perrorf (g, "%s", filename);
    return -1;
  }

  len = strlen (str);
  if (full_write (fd, str, len) != len) {
    perrorf (g, "%s: write", filename);
    return -1;
  }

  return 0;
}

/**
 * Run a generic QMP test on the QEMU binary.
 */
static int
generic_qmp_test (guestfs_h *g, struct qemu_data *data,
                  const char *qmp_command,
                  char **outp)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r, fd;
  CLEANUP_FCLOSE FILE *fp = NULL;
  CLEANUP_FREE char *line = NULL;
  size_t allocsize = 0;
  ssize_t len;

  guestfs_int_cmd_add_string_unquoted (cmd, "echo ");
  /* QMP is modal.  You have to send the qmp_capabilities command first. */
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"qmp_capabilities\" }' ");
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"");
  guestfs_int_cmd_add_string_unquoted (cmd, qmp_command);
  guestfs_int_cmd_add_string_unquoted (cmd, "\" }' ");
  /* Exit QEMU after sending the commands. */
  guestfs_int_cmd_add_string_unquoted (cmd, "'{ \"execute\": \"quit\" }' ");
  guestfs_int_cmd_add_string_unquoted (cmd, " | ");
  guestfs_int_cmd_add_string_unquoted (cmd, "QEMU_AUDIO_DRV=none ");
  guestfs_int_cmd_add_string_quoted (cmd, g->hv);
  guestfs_int_cmd_add_string_unquoted (cmd, " -display none");
  guestfs_int_cmd_add_string_unquoted (cmd, " -machine ");
  guestfs_int_cmd_add_string_quoted (cmd,
#ifdef MACHINE_TYPE
                                     MACHINE_TYPE ","
#endif
                                     "accel=kvm:tcg");
  guestfs_int_cmd_add_string_unquoted (cmd, " -qmp stdio");
  guestfs_int_cmd_clear_capture_errors (cmd);

  fd = guestfs_int_cmd_pipe_run (cmd, "r");
  if (fd == -1)
    return -1;

  /* Read the output line by line.  We expect to see:
   * line 1: {"QMP": {"version": ... } }   # greeting from QMP
   * line 2: {"return": {}}                # output from qmp_capabilities
   * line 3: {"return": ... }              # the data from our qmp_command
   * line 4: {"return": {}}                # output from quit
   * line 5: {"timestamp": ...}            # shutdown event
   */
  fp = fdopen (fd, "r");        /* this will close (fd) at end of scope */
  if (fp == NULL) {
    perrorf (g, "fdopen");
    return -1;
  }
  len = getline (&line, &allocsize, fp); /* line 1 */
  if (len == -1 || strstr (line, "\"QMP\"") == NULL) {
  parse_failure:
    debug (g, "did not understand QMP monitor output from %s (ignored)",
           g->hv);
    /* QMP tests are optional, don't fail if we cannot parse the
     * output.  However we MUST return an empty string on non-error
     * paths.
     */
    *outp = safe_strdup (g, "");
    return 0;
  }
  len = getline (&line, &allocsize, fp); /* line 2 */
  if (len == -1 || strstr (line, "\"return\"") == NULL)
    goto parse_failure;
  len = getline (&line, &allocsize, fp); /* line 3 */
  if (len == -1 || strstr (line, "\"return\"") == NULL)
    goto parse_failure;
  *outp = safe_strdup (g, line);
  /* The other lines we don't care about, so finish parsing here. */
  ignore_value (getline (&line, &allocsize, fp)); /* line 4 */
  ignore_value (getline (&line, &allocsize, fp)); /* line 5 */

  r = guestfs_int_cmd_pipe_wait (cmd);
  /* QMP tests are optional, don't fail if the tests fail. */
  if (r == -1 || !WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    debug (g, "%s wait failed or unexpected exit status (ignored)", g->hv);
    return 0;
  }

  return 0;
}

static void
read_all (guestfs_h *g, void *retv, const char *buf, size_t len)
{
  char **ret = retv;

  *ret = safe_strndup (g, buf, len);
}

/**
 * Return the parsed version of qemu.
 */
struct version
guestfs_int_qemu_version (guestfs_h *g, struct qemu_data *data)
{
  return data->qemu_version;
}

/**
 * Test if option is supported by qemu command line (just by grepping
 * the help text).
 */
int
guestfs_int_qemu_supports (guestfs_h *g, const struct qemu_data *data,
                           const char *option)
{
  return strstr (data->qemu_help, option) != NULL;
}

/**
 * Test if device is supported by qemu (currently just greps the
 * C<qemu -device ?> output).
 */
int
guestfs_int_qemu_supports_device (guestfs_h *g,
                                  const struct qemu_data *data,
                                  const char *device_name)
{
  return strstr (data->qemu_devices, device_name) != NULL;
}

/**
 * Test if the qemu binary uses mandatory file locking, added in
 * QEMU >= 2.10 (but sometimes disabled).
 */
int
guestfs_int_qemu_mandatory_locking (guestfs_h *g,
                                    const struct qemu_data *data)
{
  json_t *schema, *v, *meta_type, *members, *m, *name;
  size_t i, j;

  /* If there's no QMP schema, fall back to checking the version. */
  if (!data->qmp_schema_tree) {
  fallback:
    return guestfs_int_version_ge (&data->qemu_version, 2, 10, 0);
  }

  /* Top element of qmp_schema_tree is the { "return": ... } wrapper.
   * Extract the schema from the wrapper.  Note the returned ‘schema’
   * will be an array.
   */
  schema = json_object_get (data->qmp_schema_tree, "return");
  if (!json_is_array (schema))
    goto fallback;

  /* Now look for any member of the array which has:
   * { "meta-type": "object",
   *   "members": [ ... { "name": "locking", ... } ... ] ... }
   */
  json_array_foreach (schema, i, v) {
    meta_type = json_object_get (v, "meta-type");
    if (json_is_string (meta_type) &&
        STREQ (json_string_value (meta_type), "object")) {
      members = json_object_get (v, "members");
      if (json_is_array (members)) {
        json_array_foreach (members, j, m) {
          name = json_object_get (m, "name");
          if (json_is_string (name) &&
              STREQ (json_string_value (name), "locking"))
            return 1;
        }
      }
    }
  }

  return 0;
}

bool
guestfs_int_platform_has_kvm (guestfs_h *g, const struct qemu_data *data)
{
  return data->has_kvm;
}

/**
 * Escape a qemu parameter.
 *
 * Every C<,> becomes C<,,>.  The caller must free the returned string.
 *
 * XXX This functionality is now only used when constructing a
 * qemu-img command in F<lib/create.c>.  We should extend the qemuopts
 * library to cover this use case.
 */
char *
guestfs_int_qemu_escape_param (guestfs_h *g, const char *param)
{
  size_t i;
  const size_t len = strlen (param);
  char *p, *ret;

  ret = p = safe_malloc (g, len*2 + 1); /* max length of escaped name*/
  for (i = 0; i < len; ++i) {
    *p++ = param[i];
    if (param[i] == ',')
      *p++ = ',';
  }
  *p = '\0';

  return ret;
}

static char *
make_uri (guestfs_h *g, const char *scheme, const char *user,
          const char *password,
          struct drive_server *server, const char *path)
{
  xmlURI uri = { .scheme = (char *) scheme,
                 .user = (char *) user };
  CLEANUP_FREE char *query = NULL;
  CLEANUP_FREE char *pathslash = NULL;
  CLEANUP_FREE char *userauth = NULL;

  /* Need to add a leading '/' to URI paths since xmlSaveUri doesn't. */
  if (path != NULL && path[0] != '/') {
    pathslash = safe_asprintf (g, "/%s", path);
    uri.path = pathslash;
  }
  else
    uri.path = (char *) path;

  /* Rebuild user:password. */
  if (user != NULL && password != NULL) {
    /* Keep the string in an own variable so it can be freed automatically. */
    userauth = safe_asprintf (g, "%s:%s", user, password);
    uri.user = userauth;
  }

  switch (server->transport) {
  case drive_transport_none:
  case drive_transport_tcp:
    uri.server = server->u.hostname;
    uri.port = server->port;
    break;
  case drive_transport_unix:
    query = safe_asprintf (g, "socket=%s", server->u.socket);
    uri.query_raw = query;
    break;
  }

  return (char *) xmlSaveUri (&uri);
}

/**
 * Useful function to format a drive + protocol for qemu.
 *
 * Note that the qemu parameter is the bit after C<"file=">.  It is
 * not escaped here, but would usually be escaped if passed to qemu as
 * part of a full -drive parameter (but not for L<qemu-img(1)>).
 */
char *
guestfs_int_drive_source_qemu_param (guestfs_h *g,
                                     const struct drive_source *src)
{
  char *path;

  switch (src->protocol) {
  case drive_protocol_file:
    /* We have to convert the path to an absolute path, since
     * otherwise qemu will look for the backing file relative to the
     * overlay (which is located in g->tmpdir).
     *
     * As a side-effect this deals with paths that contain ':' since
     * qemu will not process the ':' if the path begins with '/'.
     */
    path = realpath (src->u.path, NULL);
    if (path == NULL) {
      perrorf (g, _("realpath: could not convert ‘%s’ to absolute path"),
               src->u.path);
      return NULL;
    }
    return path;

  case drive_protocol_ftp:
    return make_uri (g, "ftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_ftps:
    return make_uri (g, "ftps", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_gluster:
    switch (src->servers[0].transport) {
    case drive_transport_none:
      return make_uri (g, "gluster", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_tcp:
      return make_uri (g, "gluster+tcp", NULL, NULL,
                       &src->servers[0], src->u.exportname);
    case drive_transport_unix:
      return make_uri (g, "gluster+unix", NULL, NULL,
                       &src->servers[0], NULL);
    }
    break;

  case drive_protocol_http:
    return make_uri (g, "http", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_https:
    return make_uri (g, "https", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_iscsi: {
    CLEANUP_FREE char *escaped_hostname = NULL;
    CLEANUP_FREE char *escaped_target = NULL;
    CLEANUP_FREE char *userauth = NULL;
    char port_str[16];
    char *ret;

    escaped_hostname =
      (char *) xmlURIEscapeStr(BAD_CAST src->servers[0].u.hostname,
                               BAD_CAST "");
    /* The target string must keep slash as it is, as exportname contains
     * "iqn/lun".
     */
    escaped_target =
      (char *) xmlURIEscapeStr(BAD_CAST src->u.exportname, BAD_CAST "/");
    if (src->username != NULL && src->secret != NULL)
      userauth = safe_asprintf (g, "%s%%%s@", src->username, src->secret);
    if (src->servers[0].port != 0)
      snprintf (port_str, sizeof port_str, ":%d", src->servers[0].port);

    ret = safe_asprintf (g, "iscsi://%s%s%s/%s",
                         userauth != NULL ? userauth : "",
                         escaped_hostname,
                         src->servers[0].port != 0 ? port_str : "",
                         escaped_target);

    return ret;
  }

  case drive_protocol_nbd: {
    CLEANUP_FREE char *p = NULL;
    char *ret;

    switch (src->servers[0].transport) {
    case drive_transport_none:
    case drive_transport_tcp:
      p = safe_asprintf (g, "nbd:%s:%d",
                         src->servers[0].u.hostname, src->servers[0].port);
      break;
    case drive_transport_unix:
      p = safe_asprintf (g, "nbd:unix:%s", src->servers[0].u.socket);
      break;
    }
    assert (p);

    if (STREQ (src->u.exportname, ""))
      ret = safe_strdup (g, p);
    else
      ret = safe_asprintf (g, "%s:exportname=%s", p, src->u.exportname);

    return ret;
  }

  case drive_protocol_rbd: {
    CLEANUP_FREE_STRING_LIST char **hosts = NULL;
    CLEANUP_FREE char *mon_host = NULL, *username = NULL, *secret = NULL;
    const char *auth;
    size_t i;

    /* Build the list of all the mon hosts. */
    hosts = safe_calloc (g, src->nr_servers + 1, sizeof (char *));

    for (i = 0; i < src->nr_servers; i++) {
      CLEANUP_FREE char *escaped_host;

      escaped_host =
        guestfs_int_replace_string (src->servers[i].u.hostname, ":", "\\:");
      if (escaped_host == NULL) g->abort_cb ();
      hosts[i] =
        safe_asprintf (g, "%s\\:%d", escaped_host, src->servers[i].port);
    }
    mon_host = guestfs_int_join_strings ("\\;", hosts);

    if (src->username)
      username = safe_asprintf (g, ":id=%s", src->username);
    if (src->secret)
      secret = safe_asprintf (g, ":key=%s", src->secret);
    if (username || secret)
      auth = ":auth_supported=cephx\\;none";
    else
      auth = ":auth_supported=none";

    return safe_asprintf (g, "rbd:%s%s%s%s%s%s",
                          src->u.exportname,
                          src->nr_servers > 0 ? ":mon_host=" : "",
                          src->nr_servers > 0 ? mon_host : "",
                          username ? username : "",
                          auth,
                          secret ? secret : "");
  }

  case drive_protocol_sheepdog:
    if (src->nr_servers == 0)
      return safe_asprintf (g, "sheepdog:%s", src->u.exportname);
    else                        /* XXX How to pass multiple hosts? */
      return safe_asprintf (g, "sheepdog:%s:%d:%s",
                            src->servers[0].u.hostname, src->servers[0].port,
                            src->u.exportname);

  case drive_protocol_ssh:
    return make_uri (g, "ssh", src->username, src->secret,
                     &src->servers[0], src->u.exportname);

  case drive_protocol_tftp:
    return make_uri (g, "tftp", src->username, src->secret,
                     &src->servers[0], src->u.exportname);
  }

  abort ();
}

/**
 * Test if discard is both supported by qemu AND possible with the
 * underlying file or device.  This returns C<1> if discard is
 * possible.  It returns C<0> if not possible and sets the error to
 * the reason why.
 *
 * This function is called when the user set C<discard == "enable">.
 */
bool
guestfs_int_discard_possible (guestfs_h *g, struct drive *drv,
			      const struct version *qemu_version)
{
  /* qemu >= 1.5.  This was the first version that supported the
   * discard option on -drive at all.
   */
  bool qemu15 = guestfs_int_version_ge (qemu_version, 1, 5, 0);
  /* qemu >= 1.6.  This was the first version that supported unmap on
   * qcow2 backing files.
   */
  bool qemu16 = guestfs_int_version_ge (qemu_version, 1, 6, 0);

  if (!qemu15)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu < 1.5"));

  /* If it's an overlay, discard is not possible (on the underlying
   * file).  This has probably been caught earlier since we already
   * checked that the drive is !readonly.  Nevertheless ...
   */
  if (drv->overlay)
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "the drive has a read-only overlay"));

  /* Look at the source format. */
  if (drv->src.format == NULL) {
    /* We could autodetect the format, but we don't ... yet. XXX */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "you have to specify the format of the file"));
  }
  else if (STREQ (drv->src.format, "raw"))
    /* OK */ ;
  else if (STREQ (drv->src.format, "qcow2")) {
    if (!qemu16)
      NOT_SUPPORTED (g, false,
                     _("discard cannot be enabled on this drive: "
                       "qemu < 1.6 cannot do discard on qcow2 files"));
  }
  else {
    /* It's possible in future other formats will support discard, but
     * currently (qemu 1.7) none of them do.
     */
    NOT_SUPPORTED (g, false,
                   _("discard cannot be enabled on this drive: "
                     "qemu does not support discard for ‘%s’ format files"),
                   drv->src.format);
  }

  switch (drv->src.protocol) {
    /* Protocols which support discard. */
  case drive_protocol_file:
  case drive_protocol_gluster:
  case drive_protocol_iscsi:
  case drive_protocol_nbd:
  case drive_protocol_rbd:
  case drive_protocol_sheepdog: /* XXX depends on server version */
    break;

    /* Protocols which don't support discard. */
  case drive_protocol_ftp:
  case drive_protocol_ftps:
  case drive_protocol_http:
  case drive_protocol_https:
  case drive_protocol_ssh:
  case drive_protocol_tftp:
    NOT_SUPPORTED (g, -1,
                   _("discard cannot be enabled on this drive: "
                     "protocol ‘%s’ does not support discard"),
                   guestfs_int_drive_protocol_to_string (drv->src.protocol));
  }

  return true;
}

/**
 * Free the C<struct qemu_data>.
 */
void
guestfs_int_free_qemu_data (struct qemu_data *data)
{
  if (data) {
    free (data->qemu_help);
    free (data->qemu_devices);
    free (data->qmp_schema);
    free (data->query_kvm);
    json_decref (data->qmp_schema_tree);
    free (data);
  }
}
