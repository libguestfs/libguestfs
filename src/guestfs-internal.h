/* libguestfs
 * Copyright (C) 2009 Red Hat Inc.
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

#ifndef GUESTFS_INTERNAL_H_
#define GUESTFS_INTERNAL_H_

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

struct guestfs_message_header;
struct guestfs_message_error;
extern void guestfs_error (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void *guestfs_safe_realloc (guestfs_h *g, void *ptr, int nbytes);
extern char *guestfs_safe_strdup (guestfs_h *g, const char *str);
extern void *guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size);
extern int guestfs___set_busy (guestfs_h *g);
extern int guestfs___end_busy (guestfs_h *g);
extern int guestfs___send (guestfs_h *g, int proc_nr, xdrproc_t xdrp, char *args);
extern int guestfs___recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs___send_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_file (guestfs_h *g, const char *filename);

#endif /* GUESTFS_INTERNAL_H_ */
