/* libguestfs - shared file editing
 * Copyright (C) 2009-2014 Red Hat Inc.
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

#ifndef FISH_FILE_EDIT_H
#define FISH_FILE_EDIT_H

#include <guestfs.h>

/**
 * Edit 'filename' using the specified 'editor' application.
 * If 'backup_extension' is not null, then a copy of 'filename' is saved
 * with 'backup_extension' appended to its file name.
 * If 'editor' is null, then the EDITOR environment variable
 * will be queried for the editor application, leaving "vi" as fallback
 * if not set.
 *
 * Returns -1 for failure, 0 on success, 1 if the editor did not change
 * the file (e.g. the user closed the editor without saving).
 */
extern int edit_file_editor (guestfs_h *g, const char *filename,
                             const char *editor, const char *backup_extension,
                             int verbose);

/**
 * Edit 'filename' running the specified 'perl_expr' using Perl.
 * If 'backup_extension' is not null, then a copy of 'filename' is saved
 * with 'backup_extension' appended to its file name.
 *
 * Returns -1 for failure, 0 otherwise (on success).
 */
extern int edit_file_perl (guestfs_h *g, const char *filename,
                           const char *perl_expr,
                           const char *backup_extension, int verbose);

#endif
