/* virt-df & virt-alignment-scan parallel appliances code.
 * Copyright (C) 2013 Red Hat Inc.
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

#ifndef GUESTFS_PARALLEL_H_
#define GUESTFS_PARALLEL_H_

#if defined(HAVE_LIBVIRT)

#include "domains.h"

typedef int (*work_fn) (guestfs_h *g, size_t i, FILE *fp);

extern int start_threads (size_t option_P, guestfs_h *options_handle, work_fn work);

#endif /* HAVE_LIBVIRT */

#endif /* GUESTFS_PARALLEL_H_ */
