/* libguestfs
 * Copyright (C) 2015 Red Hat Inc.
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

#include <string.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

static const struct cached_feature *
find_or_cache_feature (guestfs_h *g, const char *group)
{
  struct cached_feature *f;
  size_t i;
  int res;

  for (i = 0; i < g->nr_features; ++i) {
    f = &g->features[i];

    if (STRNEQ (f->group, group))
      continue;

    return f;
  }

  res = guestfs_internal_feature_available (g, group);
  if (res < 0)
    return 0;  /* internal_feature_available sent an error. */

  g->features =
    safe_realloc (g, g->features,
                  (g->nr_features+1) * sizeof (struct cached_feature));
  f = &g->features[g->nr_features];
  ++g->nr_features;
  f->group = safe_strdup (g, group);
  f->result = res;

  return f;
}

int
guestfs_impl_available (guestfs_h *g, char *const *groups)
{
  char *const *ptr;

  for (ptr = groups; *ptr != NULL; ++ptr) {
    const char *group = *ptr;
    const struct cached_feature *f = find_or_cache_feature (g, group);

    if (f == NULL)
      return -1;

    if (f->result == 2) {
      error (g, _("%s: unknown group"), group);
      return -1;
    } else if (f->result == 1) {
      error (g, _("%s: group not available"), group);
      return -1;
    }
  }

  return 0;
}

int
guestfs_impl_feature_available (guestfs_h *g, char *const *groups)
{
  char *const *ptr;

  for (ptr = groups; *ptr != NULL; ++ptr) {
    const char *group = *ptr;
    const struct cached_feature *f = find_or_cache_feature (g, group);

    if (f == NULL)
      return -1;

    if (f->result == 2) {
      error (g, _("%s: unknown group"), group);
      return -1;
    } else if (f->result == 1) {
      return 0;
    }
  }

  /* All specified groups available. */
  return 1;
}
