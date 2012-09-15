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

#ifdef HAVE_HIVEX
#include <hivex.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"

#if defined(DB_DUMP)

static unsigned char *convert_hex_to_binary (guestfs_h *g, const char *hex, size_t hexlen, size_t *binlen_rtn);

/* This helper function is specialized to just reading the hash-format
 * output from db_dump/db4_dump.  It's just enough to support the RPM
 * database format.  Note that the filename must not contain any shell
 * characters (this is guaranteed by the caller).
 */
int
guestfs___read_db_dump (guestfs_h *g,
                        const char *dumpfile, void *opaque,
                        guestfs___db_dump_callback callback)
{
#define cmd_len (strlen (dumpfile) + 64)
  char cmd[cmd_len];
  FILE *pp = NULL;
  char *line = NULL;
  size_t len = 0;
  ssize_t linelen;
  unsigned char *key = NULL, *value = NULL;
  size_t keylen, valuelen;
  int ret = -1;

  snprintf (cmd, cmd_len, DB_DUMP " -k '%s'", dumpfile);

  debug (g, "read_db_dump command: %s", cmd);

  pp = popen (cmd, "r");
  if (pp == NULL) {
    perrorf (g, "popen: %s", cmd);
    goto out;
  }

  /* Ignore everything to end-of-header marker. */
  while ((linelen = getline (&line, &len, pp)) != -1) {
    if (STRPREFIX (line, "HEADER=END"))
      break;
  }

  if (linelen == -1) {
    error (g, _("unexpected end of output from db_dump command before end of header"));
    goto out;
  }

  /* Now read the key, value pairs.  They are prefixed with a space and
   * printed as hex strings, so convert those strings to binary.  Pass
   * the strings up to the callback function.
   */
  while ((linelen = getline (&line, &len, pp)) != -1) {
    if (STRPREFIX (line, "DATA=END"))
      break;

    if (linelen < 1 || line[0] != ' ') {
      error (g, _("unexpected line from db_dump command, no space prefix"));
      goto out;
    }

    if ((key = convert_hex_to_binary (g, &line[1], linelen-1,
                                      &keylen)) == NULL)
      goto out;

    if ((linelen = getline (&line, &len, pp)) == -1)
      break;

    if (linelen < 1 || line[0] != ' ') {
      error (g, _("unexpected line from db_dump command, no space prefix"));
      goto out;
    }

    if ((value = convert_hex_to_binary (g, &line[1], linelen-1,
                                        &valuelen)) == NULL)
      goto out;

    if (callback (g, key, keylen, value, valuelen, opaque) == -1)
      goto out;

    free (key);
    free (value);
    key = value = NULL;
  }

  if (linelen == -1) {
    error (g, _("unexpected end of output from db_dump command before end of data"));
    goto out;
  }

  /* Catch errors from the db_dump command. */
  if (pclose (pp) != 0) {
    perrorf (g, "pclose: %s", cmd);
    pp = NULL;
    goto out;
  }
  pp = NULL;

  ret = 0;

 out:
  if (pp)
    pclose (pp);

  free (line);
  free (key);
  free (value);

  return ret;
#undef cmd_len
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
