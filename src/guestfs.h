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

/* For API documentation, please read the manual page guestfs(3). */

typedef struct guestfs_h guestfs_h;

/* Create and destroy the guest handle. */
extern guestfs_h *guestfs_create (void);
extern void guestfs_free (guestfs_h *g);

/* Guest configuration. */
extern int guestfs_config (guestfs_h *g,
			   const char *qemu_param, const char *qemu_value);
extern int guestfs_add_drive (guestfs_h *g, const char *filename);
extern int guestfs_add_cdrom (guestfs_h *g, const char *filename);

/* Steps to start up the guest. */
extern int guestfs_launch (guestfs_h *g);
extern int guestfs_wait_ready (guestfs_h *g);

/* Kill the guest subprocess. */
extern void guestfs_kill_subprocess (guestfs_h *g);

/* Error handling. */
typedef void (*guestfs_abort_fn) (void);
extern void guestfs_set_out_of_memory_handler (guestfs_h *g, guestfs_abort_fn);
extern guestfs_abort_fn guestfs_get_out_of_memory_handler (guestfs_h *g);

extern void guestfs_set_exit_on_error (guestfs_h *g, int exit_on_error);
extern int guestfs_get_exit_on_error (guestfs_h *g);

extern void guestfs_set_verbose (guestfs_h *g, int verbose);
extern int guestfs_get_verbose (guestfs_h *g);

#endif /* GUESTFS_H_ */
