/* guestmount - mount guests using libguestfs and FUSE
 * Copyright (C) 2009 Red Hat Inc.
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
 *
 * Derived from the example program 'fusexmp.c':
 * Copyright (C) 2001-2007  Miklos Szeredi <miklos@szeredi.hu>
 *
 * This program can be distributed under the terms of the GNU GPL.
 * See the file COPYING.
 */

#ifndef GUESTMOUNT_DIRCACHE_H
#define GUESTMOUNT_DIRCACHE_H 1

#include <time.h>
#include <sys/stat.h>
#include <guestfs.h>

extern void init_dir_caches (void);
extern void free_dir_caches (void);
extern void dir_cache_remove_all_expired (time_t now);
extern void dir_cache_invalidate (const char *path);

extern int lsc_insert (const char *path, const char *name, time_t now, struct stat const *statbuf);
extern int xac_insert (const char *path, const char *name, time_t now, struct guestfs_xattr_list *xattrs);
extern int rlc_insert (const char *path, const char *name, time_t now, char *link);
extern const struct stat *lsc_lookup (const char *pathname);
extern const struct guestfs_xattr_list *xac_lookup (const char *pathname);
extern const char *rlc_lookup (const char *pathname);

extern int dir_cache_timeout;

#endif /* GUESTMOUNT_DIRCACHE_H */
