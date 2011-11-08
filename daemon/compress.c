/* libguestfs - the guestfsd daemon
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* Has one FileOut parameter. */
static int
do_compressX_out (const char *file, const char *filter, int is_device)
{
  int r;
  FILE *fp;
  char *cmd;
  char buf[GUESTFS_MAX_CHUNK_SIZE];

  /* The command will look something like:
   *   gzip -c /sysroot%s     # file
   * or:
   *   gzip -c < %s           # device
   *
   * We have to quote the file or device name.
   *
   * The unnecessary redirect for devices is there because lzop
   * unhelpfully refuses to compress anything that isn't a regular
   * file.
   */
  if (!is_device) {
    if (asprintf_nowarn (&cmd, "%s %R", filter, file) == -1) {
      reply_with_perror ("asprintf");
      return -1;
    }
  } else {
    if (asprintf_nowarn (&cmd, "%s < %Q", filter, file) == -1) {
      reply_with_perror ("asprintf");
      return -1;
    }
  }

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("%s", cmd);
    free (cmd);
    return -1;
  }
  free (cmd);

  /* Now we must send the reply message, before the file contents.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  while ((r = fread (buf, 1, sizeof buf, fp)) > 0) {
    if (send_file_write (buf, r) < 0) {
      pclose (fp);
      return -1;
    }
  }

  if (ferror (fp)) {
    perror (file);
    send_file_end (1);		/* Cancel. */
    pclose (fp);
    return -1;
  }

  if (pclose (fp) != 0) {
    perror (file);
    send_file_end (1);		/* Cancel. */
    return -1;
  }

  if (send_file_end (0))	/* Normal end of file. */
    return -1;

  return 0;
}

#define CHECK_SUPPORTED(prog)                                           \
  if (!prog_exists (prog)) {                                            \
    /* note: substring "not supported" must appear in this error */     \
    reply_with_error ("compression type %s is not supported", prog);    \
    return -1;                                                          \
  }

static int
get_filter (const char *ctype, int level, char *ret, size_t n)
{
  if (STREQ (ctype, "compress")) {
    CHECK_SUPPORTED ("compress");
    if (level != -1) {
      reply_with_error ("compress: cannot use optional level parameter with this compression type");
      return -1;
    }
    snprintf (ret, n, "compress -c");
    return 0;
  }
  else if (STREQ (ctype, "gzip")) {
    CHECK_SUPPORTED ("gzip");
    if (level == -1)
      snprintf (ret, n, "gzip -c");
    else if (level >= 1 && level <= 9)
      snprintf (ret, n, "gzip -c -%d", level);
    else {
      reply_with_error ("gzip: incorrect value for level parameter");
      return -1;
    }
    return 0;
  }
  else if (STREQ (ctype, "bzip2")) {
    CHECK_SUPPORTED ("bzip2");
    if (level == -1)
      snprintf (ret, n, "bzip2 -c");
    else if (level >= 1 && level <= 9)
      snprintf (ret, n, "bzip2 -c -%d", level);
    else {
      reply_with_error ("bzip2: incorrect value for level parameter");
      return -1;
    }
    return 0;
  }
  else if (STREQ (ctype, "xz")) {
    CHECK_SUPPORTED ("xz");
    if (level == -1)
      snprintf (ret, n, "xz -c");
    else if (level >= 0 && level <= 9)
      snprintf (ret, n, "xz -c -%d", level);
    else {
      reply_with_error ("xz: incorrect value for level parameter");
      return -1;
    }
    return 0;
  }
  else if (STREQ (ctype, "lzop")) {
    CHECK_SUPPORTED ("lzop");
    if (level == -1)
      snprintf (ret, n, "lzop -c");
    else if (level >= 1 && level <= 9)
      snprintf (ret, n, "lzop -c -%d", level);
    else {
      reply_with_error ("lzop: incorrect value for level parameter");
      return -1;
    }
    return 0;
  }

  reply_with_error ("unknown compression type");
  return -1;
}

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_compress_out (const char *ctype, const char *file, int level)
{
  char filter[64];

  if (!(optargs_bitmask & GUESTFS_COMPRESS_OUT_LEVEL_BITMASK))
    level = -1;

  if (get_filter (ctype, level, filter, sizeof filter) == -1)
    return -1;

  return do_compressX_out (file, filter, 0);
}

/* Has one FileOut parameter. */
/* Takes optional arguments, consult optargs_bitmask. */
int
do_compress_device_out (const char *ctype, const char *file, int level)
{
  char filter[64];

  if (!(optargs_bitmask & GUESTFS_COMPRESS_DEVICE_OUT_LEVEL_BITMASK))
    level = -1;

  if (get_filter (ctype, level, filter, sizeof filter) == -1)
    return -1;

  return do_compressX_out (file, filter, 1);
}
