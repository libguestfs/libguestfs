/* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <libintl.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

void
guestfs___free_string_list (char **argv)
{
  size_t i;

  if (argv == NULL)
    return;

  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

size_t
guestfs___count_strings (char *const *argv)
{
  size_t r;

  for (r = 0; argv[r]; ++r)
    ;

  return r;
}

/* Note that near-identical functions exist in the daemon. */
char *
guestfs___concat_strings (char *const *argv)
{
  return guestfs___join_strings ("", argv);
}

char *
guestfs___join_strings (const char *sep, char *const *argv)
{
  size_t i, len, seplen, rlen;
  char *r;

  seplen = strlen (sep);

  len = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0)
      len += seplen;
    len += strlen (argv[i]);
  }
  len++; /* for final \0 */

  r = malloc (len);
  if (r == NULL)
    return NULL;

  rlen = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0) {
      memcpy (&r[rlen], sep, seplen);
      rlen += seplen;
    }
    len = strlen (argv[i]);
    memcpy (&r[rlen], argv[i], len);
    rlen += len;
  }
  r[rlen] = '\0';

  return r;
}

/* Translate a wait/system exit status into a printable string.  The
 * string must be freed by the caller.
 */
char *
guestfs___exit_status_to_string (int status, const char *cmd_name,
                                 char *buffer, size_t buflen)
{
  if (WIFEXITED (status)) {
    if (WEXITSTATUS (status) == 0)
      snprintf (buffer, buflen, _("%s exited successfully"),
                cmd_name);
    else
      snprintf (buffer, buflen, _("%s exited with error status %d"),
                cmd_name, WEXITSTATUS (status));
  }
  else if (WIFSIGNALED (status)) {
    snprintf (buffer, buflen, _("%s killed by signal %d (%s)"),
              cmd_name, WTERMSIG (status), strsignal (WTERMSIG (status)));
  }
  else if (WIFSTOPPED (status)) {
    snprintf (buffer, buflen, _("%s stopped by signal %d (%s)"),
              cmd_name, WSTOPSIG (status), strsignal (WSTOPSIG (status)));
  }
  else {
    snprintf (buffer, buflen, _("%s exited for an unknown reason (status %d)"),
              cmd_name, status);
  }

  return buffer;
}
