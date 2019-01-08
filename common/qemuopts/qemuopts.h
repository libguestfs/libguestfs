/* libguestfs
 * Copyright (C) 2009-2019 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/* See qemuopts.c for documentation on how to use the library. */

#ifndef QEMUOPTS_H_
#define QEMUOPTS_H_

#include <stdarg.h>

struct qemuopts;

extern struct qemuopts *qemuopts_create (void);
extern void qemuopts_free (struct qemuopts *qopts);
extern int qemuopts_add_flag (struct qemuopts *qopts, const char *flag);
extern int qemuopts_add_arg (struct qemuopts *qopts, const char *flag, const char *value);
extern int qemuopts_add_arg_format (struct qemuopts *qopts, const char *flag, const char *fs, ...) __attribute__((format (printf,3,4)));
extern int qemuopts_add_arg_noquote (struct qemuopts *qopts, const char *flag, const char *value);
extern int qemuopts_start_arg_list (struct qemuopts *qopts, const char *flag);
extern int qemuopts_append_arg_list (struct qemuopts *qopts, const char *value);
extern int qemuopts_append_arg_list_format (struct qemuopts *qopts, const char *fs, ...) __attribute__((format (printf,2,3)));
extern int qemuopts_end_arg_list (struct qemuopts *qopts);
extern int qemuopts_add_arg_list (struct qemuopts *qopts, const char *flag, const char *elem0, ...) __attribute__((sentinel));
extern int qemuopts_set_binary (struct qemuopts *qopts, const char *binary);
extern int qemuopts_set_binary_by_arch (struct qemuopts *qopts, const char *arch);
extern int qemuopts_to_script (struct qemuopts *qopts, const char *filename);
extern int qemuopts_to_channel (struct qemuopts *qopts, FILE *fp);
extern char **qemuopts_to_argv (struct qemuopts *qopts);
extern int qemuopts_to_config_file (struct qemuopts *qopts, const char *filename);
extern int qemuopts_to_config_channel (struct qemuopts *qopts, FILE *fp);

#endif /* QEMUOPTS_H_ */
