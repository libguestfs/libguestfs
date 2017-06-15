/* libguestfs
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <errno.h>
#include <iconv.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

/* Read the data from 'valueh', assume it is UTF16LE and convert it to
 * UTF8.  This is copied from hivex_value_string which doesn't work in
 * the appliance because it uses iconv_open which doesn't work because
 * we delete all the i18n databases.
 */
static char *utf16_to_utf8 (/* const */ char *input, size_t len);

char *
guestfs_impl_hivex_value_utf8 (guestfs_h *g, int64_t valueh)
{
  char *ret;
  size_t buflen;

  CLEANUP_FREE char *buf = guestfs_hivex_value_value (g, valueh, &buflen);
  if (buf == NULL)
    return NULL;

  ret = utf16_to_utf8 (buf, buflen);
  if (ret == NULL) {
    perrorf (g, "hivex: conversion of registry value to UTF8 failed");
    return NULL;
  }

  return ret;
}

static char *
utf16_to_utf8 (/* const */ char *input, size_t len)
{
  iconv_t ic = iconv_open ("UTF-8", "UTF-16LE");
  if (ic == (iconv_t) -1)
    return NULL;

  /* iconv(3) has an insane interface ... */

  /* Mostly UTF-8 will be smaller, so this is a good initial guess. */
  size_t outalloc = len;

 again:;
  size_t inlen = len;
  size_t outlen = outalloc;
  char *out = malloc (outlen + 1);
  if (out == NULL) {
    int err = errno;
    iconv_close (ic);
    errno = err;
    return NULL;
  }
  char *inp = input;
  char *outp = out;

  const size_t r =
    iconv (ic, (ICONV_CONST char **) &inp, &inlen, &outp, &outlen);
  if (r == (size_t) -1) {
    if (errno == E2BIG) {
      const int err = errno;
      const size_t prev = outalloc;
      /* Try again with a larger output buffer. */
      free (out);
      outalloc *= 2;
      if (outalloc < prev) {
        iconv_close (ic);
        errno = err;
        return NULL;
      }
      goto again;
    }
    else {
      /* Else some conversion failure, eg. EILSEQ, EINVAL. */
      const int err = errno;
      iconv_close (ic);
      free (out);
      errno = err;
      return NULL;
    }
  }

  *outp = '\0';
  iconv_close (ic);

  return out;
}
