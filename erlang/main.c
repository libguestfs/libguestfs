/* libguestfs Erlang bindings.
 * Copyright (C) 2011-2023 Red Hat Inc.
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

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>

#include <ei.h>

#include "error.h"
#include "full-read.h"
#include "full-write.h"

#include "guestfs.h"
#include "guestfs-utils.h"

#include "actions.h"

guestfs_h *g;

/* This stops things getting out of hand, but also lets us detect
 * protocol problems quickly.
 */
#define MAX_MESSAGE_SIZE (32*1024*1024)

static char *read_message (void);
static void write_reply (ei_x_buff *);

int
main (void)
{
  char *buff;
  int index;
  int version;
  ei_x_buff reply;

  /* This process has a single libguestfs handle.  If the Erlang
   * system creates more than one handle, then more than one of these
   * processes will be running.
   */
  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, 0, "could not create guestfs handle");

  guestfs_set_error_handler (g, NULL, NULL);

  while ((buff = read_message ()) != NULL) {
    if (ei_x_new_with_version (&reply) != 0)
      error (EXIT_FAILURE, 0, "could not allocate reply buffer");

    index = 0;
    if (ei_decode_version (buff, &index, &version) != 0)
      error (EXIT_FAILURE, 0, "could not interpret the input message");

    if (dispatch (&reply, buff, &index) != 0)
      error (EXIT_FAILURE, 0, "could not decode input data or encode reply message");

    free (buff);
    write_reply (&reply);
    ei_x_free (&reply);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

/* The Erlang port always sends the length of the buffer as 4
 * bytes in network byte order, followed by the message buffer.
 */
static char *
read_message (void)
{
  uint32_t buf;
  size_t size;
  char *r;

  errno = 0;
  if (full_read (0, &buf, 4) != 4) {
    if (errno == 0) /* ok - closed connection normally */
      return NULL;
    else
      error (EXIT_FAILURE, errno, "read message size");
  }

  size = ntohl (buf);

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
write_reply (ei_x_buff *buff)
{
  size_t size = buff->index;
  unsigned char sbuf[4];

  sbuf[0] = (size >> 24) & 0xff;
  sbuf[1] = (size >> 16) & 0xff;
  sbuf[2] = (size >> 8) & 0xff;
  sbuf[3] = size & 0xff;

  if (full_write (1, sbuf, 4) != 4)
    error (EXIT_FAILURE, errno, "write message size");

  if (full_write (1, buff->buff, size) != size)
    error (EXIT_FAILURE, errno, "write message content");
}

/* Note that all published Erlang code/examples etc uses strncmp in
 * a buggy way.  This is the right way to do it.
 */
int
atom_equals (const char *atom, const char *name)
{
  const size_t namelen = strlen (name);
  const size_t atomlen = strlen (atom);
  if (namelen != atomlen) return 0;
  return strncmp (atom, name, atomlen) == 0;
}

int
make_error (ei_x_buff *buff, const char *funname)
{
  if (ei_x_encode_tuple_header (buff, 3) != 0) return -1;
  if (ei_x_encode_atom (buff, "error") != 0) return -1;
  if (ei_x_encode_string (buff, guestfs_last_error (g)) != 0) return -1;
  if (ei_x_encode_long (buff, guestfs_last_errno (g)) != 0) return -1;
  return 0;
}

int
unknown_function (ei_x_buff *buff, const char *fun)
{
  if (ei_x_encode_tuple_header (buff, 2) != 0) return -1;
  if (ei_x_encode_atom (buff, "unknown") != 0) return -1;
  if (ei_x_encode_atom (buff, fun) != 0) return -1;
  return 0;
}

int
unknown_optarg (ei_x_buff *buff, const char *funname, const char *optargname)
{
  if (ei_x_encode_tuple_header (buff, 2) != 0) return -1;
  if (ei_x_encode_atom (buff, "unknownarg") != 0) return -1;
  if (ei_x_encode_atom (buff, optargname) != 0) return -1;
  return 0;
}

int
make_string_list (ei_x_buff *buff, char **r)
{
  size_t i, size;

  for (size = 0; r[size] != NULL; ++size);

  if (ei_x_encode_list_header (buff, size) != 0) return -1;

  for (i = 0; r[i] != NULL; ++i)
    if (ei_x_encode_string (buff, r[i]) != 0) return -1;

  if (size > 0)
    if (ei_x_encode_empty_list (buff) != 0) return -1;

  return 0;
}

/* Make a hash table.  The number of elements returned by the C
 * function is always even.
 */
int
make_table (ei_x_buff *buff, char **r)
{
  size_t i, size;

  for (size = 0; r[size] != NULL; ++size);

  if (ei_x_encode_list_header (buff, size/2) != 0) return -1;

  for (i = 0; r[i] != NULL; i += 2) {
    if (ei_x_encode_tuple_header (buff, 2) != 0) return -1;
    if (ei_x_encode_string (buff, r[i]) != 0) return -1;
    if (ei_x_encode_string (buff, r[i+1]) != 0) return -1;
  }

  if (size/2 > 0)
    if (ei_x_encode_empty_list (buff) != 0) return -1;

  return 0;
}

int
make_bool (ei_x_buff *buff, int r)
{
  if (r)
    return ei_x_encode_atom (buff, "true");
  else
    return ei_x_encode_atom (buff, "false");
}

int
decode_string_list (const char *buff, int *index, char ***res)
{
  int i, size;
  char **r;

  if (ei_decode_list_header (buff, index, &size) != 0)
    error (EXIT_FAILURE, 0, "not a list");

  r = malloc ((size+1) * sizeof (char *));
  if (r == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  for (i = 0; i < size; i++)
    if (decode_string (buff, index, &r[i]) != 0) return -1;

  // End of a list is encoded by an empty list, so skip it
  if (size > 0 && buff[*index] == ERL_NIL_EXT)
    (*index)++;

  r[size] = NULL;
  *res = r;

  return 0;
}

int
decode_string (const char *buff, int *index, char **res)
{
  size_t size;

  if (decode_binary (buff, index, res, &size) != 0) return -1;

  (*res)[size] = 0;

  return 0;
}

int
decode_binary (const char *buff, int *index, char **res, size_t *size)
{
  int index0;
  int size0;
  char *r;

  index0 = *index;
  if (ei_decode_iodata (buff, index, &size0, NULL) != 0) return -1;

  r = malloc (size0+1); // In case if it's called from decode_string ()
  if (r == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  *index = index0;
  if (ei_decode_iodata (buff, index, NULL, r) != 0) {
      free (r);
      return -1;
  }

  *res = r;
  *size = (size_t) size0;

  return 0;
}

int
decode_bool (const char *buff, int *index, int *res)
{
  char atom[MAXATOMLEN];

  if (ei_decode_atom (buff, index, atom) != 0) return -1;

  if (atom_equals (atom, "true"))
    *res = 1;
  else
    *res = 0;

  return 0;
}

int
decode_int (const char *buff, int *index, int *res)
{
  unsigned char c;
  long l;
  long long ll;

  if (ei_decode_char (buff, index, (char *) &c) == 0) {
    // Byte integers in Erlang are to be treated as unsigned
    *res = (int) c;
    return 0;
  }
  if (ei_decode_long (buff, index, &l) == 0) {
    /* XXX check for overflow */
    *res = (int) l;
    return 0;
  }
  if (ei_decode_longlong (buff, index, &ll) == 0) {
    /* XXX check for overflow */
    *res = (int) ll;
    return 0;
  }
  /* XXX fail in some way */
  return -1;
}

int
decode_int64 (const char *buff, int *index, int64_t *res)
{
  unsigned char c;
  long l;
  long long ll;

  if (ei_decode_char (buff, index, (char *) &c) == 0) {
    // Byte integers in Erlang are to be treated as unsigned
    *res = (int64_t) c;
    return 0;
  }
  if (ei_decode_long (buff, index, &l) == 0) {
    *res = (int64_t) l;
    return 0;
  }
  if (ei_decode_longlong (buff, index, &ll) == 0) {
    /* XXX check for overflow */
    *res = (int64_t) ll;
    return 0;
  }
  /* XXX fail in some way */
  return -1;
}

