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

#include <stdio.h>
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
  FILE *debug_fp;
  void *user1;
  void *user2;
  void *user3;
};
typedef struct mexp_h mexp_h;

/* Methods to access (some) fields in the handle. */
#define mexp_get_fd(h) ((h)->fd)
#define mexp_get_pid(h) ((h)->pid)
#define mexp_get_timeout_ms(h) ((h)->timeout)
#define mexp_set_timeout_ms(h, ms) ((h)->timeout = (ms))
/* If secs == -1, then this sets h->timeout to -1000, but the main
 * code handles this since it only checks for h->timeout < 0.
 */
#define mexp_set_timeout(h, secs) ((h)->timeout = 1000 * (secs))
#define mexp_get_read_size(h) ((h)->read_size)
#define mexp_set_read_size(h, size) ((h)->read_size = (size))
#define mexp_get_pcre_error(h) ((h)->pcre_error)
#define mexp_set_debug_file(h, fp) ((h)->debug_fp = (fp))
#define mexp_get_debug_file(h) ((h)->debug_fp)

/* Spawn a subprocess. */
extern mexp_h *mexp_spawnvf (unsigned flags, const char *file, char **argv);
extern mexp_h *mexp_spawnlf (unsigned flags, const char *file, const char *arg, ...);
#define mexp_spawnv(file,argv) mexp_spawnvf (0, (file), (argv))
#define mexp_spawnl(file,...) mexp_spawnlf (0, (file), __VA_ARGS__)

#define MEXP_SPAWN_KEEP_SIGNALS 1
#define MEXP_SPAWN_KEEP_FDS     2
#define MEXP_SPAWN_COOKED_MODE  4
#define MEXP_SPAWN_RAW_MODE     0

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

/* Sending commands, keypresses. */
extern int mexp_printf (mexp_h *h, const char *fs, ...)
  __attribute__((format(printf,2,3)));
extern int mexp_printf_password (mexp_h *h, const char *fs, ...)
  __attribute__((format(printf,2,3)));
extern int mexp_send_interrupt (mexp_h *h);

#endif /* MINIEXPECT_H_ */
