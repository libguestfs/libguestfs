/* libguestfs
 * Copyright (C) 2009-2010 Red Hat Inc.
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

/* IMPORTANT NOTE:
 *
 * All API documentation is in the manpage, 'guestfs(3)'.
 * To read it, type:
 *   man 3 guestfs
 * Or read it online here:
 *   http://libguestfs.org/guestfs.3.html
 *
 * Go and read it now, I'll wait for you to come back.
 */

#ifndef GUESTFS_H_
#define GUESTFS_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef struct guestfs_h guestfs_h;

/*--- Connection management ---*/
extern guestfs_h *guestfs_create (void);
extern void guestfs_close (guestfs_h *g);

/*--- Error handling ---*/
extern const char *guestfs_last_error (guestfs_h *g);

typedef void (*guestfs_error_handler_cb) (guestfs_h *g, void *data, const char *msg);
typedef void (*guestfs_abort_cb) (void) __attribute__((__noreturn__));

extern void guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *data);
extern guestfs_error_handler_cb guestfs_get_error_handler (guestfs_h *g, void **data_rtn);

extern void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb);
extern guestfs_abort_cb guestfs_get_out_of_memory_handler (guestfs_h *g);

/*--- Events ---*/
typedef void (*guestfs_log_message_cb) (guestfs_h *g, void *data, char *buf, int len);
typedef void (*guestfs_subprocess_quit_cb) (guestfs_h *g, void *data);
typedef void (*guestfs_launch_done_cb) (guestfs_h *g, void *data);
typedef void (*guestfs_close_cb) (guestfs_h *g, void *data);

extern void guestfs_set_log_message_callback (guestfs_h *g, guestfs_log_message_cb cb, void *opaque);
extern void guestfs_set_subprocess_quit_callback (guestfs_h *g, guestfs_subprocess_quit_cb cb, void *opaque);
extern void guestfs_set_launch_done_callback (guestfs_h *g, guestfs_launch_done_cb cb, void *opaque);
extern void guestfs_set_close_callback (guestfs_h *g, guestfs_close_cb cb, void *opaque);

/*--- Structures and actions ---*/
#include <stdint.h>
#include <rpc/types.h>
#include <rpc/xdr.h>
#include <guestfs-structs.h>
#include <guestfs-actions.h>

/*--- Private ---
 *
 * These are NOT part of the public, stable API, and can change at any
 * time!  We export them because they are used by some of the language
 * bindings.
 */
extern void *guestfs_safe_malloc (guestfs_h *g, size_t nbytes);
extern void *guestfs_safe_calloc (guestfs_h *g, size_t n, size_t s);
/* End of private functions. */

#ifdef __cplusplus
}
#endif

#endif /* GUESTFS_H_ */
