/* base64.h -- Encode binary data using printable characters.
   Copyright (C) 2004-2006, 2009-2023 Free Software Foundation, Inc.
   Written by Simon Josefsson.

   (NB: I modified the original GPL boilerplate here to LGPLv2+.  This
   is because of the weird way that gnulib uses licenses, where the
   real license is covered in the modules/X file.  The real license
   for this file is LGPLv2+, not GPL.  - RWMJ)

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#ifndef BASE64_H
# define BASE64_H

/* Get size_t. */
# include <stddef.h>

/* Get bool. */
# include <stdbool.h>

# ifdef __cplusplus
extern "C" {
# endif

/* This uses that the expression (n+(k-1))/k means the smallest
   integer >= n/k, i.e., the ceiling of n/k.  */
# define BASE64_LENGTH(inlen) ((((inlen) + 2) / 3) * 4)

struct base64_decode_context
{
  unsigned int i;
  char buf[4];
};

extern bool isbase64 (char ch);

extern void base64_encode (const char *restrict in, size_t inlen,
                           char *restrict out, size_t outlen);

extern size_t base64_encode_alloc (const char *in, size_t inlen, char **out);

extern void base64_decode_ctx_init (struct base64_decode_context *ctx);

extern bool base64_decode_ctx (struct base64_decode_context *ctx,
                               const char *restrict in, size_t inlen,
                               char *restrict out, size_t *outlen);

extern bool base64_decode_alloc_ctx (struct base64_decode_context *ctx,
                                     const char *in, size_t inlen,
                                     char **out, size_t *outlen);

#define base64_decode(in, inlen, out, outlen) \
        base64_decode_ctx (NULL, in, inlen, out, outlen)

#define base64_decode_alloc(in, inlen, out, outlen) \
        base64_decode_alloc_ctx (NULL, in, inlen, out, outlen)

# ifdef __cplusplus
}
# endif

#endif /* BASE64_H */
