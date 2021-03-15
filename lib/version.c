/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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
 * This file provides simple version number management.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libintl.h>

#include "ignore-value.h"
#include "xstrtol.h"

#include "guestfs.h"
#include "guestfs-internal.h"

COMPILE_REGEXP (re_major_minor, "(\\d+)\\.(\\d+)", 0)

static int version_from_x_y_or_x (guestfs_h *g, struct version *v, const char *str, const pcre2_code *re, bool allow_only_x);

void
guestfs_int_version_from_libvirt (struct version *v, int vernum)
{
  v->v_major = vernum / 1000000UL;
  v->v_minor = vernum / 1000UL % 1000UL;
  v->v_micro = vernum % 1000UL;
}

void
guestfs_int_version_from_values (struct version *v, int maj, int min, int mic)
{
  v->v_major = maj;
  v->v_minor = min;
  v->v_micro = mic;
}

/**
 * Parses a version from a string, looking for a C<X.Y> pattern.
 *
 * Returns C<-1> on failure (like failed integer parsing), C<0> on missing
 * match, and C<1> on match and successful parsing.  C<v> is changed only
 * on successful match.
 */
int
guestfs_int_version_from_x_y (guestfs_h *g, struct version *v, const char *str)
{
  return version_from_x_y_or_x (g, v, str, re_major_minor, false);
}

/**
 * Parses a version from a string, using the specified C<re> as regular
 * expression which I<must> provide (at least) two matches.
 *
 * Returns C<-1> on failure (like failed integer parsing), C<0> on missing
 * match, and C<1> on match and successful parsing.  C<v> is changed only
 * on successful match.
 */
int
guestfs_int_version_from_x_y_re (guestfs_h *g, struct version *v,
                                 const char *str, const pcre2_code *re)
{
  return version_from_x_y_or_x (g, v, str, re, false);
}

/**
 * Parses a version from a string, either looking for a C<X.Y> pattern or
 * considering it as whole integer.
 *
 * Returns C<-1> on failure (like failed integer parsing), C<0> on missing
 * match, and C<1> on match and successful parsing.  C<v> is changed only
 * on successful match.
 */
int
guestfs_int_version_from_x_y_or_x (guestfs_h *g, struct version *v,
                                   const char *str)
{
  return version_from_x_y_or_x (g, v, str, re_major_minor, true);
}

bool
guestfs_int_version_ge (const struct version *v, int maj, int min, int mic)
{
  return (v->v_major > maj) ||
         ((v->v_major == maj) &&
          ((v->v_minor > min) ||
           ((v->v_minor == min) &&
            (v->v_micro >= mic))));
}

bool
guestfs_int_version_cmp_ge (const struct version *a, const struct version *b)
{
  return guestfs_int_version_ge (a, b->v_major, b->v_minor, b->v_micro);
}

static int
version_from_x_y_or_x (guestfs_h *g, struct version *v, const char *str,
                       const pcre2_code *re, bool allow_only_x)
{
  CLEANUP_FREE char *major = NULL;
  CLEANUP_FREE char *minor = NULL;

  if (match2 (g, str, re, &major, &minor)) {
    int major_version, minor_version;

    major_version = guestfs_int_parse_unsigned_int (g, major);
    if (major_version == -1)
      return -1;
    minor_version = guestfs_int_parse_unsigned_int (g, minor);
    if (minor_version == -1)
      return -1;

    v->v_major = major_version;
    v->v_minor = minor_version;
    v->v_micro = 0;

    return 1;
  } else if (allow_only_x) {
    const int major_version = guestfs_int_parse_unsigned_int (g, str);
    if (major_version == -1)
      return -1;

    v->v_major = major_version;
    v->v_minor = 0;
    v->v_micro = 0;

    return 1;
  }
  return 0;
}

/**
 * Parse small, unsigned ints, as used in version numbers.
 *
 * This will fail with an error if trailing characters are found after
 * the integer.
 *
 * Returns E<ge> C<0> on success, or C<-1> on failure.
 */
int
guestfs_int_parse_unsigned_int (guestfs_h *g, const char *str)
{
  long ret;
  const int r = xstrtol (str, NULL, 10, &ret, "");
  if (r != LONGINT_OK) {
    error (g, _("could not parse integer in version number: %s"), str);
    return -1;
  }
  return ret;
}
