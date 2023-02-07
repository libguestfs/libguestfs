/* libguestfs
 * Copyright (C) 2013-2023 Red Hat Inc.
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
 * This header contains definitions which are shared by all parts of
 * libguestfs, ie. the daemon, the library, language bindings and virt
 * tools (ie. I<all> C code).
 *
 * If you need a definition used by only the library, put it in
 * F<lib/guestfs-internal.h> instead.
 *
 * If a definition is used by only a single tool, it should not be in
 * any shared header file at all.
 */

#ifndef GUESTFS_INTERNAL_ALL_H_
#define GUESTFS_INTERNAL_ALL_H_

#include <string.h>

/* This is also defined in <guestfs.h>, so don't redefine it. */
#if defined(__GNUC__) && !defined(GUESTFS_GCC_VERSION)
# define GUESTFS_GCC_VERSION \
    (__GNUC__ * 10000 + __GNUC_MINOR__ * 100 + __GNUC_PATCHLEVEL__)
#endif

#if !defined(__attribute__) && defined(__GNUC__) && GUESTFS_GCC_VERSION < 20800 /* gcc < 2.8 */
# define __attribute__(x) /* empty */
#endif

#ifndef ATTRIBUTE_UNUSED
# define ATTRIBUTE_UNUSED __attribute__ ((__unused__))
#endif

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)
#define STRCASEPREFIX(a,b) (strncasecmp((a),(b),strlen((b))) == 0)
#define STRSUFFIX(a,b) (strlen((a)) >= strlen((b)) && STREQ((a)+strlen((a))-strlen((b)),(b)))

/* A simple (indeed, simplistic) way to build up short lists of
 * arguments.  Your code must define MAX_ARGS to a suitable "larger
 * than could ever be needed" value.  (If the value is exceeded then
 * your code will abort).  For more complex needs, use something else
 * more suitable.
 */
#define ADD_ARG(argv,i,v)                                               \
  do {                                                                  \
    if ((i) >= MAX_ARGS) {                                              \
      fprintf (stderr, "%s: %d: internal error: exceeded MAX_ARGS (%zu) when constructing the command line\n", __FILE__, __LINE__, (size_t) MAX_ARGS); \
      abort ();                                                         \
    }                                                                   \
    (argv)[(i)++] = (v);                                                \
  } while (0)

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0
#endif

#ifndef MAX
#define MAX(a,b) ((a)>(b)?(a):(b))
#endif

#ifndef MIN
#define MIN(a,b) ((a)<(b)?(a):(b))
#endif

#ifdef __APPLE__
#define xdr_uint32_t xdr_u_int32_t
#endif

/* Return true iff the buffer is all zero bytes.
 *
 * The clever approach here was suggested by Eric Blake.  See:
 * https://www.redhat.com/archives/libguestfs/2017-April/msg00171.html
 */
static inline int
is_zero (const char *buffer, size_t size)
{
  size_t i;
  const size_t limit = MIN (size, 16);

  for (i = 0; i < limit; ++i)
    if (buffer[i])
      return 0;
  if (size != limit)
    return !memcmp (buffer, buffer + 16, size - 16);

  return 1;
}

/* Macro which compiles the regexp once when the program/library is
 * loaded, and frees it when the library is unloaded.
 */
#define COMPILE_REGEXP(name,pattern,options)                            \
  static void compile_regexp_##name (void) __attribute__((constructor)); \
  static void free_regexp_##name (void) __attribute__((destructor));    \
  static pcre2_code *name;                                              \
                                                                        \
  static void                                                           \
  compile_regexp_##name (void)                                          \
  {                                                                     \
    int errnum;                                                         \
    PCRE2_SIZE offset;                                                  \
    name = pcre2_compile ((PCRE2_SPTR)(pattern),                        \
                          PCRE2_ZERO_TERMINATED,                        \
                          (options), &errnum, &offset, NULL);           \
    if (name == NULL) {                                                 \
      PCRE2_UCHAR err[256];                                             \
      pcre2_get_error_message (errnum, err, sizeof err);                \
      ignore_value (write (2, err, strlen ((char *)err)));              \
      abort ();                                                         \
    }                                                                   \
  }                                                                     \
                                                                        \
  static void                                                           \
  free_regexp_##name (void)                                             \
  {                                                                     \
    pcre2_code_free (name);                                             \
  }

/* The type field of a parsed mountable.
 *
 * This is used both by mountable_t in the daemon, and
 * struct guestfs_int_mountable_internal in the library.
 */

typedef enum {
  MOUNTABLE_DEVICE,     /* A bare device */
  MOUNTABLE_BTRFSVOL,   /* A btrfs subvolume: device + volume */
  MOUNTABLE_PATH        /* An already mounted path: device = path */
} mountable_type_t;

/* Some functions replaced by gnulib */
#ifndef HAVE_ACCEPT4
#include <sys/socket.h>

extern int accept4 (int sockfd, struct sockaddr *__restrict__ addr,
		    socklen_t *__restrict__ addrlen, int flags);
#endif

#ifndef HAVE_PIPE2
extern int pipe2 (int pipefd[2], int flags);
#endif

#endif /* GUESTFS_INTERNAL_ALL_H_ */
