/* virt-ls visitor function
 * Copyright (C) 2010-2014 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef VISIT_H
#define VISIT_H

typedef int (*visitor_function) (const char *dir, const char *name, const struct guestfs_statns *stat, const struct guestfs_xattr_list *xattrs, void *opaque);

extern int visit (guestfs_h *g, const char *dir, visitor_function f, void *opaque);

extern char *full_path (const char *dir, const char *name);

extern int is_reg (int64_t mode);
extern int is_dir (int64_t mode);
extern int is_chr (int64_t mode);
extern int is_blk (int64_t mode);
extern int is_fifo (int64_t mode);
extern int is_lnk (int64_t mode);
extern int is_sock (int64_t mode);

#endif /* VISIT_H */
