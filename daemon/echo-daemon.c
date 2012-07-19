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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <string.h>

#include "actions.h"
#include "daemon.h"

char *
do_echo_daemon (char *const *argv)
{
  char *out = NULL;
  size_t out_len = 0;

  /* Iterate over argv entries until reaching the NULL terminator */
  while (*argv) {
    char add_space = 0;

    /* Store the end of current output */
    size_t out_end = out_len;

    /* Calculate the new output size */
    size_t arg_len = strlen(*argv);
    out_len += arg_len;

    /* We will prepend a space if this isn't the first argument added */
    if (NULL != out) {
      out_len++;
      add_space = 1;
    }

    /* Make the output buffer big enough for the string and its terminator */
    char *out_new = realloc (out, out_len + 1);
    if (NULL == out_new) {
      reply_with_perror ("realloc");
      free(out);
      return 0;
    }
    out = out_new;

    /* Prepend a space if required */
    if (add_space) {
      out[out_end++] = ' ';
    }

    /* Copy the argument to the output */
    memcpy(&out[out_end], *argv, arg_len);

    argv++;
  }

  /* NULL terminate the output */
  out[out_len] = '\0';

  return out;
}
