/* libguestfs
 * Copyright (C) 2013-2016 Red Hat Inc.
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
 * library, bindings, tools and tests (NOT the daemon).
 *
 * If a definition is only needed by a single component of libguestfs,
 * then it should NOT be here!
 *
 * The daemon does NOT use this header.  If you need a place to put
 * something shared with absolutely everything including the daemon,
 * put it in 'src/guestfs-internal-all.h'.
 */

#ifndef GUESTFS_INTERNAL_FRONTEND_H_
#define GUESTFS_INTERNAL_FRONTEND_H_

#include "guestfs-internal-all.h"

#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE __attribute__((cleanup(guestfs_int_cleanup_free)))
#define CLEANUP_FREE_STRING_LIST                                \
  __attribute__((cleanup(guestfs_int_cleanup_free_string_list)))
#define CLEANUP_HASH_FREE                               \
  __attribute__((cleanup(guestfs_int_cleanup_hash_free)))
#define CLEANUP_UNLINK_FREE                                     \
  __attribute__((cleanup(guestfs_int_cleanup_unlink_free)))
#define CLEANUP_XMLBUFFERFREE                                   \
  __attribute__((cleanup(guestfs_int_cleanup_xmlBufferFree)))
#define CLEANUP_XMLFREEDOC                                      \
  __attribute__((cleanup(guestfs_int_cleanup_xmlFreeDoc)))
#define CLEANUP_XMLFREEURI                                              \
  __attribute__((cleanup(guestfs_int_cleanup_xmlFreeURI)))
#define CLEANUP_XMLFREETEXTWRITER                               \
  __attribute__((cleanup(guestfs_int_cleanup_xmlFreeTextWriter)))
#define CLEANUP_XMLXPATHFREECONTEXT                                     \
  __attribute__((cleanup(guestfs_int_cleanup_xmlXPathFreeContext)))
#define CLEANUP_XMLXPATHFREEOBJECT                                      \
  __attribute__((cleanup(guestfs_int_cleanup_xmlXPathFreeObject)))
#define CLEANUP_FCLOSE __attribute__((cleanup(guestfs_int_cleanup_fclose)))
#define CLEANUP_PCLOSE __attribute__((cleanup(guestfs_int_cleanup_pclose)))
#else
#define CLEANUP_FREE
#define CLEANUP_FREE_STRING_LIST
#define CLEANUP_HASH_FREE
#define CLEANUP_UNLINK_FREE
#define CLEANUP_XMLBUFFERFREE
#define CLEANUP_XMLFREEDOC
#define CLEANUP_XMLFREEURI
#define CLEANUP_XMLFREETEXTWRITER
#define CLEANUP_XMLXPATHFREECONTEXT
#define CLEANUP_XMLXPATHFREEOBJECT
#define CLEANUP_FCLOSE
#define CLEANUP_PCLOSE
#endif

/* utils.c */
extern void guestfs_int_free_string_list (char **);
extern size_t guestfs_int_count_strings (char *const *);
extern char *guestfs_int_concat_strings (char *const *);
extern char **guestfs_int_copy_string_list (char *const *);
extern char *guestfs_int_join_strings (const char *sep, char *const *);
extern char **guestfs_int_split_string (char sep, const char *);
extern char *guestfs_int_exit_status_to_string (int status, const char *cmd_name, char *buffer, size_t buflen);
extern int guestfs_int_random_string (char *ret, size_t len);
extern char *guestfs_int_drive_name (size_t index, char *ret);
extern ssize_t guestfs_int_drive_index (const char *);
extern int guestfs_int_is_true (const char *str);
extern const char *guestfs_int_ovmf_i386_firmware[];
extern const char *guestfs_int_ovmf_x86_64_firmware[];
extern const char *guestfs_int_aavmf_firmware[];
//extern void guestfs_int_fadvise_normal (int fd);
extern void guestfs_int_fadvise_sequential (int fd);
extern void guestfs_int_fadvise_random (int fd);
extern void guestfs_int_fadvise_noreuse (int fd);
//extern void guestfs_int_fadvise_dontneed (int fd);
//extern void guestfs_int_fadvise_willneed (int fd);

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */
extern void guestfs_int_cleanup_free (void *ptr);
extern void guestfs_int_cleanup_free_string_list (char ***ptr);
extern void guestfs_int_cleanup_hash_free (void *ptr);
extern void guestfs_int_cleanup_unlink_free (char **ptr);
extern void guestfs_int_cleanup_xmlBufferFree (void *ptr);
extern void guestfs_int_cleanup_xmlFreeDoc (void *ptr);
extern void guestfs_int_cleanup_xmlFreeURI (void *ptr);
extern void guestfs_int_cleanup_xmlFreeTextWriter (void *ptr);
extern void guestfs_int_cleanup_xmlXPathFreeContext (void *ptr);
extern void guestfs_int_cleanup_xmlXPathFreeObject (void *ptr);
extern void guestfs_int_cleanup_fclose (void *ptr);
extern void guestfs_int_cleanup_pclose (void *ptr);

/* These are in a separate header so the header can be generated.
 * Don't include the following file directly:
 */
#include "guestfs-internal-frontend-cleanups.h"

/* Current program name.  Note <errno.h> must be included in all files
 * that want to use 'guestfs_int_program_name'.
 */
#if HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME == 1
#  define guestfs_int_program_name program_invocation_short_name
#elif HAVE_GETPROGNAME
#  define guestfs_int_program_name getprogname()
#else
#  define guestfs_int_program_name "libguestfs"
#endif

/* Close all file descriptors matching the condition. */
#define close_file_descriptors(cond) do {                               \
    int max_fd = sysconf (_SC_OPEN_MAX);                                \
    int fd;                                                             \
    if (max_fd == -1)                                                   \
      max_fd = 1024;                                                    \
    if (max_fd > 65536)                                                 \
      max_fd = 65536;          /* bound the amount of work we do here */ \
    for (fd = 0; fd < max_fd; ++fd) {                                   \
      if (cond)                                                         \
        close (fd);                                                     \
    }                                                                   \
  } while (0)

/* Not all language bindings know how to deal with Pointer arguments.
 * Those that don't will use this macro which complains noisily and
 * returns NULL.
 */
#define POINTER_NOT_IMPLEMENTED(type)                                   \
  (                                                                     \
   fprintf (stderr, "*** WARNING: this language binding does not support conversion of Pointer(%s), so the current function will always fail.  Patches to fix this should be sent to the libguestfs upstream mailing list.\n", \
            type),                                                      \
   NULL                                                                 \
)

#endif /* GUESTFS_INTERNAL_FRONTEND_H_ */
