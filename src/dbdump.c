/* libguestfs
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>

#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif

#include <pcre.h>

#include "guestfs.h"
#include "guestfs-internal.h"

#if defined(DB_DUMP)

static void read_db_dump_line (guestfs_h *g, void *datav, const char *line, size_t len);
static unsigned char *convert_hex_to_binary (guestfs_h *g, const char *hex, size_t hexlen, size_t *binlen_rtn);

struct cb_data {
  guestfs_int_db_dump_callback callback;
  void *opaque;
  enum { reading_header,
         reading_key, reading_value,
         reading_finished,
         reading_failed } state;
  unsigned char *key;
  size_t keylen;
};

/* This helper function is specialized to just reading the hash-format
 * output from db_dump/db4_dump.  It's just enough to support the RPM
 * database format.
 */
int
guestfs_int_read_db_dump (guestfs_h *g,
                        const char *dumpfile, void *opaque,
                        guestfs_int_db_dump_callback callback)
{
  struct cb_data data;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  int r;

  data.callback = callback;
  data.opaque = opaque;
  data.state = reading_header;
  data.key = NULL;

  guestfs_int_cmd_add_arg (cmd, DB_DUMP);
  guestfs_int_cmd_add_arg (cmd, "-k");
  guestfs_int_cmd_add_arg (cmd, dumpfile);
  guestfs_int_cmd_set_stdout_callback (cmd, read_db_dump_line, &data, 0);

  r = guestfs_int_cmd_run (cmd);
  free (data.key);

  if (r == -1)
    return -1;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, DB_DUMP, NULL);
    return -1;
  }
  if (data.state != reading_finished) {
    error (g, _("%s: unexpected error or end of output"), DB_DUMP);
    return -1;
  }

  return 0;
}

static void
read_db_dump_line (guestfs_h *g, void *datav, const char *line, size_t len)
{
  struct cb_data *data = datav;

  switch (data->state) {
  case reading_finished:
  case reading_failed:
    return;

  case reading_header:
    /* Ignore everything to end-of-header marker. */
    if (STRPREFIX (line, "HEADER=END"))
      data->state = reading_key;
    return;

    /* Read the key, value pairs using a state machine.  They are
     * prefixed with a space and printed as hex strings, so convert
     * those strings to binary.  Pass the strings up to the callback
     * function.
     */
  case reading_key:
    if (STRPREFIX (line, "DATA=END")) {
      data->state = reading_finished;
      return;
    }

    if (len < 1 || line[0] != ' ') {
      debug (g, _("unexpected line from db_dump command, no space prefix"));
      data->state = reading_failed;
      return;
    }

    data->key = convert_hex_to_binary (g, &line[1], len-1, &data->keylen);
    if (data->key == NULL) {
      data->state = reading_failed;
      return;
    }

    data->state = reading_value;
    return;

  case reading_value: {
    CLEANUP_FREE unsigned char *value = NULL;
    size_t valuelen;

    if (len < 1 || line[0] != ' ') {
      debug (g, _("unexpected line from db_dump command, no space prefix"));
      data->state = reading_failed;
      return;
    }

    value = convert_hex_to_binary (g, &line[1], len-1, &valuelen);
    if (value == NULL) {
      data->state = reading_failed;
      return;
    }

    if (data->callback (g, data->key, data->keylen,
                        value, valuelen, data->opaque) == -1) {
      data->state = reading_failed;
      return;
    }

    free (data->key);
    data->key = NULL;

    data->state = reading_key;
    return;
  }
  }
}

static int
convert_hex_octet (const char *h)
{
  int r;

  switch (h[0]) {
  case 'a'...'f':
    r = (h[0] - 'a' + 10) << 4;
    break;
  case 'A'...'F':
    r = (h[0] - 'A' + 10) << 4;
    break;
  case '0'...'9':
    r = (h[0] - '0') << 4;
    break;
  default:
    return -1;
  }

  switch (h[1]) {
  case 'a'...'f':
    r |= h[1] - 'a' + 10;
    break;
  case 'A'...'F':
    r |= h[1] - 'A' + 10;
    break;
  case '0'...'9':
    r |= h[1] - '0';
    break;
  default:
    return -1;
  }

  return r;
}

static unsigned char *
convert_hex_to_binary (guestfs_h *g, const char *hex, size_t hexlen,
                       size_t *binlen_rtn)
{
  unsigned char *bin;
  size_t binlen;
  size_t i, o;
  int b;

  if (hexlen > 0 && hex[hexlen-1] == '\n')
    hexlen--;

  binlen = hexlen / 2;
  bin = safe_malloc (g, binlen);

  for (i = o = 0; i+1 < hexlen && o < binlen; i += 2, ++o) {
    b = convert_hex_octet (&hex[i]);
    if (b >= 0)
      bin[o] = b;
    else {
      error (g, _("unexpected non-hex digits in output of db_dump command"));
      free (bin);
      return NULL;
    }
  }

  *binlen_rtn = binlen;
  return bin;
}

#endif /* defined(DB_DUMP) */
