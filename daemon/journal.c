/* libguestfs - the guestfsd daemon
 * Copyright (C) 2013 Red Hat Inc.
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
#include <inttypes.h>
#include <string.h>
#ifdef HAVE_ENDIAN_H
#include <endian.h>
#endif
#ifdef HAVE_SYS_ENDIAN_H
#include <sys/endian.h>
#endif

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"
#include "optgroups.h"

#ifdef HAVE_SD_JOURNAL

#include <systemd/sd-journal.h>

int
optgroup_journal_available (void)
{
  return 1;
}

/* The handle.  As with Augeas and hivex, there is one per guestfs
 * handle / daemon.
 */
static sd_journal *j = NULL;

/* Clean up the handle on daemon exit. */
void journal_finalize (void) __attribute__((destructor));
void
journal_finalize (void)
{
  if (j) {
    sd_journal_close (j);
    j = NULL;
  }
}

#define NEED_HANDLE(errcode)						\
  do {									\
    if (!j) {								\
      reply_with_error ("%s: you must call 'journal-open' first to initialize the journal handle", __func__); \
      return (errcode);							\
    }									\
  }									\
  while (0)

int
do_journal_open (const char *directory)
{
  CLEANUP_FREE char *buf = NULL;
  int r;

  if (j) {
    sd_journal_close (j);
    j = NULL;
  }

  buf = sysroot_path (directory);
  if (!buf) {
    reply_with_perror ("malloc");
    return -1;
  }

  r = sd_journal_open_directory (&j, buf, 0);
  if (r < 0) {
    reply_with_perror_errno (-r, "sd_journal_open_directory: %s", directory);
    return -1;
  }

  return 0;
}

int
do_journal_close (void)
{
  NEED_HANDLE (-1);

  sd_journal_close (j);
  j = NULL;

  return 0;
}

int
do_journal_next (void)
{
  int r;

  NEED_HANDLE (-1);

  r = sd_journal_next (j);
  if (r < 0) {
    reply_with_perror_errno (-r, "sd_journal_next");
    return -1;
  }

  return r != 0;
}

int64_t
do_journal_skip (int64_t skip)
{
  int r;

  NEED_HANDLE (-1);

  if (skip == 0)
    return 0;

  if (skip > 0)
    r = sd_journal_next_skip (j, (uint64_t) skip);
  else /* skip < 0 */
    r = sd_journal_previous_skip (j, (uint64_t) -skip);
  if (r < 0) {
    reply_with_perror_errno (-r, "failed to skip %" PRIi64 " journal entries",
			     skip);
    return -1;
  }

  return r;
}

/* Has one FileOut parameter. */
int
do_internal_journal_get (void)
{
  const void *data;
  size_t len;
  uint64_t len_be;
  int r;

  NEED_HANDLE (-1);

  /* Now we must send the reply message, before the filenames.  After
   * this there is no opportunity in the protocol to send any error
   * message back.  Instead we can only cancel the transfer.
   */
  reply (NULL, NULL);

  sd_journal_restart_data (j);
  while ((r = sd_journal_enumerate_data (j, &data, &len)) > 0) {
    //fprintf (stderr, "data[%zu] = %.*s\n", len, (int) len, (char*) data);
    len_be = htobe64 ((uint64_t) len);
    if (send_file_write (&len_be, sizeof (len_be)) < 0)
      return -1;
    if (send_file_write (data, len) < 0)
      return -1;
  }

  /* Failure while enumerating the fields. */
  if (r < 0) {
    send_file_end (1);          /* Cancel. */
    errno = -r;
    perror ("sd_journal_enumerate_data");
    return -1;
  }

  /* Normal end of file. */
  if (send_file_end (0))
    return -1;
  return 0;
}

int64_t
do_journal_get_data_threshold (void)
{
  int r;
  size_t ret;

  NEED_HANDLE (-1);

  r = sd_journal_get_data_threshold (j, &ret);
  if (r < 0) {
    reply_with_perror_errno (-r, "sd_journal_get_data_threshold");
    return -1;
  }

  return ret;
}

int
do_journal_set_data_threshold (int64_t threshold)
{
  int r;

  NEED_HANDLE (-1);

  r = sd_journal_set_data_threshold (j, threshold);
  if (r < 0) {
    reply_with_perror_errno (-r, "sd_journal_set_data_threshold");
    return -1;
  }

  return 0;
}

int64_t
do_journal_get_realtime_usec (void)
{
  int r;
  uint64_t usec;

  NEED_HANDLE (-1);

  r = sd_journal_get_realtime_usec (j, &usec);
  if (r < 0) {
    reply_with_perror_errno (-r, "sd_journal_get_realtime_usec");
    return -1;
  }

  return (int64_t) usec;
}

#else /* !HAVE_SD_JOURNAL */

OPTGROUP_JOURNAL_NOT_AVAILABLE

void
journal_finalize (void)
{
}

#endif /* !HAVE_SD_JOURNAL */
