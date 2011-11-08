/* libguestfs - mini library for progress bars.
 * Copyright (C) 2010-2011 Red Hat Inc.
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

#include <config.h>

#ifndef PROGRESS_H
#define PROGRESS_H

struct progress_bar;

/* Initialize the progress bar mini library.
 *
 * Function returns a handle, or NULL if there was an error.
 */
#define PROGRESS_BAR_MACHINE_READABLE 1
extern struct progress_bar *progress_bar_init (unsigned flags);

/* This should be called at the start of each command. */
extern void progress_bar_reset (struct progress_bar *);

/* This should be called from the progress bar callback.  It displays
 * the progress bar.
 */
extern void progress_bar_set (struct progress_bar *, uint64_t position, uint64_t total);

/* Free up progress bar handle and resources. */
extern void progress_bar_free (struct progress_bar *);

#endif /* PROGRESS_H */
