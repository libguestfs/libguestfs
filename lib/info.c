/* libguestfs
 * Copyright (C) 2012 Red Hat Inc.
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
#include <inttypes.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>

#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif

#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif

#include <jansson.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

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

static json_t *get_json_output (guestfs_h *g, const char *filename);
static int qemu_img_supports_U_option (guestfs_h *g);
static void set_child_rlimits (struct command *);

char *
guestfs_impl_disk_format (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_T_DECREF json_t *tree = get_json_output (g, filename);
  json_t *node;

  if (tree == NULL)
    return NULL;

  if (!json_is_object (tree))
    goto bad_type;

  node = json_object_get (tree, "format");
  if (!json_is_string (node))
    goto bad_type;

  return safe_strndup (g, json_string_value (node),
                          json_string_length (node)); /* caller frees */

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain ‘format’ key"));
  return NULL;
}

int64_t
guestfs_impl_disk_virtual_size (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_T_DECREF json_t *tree = get_json_output (g, filename);
  json_t *node;

  if (tree == NULL)
    return -1;

  if (!json_is_object (tree))
    goto bad_type;

  node = json_object_get (tree, "virtual-size");
  if (!json_is_integer (node))
    goto bad_type;

  return json_integer_value (node);

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain ‘virtual-size’ key"));
  return -1;
}

int
guestfs_impl_disk_has_backing_file (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_T_DECREF json_t *tree = get_json_output (g, filename);
  json_t *node;

  if (tree == NULL)
    return -1;

  if (!json_is_object (tree))
    goto bad_type;

  node = json_object_get (tree, "backing-filename");
  if (node == NULL)
    return 0; /* no backing-filename key means no backing file */

  /* Work on the assumption that if this field is null, it means
   * no backing file, rather than being an error.
   */
  if (json_is_null (node))
    return 0;
  return 1;

 bad_type:
  error (g, _("qemu-img info: JSON output was not an object"));
  return -1;
}

/* Run 'qemu-img info --output json filename', and parse the output
 * as JSON, returning a JSON tree and handling errors.
 */
static void parse_json (guestfs_h *g, void *treevp, const char *input, size_t len);
#define PARSE_JSON_NO_OUTPUT ((void *) -1)

static json_t *
get_json_output (guestfs_h *g, const char *filename)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  json_t *tree = NULL;

  guestfs_int_cmd_add_arg (cmd, "qemu-img");
  guestfs_int_cmd_add_arg (cmd, "info");
  switch (qemu_img_supports_U_option (g)) {
  case -1: return NULL;
  case 0:  break;
  default: guestfs_int_cmd_add_arg (cmd, "-U");
  }
  guestfs_int_cmd_add_arg (cmd, "--output");
  guestfs_int_cmd_add_arg (cmd, "json");
  if (filename[0] == '/')
    guestfs_int_cmd_add_arg (cmd, filename);
  else
    guestfs_int_cmd_add_arg_format (cmd, "./%s", filename);
  guestfs_int_cmd_set_stdout_callback (cmd, parse_json, &tree,
                                       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  set_child_rlimits (cmd);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return NULL;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "qemu-img info", filename);
    return NULL;
  }

  if (tree == NULL)
    return NULL;        /* parse_json callback already set an error */

  if (tree == PARSE_JSON_NO_OUTPUT) {
    /* If this ever happened, it would indicate a bug in 'qemu-img info'. */
    error (g, _("qemu-img info command produced no output, but didn't return an error status code"));
    return NULL;
  }

  return tree;          /* caller must call json_decref (tree) */
}

/* Parse the JSON document printed by qemu-img info --output json. */
static void
parse_json (guestfs_h *g, void *treevp, const char *input, size_t len)
{
  json_t **tree_ret = treevp;
  json_error_t err;

  assert (*tree_ret == NULL);

  /* If the input is completely empty, return a magic value to the
   * caller.  'qemu-img info' will return an error, but this will let
   * us catch the case where it does not.
   */
  if (len == 0) {
    *tree_ret = PARSE_JSON_NO_OUTPUT;
    return;
  }

  debug (g, "%s: qemu-img info JSON output:\n%.*s\n", __func__, (int) len, input);

  *tree_ret = json_loadb (input, len, 0, &err);
  if (*tree_ret == NULL) {
    if (strlen (err.text) > 0)
      error (g, _("qemu-img info: JSON parse error: %s"), err.text);
    else
      error (g, _("qemu-img info: unknown JSON parse error"));
  }
}

static void
set_child_rlimits (struct command *cmd)
{
#ifdef RLIMIT_AS
  const long one_gb = 1024L * 1024 * 1024;
  guestfs_int_cmd_set_child_rlimit (cmd, RLIMIT_AS, one_gb);
#endif
#ifdef RLIMIT_CPU
  guestfs_int_cmd_set_child_rlimit (cmd, RLIMIT_CPU, 10 /* seconds */);
#endif
}

/**
 * Test if the qemu-img info command supports the C<-U> option to
 * disable locking.  The result is memoized in the handle.
 *
 * Note this option was added in qemu 2.11.  We can remove this test
 * when we can assume everyone is using qemu >= 2.11.
 */
static int
qemu_img_supports_U_option (guestfs_h *g)
{
  if (g->qemu_img_supports_U_option >= 0)
    return g->qemu_img_supports_U_option;

  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  guestfs_int_cmd_add_string_unquoted (cmd,
                                       "qemu-img --help | "
                                       "grep -sqE -- '\\binfo\\b.*-U\\b'");
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r)) {
    guestfs_int_external_command_failed (g, r,
                                         "qemu-img info -U option test",
                                         NULL);
    return -1;
  }

  g->qemu_img_supports_U_option = WEXITSTATUS (r) == 0;
  return g->qemu_img_supports_U_option;
}
