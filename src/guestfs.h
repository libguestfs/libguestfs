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

#ifndef GUESTFS_H_
#define GUESTFS_H_

/* IMPORTANT NOTE!
 * All API documentation is in the manual page --> guestfs(3) <--
 * Go and read it now, I'll wait.
 */

#include <rpc/xdr.h>

#ifdef __cplusplus
extern "C" {
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

typedef struct guestfs_h guestfs_h;

/* Connection management. */
extern guestfs_h *guestfs_create (void);
extern void guestfs_close (guestfs_h *g);

/* Error handling. */
extern const char *guestfs_last_error (guestfs_h *g);

typedef void (*guestfs_error_handler_cb) (guestfs_h *g, void *data, const char *msg);
typedef void (*guestfs_abort_cb) (void) __attribute__((__noreturn__));

extern void guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *data);
extern guestfs_error_handler_cb guestfs_get_error_handler (guestfs_h *g, void **data_rtn);

extern void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb);
extern guestfs_abort_cb guestfs_get_out_of_memory_handler (guestfs_h *g);

#include <guestfs-structs.h>
#include <guestfs-actions.h>

/* Events. */
typedef void (*guestfs_log_message_cb) (guestfs_h *g, void *data, char *buf, int len);
typedef void (*guestfs_subprocess_quit_cb) (guestfs_h *g, void *data);
typedef void (*guestfs_launch_done_cb) (guestfs_h *g, void *data);

extern void guestfs_set_log_message_callback (guestfs_h *g, guestfs_log_message_cb cb, void *opaque);
extern void guestfs_set_subprocess_quit_callback (guestfs_h *g, guestfs_subprocess_quit_cb cb, void *opaque);
extern void guestfs_set_launch_done_callback (guestfs_h *g, guestfs_launch_done_cb cb, void *opaque);

/* Private, for use only by the actions. */
struct guestfs_message_header;
struct guestfs_message_error;
extern void guestfs_error (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void guestfs_perrorf (guestfs_h *g, const char *fs, ...)
  __attribute__((format (printf,2,3)));
extern void *guestfs_safe_malloc (guestfs_h *g, size_t nbytes);
extern void *guestfs_safe_calloc (guestfs_h *g, size_t n, size_t s);
extern void *guestfs_safe_realloc (guestfs_h *g, void *ptr, int nbytes);
extern char *guestfs_safe_strdup (guestfs_h *g, const char *str);
extern void *guestfs_safe_memdup (guestfs_h *g, void *ptr, size_t size);
extern int guestfs___set_busy (guestfs_h *g);
extern int guestfs___end_busy (guestfs_h *g);
extern int guestfs___send (guestfs_h *g, int proc_nr, xdrproc_t xdrp, char *args);
extern int guestfs___recv (guestfs_h *g, const char *fn, struct guestfs_message_header *hdr, struct guestfs_message_error *err, xdrproc_t xdrp, char *ret);
extern int guestfs___send_file (guestfs_h *g, const char *filename);
extern int guestfs___recv_file (guestfs_h *g, const char *filename);

#ifdef __cplusplus
}
#endif

#endif /* GUESTFS_H_ */
