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
#include <string.h>
#include <assert.h>

#include "hash.h"
#include "hash-pjw.h"

#include "guestfs.h"
#include "guestfs-internal.h"

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
  struct pda_entry *new_entry, *old_entry, *entry;

  if (g->pda == NULL) {
    g->pda = hash_initialize (16, NULL, hasher, comparator, freer);
    if (g->pda == NULL)
      g->abort_cb ();
  }

  new_entry = safe_malloc (g, sizeof *new_entry);
  new_entry->key = safe_strdup (g, key);
  new_entry->data = data;

  old_entry = hash_delete (g->pda, new_entry);
  freer (old_entry);

  entry = hash_insert (g->pda, new_entry);
  if (entry == NULL)
    g->abort_cb ();
  assert (entry == new_entry);
}

void *
guestfs_get_private (guestfs_h *g, const char *key)
{
  if (g->pda == NULL)
    return NULL;                /* no keys have been set */

  const struct pda_entry k = { .key = (char *) key };
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
