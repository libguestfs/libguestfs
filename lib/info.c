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

#include <json.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

#define CLEANUP_JSON_OBJECT_PUT \
  __attribute__((cleanup(cleanup_json_object_put)))

static void
cleanup_json_object_put (void *ptr)
{
  json_object_put (* (json_object **) ptr);
}

static json_object *get_json_output (guestfs_h *g, const char *filename);
static int qemu_img_supports_U_option (guestfs_h *g);
static void set_child_rlimits (struct command *);

char *
guestfs_impl_disk_format (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_OBJECT_PUT json_object *tree = get_json_output (g, filename);
  json_object *node;
  const char *format;

  if (tree == NULL)
    return NULL;

  if (json_object_get_type (tree) != json_type_object)
    goto bad_type;

  node = json_object_object_get (tree, "format");
  if (node == NULL)
    goto bad_type;

  format = json_object_get_string (node);

  return safe_strdup (g, format); /* caller frees */

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain ‘format’ key"));
  return NULL;
}

int64_t
guestfs_impl_disk_virtual_size (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_OBJECT_PUT json_object *tree = get_json_output (g, filename);
  json_object *node;

  if (tree == NULL)
    return -1;

  if (json_object_get_type (tree) != json_type_object)
    goto bad_type;

  node = json_object_object_get (tree, "virtual-size");
  if (node == NULL)
    goto bad_type;

  return json_object_get_int64 (node);

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain ‘virtual-size’ key"));
  return -1;
}

int
guestfs_impl_disk_has_backing_file (guestfs_h *g, const char *filename)
{
  CLEANUP_JSON_OBJECT_PUT json_object *tree = get_json_output (g, filename);
  json_object *node;

  if (tree == NULL)
    return -1;

  if (json_object_get_type (tree) != json_type_object)
    goto bad_type;

  node = json_object_object_get (tree, "backing-filename");
  if (node == NULL)
    return 0; /* no backing-filename key or null means no backing file */
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

static json_object *
get_json_output (guestfs_h *g, const char *filename)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;
  json_object *tree = NULL;

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

  return tree;          /* caller must call json_object_put (tree) */
}

/* Parse the JSON document printed by qemu-img info --output json. */
static void
parse_json (guestfs_h *g, void *treevp, const char *input, size_t len)
{
  json_tokener *tok = NULL;
  json_object **tree_ret = treevp;
  enum json_tokener_error err;

  assert (*tree_ret == NULL);

  /* If the input is completely empty, return a magic value to the
   * caller.  'qemu-img info' will return an error, but this will let
   * us catch the case where it does not.
   */
  if (len == 0) {
    *tree_ret = PARSE_JSON_NO_OUTPUT;
    return;
  }

  debug (g, "%s: qemu-img info JSON output:\n%.*s\n",
         __func__, (int) len, input);

  tok = json_tokener_new ();
  json_tokener_set_flags (tok,
                          JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
  *tree_ret = json_tokener_parse_ex (tok, input, len);
  err = json_tokener_get_error (tok);
  if (err != json_tokener_success) {
    error (g, _("qemu-img info: JSON parse error: %s"),
           json_tokener_error_desc (err));
    *tree_ret = NULL;           /* should already be */
  }
  json_tokener_free (tok);
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
