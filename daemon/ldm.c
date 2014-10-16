/* libguestfs - the guestfsd daemon
 * Copyright (C) 2012 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <glob.h>
#include <string.h>

#if HAVE_YAJL
#include <yajl/yajl_tree.h>
#endif

#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#if HAVE_YAJL

GUESTFSD_EXT_CMD(str_ldmtool, ldmtool);

int
optgroup_ldm_available (void)
{
  return prog_exists (str_ldmtool);
}

static int
glob_errfunc (const char *epath, int eerrno)
{
  fprintf (stderr, "glob: failure reading %s: %s\n", epath, strerror (eerrno));
  return 1;
}

static char **
get_devices (const char *pattern)
{
  DECLARE_STRINGSBUF (ret);
  glob_t devs;
  int err;
  size_t i;

  memset (&devs, 0, sizeof devs);

  err = glob (pattern, GLOB_ERR, glob_errfunc, &devs);
  if (err == GLOB_NOSPACE) {
    reply_with_error ("glob: returned GLOB_NOSPACE: "
                      "rerun with LIBGUESTFS_DEBUG=1");
    goto error;
  } else if (err == GLOB_ABORTED) {
    reply_with_error ("glob: returned GLOB_ABORTED: "
                      "rerun with LIBGUESTFS_DEBUG=1");
    goto error;
  }

  for (i = 0; i < devs.gl_pathc; ++i) {
    if (add_string (&ret, devs.gl_pathv[i]) == -1)
      goto error;
  }

  if (end_stringsbuf (&ret) == -1) goto error;

  globfree (&devs);
  return ret.argv;

 error:
  globfree (&devs);
  if (ret.argv != NULL)
    free_stringslen (ret.argv, ret.size);

  return NULL;
}

/* All device mapper devices called /dev/mapper/ldm_vol_*.  XXX We
 * could tighten this up in future if ldmtool had a way to read these
 * names back after they have been created.
 */
char **
do_list_ldm_volumes (void)
{
  struct stat buf;

  /* If /dev/mapper doesn't exist at all, don't give an error. */
  if (stat ("/dev/mapper", &buf) == -1) {
    if (errno == ENOENT)
      return empty_list ();
    reply_with_perror ("/dev/mapper");
    return NULL;
  }

  return get_devices ("/dev/mapper/ldm_vol_*");
}

/* Same as above but /dev/mapper/ldm_part_*.  See comment above. */
char **
do_list_ldm_partitions (void)
{
  struct stat buf;

  /* If /dev/mapper doesn't exist at all, don't give an error. */
  if (stat ("/dev/mapper", &buf) == -1) {
    if (errno == ENOENT)
      return empty_list ();
    reply_with_perror ("/dev/mapper");
    return NULL;
  }

  return get_devices ("/dev/mapper/ldm_part_*");
}

int
do_ldmtool_create_all (void)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, str_ldmtool, "create", "all", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }
  return 0;
}

int
do_ldmtool_remove_all (void)
{
  int r;
  CLEANUP_FREE char *err = NULL;

  r = command (NULL, &err, str_ldmtool, "remove", "all", NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return -1;
  }
  return 0;
}

static yajl_val
parse_json (const char *json, const char *func)
{
  yajl_val tree;
  char parse_error[1024];

  if (verbose)
    fprintf (stderr, "%s: parsing json: %s\n", func, json);

  tree = yajl_tree_parse (json, parse_error, sizeof parse_error);
  if (tree == NULL) {
    reply_with_error ("parse error: %s",
                      strlen (parse_error) ? parse_error : "unknown error");
    return NULL;
  }

  /* Caller should free this by doing 'yajl_tree_free (tree);'. */
  return tree;
}

#define TYPE_ERROR ((char **) -1)

static char **
json_value_to_string_list (yajl_val node)
{
  DECLARE_STRINGSBUF (strs);
  yajl_val n;
  size_t i, len;

  if (! YAJL_IS_ARRAY (node))
    return TYPE_ERROR;

  len = YAJL_GET_ARRAY(node)->len;
  for (i = 0; i < len; ++i) {
    n = YAJL_GET_ARRAY(node)->values[i];
    if (! YAJL_IS_STRING (n))
      return TYPE_ERROR;
    if (add_string (&strs, YAJL_GET_STRING (n)) == -1)
      return NULL;
  }
  if (end_stringsbuf (&strs) == -1)
    return NULL;

  return strs.argv;
}

static char **
parse_json_get_string_list (const char *json,
                            const char *func, const char *cmd)
{
  char **ret;
  yajl_val tree = NULL;

  tree = parse_json (json, func);
  if (tree == NULL)
    return NULL;

  ret = json_value_to_string_list (tree);
  yajl_tree_free (tree);
  if (ret == TYPE_ERROR) {
    reply_with_error ("output of '%s' was not a JSON array of strings", cmd);
    return NULL;
  }
  return ret;
}

#define GET_STRING_NULL_TO_EMPTY 1

static char *
parse_json_get_object_string (const char *json, const char *key, int flags,
                              const char *func, const char *cmd)
{
  char *str, *ret;
  yajl_val tree = NULL, node;
  size_t i, len;

  tree = parse_json (json, func);
  if (tree == NULL)
    return NULL;

  if (! YAJL_IS_OBJECT (tree))
    goto bad_type;

  len = YAJL_GET_OBJECT(tree)->len;
  for (i = 0; i < len; ++i) {
    if (STREQ (YAJL_GET_OBJECT(tree)->keys[i], key)) {
      node = YAJL_GET_OBJECT(tree)->values[i];

      if ((flags & GET_STRING_NULL_TO_EMPTY) && YAJL_IS_NULL (node))
        ret = strdup ("");
      else {
        str = YAJL_GET_STRING (node);
        if (str == NULL)
          goto bad_type;
        ret = strdup (str);
      }
      if (ret == NULL)
        reply_with_perror ("strdup");

      yajl_tree_free (tree);

      return ret;
    }
  }

 bad_type:
  reply_with_error ("output of '%s' was not a JSON object "
                    "containing a key '%s' of type string", cmd, key);
  yajl_tree_free (tree);
  return NULL;
}

static char **
parse_json_get_object_string_list (const char *json, const char *key,
                                   const char *func, const char *cmd)
{
  char **ret;
  yajl_val tree, node;
  size_t i, len;

  tree = parse_json (json, func);
  if (tree == NULL)
    return NULL;

  if (! YAJL_IS_OBJECT (tree))
    goto bad_type;

  len = YAJL_GET_OBJECT(tree)->len;
  for (i = 0; i < len; ++i) {
    if (STREQ (YAJL_GET_OBJECT(tree)->keys[i], key)) {
      node = YAJL_GET_OBJECT(tree)->values[i];
      ret = json_value_to_string_list (node);
      if (ret == TYPE_ERROR)
        goto bad_type;
      yajl_tree_free (tree);
      return ret;
    }
  }

 bad_type:
  reply_with_error ("output of '%s' was not a JSON object "
                    "containing a key '%s' of type array of strings",
                    cmd, key);
  yajl_tree_free (tree);
  return NULL;
}

char **
do_ldmtool_scan (void)
{
  const char *empty_list[] = { NULL };

  return do_ldmtool_scan_devices ((char * const *) empty_list);
}

char **
do_ldmtool_scan_devices (char * const * devices)
{
  char **ret;
  size_t i, nr_devices;
  CLEANUP_FREE_STRING_LIST const char **argv = NULL;
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  nr_devices = count_strings (devices);
  argv = malloc ((3 + nr_devices) * sizeof (char *));
  if (argv == NULL) {
    reply_with_perror ("malloc");
    return NULL;
  }

  argv[0] = str_ldmtool;
  argv[1] = "scan";
  for (i = 0; i < nr_devices; ++i)
    argv[2+i] = devices[i];
  argv[2+i] = NULL;

  r = commandv (&out, &err, argv);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  ret = parse_json_get_string_list (out, __func__, "ldmtool scan");
  return ret;
}

char *
do_ldmtool_diskgroup_name (const char *diskgroup)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err, str_ldmtool, "show", "diskgroup", diskgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  return parse_json_get_object_string (out, "name", 0,
                                       __func__, "ldmtool show diskgroup");
}

char **
do_ldmtool_diskgroup_volumes (const char *diskgroup)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err, str_ldmtool, "show", "diskgroup", diskgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }
  free (err);

  return parse_json_get_object_string_list (out, "volumes",
                                            __func__, "ldmtool show diskgroup");
}

char **
do_ldmtool_diskgroup_disks (const char *diskgroup)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err, str_ldmtool, "show", "diskgroup", diskgroup, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  return parse_json_get_object_string_list (out, "disks",
                                            __func__, "ldmtool show diskgroup");
}

char *
do_ldmtool_volume_type (const char *diskgroup, const char *volume)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err,
               str_ldmtool, "show", "volume", diskgroup, volume, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  return parse_json_get_object_string (out, "type", 0,
                                       __func__, "ldmtool show volume");
}

char *
do_ldmtool_volume_hint (const char *diskgroup, const char *volume)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err,
               str_ldmtool, "show", "volume", diskgroup, volume, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  return parse_json_get_object_string (out, "hint", GET_STRING_NULL_TO_EMPTY,
                                       __func__, "ldmtool show volume");
}

char **
do_ldmtool_volume_partitions (const char *diskgroup, const char *volume)
{
  int r;
  CLEANUP_FREE char *out = NULL, *err = NULL;

  r = command (&out, &err,
               str_ldmtool, "show", "volume", diskgroup, volume, NULL);
  if (r == -1) {
    reply_with_error ("%s", err);
    return NULL;
  }

  return parse_json_get_object_string_list (out, "partitions",
                                            __func__, "ldmtool show volume");
}

#else /* !HAVE_YAJL */

OPTGROUP_LDM_NOT_AVAILABLE

#endif
