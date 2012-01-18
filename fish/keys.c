/* libguestfs - guestfish and guestmount shared option parsing
 * Copyright (C) 2010-2012 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <termios.h>
#include <string.h>

#include "guestfs.h"

#include "options.h"

/* Read a passphrase ('Key') from /dev/tty with echo off.
 * The caller (cmds.c) will call free on the string afterwards.
 * Based on the code in cryptsetup file lib/utils.c.
 */
char *
read_key (const char *param)
{
  FILE *infp, *outfp;
  struct termios orig, temp;
  char *ret = NULL;

  /* Read and write to /dev/tty if available. */
  if (keys_from_stdin ||
      (infp = outfp = fopen ("/dev/tty", "w+")) == NULL) {
    infp = stdin;
    outfp = stdout;
  }

  /* Print the prompt and set no echo. */
  int tty = isatty (fileno (infp));
  int tcset = 0;
  if (tty) {
    fprintf (outfp, _("Enter key or passphrase (\"%s\"): "), param);

    if (!echo_keys) {
      if (tcgetattr (fileno (infp), &orig) == -1) {
        perror ("tcgetattr");
        goto error;
      }
      memcpy (&temp, &orig, sizeof temp);
      temp.c_lflag &= ~ECHO;

      tcsetattr (fileno (infp), TCSAFLUSH, &temp);
      tcset = 1;
    }
  }

  size_t n = 0;
  ssize_t len;
  len = getline (&ret, &n, infp);
  if (len == -1) {
    perror ("getline");
    ret = NULL;
    goto error;
  }

  /* Remove the terminating \n if there is one. */
  if (len > 0 && ret[len-1] == '\n')
    ret[len-1] = '\0';

 error:
  /* Restore echo, close file descriptor. */
  if (tty && tcset) {
    printf ("\n");
    tcsetattr (fileno (infp), TCSAFLUSH, &orig);
  }

  if (infp != stdin)
    fclose (infp); /* outfp == infp, so this is closed also */

  return ret;
}
