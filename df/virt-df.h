/* virt-df
 * Copyright (C) 2010 Red Hat Inc.
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

#ifndef GUESTFS_VIRT_DF_
#define GUESTFS_VIRT_DF_

extern guestfs_h *g;
extern const char *libvirt_uri; /* --connect */
extern int csv;                 /* --csv */
extern int human;               /* --human-readable|-h */
extern int inodes;              /* --inodes */
extern int one_per_guest;       /* --one-per-guest */
extern int uuid;                /* --uuid */

/* df.c */
extern int df_on_handle (const char *name, const char *uuid, char **devices, int offset);

/* domains.c */
#ifdef HAVE_LIBVIRT
extern void get_domains_from_libvirt (void);
#endif

/* output.c */
extern void print_title (void);
extern void print_stat (const char *name, const char *uuid, const char *dev, int offset, const struct guestfs_statvfs *stat);

#endif /* GUESTFS_VIRT_DF_ */
