/* virt-df & virt-alignment-scan domains code.
 * Copyright (C) 2010-2019 Red Hat Inc.
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

#ifndef GUESTFS_DOMAINS_H_
#define GUESTFS_DOMAINS_H_

#if defined(HAVE_LIBVIRT)

#include <libvirt/libvirt.h>

/* The list of domains that we build up in get_all_libvirt_guests. */
struct domain {
  virDomainPtr dom;
  char *name;
  char *uuid;
};

extern struct domain *domains;
extern size_t nr_domains;

extern void free_domains (void);

extern void get_all_libvirt_domains (const char *libvirt_uri);

#endif /* HAVE_LIBVIRT */

#endif /* GUESTFS_DOMAINS_H_ */
