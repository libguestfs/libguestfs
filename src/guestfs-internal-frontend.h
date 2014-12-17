/* libguestfs
 * Copyright (C) 2013-2014 Red Hat Inc.
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
#define CLEANUP_FREE __attribute__((cleanup(guestfs___cleanup_free)))
#define CLEANUP_FREE_STRING_LIST                                \
  __attribute__((cleanup(guestfs___cleanup_free_string_list)))
#define CLEANUP_HASH_FREE                               \
  __attribute__((cleanup(guestfs___cleanup_hash_free)))
#define CLEANUP_UNLINK_FREE                                     \
  __attribute__((cleanup(guestfs___cleanup_unlink_free)))
#define CLEANUP_XMLBUFFERFREE                                   \
  __attribute__((cleanup(guestfs___cleanup_xmlBufferFree)))
#define CLEANUP_XMLFREEDOC                                      \
  __attribute__((cleanup(guestfs___cleanup_xmlFreeDoc)))
#define CLEANUP_XMLFREEURI                                              \
  __attribute__((cleanup(guestfs___cleanup_xmlFreeURI)))
#define CLEANUP_XMLFREETEXTWRITER                               \
  __attribute__((cleanup(guestfs___cleanup_xmlFreeTextWriter)))
#define CLEANUP_XMLXPATHFREECONTEXT                                     \
  __attribute__((cleanup(guestfs___cleanup_xmlXPathFreeContext)))
#define CLEANUP_XMLXPATHFREEOBJECT                                      \
  __attribute__((cleanup(guestfs___cleanup_xmlXPathFreeObject)))
#define CLEANUP_FCLOSE __attribute__((cleanup(guestfs___cleanup_fclose)))
#define CLEANUP_PCLOSE __attribute__((cleanup(guestfs___cleanup_pclose)))
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

/* NB: At some point we will stop exporting these safe_* allocation
 * functions outside the library, so don't use them in new tools or
 * bindings code.
 */
extern GUESTFS_DLL_PUBLIC void *guestfs___safe_malloc (guestfs_h *g, size_t nbytes);
extern GUESTFS_DLL_PUBLIC void *guestfs___safe_calloc (guestfs_h *g, size_t n, size_t s);
extern GUESTFS_DLL_PUBLIC char *guestfs___safe_strdup (guestfs_h *g, const char *str);
extern GUESTFS_DLL_PUBLIC void *guestfs___safe_memdup (guestfs_h *g, const void *ptr, size_t size);
extern void *guestfs___safe_realloc (guestfs_h *g, void *ptr, size_t nbytes);
extern char *guestfs___safe_strdup (guestfs_h *g, const char *str);
extern char *guestfs___safe_strndup (guestfs_h *g, const char *str, size_t n);
extern void *guestfs___safe_memdup (guestfs_h *g, const void *ptr, size_t size);
extern char *guestfs___safe_asprintf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));

#define safe_calloc guestfs___safe_calloc
#define safe_malloc guestfs___safe_malloc
#define safe_realloc guestfs___safe_realloc
#define safe_strdup guestfs___safe_strdup
#define safe_strndup guestfs___safe_strndup
#define safe_memdup guestfs___safe_memdup
#define safe_asprintf guestfs___safe_asprintf

/* utils.c */
extern void guestfs___free_string_list (char **);
extern size_t guestfs___count_strings (char *const *);
extern char *guestfs___concat_strings (char *const *);
extern char **guestfs___copy_string_list (char *const *);
extern char *guestfs___join_strings (const char *sep, char *const *);
extern char **guestfs___split_string (char sep, const char *);
extern char *guestfs___exit_status_to_string (int status, const char *cmd_name, char *buffer, size_t buflen);
extern int guestfs___random_string (char *ret, size_t len);
extern char *guestfs___drive_name (size_t index, char *ret);
extern int guestfs___is_true (const char *str);

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */
extern void guestfs___cleanup_free (void *ptr);
extern void guestfs___cleanup_free_string_list (char ***ptr);
extern void guestfs___cleanup_hash_free (void *ptr);
extern void guestfs___cleanup_unlink_free (char **ptr);
extern void guestfs___cleanup_xmlBufferFree (void *ptr);
extern void guestfs___cleanup_xmlFreeDoc (void *ptr);
extern void guestfs___cleanup_xmlFreeURI (void *ptr);
extern void guestfs___cleanup_xmlFreeTextWriter (void *ptr);
extern void guestfs___cleanup_xmlXPathFreeContext (void *ptr);
extern void guestfs___cleanup_xmlXPathFreeObject (void *ptr);
extern void guestfs___cleanup_fclose (void *ptr);
extern void guestfs___cleanup_pclose (void *ptr);

/* These are in a separate header so the header can be generated.
 * Don't include the following file directly:
 */
#include "guestfs-internal-frontend-cleanups.h"

#if defined(HAVE_LIBVIRT)

#include <libvirt/libvirt.h>

/* This was proposed as an external API, but there's a problem: the
 * generator is unable to bind a virDomainPtr in any language other
 * than C.  For now this API is only used by virt-df and
 * virt-alignment-scan (both C tools) and it's only exported
 * internally within the libguestfs code, not to external users.
 */

struct guestfs___add_libvirt_dom_argv {
  uint64_t bitmask;
#define GUESTFS___ADD_LIBVIRT_DOM_READONLY_BITMASK (UINT64_C(1)<<0)
  int readonly;
#define GUESTFS___ADD_LIBVIRT_DOM_IFACE_BITMASK (UINT64_C(1)<<1)
  const char *iface;
#define GUESTFS___ADD_LIBVIRT_DOM_LIVE_BITMASK (UINT64_C(1)<<2)
  int live;
#define GUESTFS___ADD_LIBVIRT_DOM_READONLYDISK_BITMASK (UINT64_C(1)<<3)
  const char *readonlydisk;
#define GUESTFS___ADD_LIBVIRT_DOM_CACHEMODE_BITMASK (UINT64_C(1)<<4)
  const char *cachemode;
#define GUESTFS___ADD_LIBVIRT_DOM_DISCARD_BITMASK (UINT64_C(1)<<5)
  const char *discard;
#define GUESTFS___ADD_LIBVIRT_DOM_COPYONREAD_BITMASK (UINT64_C(1)<<6)
  int copyonread;
};

extern GUESTFS_DLL_PUBLIC int guestfs___add_libvirt_dom (guestfs_h *g, virDomainPtr dom, const struct guestfs___add_libvirt_dom_argv *optargs);

#endif /* HAVE_LIBVIRT */

/* Current program name.  Note <errno.h> must be included in all files
 * that want to use 'program_name'.
 */
#if HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME == 1
#  define program_name program_invocation_short_name
#else
#  define program_name "libguestfs"
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

#endif /* GUESTFS_INTERNAL_FRONTEND_H_ */
