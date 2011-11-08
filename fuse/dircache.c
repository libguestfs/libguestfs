/* guestmount - mount guests using libguestfs and FUSE
 * Copyright (C) 2009 Red Hat Inc.
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
 *
 * Derived from the example program 'fusexmp.c':
 * Copyright (C) 2001-2007  Miklos Szeredi <miklos@szeredi.hu>
 *
 * This program can be distributed under the terms of the GNU GPL.
 * See the file COPYING.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#include <sys/time.h>
#include <sys/types.h>

#include <guestfs.h>

#include "hash.h"
#include "hash-pjw.h"

#include "guestmount.h"
#include "dircache.h"

/* Note on attribute caching: FUSE can cache filesystem attributes for
 * short periods of time (configurable via -o attr_timeout).  It
 * doesn't cache xattrs, and in any case FUSE caching doesn't solve
 * the problem that we have to make a series of guestfs_lstat and
 * guestfs_lgetxattr calls when we first list a directory (thus, many
 * round trips).
 *
 * For this reason, we also implement a readdir cache here which is
 * invoked when a readdir call is made.  readdir is modified so that
 * as well as reading the directory, it also requests all the stat
 * structures, xattrs and readlinks of all entries in the directory,
 * and these are added to the cache here (for a short, configurable
 * period of time) in anticipation that they will be needed
 * immediately afterwards, which is usually the case when the user is
 * doing an "ls"-like operation.
 *
 * You can still use FUSE attribute caching on top of this mechanism
 * if you like.
 */

struct lsc_entry {              /* lstat cache entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  struct stat statbuf;          /* statbuf */
};

struct xac_entry {              /* xattr cache entry */
  /* NB first two fields must be same as lsc_entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  struct guestfs_xattr_list *xattrs;
};

struct rlc_entry {              /* readlink cache entry */
  /* NB first two fields must be same as lsc_entry */
  char *pathname;               /* full path to the file */
  time_t timeout;               /* when this entry expires */
  char *link;
};

static size_t
gen_hash (void const *x, size_t table_size)
{
  struct lsc_entry const *p = x;
  return hash_pjw (p->pathname, table_size);
}

static bool
gen_compare (void const *x, void const *y)
{
  struct lsc_entry const *a = x;
  struct lsc_entry const *b = y;
  return STREQ (a->pathname, b->pathname);
}

static void
lsc_free (void *x)
{
  if (x) {
    struct lsc_entry *p = x;

    free (p->pathname);
    free (p);
  }
}

static void
xac_free (void *x)
{
  if (x) {
    struct xac_entry *p = x;

    guestfs_free_xattr_list (p->xattrs);
    lsc_free (x);
  }
}

static void
rlc_free (void *x)
{
  if (x) {
    struct rlc_entry *p = x;

    free (p->link);
    lsc_free (x);
  }
}

static Hash_table *lsc_ht, *xac_ht, *rlc_ht;

void
init_dir_caches (void)
{
  lsc_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, lsc_free);
  xac_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, xac_free);
  rlc_ht = hash_initialize (1024, NULL, gen_hash, gen_compare, rlc_free);
  if (!lsc_ht || !xac_ht || !rlc_ht) {
    fprintf (stderr, "guestmount: could not initialize dir cache hashtables\n");
    exit (EXIT_FAILURE);
  }
}

void
free_dir_caches (void)
{
  hash_free (lsc_ht);
  hash_free (xac_ht);
  hash_free (rlc_ht);
}

struct gen_remove_data {
  time_t now;
  Hash_table *ht;
  Hash_data_freer freer;
};

static bool
gen_remove_if_expired (void *x, void *data)
{
  /* XXX hash_do_for_each was observed calling this function
   * with x == NULL.
   */
  if (x) {
    struct lsc_entry *p = x;
    struct gen_remove_data *d = data;

    if (p->timeout < d->now) {
      if (verbose)
        fprintf (stderr, "dir cache: expiring entry %p (%s)\n",
                 p, p->pathname);
      d->freer (hash_delete (d->ht, x));
    }
  }

  return 1;
}

static void
gen_remove_all_expired (Hash_table *ht, Hash_data_freer freer, time_t now)
{
  struct gen_remove_data data;
  data.now = now;
  data.ht = ht;
  data.freer = freer;

  /* Careful reading of the documentation to hash _seems_ to indicate
   * that this is safe, _provided_ we use the default thresholds (in
   * particular, no shrink threshold).
   */
  hash_do_for_each (ht, gen_remove_if_expired, &data);
}

void
dir_cache_remove_all_expired (time_t now)
{
  gen_remove_all_expired (lsc_ht, lsc_free, now);
  gen_remove_all_expired (xac_ht, xac_free, now);
  gen_remove_all_expired (rlc_ht, rlc_free, now);
}

static int
gen_replace (Hash_table *ht, struct lsc_entry *new_entry, Hash_data_freer freer)
{
  struct lsc_entry *old_entry;

  old_entry = hash_delete (ht, new_entry);
  freer (old_entry);

  if (verbose && old_entry)
    fprintf (stderr, "dir cache: this entry replaced old entry %p (%s)\n",
             old_entry, old_entry->pathname);

  old_entry = hash_insert (ht, new_entry);
  if (old_entry == NULL) {
    perror ("hash_insert");
    freer (new_entry);
    return -1;
  }
  assert (old_entry == new_entry);

  return 0;
}

int
lsc_insert (const char *path, const char *name, time_t now,
            struct stat const *statbuf)
{
  struct lsc_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  memcpy (&entry->statbuf, statbuf, sizeof entry->statbuf);

  entry->timeout = now + dir_cache_timeout;

  if (verbose)
    fprintf (stderr, "dir cache: inserting lstat entry %p (%s)\n",
             entry, entry->pathname);

  return gen_replace (lsc_ht, entry, lsc_free);
}

int
xac_insert (const char *path, const char *name, time_t now,
            struct guestfs_xattr_list *xattrs)
{
  struct xac_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  entry->xattrs = xattrs;

  entry->timeout = now + dir_cache_timeout;

  if (verbose)
    fprintf (stderr, "dir cache: inserting xattr entry %p (%s)\n",
             entry, entry->pathname);

  return gen_replace (xac_ht, (struct lsc_entry *) entry, xac_free);
}

int
rlc_insert (const char *path, const char *name, time_t now,
            char *link)
{
  struct rlc_entry *entry;

  entry = malloc (sizeof *entry);
  if (entry == NULL) {
    perror ("malloc");
    return -1;
  }

  size_t len = strlen (path) + strlen (name) + 2;
  entry->pathname = malloc (len);
  if (entry->pathname == NULL) {
    perror ("malloc");
    free (entry);
    return -1;
  }
  if (STREQ (path, "/"))
    snprintf (entry->pathname, len, "/%s", name);
  else
    snprintf (entry->pathname, len, "%s/%s", path, name);

  entry->link = link;

  entry->timeout = now + dir_cache_timeout;

  if (verbose)
    fprintf (stderr, "dir cache: inserting readlink entry %p (%s)\n",
             entry, entry->pathname);

  return gen_replace (rlc_ht, (struct lsc_entry *) entry, rlc_free);
}

const struct stat *
lsc_lookup (const char *pathname)
{
  const struct lsc_entry key = { .pathname = bad_cast (pathname) };
  struct lsc_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (lsc_ht, &key);
  if (entry && entry->timeout >= now)
    return &entry->statbuf;
  else
    return NULL;
}

const struct guestfs_xattr_list *
xac_lookup (const char *pathname)
{
  const struct xac_entry key = { .pathname = bad_cast (pathname) };
  struct xac_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (xac_ht, &key);
  if (entry && entry->timeout >= now)
    return entry->xattrs;
  else
    return NULL;
}

const char *
rlc_lookup (const char *pathname)
{
  const struct rlc_entry key = { .pathname = bad_cast (pathname) };
  struct rlc_entry *entry;
  time_t now;

  time (&now);

  entry = hash_lookup (rlc_ht, &key);
  if (entry && entry->timeout >= now)
    return entry->link;
  else
    return NULL;
}

static void
lsc_remove (Hash_table *ht, const char *pathname, Hash_data_freer freer)
{
  const struct lsc_entry key = { .pathname = bad_cast (pathname) };
  struct lsc_entry *entry;

  entry = hash_delete (ht, &key);

  if (verbose && entry)
    fprintf (stderr, "dir cache: invalidating entry %p (%s)\n",
             entry, entry->pathname);

  freer (entry);
}

void
dir_cache_invalidate (const char *path)
{
  lsc_remove (lsc_ht, path, lsc_free);
  lsc_remove (xac_ht, path, xac_free);
  lsc_remove (rlc_ht, path, rlc_free);
}
