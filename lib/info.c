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
#include <sys/stat.h>
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

#include <yajl/yajl_tree.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_YAJL_TREE_FREE __attribute__((cleanup(cleanup_yajl_tree_free)))

static void
cleanup_yajl_tree_free (void *ptr)
{
  yajl_tree_free (* (yajl_val *) ptr);
}

#else
#define CLEANUP_YAJL_TREE_FREE
#endif

static yajl_val get_json_output (guestfs_h *g, const char *filename);
static void set_child_rlimits (struct command *);

char *
guestfs_impl_disk_format (guestfs_h *g, const char *filename)
{
  size_t i, len;
  CLEANUP_YAJL_TREE_FREE yajl_val tree = get_json_output (g, filename);

  if (tree == NULL)
    return NULL;

  if (! YAJL_IS_OBJECT (tree))
    goto bad_type;

  len = YAJL_GET_OBJECT(tree)->len;
  for (i = 0; i < len; ++i) {
    if (STREQ (YAJL_GET_OBJECT(tree)->keys[i], "format")) {
      const char *str;
      yajl_val node = YAJL_GET_OBJECT(tree)->values[i];
      if (YAJL_IS_NULL (node))
        goto bad_type;
      str = YAJL_GET_STRING (node);
      if (str == NULL)
        goto bad_type;
      return safe_strdup (g, str); /* caller frees */
    }
  }

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain 'format' key"));
  return NULL;
}

int64_t
guestfs_impl_disk_virtual_size (guestfs_h *g, const char *filename)
{
  size_t i, len;
  CLEANUP_YAJL_TREE_FREE yajl_val tree = get_json_output (g, filename);

  if (tree == NULL)
    return -1;

  if (! YAJL_IS_OBJECT (tree))
    goto bad_type;

  len = YAJL_GET_OBJECT(tree)->len;
  for (i = 0; i < len; ++i) {
    if (STREQ (YAJL_GET_OBJECT(tree)->keys[i], "virtual-size")) {
      yajl_val node = YAJL_GET_OBJECT(tree)->values[i];
      if (YAJL_IS_NULL (node))
        goto bad_type;
      if (! YAJL_IS_NUMBER (node))
        goto bad_type;
      if (! YAJL_IS_INTEGER (node)) {
        error (g, _("qemu-img info: 'virtual-size' is not representable as a 64 bit integer"));
        return -1;
      }
      return YAJL_GET_INTEGER (node);
    }
  }

 bad_type:
  error (g, _("qemu-img info: JSON output did not contain 'virtual-size' key"));
  return -1;
}

int
guestfs_impl_disk_has_backing_file (guestfs_h *g, const char *filename)
{
  size_t i, len;
  CLEANUP_YAJL_TREE_FREE yajl_val tree = get_json_output (g, filename);

  if (tree == NULL)
    return -1;

  if (! YAJL_IS_OBJECT (tree))
    goto bad_type;

  len = YAJL_GET_OBJECT(tree)->len;
  for (i = 0; i < len; ++i) {
    if (STREQ (YAJL_GET_OBJECT(tree)->keys[i], "backing-filename")) {
      yajl_val node = YAJL_GET_OBJECT(tree)->values[i];
      /* Work on the assumption that if this field is null, it means
       * no backing file, rather than being an error.
       */
      if (YAJL_IS_NULL (node))
        return 0;
      return 1;
    }
  }

  return 0; /* no backing-filename key means no backing file */

 bad_type:
  error (g, _("qemu-img info: JSON output was not an object"));
  return -1;
}

/* Run 'qemu-img info --output json filename', and parse the output
 * as JSON, returning a JSON tree and handling errors.
 */
static void parse_json (guestfs_h *g, void *treevp, const char *input, size_t len);
#define PARSE_JSON_NO_OUTPUT ((void *) -1)

static yajl_val
get_json_output (guestfs_h *g, const char *filename)
{
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int fd, r;
  char fdpath[64];
  yajl_val tree = NULL;
  struct stat statbuf;

  fd = open (filename, O_RDONLY /* NB: !O_CLOEXEC */);
  if (fd == -1) {
    perrorf (g, "disk info: %s", filename);
    return NULL;
  }

  if (fstat (fd, &statbuf) == -1) {
    perrorf (g, "disk info: fstat: %s", filename);
    close (fd);
    return NULL;
  }
  if (S_ISDIR (statbuf.st_mode)) {
    error (g, "disk info: %s is a directory", filename);
    close (fd);
    return NULL;
  }

  snprintf (fdpath, sizeof fdpath, "/dev/fd/%d", fd);
  guestfs_int_cmd_clear_close_files (cmd);

  guestfs_int_cmd_add_arg (cmd, "qemu-img");
  guestfs_int_cmd_add_arg (cmd, "info");
  guestfs_int_cmd_add_arg (cmd, "--output");
  guestfs_int_cmd_add_arg (cmd, "json");
  guestfs_int_cmd_add_arg (cmd, fdpath);
  guestfs_int_cmd_set_stdout_callback (cmd, parse_json, &tree,
                                       CMD_STDOUT_FLAG_WHOLE_BUFFER);
  set_child_rlimits (cmd);
  r = guestfs_int_cmd_run (cmd);
  close (fd);
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

  return tree;          /* caller must call yajl_tree_free (tree) */
}

/* Parse the JSON document printed by qemu-img info --output json. */
static void
parse_json (guestfs_h *g, void *treevp, const char *input, size_t len)
{
  yajl_val *tree_ret = treevp;
  CLEANUP_FREE char *input_copy = NULL;
  char parse_error[256];

  assert (*tree_ret == NULL);

  /* If the input is completely empty, return a magic value to the
   * caller.  'qemu-img info' will return an error, but this will let
   * us catch the case where it does not.
   */
  if (len == 0) {
    *tree_ret = PARSE_JSON_NO_OUTPUT;
    return;
  }

  /* 'input' is not \0-terminated; we have to make it so. */
  input_copy = safe_strndup (g, input, len);

  debug (g, "%s: qemu-img info JSON output:\n%s\n", __func__, input_copy);

  *tree_ret = yajl_tree_parse (input_copy, parse_error, sizeof parse_error);
  if (*tree_ret == NULL) {
    if (strlen (parse_error) > 0)
      error (g, _("qemu-img info: JSON parse error: %s"), parse_error);
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
