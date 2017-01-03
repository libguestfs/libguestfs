/* virt-df
 * Copyright (C) 2010-2017 Red Hat Inc.
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

#ifndef GUESTFS_VIRT_DF_H_
#define GUESTFS_VIRT_DF_H_

extern int csv;                 /* --csv */
extern int human;               /* --human-readable|-h */
extern int inodes;              /* --inodes */
extern int uuid;                /* --uuid */

/* df.c */
extern int df_on_handle (guestfs_h *g, const char *name, const char *uuid, FILE *fp);
#if defined(HAVE_LIBVIRT)
extern int df_work (guestfs_h *g, size_t i, FILE *fp);
#endif

/* output.c */
extern void print_title (void);
extern void print_stat (FILE *fp, const char *name, const char *uuid, const char *dev, const struct guestfs_statvfs *stat);

#endif /* GUESTFS_VIRT_DF_H_ */
