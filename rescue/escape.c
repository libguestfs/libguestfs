/* virt-rescue
 * Copyright (C) 2010-2023 Red Hat Inc.
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
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <locale.h>
#include <libintl.h>

#include "c-ctype.h"

#include "guestfs.h"
#include "guestfs-utils.h"

#include "rescue.h"

static void print_help (void);
static void print_inspector (void);
static void crlf (void);
static void print_escape_key (void);

/* Parse the -e parameter from the command line. */
int
parse_escape_key (const char *arg)
{
  size_t len;

  if (STREQ (arg, "none"))
    return 0;

  len = strlen (arg);
  if (len == 0)
    return -1;

  switch (arg[0]) {
  case '^':
    if (len == 2 &&
        ((arg[1] >= 'a' && arg[1] <= 'z') ||
         (arg[1] >= 'A' && arg[1] <= '_'))) {
      return c_toupper (arg[1]) - '@';
    }
    else
      return -1;
    break;
  }

  return -1;
}

/* Print one-line end user description of the escape key.
 *
 * This is printed when virt-rescue starts.
 */
void
print_escape_key_help (void)
{
  crlf ();
  /* Difficult to translate this string. XXX */
  printf ("The virt-rescue escape key is ‘");
  print_escape_key ();
  printf ("’.  Type ‘");
  print_escape_key ();
  printf (" h’ for help.");
  crlf ();
}

void
init_escape_state (struct escape_state *state)
{
  state->in_escape = false;
}

/* Process escapes in the tty input buffer.
 *
 * This function has a state parameter so that we can handle an escape
 * sequence split over the end of the buffer.
 *
 * Escape sequences are removed from the buffer.
 *
 * Returns true iff virt-rescue should exit.
 */
bool
process_escapes (struct escape_state *state, char *buf, size_t *len)
{
  size_t i;

  for (i = 0; i < *len; ++i) {
#define DROP_CURRENT_CHAR() \
    memmove (&buf[i], &buf[i+1], --(*len))
#define PRINT_ESC() \
    do { print_escape_key (); putchar (buf[i]); crlf (); } while (0)

    if (!state->in_escape) {
      if (buf[i] == escape_key) {
        /* Drop the escape key from the buffer and go to escape mode. */
        DROP_CURRENT_CHAR ();
        state->in_escape = true;
      }
    }
    else /* in escape sequence */ {
      if (buf[i] == escape_key) /* ^] ^] means send ^] to rescue shell */
        state->in_escape = false;
      else {
        switch (buf[i]) {
        case '?': case 'h':
          PRINT_ESC ();
          print_help ();
          break;

        case 'i':
          PRINT_ESC ();
          print_inspector ();
          break;

        case 'q': case 'x':
          PRINT_ESC ();
          return true /* exit virt-rescue at once */;

        case 's':
          PRINT_ESC ();
          printf (_("attempting to sync filesystems ..."));
          crlf ();
          guestfs_sync (g);
          break;

        case 'u':
          PRINT_ESC ();
          printf (_("unmounting filesystems ..."));
          crlf ();
          guestfs_umount_all (g);
          break;

        case 'z':
          PRINT_ESC ();
          raise (SIGTSTP);
          break;

        default:
          /* Any unrecognized escape sequence will be dropped.  We
           * could be obnoxious and ring the bell, but I hate it when
           * programs do that.
           */
          break;
        }

        /* Drop the escape key and return to non-escape mode. */
        DROP_CURRENT_CHAR ();
        state->in_escape = false;

        /* The output is line buffered, this is just to make sure
         * everything gets written to stdout before we continue
         * writing to STDOUT_FILENO.
         */
        fflush (stdout);
      }
    } /* in escape sequence */
  } /* for */

  return false /* don't exit */;
}

/* This is called when the user types ^] h */
static void
print_help (void)
{
  printf (_("virt-rescue escape sequences:"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" ? - print this message"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" h - print this message"));
  crlf ();

  if (inspector) {
    putchar (' ');
    print_escape_key ();
    printf (_(" i - print inspection data"));
    crlf ();
  }

  putchar (' ');
  print_escape_key ();
  printf (_(" q - quit virt-rescue"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" s - sync the filesystems"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" u - unmount filesystems"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" x - quit virt-rescue"));
  crlf ();

  putchar (' ');
  print_escape_key ();
  printf (_(" z - suspend virt-rescue"));
  crlf ();

  printf (_("to pass the escape key through to the rescue shell, type it twice"));
  crlf ();
}

/* This is called when the user types ^] i */
static void
print_inspector (void)
{
  CLEANUP_FREE_STRING_LIST char **roots = NULL;
  size_t i;
  const char *root;
  char *str;

  if (inspector) {
    roots = guestfs_inspect_get_roots (g);
    if (roots) {
      crlf ();
      for (i = 0; roots[i] != NULL; ++i) {
        root = roots[i];
        printf (_("root device: %s"), root);
        crlf ();

        str = guestfs_inspect_get_product_name (g, root);
        if (str) {
          printf (_("  product name: %s"), str);
          crlf ();
        }
        free (str);

        str = guestfs_inspect_get_type (g, root);
        if (str) {
          printf (_("  type: %s"), str);
          crlf ();
        }
        free (str);

        str = guestfs_inspect_get_distro (g, root);
        if (str) {
          printf (_("  distro: %s"), str);
          crlf ();
        }
        free (str);
      }
    }
  }
}

/* Because the terminal is in raw mode, we have to send CR LF instead
 * of printing just \n.
 */
static void
crlf (void)
{
  putchar ('\r');
  putchar ('\n');
}

static void
print_escape_key (void)
{
  switch (escape_key) {
  case 0:
    printf ("none");
    break;
  case '\x1'...'\x1f':
    putchar ('^');
    putchar (escape_key + '@');
    break;
  default:
    abort ();
  }
}
