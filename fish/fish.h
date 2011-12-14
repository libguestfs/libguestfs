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

#include "fish-cmds.h"

#ifdef HAVE_GETTEXT
#include "gettext.h"
#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))
#else
#define _(str) str
#define N_(str) str
#endif

#if !ENABLE_NLS
#undef textdomain
#define textdomain(Domainname) /* empty */
#undef bindtextdomain
#define bindtextdomain(Domainname, Dirname) /* empty */
#endif

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

#define TMP_TEMPLATE_ON_STACK(var)                        \
  const char *ttos_tmpdir = guestfs_tmpdir ();            \
  char var[strlen (ttos_tmpdir) + 32];                    \
  sprintf (var, "%s/guestfishXXXXXX", ttos_tmpdir)        \

/* in fish.c */
extern guestfs_h *g;
extern int read_only;
extern int quit;
extern int verbose;
extern int command_num;
extern int progress_bars;
extern int remote_control_csh;
extern const char *libvirt_uri;
extern int input_lineno;

extern int issue_command (const char *cmd, char *argv[], const char *pipe, int rc_exit_on_error_flag);
extern void list_builtin_commands (void);
extern int display_builtin_command (const char *cmd);
extern void free_strings (char **argv);
extern int count_strings (char *const *argv);
extern void print_strings (char *const *argv);
extern void print_table (char *const *argv);
extern int is_true (const char *str);
extern char **parse_string_list (const char *str);
extern int xwrite (int fd, const void *buf, size_t len);
extern char *win_prefix (const char *path);
extern char *file_in (const char *arg);
extern void free_file_in (char *s);
extern char *file_out (const char *arg);
extern void extended_help_message (void);
extern void progress_callback (guestfs_h *g, void *data, uint64_t event, int event_handle, int flags, const char *buf, size_t buf_len, const uint64_t *array, size_t array_len);

/* in cmds.c (auto-generated) */
extern void list_commands (void);
extern int display_command (const char *cmd);
extern int run_action (const char *cmd, size_t argc, char *argv[]);

/* in completion.c (auto-generated) */
extern char **do_completion (const char *text, int start, int end);

/* in destpaths.c */
extern int complete_dest_paths;
extern char *complete_dest_paths_generator (const char *text, int state);

/* in events.c */
extern void init_event_handlers (void);
extern void free_event_handlers (void);

/* in event-names.c (auto-generated) */
extern const char *event_name_of_event_bitmask (uint64_t);
extern void print_event_set (uint64_t, FILE *);
extern int event_bitmask_of_event_set (const char *arg, uint64_t *);

/* in alloc.c */
extern int alloc_disk (const char *filename, const char *size,
                       int add, int sparse);
extern int parse_size (const char *str, off_t *size_rtn);

/* in help.c */
extern void display_help (void);

/* in prep.c */
struct prep_data {
  const struct prep *prep;
  const char *orig_type_string;
  char **params;
};
typedef struct prep_data prep_data;
extern void list_prepared_drives (void);
extern prep_data *create_prepared_file (const char *type_string,
                                        const char *filename);
extern void prepare_drive (const char *filename, prep_data *data,
                           const char *device);
extern void prep_error (prep_data *data, const char *filename, const char *fs, ...) __attribute__((noreturn, format (printf,3,4)));
extern void free_prep_data (void *data);

/* in prep_lv.c */
extern int vg_lv_parse (const char *device, char **vg, char **lv);

/* in rc.c (remote control) */
extern void rc_listen (void) __attribute__((noreturn));
extern int rc_remote (int pid, const char *cmd, size_t argc, char *argv[],
                      int exit_on_error);

/* in tilde.c */
extern char *try_tilde_expansion (char *path);

/* This should just list all the built-in commands so they can
 * be added to the generated auto-completion code.
 */
#define BUILTIN_COMMANDS_FOR_COMPLETION \
  "help",				\
  "quit", "exit", "q"

static inline char *
bad_cast (char const *s)
{
  return (char *) s;
}

#endif /* FISH_H */
