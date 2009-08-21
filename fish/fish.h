/* libguestfs - guestfish shell
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

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
#define N_(str) str
#endif

/* in fish.c */
extern guestfs_h *g;
extern int quit;
extern int verbose;
extern int issue_command (const char *cmd, char *argv[], const char *pipe);
extern void pod2text (const char *name, const char *shortdesc, const char *body);
extern void list_builtin_commands (void);
extern void display_builtin_command (const char *cmd);
extern void free_strings (char **argv);
extern int count_strings (char *const *argv);
extern void print_strings (char *const *argv);
extern void print_table (char *const *argv);
extern int launch (guestfs_h *);
extern int is_true (const char *str);
extern char **parse_string_list (const char *str);
extern int xwrite (int fd, const void *buf, size_t len);

/* in cmds.c (auto-generated) */
extern void list_commands (void);
extern void display_command (const char *cmd);
extern int run_action (const char *cmd, int argc, char *argv[]);

/* in completion.c (auto-generated) */
extern char **do_completion (const char *text, int start, int end);

/* in destpaths.c */
extern int complete_dest_paths;
extern char *complete_dest_paths_generator (const char *text, int state);

/* in alloc.c */
extern int do_alloc (const char *cmd, int argc, char *argv[]);

/* in echo.c */
extern int do_echo (const char *cmd, int argc, char *argv[]);

/* in edit.c */
extern int do_edit (const char *cmd, int argc, char *argv[]);

/* in lcd.c */
extern int do_lcd (const char *cmd, int argc, char *argv[]);

/* in glob.c */
extern int do_glob (const char *cmd, int argc, char *argv[]);

/* in more.c */
extern int do_more (const char *cmd, int argc, char *argv[]);

/* in rc.c (remote control) */
extern void rc_listen (void) __attribute__((noreturn));
extern int rc_remote (int pid, const char *cmd, int argc, char *argv[],
                      int exit_on_error);

/* in reopen.c */
extern int do_reopen (const char *cmd, int argc, char *argv[]);

/* in time.c */
extern int do_time (const char *cmd, int argc, char *argv[]);

/* in tilde.c */
extern char *try_tilde_expansion (char *path);

/* This should just list all the built-in commands so they can
 * be added to the generated auto-completion code.
 */
#define BUILTIN_COMMANDS_FOR_COMPLETION \
  "help",				\
  "quit", "exit", "q",		        \
  "alloc", "allocate",		        \
  "echo",				\
  "edit", "vi", "emacs",		\
  "lcd",				\
  "glob",				\
  "more", "less",			\
  "reopen",				\
  "time"

#endif /* FISH_H */
