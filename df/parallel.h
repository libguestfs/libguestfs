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

/* The work function should do the work (inspecting the domain, etc.)
 * on domain index 'i'.  However it MUST NOT print out any result
 * directly.  Instead it prints anything it needs to the supplied
 * 'FILE *'.
 * Returns 0 on success or -1 on error.
 */
typedef int (*work_fn) (guestfs_h *g, size_t i, FILE *fp);

/* Run the threads and work through the global list of libvirt
 * domains.  'option_P' is whatever the user passed in the '-P'
 * option, or 0 if the user didn't use the '-P' option (in which case
 * the number of threads is chosen heuristically.  'options_handle'
 * (which may be NULL) is the global guestfs handle created by the
 * options mini-library.
 *
 * Returns 0 if all work items completed successfully, or -1 if there
 * was an error.
 */
extern int start_threads (size_t option_P, guestfs_h *options_handle, work_fn work);

#endif /* HAVE_LIBVIRT */

#endif /* GUESTFS_PARALLEL_H_ */
