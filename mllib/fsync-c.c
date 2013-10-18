/* virt-resize - interface to fsync
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
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

/* OCaml doesn't bind any *sync* calls. */

/* NB: This is a "noalloc" call. */
value
virt_resize_sync (value unitv)
{
  sync ();
  return Val_unit;
}

/* Flush all writes associated with the named file to the disk.
 *
 * Note the wording in the SUS definition:
 *
 * "The fsync() function forces all currently queued I/O operations
 * associated with the file indicated by file descriptor fildes to the
 * synchronised I/O completion state."
 *
 * http://pubs.opengroup.org/onlinepubs/007908775/xsh/fsync.html
 */
value
virt_resize_fsync_file (value filenamev)
{
  CAMLparam1 (filenamev);
  const char *filename = String_val (filenamev);
  int fd, err;

  /* Note to do fsync you have to open for write. */
  fd = open (filename, O_RDWR);
  if (fd == -1)
    unix_error (errno, (char *) "open", filenamev);

  if (fsync (fd) == -1) {
    err = errno;
    close (fd);
    unix_error (err, (char *) "fsync", filenamev);
  }

  if (close (fd) == -1)
    unix_error (errno, (char *) "close", filenamev);

  CAMLreturn (Val_unit);
}
