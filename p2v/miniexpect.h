/* miniexpect
 * Copyright (C) 2014 Red Hat Inc.
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

/* ** NOTE ** All API documentation is in the manual page.
 *
 * To read the manual page from the source directory, do:
 *    man ./miniexpect.3
 * If you have installed miniexpect, do:
 *    man 3 miniexpect
 *
 * The source for the manual page is miniexpect.pod.
 */

#ifndef MINIEXPECT_H_
#define MINIEXPECT_H_

#include <unistd.h>

#include <pcre.h>

/* This handle is created per subprocess that is spawned. */
struct mexp_h {
  int fd;
  pid_t pid;
  int timeout;
  char *buffer;
  size_t len;
  size_t alloc;
  ssize_t next_match;
  size_t read_size;
  int pcre_error;
  void *user1;
  void *user2;
  void *user3;
};
typedef struct mexp_h mexp_h;

/* Spawn a subprocess. */
extern mexp_h *mexp_spawnv (const char *file, char **argv);
extern mexp_h *mexp_spawnl (const char *file, const char *arg, ...);

/* Close the handle. */
extern int mexp_close (mexp_h *h);

/* Expect. */
struct mexp_regexp {
  int r;
  const pcre *re;
  const pcre_extra *extra;
  int options;
};
typedef struct mexp_regexp mexp_regexp;

enum mexp_status {
  MEXP_EOF        = 0,
  MEXP_ERROR      = -1,
  MEXP_PCRE_ERROR = -2,
  MEXP_TIMEOUT    = -3,
};

extern int mexp_expect (mexp_h *h, const mexp_regexp *regexps,
                        int *ovector, int ovecsize);

extern int mexp_printf (mexp_h *h, const char *fs, ...)
  __attribute__((format(printf,2,3)));

#endif /* MINIEXPECT_H_ */
