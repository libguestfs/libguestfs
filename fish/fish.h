/* libguestfs - the guestfsd daemon
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef FISH_H
#define FISH_H

#include <guestfs.h>

/* in fish.c */
extern guestfs_h *g;
extern int g_launched;
extern int quit;
extern int verbose;
extern void pod2text (const char *heading, const char *body);
extern void list_builtin_commands (void);
extern void display_builtin_command (const char *cmd);
extern void free_strings (char **argv);
extern void print_strings (char * const * const argv);
extern void print_table (char * const * const argv);
extern int launch (guestfs_h *);
extern int is_true (const char *str);
extern char **parse_string_list (const char *str);

/* in cmds.c (auto-generated) */
extern void list_commands (void);
extern void display_command (const char *cmd);
extern int run_action (const char *cmd, int argc, char *argv[]);

/* in completion.c (auto-generated) */
extern char **do_completion (const char *text, int start, int end);

/* in alloc.c */
extern int do_alloc (int argc, char *argv[]);

#endif /* FISH_H */
