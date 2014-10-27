/* libguestfs
 * Copyright (C) 2013 Red Hat Inc.
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

/* NB: This contains ONLY definitions which are shared by libguestfs
 * daemon, library, bindings and tools (ie. ALL C code).
 */

#ifndef GUESTFS_INTERNAL_ALL_H_
#define GUESTFS_INTERNAL_ALL_H_

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

#endif /* GUESTFS_INTERNAL_ALL_H_ */
