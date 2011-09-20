/* libguestfs Erlang bindings.
 * Copyright (C) 2011 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <erl_interface.h>
#include <ei.h>

#include "error.h"
#include "full-read.h"
#include "full-write.h"

#include "guestfs.h"

guestfs_h *g;

extern ETERM *dispatch (ETERM *message);
extern int atom_equals (ETERM *atom, const char *name);
extern ETERM *make_error (const char *funname);
extern ETERM *unknown_optarg (const char *funname, ETERM *optargname);
extern ETERM *unknown_function (ETERM *fun);
extern ETERM *make_string_list (char **r);
extern ETERM *make_table (char **r);
extern ETERM *make_bool (int r);
extern char **get_string_list (ETERM *term);
extern int get_bool (ETERM *term);
extern void free_strings (char **r);

/* This stops things getting out of hand, but also lets us detect
 * protocol problems quickly.
 */
#define MAX_MESSAGE_SIZE (32*1024*1024)

static unsigned char *read_message (void);
static void write_reply (ETERM *);

int
main (void)
{
  unsigned char *buf;
  ETERM *ret, *message;

  erl_init (NULL, 0);

  /* This process has a single libguestfs handle.  If the Erlang
   * system creates more than one handle, then more than one of these
   * processes will be running.
   */
  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, 0, "could not create guestfs handle");

  guestfs_set_error_handler (g, NULL, NULL);

  while ((buf = read_message ()) != NULL) {
    message = erl_decode (buf);
    free (buf);

    ret = dispatch (message);
    erl_free_term (message);

    write_reply (ret);
    erl_free_term (ret);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/* The Erlang port always sends the length of the buffer as 4
 * bytes in network byte order, followed by the message buffer.
 */
static unsigned char *
read_message (void)
{
  unsigned char buf[4];
  size_t size;
  unsigned char *r;

  errno = 0;
  if (full_read (0, buf, 4) != 4) {
    if (errno == 0) /* ok - closed connection normally */
      return NULL;
    else
      error (EXIT_FAILURE, errno, "read message size");
  }

  size = buf[0] << 24 | buf[1] << 16 | buf[2] << 8 | buf[3];

  if (size > MAX_MESSAGE_SIZE)
    error (EXIT_FAILURE, 0, "message larger than MAX_MESSAGE_SIZE");

  r = malloc (size);
  if (r == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  if (full_read (0, r, size) != size)
    error (EXIT_FAILURE, errno, "read message content");

  return r;
}

static void
write_reply (ETERM *term)
{
  size_t size;
  unsigned char sbuf[4];
  unsigned char *buf;

  size = erl_term_len (term);

  buf = malloc (size);
  if (buf == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  erl_encode (term, buf);

  sbuf[0] = (size >> 24) & 0xff;
  sbuf[1] = (size >> 16) & 0xff;
  sbuf[2] = (size >> 8) & 0xff;
  sbuf[3] = size & 0xff;

  if (full_write (1, sbuf, 4) != 4)
    error (EXIT_FAILURE, errno, "write message size");

  if (full_write (1, buf, size) != size)
    error (EXIT_FAILURE, errno, "write message content");

  free (buf);
}

/* Note that all published Erlang code/examples etc uses strncmp in
 * a buggy way.  This is the right way to do it.
 */
int
atom_equals (ETERM *atom, const char *name)
{
  size_t namelen = strlen (name);
  size_t atomlen = ERL_ATOM_SIZE (atom);
  if (namelen != atomlen) return 0;
  return strncmp (ERL_ATOM_PTR (atom), name, atomlen) == 0;
}

ETERM *
make_error (const char *funname)
{
  ETERM *error = erl_mk_atom ("error");
  ETERM *msg = erl_mk_string (guestfs_last_error (g));
  ETERM *num = erl_mk_int (guestfs_last_errno (g));
  ETERM *t[3] = { error, msg, num };
  return erl_mk_tuple (t, 3);
}

ETERM *
unknown_function (ETERM *fun)
{
  ETERM *unknown = erl_mk_atom ("unknown");
  ETERM *funcopy = erl_copy_term (fun);
  ETERM *t[2] = { unknown, funcopy };
  return erl_mk_tuple (t, 2);
}

ETERM *
unknown_optarg (const char *funname, ETERM *optargname)
{
  ETERM *unknownarg = erl_mk_atom ("unknownarg");
  ETERM *copy = erl_copy_term (optargname);
  ETERM *t[2] = { unknownarg, copy };
  return erl_mk_tuple (t, 2);
}

ETERM *
make_string_list (char **r)
{
  size_t i, size;

  for (size = 0; r[size] != NULL; ++size)
    ;

  ETERM *t[size];

  for (i = 0; r[i] != NULL; ++i)
    t[i] = erl_mk_string (r[i]);

  return erl_mk_list (t, size);
}

/* Make a hash table.  The number of elements returned by the C
 * function is always even.
 */
ETERM *
make_table (char **r)
{
  size_t i, size;

  for (size = 0; r[size] != NULL; ++size)
    ;

  ETERM *t[size/2];
  ETERM *a[2];

  for (i = 0; r[i] != NULL; i += 2) {
    a[0] = erl_mk_string (r[i]);
    a[1] = erl_mk_string (r[i+1]);
    t[i/2] = erl_mk_tuple (a, 2);
  }

  return erl_mk_list (t, size/2);
}

ETERM *
make_bool (int r)
{
  if (r)
    return erl_mk_atom ("true");
  else
    return erl_mk_atom ("false");
}

char **
get_string_list (ETERM *term)
{
  ETERM *t;
  size_t i, size;
  char **r;

  for (size = 0, t = term; !ERL_IS_EMPTY_LIST (t);
       size++, t = ERL_CONS_TAIL (t))
    ;

  r = malloc ((size+1) * sizeof (char *));
  if (r == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  for (i = 0, t = term; !ERL_IS_EMPTY_LIST (t); i++, t = ERL_CONS_TAIL (t))
    r[i] = erl_iolist_to_string (ERL_CONS_HEAD (t));
  r[size] = NULL;

  return r;
}

int
get_bool (ETERM *term)
{
  if (atom_equals (term, "true"))
    return 1;
  else
    return 0;
}

void
free_strings (char **r)
{
  size_t i;

  for (i = 0; r[i] != NULL; ++i)
    free (r[i]);
  free (r);
}
