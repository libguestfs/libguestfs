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
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <assert.h>

#if HAVE_YAJL
#include <yajl/yajl_tree.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

static int which_parser (guestfs_h *g);
static char *get_disk_format (guestfs_h *g, const char *filename);
static int64_t get_disk_virtual_size (guestfs_h *g, const char *filename);
static int get_disk_has_backing_file (guestfs_h *g, const char *filename);
#if HAVE_YAJL
static yajl_val get_json_output (guestfs_h *g, const char *filename);
#endif
static char *old_parser_disk_format (guestfs_h *g, const char *filename);
static int64_t old_parser_disk_virtual_size (guestfs_h *g, const char *filename);
static int old_parser_disk_has_backing_file (guestfs_h *g, const char *filename);

char *
guestfs_impl_disk_format (guestfs_h *g, const char *filename)
{
  switch (which_parser (g)) {
  case QEMU_IMG_INFO_NEW_PARSER:
    return get_disk_format (g, filename);
  case QEMU_IMG_INFO_OLD_PARSER:
    return old_parser_disk_format (g, filename);
  case QEMU_IMG_INFO_UNKNOWN_PARSER:
    abort ();
  }

  abort ();
}

int64_t
guestfs_impl_disk_virtual_size (guestfs_h *g, const char *filename)
{
  switch (which_parser (g)) {
  case QEMU_IMG_INFO_NEW_PARSER:
    return get_disk_virtual_size (g, filename);
  case QEMU_IMG_INFO_OLD_PARSER:
    return old_parser_disk_virtual_size (g, filename);
  case QEMU_IMG_INFO_UNKNOWN_PARSER:
    abort ();
  }

  abort ();
}

int
guestfs_impl_disk_has_backing_file (guestfs_h *g, const char *filename)
{
  switch (which_parser (g)) {
  case QEMU_IMG_INFO_NEW_PARSER:
    return get_disk_has_backing_file (g, filename);
  case QEMU_IMG_INFO_OLD_PARSER:
    return old_parser_disk_has_backing_file (g, filename);
  case QEMU_IMG_INFO_UNKNOWN_PARSER:
    abort ();
  }

  abort ();
}

#if HAVE_YAJL

# ifdef HAVE_ATTRIBUTE_CLEANUP
# define CLEANUP_YAJL_TREE_FREE __attribute__((cleanup(cleanup_yajl_tree_free)))

static void
cleanup_yajl_tree_free (void *ptr)
{
  yajl_tree_free (* (yajl_val *) ptr);
}

# else
# define CLEANUP_YAJL_TREE_FREE
# endif
#endif /* HAVE_ATTRIBUTE_CLEANUP */

static char *
get_disk_format (guestfs_h *g, const char *filename)
{
#if HAVE_YAJL

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

#else /* !HAVE_YAJL */
  abort ();
#endif /* !HAVE_YAJL */
}

static int64_t
get_disk_virtual_size (guestfs_h *g, const char *filename)
{
#if HAVE_YAJL

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

#else /* !HAVE_YAJL */
  abort ();
#endif /* !HAVE_YAJL */
}

static int
get_disk_has_backing_file (guestfs_h *g, const char *filename)
{
#if HAVE_YAJL

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

#else /* !HAVE_YAJL */
  abort ();
#endif /* !HAVE_YAJL */
}

#if HAVE_YAJL

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

static void help_contains_output_json (guestfs_h *g, void *datav, const char *help_line, size_t len);

/* Choose new (JSON) or old (human) parser? */
static int
which_parser (guestfs_h *g)
{
  if (g->qemu_img_info_parser == QEMU_IMG_INFO_UNKNOWN_PARSER) {
    int qemu_img_supports_json = 0;
    CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);

    guestfs_int_cmd_add_arg (cmd, "qemu-img");
    guestfs_int_cmd_add_arg (cmd, "--help");
    guestfs_int_cmd_set_stdout_callback (cmd,
                                       help_contains_output_json,
                                       &qemu_img_supports_json, 0);
    guestfs_int_cmd_run (cmd);
    /* ignore return code, which would usually be 1 */

    if (qemu_img_supports_json)
      g->qemu_img_info_parser = QEMU_IMG_INFO_NEW_PARSER;
    else
      g->qemu_img_info_parser = QEMU_IMG_INFO_OLD_PARSER;
  }

  debug (g, "%s: g->qemu_img_info_parser = %d",
         __func__, g->qemu_img_info_parser);

  return g->qemu_img_info_parser;
}

static void
help_contains_output_json (guestfs_h *g, void *datav,
                           const char *help_line, size_t len)
{
  if (strstr (help_line, "--output") != NULL &&
      strstr (help_line, "json") != NULL) {
    * (int *) datav = 1;
  }
}

#else /* !HAVE_YAJL */

/* With no YAJL, only the old parser is available. */
static int
which_parser (guestfs_h *g)
{
  return g->qemu_img_info_parser = QEMU_IMG_INFO_OLD_PARSER;
}

#endif /* !HAVE_YAJL */

/*----------------------------------------------------------------------
 * This is the old parser for the old / human-readable output of
 * qemu-img info, ONLY used if EITHER you've got an old version of
 * qemu-img, OR you're not using yajl.  It is highly recommended that
 * you upgrade qemu-img and install yajl so that you can use the new,
 * secure JSON parser above.
 */

static int old_parser_run_qemu_img_info (guestfs_h *g, const char *filename, cmd_stdout_callback cb, void *data);

/* NB: For security reasons, the check_* callbacks MUST bail
 * after seeing the first line that matches /^backing file: /.  See:
 * https://lists.gnu.org/archive/html/qemu-devel/2012-09/msg00137.html
 */

struct old_parser_check_data {
  int stop, failed;
  union {
    char *ret;
    int reti;
    int64_t reti64;
  };
};

static void old_parser_check_disk_format (guestfs_h *g, void *data, const char *line, size_t len);
static void old_parser_check_disk_virtual_size (guestfs_h *g, void *data, const char *line, size_t len);
static void old_parser_check_disk_has_backing_file (guestfs_h *g, void *data, const char *line, size_t len);

static char *
old_parser_disk_format (guestfs_h *g, const char *filename)
{
  struct old_parser_check_data data;

  memset (&data, 0, sizeof data);

  if (old_parser_run_qemu_img_info (g, filename,
                                    old_parser_check_disk_format,
                                    &data) == -1) {
    free (data.ret);
    return NULL;
  }

  if (data.ret == NULL)
    data.ret = safe_strdup (g, "unknown");

  return data.ret;
}

static void
old_parser_check_disk_format (guestfs_h *g, void *datav,
                              const char *line, size_t len)
{
  struct old_parser_check_data *data = datav;
  const char *p;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->stop = 1;
    return;
  }

  if (STRPREFIX (line, "file format: ")) {
    p = &line[13];
    data->ret = safe_strdup (g, p);
    data->stop = 1;
  }
}

static int64_t
old_parser_disk_virtual_size (guestfs_h *g, const char *filename)
{
  struct old_parser_check_data data;

  memset (&data, 0, sizeof data);

  if (old_parser_run_qemu_img_info (g, filename,
                                    old_parser_check_disk_virtual_size,
                                    &data) == -1)
    return -1;

  if (data.failed)
    error (g, _("%s: cannot detect virtual size of disk image"), filename);

  return data.reti64;
}

static void
old_parser_check_disk_virtual_size (guestfs_h *g, void *datav,
                                    const char *line, size_t len)
{
  struct old_parser_check_data *data = datav;
  const char *p;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->stop = 1;
    return;
  }

  if (STRPREFIX (line, "virtual size: ")) {
    /* "virtual size: 500M (524288000 bytes)\n" */
    p = &line[14];
    p = strchr (p, ' ');
    if (!p || p[1] != '(' || sscanf (&p[2], "%" SCNi64, &data->reti64) != 1)
      data->failed = 1;
    data->stop = 1;
  }
}

static int
old_parser_disk_has_backing_file (guestfs_h *g, const char *filename)
{
  struct old_parser_check_data data;

  memset (&data, 0, sizeof data);

  if (old_parser_run_qemu_img_info (g, filename,
                                    old_parser_check_disk_has_backing_file,
                                    &data) == -1)
    return -1;

  return data.reti;
}

static void
old_parser_check_disk_has_backing_file (guestfs_h *g, void *datav,
                                        const char *line, size_t len)
{
  struct old_parser_check_data *data = datav;

  if (data->stop)
    return;

  if (STRPREFIX (line, "backing file: ")) {
    data->reti = 1;
    data->stop = 1;
  }
}

static int
old_parser_run_qemu_img_info (guestfs_h *g, const char *filename,
                              cmd_stdout_callback fn, void *data)
{
  CLEANUP_FREE char *abs_filename = NULL;
  CLEANUP_FREE char *safe_filename = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  if (guestfs_int_lazy_make_tmpdir (g) == -1)
    return -1;

  safe_filename = safe_asprintf (g, "%s/format.%d", g->tmpdir, ++g->unique);

  /* 'filename' must be an absolute path so we can link to it. */
  abs_filename = realpath (filename, NULL);
  if (abs_filename == NULL) {
    perrorf (g, "realpath");
    return -1;
  }

  if (symlink (abs_filename, safe_filename) == -1) {
    perrorf (g, "symlink");
    return -1;
  }

  guestfs_int_cmd_add_arg (cmd, "qemu-img");
  guestfs_int_cmd_add_arg (cmd, "info");
  guestfs_int_cmd_add_arg (cmd, safe_filename);
  guestfs_int_cmd_set_stdout_callback (cmd, fn, data, 0);
  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, "qemu-img info", filename);
    return -1;
  }

  return 0;
}
