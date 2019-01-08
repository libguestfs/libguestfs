/* libguestfs
 * Copyright (C) 2013-2019 Red Hat Inc.
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

/**
 * This header file is included in all "frontend" parts of libguestfs,
 * namely the library, non-C language bindings, virt tools and tests.
 *
 * The daemon does B<not> use this header.  If you need a place to put
 * something shared with absolutely everything including the daemon,
 * put it in F<lib/guestfs-internal-all.h>
 *
 * If a definition is only needed by a single component of libguestfs
 * (eg. just the library, or just a single virt tool) then it should
 * B<not> be here!
 */

#ifndef GUESTFS_UTILS_H_
#define GUESTFS_UTILS_H_

#include <stdbool.h>

#include "guestfs-internal-all.h"
#include "cleanups.h"

#define _(str) dgettext(PACKAGE, (str))
#define N_(str) dgettext(PACKAGE, (str))

/* utils.c */
extern void guestfs_int_free_string_list (char **);
extern size_t guestfs_int_count_strings (char *const *);
extern char *guestfs_int_concat_strings (char *const *);
extern char **guestfs_int_copy_string_list (char *const *);
extern char *guestfs_int_join_strings (const char *sep, char *const *);
extern char **guestfs_int_split_string (char sep, const char *);
extern char *guestfs_int_exit_status_to_string (int status, const char *cmd_name, char *buffer, size_t buflen);
extern int guestfs_int_random_string (char *ret, size_t len);
extern char *guestfs_int_drive_name (size_t index, char *ret);
extern ssize_t guestfs_int_drive_index (const char *);
extern int guestfs_int_is_true (const char *str);
extern bool guestfs_int_string_is_valid (const char *str, size_t min_length, size_t max_length, int flags, const char *extra);
#define VALID_FLAG_ALPHA 1
#define VALID_FLAG_DIGIT 2
//extern void guestfs_int_fadvise_normal (int fd);
extern void guestfs_int_fadvise_sequential (int fd);
extern void guestfs_int_fadvise_random (int fd);
extern void guestfs_int_fadvise_noreuse (int fd);
//extern void guestfs_int_fadvise_dontneed (int fd);
//extern void guestfs_int_fadvise_willneed (int fd);
extern char *guestfs_int_shell_unquote (const char *str);
extern int guestfs_int_is_reg (int64_t mode);
extern int guestfs_int_is_dir (int64_t mode);
extern int guestfs_int_is_chr (int64_t mode);
extern int guestfs_int_is_blk (int64_t mode);
extern int guestfs_int_is_fifo (int64_t mode);
extern int guestfs_int_is_lnk (int64_t mode);
extern int guestfs_int_is_sock (int64_t mode);
extern char *guestfs_int_full_path (const char *dir, const char *name);
extern void guestfs_int_hexdump (const void *data, size_t len, FILE *fp);

/* Not all language bindings know how to deal with Pointer arguments.
 * Those that don't will use this macro which complains noisily and
 * returns NULL.
 */
#define POINTER_NOT_IMPLEMENTED(type)                                   \
  (                                                                     \
   fprintf (stderr, "*** WARNING: this language binding does not support conversion of Pointer(%s), so the current function will always fail.  Patches to fix this should be sent to the libguestfs upstream mailing list.\n", \
            type),                                                      \
   NULL                                                                 \
)

/* ANSI colours.  These are defined as macros so that we don't have to
 * define the force_colour global variable in the library.
 */
#define ansi_green(fp)                           \
  do {                                           \
    if (force_colour || isatty (fileno (fp)))    \
      fputs ("\033[0;32m", (fp));                \
  } while (0)
#define ansi_red(fp)                             \
  do {                                           \
    if (force_colour || isatty (fileno (fp)))    \
      fputs ("\033[1;31m", (fp));                \
  } while (0)
#define ansi_blue(fp)                            \
  do {                                           \
    if (force_colour || isatty (fileno (fp)))    \
      fputs ("\033[1;34m", (fp));                \
  } while (0)
#define ansi_magenta(fp)                         \
  do {                                           \
    if (force_colour || isatty (fileno (fp)))    \
      fputs ("\033[1;35m", (fp));                \
  } while (0)
#define ansi_restore(fp)                         \
  do {                                           \
    if (force_colour || isatty (fileno (fp)))    \
      fputs ("\033[0m", (fp));                   \
  } while (0)

#endif /* GUESTFS_UTILS_H_ */
