/* libguestfs
 * Copyright (C) 2013-2019 Red Hat Inc.
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

#ifndef GUESTFS_CLEANUPS_H_
#define GUESTFS_CLEANUPS_H_

#ifdef HAVE_ATTRIBUTE_CLEANUP
#define CLEANUP_FREE                                    \
  __attribute__((cleanup(guestfs_int_cleanup_free)))
#define CLEANUP_HASH_FREE                                       \
  __attribute__((cleanup(guestfs_int_cleanup_hash_free)))
#define CLEANUP_GL_RECURSIVE_LOCK_UNLOCK \
  __attribute__((cleanup(guestfs_int_cleanup_gl_recursive_lock_unlock)))
#define CLEANUP_UNLINK_FREE                                     \
  __attribute__((cleanup(guestfs_int_cleanup_unlink_free)))
#define CLEANUP_CLOSE                                  \
  __attribute__((cleanup(guestfs_int_cleanup_close)))
#define CLEANUP_FCLOSE                                  \
  __attribute__((cleanup(guestfs_int_cleanup_fclose)))
#define CLEANUP_PCLOSE                                  \
  __attribute__((cleanup(guestfs_int_cleanup_pclose)))
#define CLEANUP_FREE_STRING_LIST                                \
  __attribute__((cleanup(guestfs_int_cleanup_free_string_list)))
#define CLEANUP_XMLFREE                                 \
  __attribute__((cleanup(guestfs_int_cleanup_xmlFree)))
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
#else
#define CLEANUP_FREE
#define CLEANUP_HASH_FREE
/* XXX no safe equivalent to CLEANUP_GL_RECURSIVE_LOCK_UNLOCK */
#define CLEANUP_UNLINK_FREE
#define CLEANUP_CLOSE
#define CLEANUP_FCLOSE
#define CLEANUP_PCLOSE
#define CLEANUP_FREE_STRING_LIST
#define CLEANUP_XMLFREE
#define CLEANUP_XMLBUFFERFREE
#define CLEANUP_XMLFREEDOC
#define CLEANUP_XMLFREEURI
#define CLEANUP_XMLFREETEXTWRITER
#define CLEANUP_XMLXPATHFREECONTEXT
#define CLEANUP_XMLXPATHFREEOBJECT
#endif

/* These functions are used internally by the CLEANUP_* macros.
 * Don't call them directly.
 */
extern void guestfs_int_cleanup_free (void *ptr);
extern void guestfs_int_cleanup_hash_free (void *ptr);
extern void guestfs_int_cleanup_gl_recursive_lock_unlock (void *ptr);
extern void guestfs_int_cleanup_unlink_free (char **ptr);
extern void guestfs_int_cleanup_close (void *ptr);
extern void guestfs_int_cleanup_fclose (void *ptr);
extern void guestfs_int_cleanup_pclose (void *ptr);
extern void guestfs_int_cleanup_free_string_list (char ***ptr);
extern void guestfs_int_cleanup_xmlFree (void *ptr);
extern void guestfs_int_cleanup_xmlBufferFree (void *ptr);
extern void guestfs_int_cleanup_xmlFreeDoc (void *ptr);
extern void guestfs_int_cleanup_xmlFreeURI (void *ptr);
extern void guestfs_int_cleanup_xmlFreeTextWriter (void *ptr);
extern void guestfs_int_cleanup_xmlXPathFreeContext (void *ptr);
extern void guestfs_int_cleanup_xmlXPathFreeObject (void *ptr);

#endif /* GUESTFS_CLEANUPS_H_ */
