/* virt-alignment-scan
 * Copyright (C) 2012 Red Hat Inc.
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

#ifndef GUESTFS_VIRT_ALIGNMENT_SCAN_H_
#define GUESTFS_VIRT_ALIGNMENT_SCAN_H_

/* domains.c */
#if defined(HAVE_LIBVIRT) && defined(HAVE_LIBXML2)
extern void get_domains_from_libvirt (int uuid, size_t *worst_alignment);
#endif

/* scan.c */
extern void scan (size_t *worst_alignment, const char *prefix);

#endif /* GUESTFS_VIRT_ALIGNMENT_SCAN_H_ */
