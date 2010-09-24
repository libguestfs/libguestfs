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
extern int utf8_mode;
extern int have_terminfo;
extern int progress_bars;
extern const char *libvirt_uri;
extern int issue_command (const char *cmd, char *argv[], const char *pipe);
extern void pod2text (const char *name, const char *shortdesc, const char *body);
extern void list_builtin_commands (void);
extern int display_builtin_command (const char *cmd);
extern void free_strings (char **argv);
extern int count_strings (char *const *argv);
extern void print_strings (char *const *argv);
extern void print_table (char *const *argv);
extern int is_true (const char *str);
extern char **parse_string_list (const char *str);
extern int xwrite (int fd, const void *buf, size_t len);
extern char *resolve_win_path (const char *path);
extern char *file_in (const char *arg);
extern void free_file_in (char *s);
extern char *file_out (const char *arg);
extern void extended_help_message (void);
extern char *read_key (const char *param);

/* in cmds.c (auto-generated) */
extern void list_commands (void);
extern int display_command (const char *cmd);
extern int run_action (const char *cmd, int argc, char *argv[]);

/* in completion.c (auto-generated) */
extern char **do_completion (const char *text, int start, int end);

/* in destpaths.c */
extern int complete_dest_paths;
extern char *complete_dest_paths_generator (const char *text, int state);

/* in alloc.c */
extern int run_alloc (const char *cmd, int argc, char *argv[]);
extern int run_sparse (const char *cmd, int argc, char *argv[]);
extern int alloc_disk (const char *filename, const char *size,
                       int add, int sparse);
extern int parse_size (const char *str, off_t *size_rtn);

/* in copy.c */
extern int run_copy_in (const char *cmd, int argc, char *argv[]);
extern int run_copy_out (const char *cmd, int argc, char *argv[]);

/* in echo.c */
extern int run_echo (const char *cmd, int argc, char *argv[]);

/* in edit.c */
extern int run_edit (const char *cmd, int argc, char *argv[]);

/* in hexedit.c */
extern int run_hexedit (const char *cmd, int argc, char *argv[]);

/* in inspect.c */
extern void inspect_mount (void);
extern void print_inspect_prompt (void);

/* in lcd.c */
extern int run_lcd (const char *cmd, int argc, char *argv[]);

/* in glob.c */
extern int run_glob (const char *cmd, int argc, char *argv[]);

/* in man.c */
extern int run_man (const char *cmd, int argc, char *argv[]);

/* in more.c */
extern int run_more (const char *cmd, int argc, char *argv[]);

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
extern void free_prep_data (prep_data *data);

/* in prep_lv.c */
extern int vg_lv_parse (const char *device, char **vg, char **lv);

/* in progress.c */
extern void reset_progress_bar (void);
extern void progress_callback (guestfs_h *g, void *data, int proc_nr, int serial, uint64_t position, uint64_t total);

/* in rc.c (remote control) */
extern void rc_listen (void) __attribute__((noreturn));
extern int rc_remote (int pid, const char *cmd, int argc, char *argv[],
                      int exit_on_error);

/* in reopen.c */
extern int run_reopen (const char *cmd, int argc, char *argv[]);

/* in supported.c */
extern int run_supported (const char *cmd, int argc, char *argv[]);

/* in time.c */
extern int run_time (const char *cmd, int argc, char *argv[]);

/* in tilde.c */
extern char *try_tilde_expansion (char *path);

/* in virt.c */
extern int add_libvirt_drives (const char *guest);

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
