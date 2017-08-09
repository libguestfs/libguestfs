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
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#ifdef HAVE_HIVEX

#include <hivex.h>

int
optgroup_hivex_available (void)
{
  return 1;
}

/* The hivex handle.  As with Augeas, there is one per guestfs handle /
 * daemon.
 */
static hive_h *h = NULL;

/* Clean up the hivex handle on daemon exit. */
void hivex_finalize (void) __attribute__((destructor));
void
hivex_finalize (void)
{
  if (h) {
    hivex_close (h);
    h = NULL;
  }
}

#define NEED_HANDLE(errcode)						\
  do {									\
    if (!h) {								\
      reply_with_error ("%s: you must call 'hivex-open' first to initialize the hivex handle", __func__); \
      return (errcode);							\
    }									\
  }									\
  while (0)

/* Takes optional arguments, consult optargs_bitmask. */
int
do_hivex_open (const char *filename,
               int verbose, int debug, int write, int unsafe)
{
  CLEANUP_FREE char *buf = NULL;
  int flags = 0;

  if (h) {
    hivex_close (h);
    h = NULL;
  }

  buf = sysroot_path (filename);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  if (optargs_bitmask & GUESTFS_HIVEX_OPEN_VERBOSE_BITMASK) {
    if (verbose)
      flags |= HIVEX_OPEN_VERBOSE;
  }
  if (optargs_bitmask & GUESTFS_HIVEX_OPEN_DEBUG_BITMASK) {
    if (debug)
      flags |= HIVEX_OPEN_DEBUG;
  }
  if (optargs_bitmask & GUESTFS_HIVEX_OPEN_WRITE_BITMASK) {
    if (write)
      flags |= HIVEX_OPEN_WRITE;
  }
#ifdef HIVEX_OPEN_UNSAFE
  if (optargs_bitmask & GUESTFS_HIVEX_OPEN_UNSAFE_BITMASK) {
    if (unsafe)
      flags |= HIVEX_OPEN_UNSAFE;
  }
#endif

  h = hivex_open (buf, flags);
  if (!h) {
    reply_with_perror ("hivex failed to open %s", filename);
    return -1;
  }

  return 0;
}

int
do_hivex_close (void)
{
  NEED_HANDLE (-1);

  hivex_close (h);
  h = NULL;

  return 0;
}

int64_t
do_hivex_root (void)
{
  int64_t r;

  NEED_HANDLE (-1);

  r = hivex_root (h);
  if (r == 0) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

char *
do_hivex_node_name (int64_t nodeh)
{
  char *r;

  NEED_HANDLE (NULL);

  r = hivex_node_name (h, nodeh);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  return r;
}

guestfs_int_hivex_node_list *
do_hivex_node_children (int64_t nodeh)
{
  guestfs_int_hivex_node_list *ret;
  CLEANUP_FREE hive_node_h *r = NULL;
  size_t i, len;

  NEED_HANDLE (NULL);

  r = hivex_node_children (h, nodeh);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  len = 0;
  for (i = 0; r[i] != 0; ++i)
    len++;

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->guestfs_int_hivex_node_list_len = len;
  ret->guestfs_int_hivex_node_list_val =
    malloc (len * sizeof (guestfs_int_hivex_node));
  if (ret->guestfs_int_hivex_node_list_val == NULL) {
    reply_with_perror ("malloc");
    free (ret);
    return NULL;
  }

  for (i = 0; i < len; ++i)
    ret->guestfs_int_hivex_node_list_val[i].hivex_node_h = r[i];

  return ret;
}

int64_t
do_hivex_node_get_child (int64_t nodeh, const char *name)
{
  int64_t r;

  NEED_HANDLE (-1);

  errno = 0;
  r = hivex_node_get_child (h, nodeh, name);
  if (r == 0 && errno != 0) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

int64_t
do_hivex_node_parent (int64_t nodeh)
{
  int64_t r;

  NEED_HANDLE (-1);

  r = hivex_node_parent (h, nodeh);
  if (r == 0) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

guestfs_int_hivex_value_list *
do_hivex_node_values (int64_t nodeh)
{
  guestfs_int_hivex_value_list *ret;
  CLEANUP_FREE hive_value_h *r = NULL;
  size_t i, len;

  NEED_HANDLE (NULL);

  r = hivex_node_values (h, nodeh);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  len = 0;
  for (i = 0; r[i] != 0; ++i)
    len++;

  ret = malloc (sizeof *ret);
  if (!ret) {
    reply_with_perror ("malloc");
    return NULL;
  }

  ret->guestfs_int_hivex_value_list_len = len;
  ret->guestfs_int_hivex_value_list_val =
    malloc (len * sizeof (guestfs_int_hivex_value));
  if (ret->guestfs_int_hivex_value_list_val == NULL) {
    reply_with_perror ("malloc");
    free (ret);
    return NULL;
  }

  for (i = 0; i < len; ++i)
    ret->guestfs_int_hivex_value_list_val[i].hivex_value_h = (int64_t) r[i];

  return ret;
}

int64_t
do_hivex_node_get_value (int64_t nodeh, const char *key)
{
  int64_t r;

  NEED_HANDLE (-1);

  errno = 0;
  r = hivex_node_get_value (h, nodeh, key);
  if (r == 0 && errno != 0) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

char *
do_hivex_value_key (int64_t valueh)
{
  char *r;

  NEED_HANDLE (NULL);

  r = hivex_value_key (h, valueh);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  return r;
}

int64_t
do_hivex_value_type (int64_t valueh)
{
  hive_type r;

  NEED_HANDLE (-1);

  if (hivex_value_type (h, valueh, &r, NULL) == -1) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

char *
do_hivex_value_value (int64_t valueh, size_t *size_r)
{
  char *r;
  size_t size;

  NEED_HANDLE (NULL);

  r = hivex_value_value (h, valueh, NULL, &size);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  *size_r = size;
  return r;
}

char *
do_hivex_value_string (int64_t valueh)
{
  char *r;

  NEED_HANDLE (NULL);

  r = hivex_value_string (h, valueh);
  if (r == NULL) {
    reply_with_perror ("failed");
    return NULL;
  }

  return r;
}

/* Deprecated alias for hivex_value_string. */
char *
do_hivex_value_utf8 (int64_t valueh)
{
  return do_hivex_value_string (valueh);
}

int
do_hivex_commit (const char *filename)
{
  CLEANUP_FREE char *buf = NULL;

  NEED_HANDLE (-1);

  /* The 'filename' parameter is an optional string, and in most
   * cases will be NULL.
   */
  if (filename) {
    /* There is no "OptPathname" in the generator, so we have
     * to do the pathname checks explicitly here.  RHBZ#981683
     */
    ABS_PATH (filename, 0, return -1);
    NEED_ROOT (0, return -1);

    buf = sysroot_path (filename);
    if (!buf) {
      reply_with_perror ("malloc");
      return -1;
    }

    if (hivex_commit (h, buf, 0) == -1) {
      reply_with_perror ("%s: commit failed", filename);
      return -1;
    }
  }
  else {
    if (hivex_commit (h, NULL, 0) == -1) {
      reply_with_perror ("commit failed");
      return -1;
    }
  }

  return 0;
}

int64_t
do_hivex_node_add_child (int64_t parent, const char *name)
{
  int64_t r;

  NEED_HANDLE (-1);

  r = hivex_node_add_child (h, parent, name);
  if (r == 0) {
    reply_with_perror ("failed");
    return -1;
  }

  return r;
}

int
do_hivex_node_delete_child (int64_t nodeh)
{
  NEED_HANDLE (-1);

  if (hivex_node_delete_child (h, nodeh) == -1) {
    reply_with_perror ("failed");
    return -1;
  }

  return 0;
}

int
do_hivex_node_set_value (int64_t nodeh,
                         const char *key, int64_t t,
                         const char *val, size_t val_size)
{
  const hive_set_value v =
    { .key = (char *) key, .t = t, .len = val_size, .value = (char *) val };

  NEED_HANDLE (-1);

  if (hivex_node_set_value (h, nodeh, &v, 0) == -1) {
    reply_with_perror ("failed");
    return -1;
  }

  return 0;
}

#else /* !HAVE_HIVEX */

OPTGROUP_HIVEX_NOT_AVAILABLE

void
hivex_finalize (void)
{
}

#endif /* !HAVE_HIVEX */
