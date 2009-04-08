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

typedef struct guestfs_h guestfs_h;

/* Connection management. */
extern guestfs_h *guestfs_create (void);
extern void guestfs_close (guestfs_h *g);

/* Error handling. */
typedef void (*guestfs_error_handler_cb) (guestfs_h *g, void *data, const char *msg);
typedef void (*guestfs_abort_cb) (void);

extern void guestfs_set_error_handler (guestfs_h *g, guestfs_error_handler_cb cb, void *data);
extern guestfs_error_handler_cb guestfs_get_error_handler (guestfs_h *g, void **data_rtn);

extern void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_cb);
extern guestfs_abort_cb guestfs_get_out_of_memory_handler (guestfs_h *g);

#include <guestfs-structs.h>
#include <guestfs-actions.h>

extern void guestfs_free_lvm_pv_list (struct guestfs_lvm_pv_list *);
extern void guestfs_free_lvm_vg_list (struct guestfs_lvm_vg_list *);
extern void guestfs_free_lvm_lv_list (struct guestfs_lvm_lv_list *);

/* Low-level event API. */
typedef void (*guestfs_reply_cb) (guestfs_h *g, void *data, XDR *xdr);
typedef void (*guestfs_log_message_cb) (guestfs_h *g, void *data, char *buf, int len);
typedef void (*guestfs_subprocess_quit_cb) (guestfs_h *g, void *data);
typedef void (*guestfs_launch_done_cb) (guestfs_h *g, void *data);

extern void guestfs_set_reply_callback (guestfs_h *g, guestfs_reply_cb cb, void *opaque);
extern void guestfs_set_log_message_callback (guestfs_h *g, guestfs_log_message_cb cb, void *opaque);
extern void guestfs_set_subprocess_quit_callback (guestfs_h *g, guestfs_subprocess_quit_cb cb, void *opaque);
extern void guestfs_set_launch_done_callback (guestfs_h *g, guestfs_launch_done_cb cb, void *opaque);

/* Main loop. */
#define GUESTFS_HANDLE_READABLE 0x1
#define GUESTFS_HANDLE_WRITABLE 0x2
#define GUESTFS_HANDLE_HANGUP   0x4
#define GUESTFS_HANDLE_ERROR    0x8

typedef void (*guestfs_handle_event_cb) (void *data, int watch, int fd, int events);
typedef int (*guestfs_add_handle_cb) (guestfs_h *g, int fd, int events, guestfs_handle_event_cb cb, void *data);
typedef int (*guestfs_remove_handle_cb) (guestfs_h *g, int watch);
typedef void (*guestfs_handle_timeout_cb) (void *data, int timer);
typedef int (*guestfs_add_timeout_cb) (guestfs_h *g, int interval, guestfs_handle_timeout_cb cb, void *data);
typedef int (*guestfs_remove_timeout_cb) (guestfs_h *g, int timer);
typedef void (*guestfs_main_loop_run_cb) (guestfs_h *g);
typedef void (*guestfs_main_loop_quit_cb) (guestfs_h *g);

struct guestfs_main_loop {
  guestfs_add_handle_cb add_handle;
  guestfs_remove_handle_cb remove_handle;
  guestfs_add_timeout_cb add_timeout;
  guestfs_remove_timeout_cb remove_timeout;
  guestfs_main_loop_run_cb main_loop_run;
  guestfs_main_loop_quit_cb main_loop_quit;
};
typedef struct guestfs_main_loop guestfs_main_loop;

extern void guestfs_set_main_loop (guestfs_main_loop *);
extern void guestfs_main_loop_run (void);
extern void guestfs_main_loop_quit (void);

#endif /* GUESTFS_H_ */
