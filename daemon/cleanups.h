/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2015 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef GUESTFSD_CLEANUPS_H
#define GUESTFSD_CLEANUPS_H

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */
extern void cleanup_free (void *ptr);
extern void cleanup_free_string_list (void *ptr);
extern void cleanup_unlink_free (void *ptr);
extern void cleanup_close (void *ptr);
extern void cleanup_fclose (void *ptr);
extern void cleanup_aug_close (void *ptr);
extern void cleanup_free_stringsbuf (void *ptr);

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE __attribute__((cleanup(cleanup_free)))
#define CLEANUP_FREE_STRING_LIST                        \
    __attribute__((cleanup(cleanup_free_string_list)))
#define CLEANUP_UNLINK_FREE __attribute__((cleanup(cleanup_unlink_free)))
#define CLEANUP_CLOSE __attribute__((cleanup(cleanup_close)))
#define CLEANUP_FCLOSE __attribute__((cleanup(cleanup_fclose)))
#define CLEANUP_AUG_CLOSE __attribute__((cleanup(cleanup_aug_close)))
#define CLEANUP_FREE_STRINGSBUF __attribute__((cleanup(cleanup_free_stringsbuf)))
#else
#define CLEANUP_FREE
#define CLEANUP_FREE_STRING_LIST
#define CLEANUP_UNLINK_FREE
#define CLEANUP_CLOSE
#define CLEANUP_AUG_CLOSE
#define CLEANUP_FREE_STRINGSBUF
#endif

#endif /* GUESTFSD_CLEANUPS_H */
