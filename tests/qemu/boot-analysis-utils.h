/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef GUESTFS_BOOT_ANALYSIS_UTILS_H_
#define GUESTFS_BOOT_ANALYSIS_UTILS_H_

/* Get current time, returning it in *ts.  If there is a system call
 * failure, this exits.
 */
extern void get_time (struct timespec *ts);

/* Computes Y - X, returning nanoseconds. */
extern int64_t timespec_diff (const struct timespec *x, const struct timespec *y);

#endif /* GUESTFS_BOOT_ANALYSIS_UTILS_H_ */
