/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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

#include <config.h> /* HAVE_STRUCT_DIRENT_D_TYPE */

#include <dirent.h>    /* readdir() */
#include <errno.h>     /* errno */
#include <rpc/xdr.h>   /* xdrmem_create() */
#include <stdio.h>     /* perror() */
#include <stdlib.h>    /* malloc() */
#include <sys/types.h> /* opendir() */

#include "daemon.h" /* reply_with_perror() */

/* Has one FileOut parameter. */
int
do_internal_readdir (const char *dir)
{
  int ret;
  DIR *dirstream;
  void *xdr_buf;
  XDR xdr;
  struct dirent fill;
  guestfs_int_dirent v;
  unsigned max_encoded;

  /* Prepare to fail. */
  ret = -1;

  CHROOT_IN;
  dirstream = opendir (dir);
  CHROOT_OUT;

  if (dirstream == NULL) {
    reply_with_perror ("opendir: %s", dir);
    return ret;
  }

  xdr_buf = malloc (GUESTFS_MAX_CHUNK_SIZE);
  if (xdr_buf == NULL) {
    reply_with_perror ("malloc");
    goto close_dir;
  }
  xdrmem_create (&xdr, xdr_buf, GUESTFS_MAX_CHUNK_SIZE, XDR_ENCODE);

  /* Calculate the max number of bytes a "guestfs_int_dirent" can be encoded to.
   */
  memset (fill.d_name, 'a', sizeof fill.d_name - 1);
  fill.d_name[sizeof fill.d_name - 1] = '\0';
  v.ino = INT64_MAX;
  v.ftyp = '?';
  v.name = fill.d_name;
  if (!xdr_guestfs_int_dirent (&xdr, &v)) {
    fprintf (stderr, "xdr_guestfs_int_dirent failed\n");
    goto release_xdr;
  }
  max_encoded = xdr_getpos (&xdr);
  xdr_setpos (&xdr, 0);

  /* Send an "OK" reply, before starting the file transfer. */
  reply (NULL, NULL);

  /* From this point on, we can only report errors by canceling the file
   * transfer.
   */
  for (;;) {
    struct dirent *d;

    errno = 0;
    d = readdir (dirstream);
    if (d == NULL) {
      if (errno == 0)
        ret = 0;
      else
        perror ("readdir");

      break;
    }

    v.name = d->d_name;
    v.ino = d->d_ino;
#ifdef HAVE_STRUCT_DIRENT_D_TYPE
    switch (d->d_type) {
    case DT_BLK: v.ftyp = 'b'; break;
    case DT_CHR: v.ftyp = 'c'; break;
    case DT_DIR: v.ftyp = 'd'; break;
    case DT_FIFO: v.ftyp = 'f'; break;
    case DT_LNK: v.ftyp = 'l'; break;
    case DT_REG: v.ftyp = 'r'; break;
    case DT_SOCK: v.ftyp = 's'; break;
    case DT_UNKNOWN: v.ftyp = 'u'; break;
    default: v.ftyp = '?'; break;
    }
#else
    v.ftyp = 'u';
#endif

    /* Flush "xdr_buf" if we may not have enough room for encoding "v". */
    if (GUESTFS_MAX_CHUNK_SIZE - xdr_getpos (&xdr) < max_encoded) {
      if (send_file_write (xdr_buf, xdr_getpos (&xdr)) != 0)
        break;

      xdr_setpos (&xdr, 0);
    }

    if (!xdr_guestfs_int_dirent (&xdr, &v)) {
      fprintf (stderr, "xdr_guestfs_int_dirent failed\n");
      break;
    }
  }

  /* Flush "xdr_buf" if the loop completed successfully and "xdr_buf" is not
   * empty. */
  if (ret == 0 && xdr_getpos (&xdr) > 0 &&
      send_file_write (xdr_buf, xdr_getpos (&xdr)) != 0)
    ret = -1;

  /* Finish or cancel the transfer. Note that if (ret == -1) because the library
   * canceled, we still need to cancel back!
   */
  send_file_end (ret == -1);

release_xdr:
  xdr_destroy (&xdr);
  free (xdr_buf);

close_dir:
  if (closedir (dirstream) == -1)
    /* Best we can do here is log an error. */
    perror ("closedir");

  return ret;
}
